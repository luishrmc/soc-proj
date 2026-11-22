#!/usr/bin/env python3
"""Generate bit-exact ADR-020 VHDL test vectors for VUnit RTL verification.

Imports the canonical ESP32 synthetic telemetry generator (`seed=42`,
`Quiescent`, `Dynamic`, `Chaotic`, 1024 B payload) and computes bit-exact
golden outputs matching `lzss_accel.vhdl` (window=256, lookahead=16, min=3)
and `aes_accel.vhdl` (NIST SP 800-38A AES-128-CTR), emitting
`cora7z/app/hw/test/tb_adr020_vectors_pkg.vhdl`.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[4]
ESP32_SCRIPTS = REPO_ROOT / "esp32" / "scripts"
if str(ESP32_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(ESP32_SCRIPTS))

from telemetry_profiles import EntropyProfile, generate_dataset  # noqa: E402

# ---------------------------------------------------------------------------
# Reference Heatshrink-compatible LZSS matching lzss_accel.vhdl generics
# ---------------------------------------------------------------------------
WINDOW_SIZE = 256
MAX_LOOKAHEAD = 16
MIN_MATCH = 3


def lzss_compress_hw_ref(src: bytes) -> bytes:
    """Compress bytes identically to lzss_accel.vhdl (lookahead=16, window=256)."""
    src_len = len(src)
    out = bytearray([(src_len >> 8) & 0xFF, src_len & 0xFF])
    in_idx = 0

    while in_idx < src_len:
        flag_idx = len(out)
        out.append(0)
        flag_mask = 0

        for bit in range(8):
            if in_idx >= src_len:
                break

            la_len = min(MAX_LOOKAHEAD, src_len - in_idx)
            if la_len >= MIN_MATCH:
                win_start = max(0, in_idx - WINDOW_SIZE)
                best_len = 0
                best_dist = 0
                for cand in range(win_start, in_idx):
                    if src[cand] != src[in_idx]:
                        continue
                    match_len = 1
                    while match_len < la_len and src[cand + match_len] == src[in_idx + match_len]:
                        match_len += 1
                    if match_len >= MIN_MATCH and match_len > best_len:
                        best_len = match_len
                        best_dist = in_idx - cand
                        if best_len == la_len:
                            break
                if best_len >= MIN_MATCH:
                    flag_mask |= 1 << bit
                    out.append((best_dist - 1) & 0xFF)
                    out.append((best_len - MIN_MATCH) & 0xFF)
                    in_idx += best_len
                    continue

            out.append(src[in_idx])
            in_idx += 1

        out[flag_idx] = flag_mask

    return bytes(out)


def lzss_decompress_ref(src: bytes) -> bytes:
    """Decode LZSS stream back to uncompressed bytes."""
    expected_len = (src[0] << 8) | src[1]
    out = bytearray()
    in_idx = 2
    while len(out) < expected_len and in_idx < len(src):
        flag_mask = src[in_idx]
        in_idx += 1
        for bit in range(8):
            if len(out) >= expected_len:
                break
            if (flag_mask >> bit) & 1:
                dist = src[in_idx] + 1
                length = src[in_idx + 1] + MIN_MATCH
                in_idx += 2
                for _ in range(length):
                    out.append(out[-dist])
            else:
                out.append(src[in_idx])
                in_idx += 1
    assert len(out) == expected_len, f"Decoded {len(out)} != {expected_len}"
    return bytes(out)


# ---------------------------------------------------------------------------
# Pure-Python FIPS-197 AES-128 & NIST SP 800-38A CTR mode
# ---------------------------------------------------------------------------
_SBOX = (
    0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
    0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
    0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
    0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
    0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
    0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
    0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
    0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
    0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
    0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
    0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
    0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
    0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
    0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
    0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
    0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
)
_RCON = (0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36)


def _xtime(a: int) -> int:
    return ((a << 1) ^ 0x1B) & 0xFF if (a & 0x80) else (a << 1) & 0xFF


def _aes128_expand_key(key: bytes) -> list[list[int]]:
    rk = list(key)
    for r in range(1, 11):
        prev = rk[-4:]
        rot = [prev[1], prev[2], prev[3], prev[0]]
        sub = [_SBOX[b] for b in rot]
        sub[0] ^= _RCON[r]
        base = len(rk) - 16
        for i in range(4):
            rk.append(rk[base + i] ^ sub[i])
        for w in range(3):
            base = len(rk) - 16
            for i in range(4):
                rk.append(rk[base + i] ^ rk[-4])
    return [rk[i * 16 : (i + 1) * 16] for i in range(11)]


def _aes128_encrypt_block(round_keys: list[list[int]], block: bytes) -> bytes:
    st = [b ^ k for b, k in zip(block, round_keys[0])]
    for rnd in range(1, 11):
        st = [_SBOX[b] for b in st]
        # ShiftRows (column-major state)
        st = [
            st[0], st[5], st[10], st[15],
            st[4], st[9], st[14], st[3],
            st[8], st[13], st[2], st[7],
            st[12], st[1], st[6], st[11],
        ]
        if rnd < 10:
            mixed = []
            for c in range(4):
                s0, s1, s2, s3 = st[4 * c : 4 * c + 4]
                t = s0 ^ s1 ^ s2 ^ s3
                mixed.extend([
                    s0 ^ t ^ _xtime(s0 ^ s1),
                    s1 ^ t ^ _xtime(s1 ^ s2),
                    s2 ^ t ^ _xtime(s2 ^ s3),
                    s3 ^ t ^ _xtime(s3 ^ s0),
                ])
            st = mixed
        st = [b ^ k for b, k in zip(st, round_keys[rnd])]
    return bytes(st)


def aes128_ctr_crypt_ref(key: bytes, iv: bytes, plaintext: bytes) -> bytes:
    """NIST SP 800-38A AES-128-CTR (matching aes_accel.vhdl 32-bit tail counter)."""
    rks = _aes128_expand_key(key)
    prefix = iv[:12]
    ctr = int.from_bytes(iv[12:16], "big")
    out = bytearray(len(plaintext))
    offset = 0
    while offset < len(plaintext):
        ctr_block = prefix + (ctr & 0xFFFFFFFF).to_bytes(4, "big")
        ks = _aes128_encrypt_block(rks, ctr_block)
        chunk = min(16, len(plaintext) - offset)
        for i in range(chunk):
            out[offset + i] = plaintext[offset + i] ^ ks[i]
        offset += chunk
        ctr = (ctr + 1) & 0xFFFFFFFF
    return bytes(out)


def _format_vhdl_byte_array(name: str, data: bytes, per_line: int = 16) -> str:
    lines = [f"  constant {name} : byte_vec_t(0 to {len(data) - 1}) := ("]
    for idx in range(0, len(data), per_line):
        chunk = data[idx : idx + per_line]
        hexes = ", ".join(f'x"{b:02X}"' for b in chunk)
        suffix = "," if (idx + per_line) < len(data) else ""
        lines.append(f"    {hexes}{suffix}")
    lines.append("  );")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=REPO_ROOT / "cora7z" / "app" / "hw" / "test" / "tb_adr020_vectors_pkg.vhdl",
        help="Destination VHDL package file path",
    )
    parser.add_argument("--seed", type=int, default=42, help="Dataset RNG seed (default: 42)")
    args = parser.parse_args()

    # Sanity-check AES against NIST SP 800-38A F.5.1 Block 1
    nist_key = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
    nist_iv = bytes.fromhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
    nist_pt1 = bytes.fromhex("6bc1bee22e409f96e93d7e117393172a")
    nist_ct1 = bytes.fromhex("874d6191b620e3261bef6864990db6ce")
    assert aes128_ctr_crypt_ref(nist_key, nist_iv, nist_pt1) == nist_ct1

    dataset = generate_dataset(seed=args.seed, frames_per_profile=1)
    profile_bytes = {p: payload for p, payload in dataset}

    q_raw = profile_bytes[EntropyProfile.QUIESCENT]
    d_raw = profile_bytes[EntropyProfile.DYNAMIC]
    c_raw = profile_bytes[EntropyProfile.CHAOTIC]

    q_lzss = lzss_compress_hw_ref(q_raw)
    d_lzss = lzss_compress_hw_ref(d_raw)
    c_lzss = lzss_compress_hw_ref(c_raw)

    assert lzss_decompress_ref(q_lzss) == q_raw
    assert lzss_decompress_ref(d_lzss) == d_raw
    assert lzss_decompress_ref(c_lzss) == c_raw
    assert len(q_lzss) < len(d_lzss) < 1024 < len(c_lzss) <= 1154

    # AES golden vectors matching pipeline_mgr key & seq_id=1 IV (or explicit test IV)
    aes_iv = bytes.fromhex("f0f1f2f3f4f5f6f7f8f9000100000001")
    aes_1024_ct = aes128_ctr_crypt_ref(nist_key, aes_iv, d_raw)
    aes_unaligned_ct = aes128_ctr_crypt_ref(nist_key, aes_iv, c_lzss)

    blocks = [
        "--------------------------------------------------------------------------------",
        "-- File:    tb_adr020_vectors_pkg.vhdl",
        "-- Purpose: Auto-generated bit-exact ADR-020 (1024 B) RTL test vectors.",
        "-- Source:  cora7z/app/hw/scripts/gen_vunit_vectors.py (seed=42)",
        "--------------------------------------------------------------------------------",
        "",
        "library ieee;",
        "use ieee.std_logic_1164.all;",
        "",
        "package tb_adr020_vectors_pkg is",
        "",
        "  type byte_vec_t is array (natural range <>) of std_logic_vector(7 downto 0);",
        "",
        f"  constant c_quiescent_lzss_len : integer := {len(q_lzss)};",
        f"  constant c_dynamic_lzss_len   : integer := {len(d_lzss)};",
        f"  constant c_chaotic_lzss_len   : integer := {len(c_lzss)};",
        f"  constant c_aes_unaligned_len  : integer := {len(c_lzss)};",
        "",
        _format_vhdl_byte_array("c_quiescent_raw", q_raw),
        "",
        _format_vhdl_byte_array("c_quiescent_lzss_gold", q_lzss),
        "",
        _format_vhdl_byte_array("c_dynamic_raw", d_raw),
        "",
        _format_vhdl_byte_array("c_dynamic_lzss_gold", d_lzss),
        "",
        _format_vhdl_byte_array("c_chaotic_raw", c_raw),
        "",
        _format_vhdl_byte_array("c_chaotic_lzss_gold", c_lzss),
        "",
        _format_vhdl_byte_array("c_aes_1024b_pt", d_raw),
        "",
        _format_vhdl_byte_array("c_aes_1024b_ct", aes_1024_ct),
        "",
        _format_vhdl_byte_array("c_aes_unaligned_pt", c_lzss),
        "",
        _format_vhdl_byte_array("c_aes_unaligned_ct", aes_unaligned_ct),
        "",
        "end package tb_adr020_vectors_pkg;",
        "",
    ]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(blocks), encoding="utf-8")
    print(
        f"[OK] Generated {args.output.relative_to(REPO_ROOT)}: "
        f"Quiescent={len(q_lzss)}B, Dynamic={len(d_lzss)}B, Chaotic={len(c_lzss)}B"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
