"""Host verification suite for the ESP32 synthetic telemetry generator."""

from __future__ import annotations

import collections
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))


class TestTelemetryProfiles(unittest.TestCase):
    """Tests for telemetry record packing, determinism, and entropy profiles."""

    def test_dataset_layout_and_record_packing(self) -> None:
        from telemetry_profiles import (
            EntropyProfile,
            PAYLOAD_SIZE,
            RECORD_FORMAT,
            RECORD_SIZE,
            RECORDS_PER_FRAME,
            generate_dataset,
        )

        self.assertEqual(RECORD_SIZE, 16)
        self.assertEqual(RECORDS_PER_FRAME, 64)
        self.assertEqual(PAYLOAD_SIZE, 1024)
        self.assertEqual(struct.calcsize(RECORD_FORMAT), 16)

        dataset = generate_dataset(seed=42, frames_per_profile=2)
        self.assertEqual(len(dataset), 6)

        expected_profiles = [
            EntropyProfile.QUIESCENT,
            EntropyProfile.QUIESCENT,
            EntropyProfile.DYNAMIC,
            EntropyProfile.DYNAMIC,
            EntropyProfile.CHAOTIC,
            EntropyProfile.CHAOTIC,
        ]
        self.assertEqual([entry[0] for entry in dataset], expected_profiles)

        for _, payload in dataset:
            self.assertIsInstance(payload, bytes)
            self.assertEqual(len(payload), 1024)
            prev_ts = -1
            for idx in range(64):
                chunk = payload[idx * 16 : (idx + 1) * 16]
                ts, temp, vx, vy, vz, vcc, flags = struct.unpack("<IhhhhHH", chunk)
                self.assertGreaterEqual(ts, 0)
                self.assertLessEqual(ts, 0xFFFFFFFF)
                self.assertGreater(ts, prev_ts)
                prev_ts = ts
                self.assertGreaterEqual(temp, -32768)
                self.assertLessEqual(temp, 32767)
                for vib in (vx, vy, vz):
                    self.assertGreaterEqual(vib, -32768)
                    self.assertLessEqual(vib, 32767)
                self.assertGreaterEqual(vcc, 0)
                self.assertLessEqual(vcc, 65535)
                self.assertGreaterEqual(flags, 0)
                self.assertLessEqual(flags, 65535)

    def test_determinism_across_seeds(self) -> None:
        from telemetry_profiles import generate_dataset

        ds_a = generate_dataset(seed=42, frames_per_profile=4)
        ds_b = generate_dataset(seed=42, frames_per_profile=4)
        ds_c = generate_dataset(seed=1337, frames_per_profile=4)

        self.assertEqual(ds_a, ds_b)
        self.assertNotEqual(ds_a, ds_c)

    def test_entropy_and_compressibility_ordering(self) -> None:
        from telemetry_profiles import EntropyProfile, generate_dataset

        def shannon_entropy_bits_per_byte(data: bytes) -> float:
            counts = collections.Counter(data)
            n = len(data)
            return -sum((c / n) * math.log2(c / n) for c in counts.values())

        dataset = generate_dataset(seed=42, frames_per_profile=10)
        by_profile: dict[EntropyProfile, list[bytes]] = {
            EntropyProfile.QUIESCENT: [],
            EntropyProfile.DYNAMIC: [],
            EntropyProfile.CHAOTIC: [],
        }
        for profile, payload in dataset:
            by_profile[profile].append(payload)

        mean_entropy = {
            p: sum(shannon_entropy_bits_per_byte(b) for b in frames) / len(frames)
            for p, frames in by_profile.items()
        }
        mean_zlib_size = {
            p: sum(len(zlib.compress(b, level=6)) for b in frames) / len(frames)
            for p, frames in by_profile.items()
        }

        self.assertLess(mean_entropy[EntropyProfile.QUIESCENT], mean_entropy[EntropyProfile.DYNAMIC])
        self.assertLess(mean_entropy[EntropyProfile.DYNAMIC], mean_entropy[EntropyProfile.CHAOTIC])

        self.assertLess(
            mean_zlib_size[EntropyProfile.QUIESCENT],
            mean_zlib_size[EntropyProfile.DYNAMIC],
        )
        self.assertLess(
            mean_zlib_size[EntropyProfile.DYNAMIC],
            mean_zlib_size[EntropyProfile.CHAOTIC],
        )
        # Ensure strong separation matching ADR-020 / spec intent
        self.assertLess(mean_entropy[EntropyProfile.QUIESCENT], 3.5)
        self.assertGreater(mean_entropy[EntropyProfile.CHAOTIC], 7.0)

    def test_json_config_overrides_and_validation(self) -> None:
        from telemetry_profiles import (
            EntropyProfile,
            generate_dataset,
            load_profile_config,
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            cfg_path = Path(tmpdir) / "override.json"
            cfg_path.write_text(
                json.dumps(
                    {
                        "quiescent": {"temp_base_x100": 3100, "temp_jitter": 0, "status_flags": 0x00A5},
                        "chaotic": {"vcc_min_mv": 3250, "vcc_max_mv": 3350},
                    }
                ),
                encoding="utf-8",
            )
            cfg = load_profile_config(cfg_path)
            dataset = generate_dataset(seed=42, frames_per_profile=1, config=cfg)

            q_payload = dict(dataset)[EntropyProfile.QUIESCENT]
            _, temp, _, _, _, _, flags = struct.unpack("<IhhhhHH", q_payload[:16])
            self.assertEqual(temp, 3100)
            self.assertEqual(flags, 0x00A5)

            c_payload = dict(dataset)[EntropyProfile.CHAOTIC]
            for idx in range(64):
                _, _, _, _, _, vcc, _ = struct.unpack("<IhhhhHH", c_payload[idx * 16 : (idx + 1) * 16])
                self.assertGreaterEqual(vcc, 3250)
                self.assertLessEqual(vcc, 3350)

            bad_cfg = Path(tmpdir) / "bad.json"
            bad_cfg.write_text('{"unknown_profile": {}}', encoding="utf-8")
            with self.assertRaises(ValueError):
                load_profile_config(bad_cfg)

            malformed_cfg = Path(tmpdir) / "malformed.json"
            malformed_cfg.write_text("{not valid json", encoding="utf-8")
            with self.assertRaises(ValueError):
                load_profile_config(malformed_cfg)

        with self.assertRaises(ValueError):
            generate_dataset(seed=42, frames_per_profile=0)
        with self.assertRaises(ValueError):
            generate_dataset(seed=42, frames_per_profile=-3)


class TestGenerateTelemetryCLI(unittest.TestCase):
    """Tests for CLI emission of C header/source and GCC syntax verification."""

    def _run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        script = SCRIPTS_DIR / "generate_telemetry.py"
        return subprocess.run(
            [sys.executable, str(script), *args],
            capture_output=True,
            text=True,
            check=False,
        )

    def _check_c11_syntax(self, c_file: Path, include_dir: Path) -> None:
        res = subprocess.run(
            [
                "gcc",
                "-std=c11",
                "-Wall",
                "-Wextra",
                "-Werror",
                "-fsyntax-only",
                f"-I{include_dir}",
                str(c_file),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            res.returncode,
            0,
            msg=f"gcc failed on {c_file}:\nstdout:\n{res.stdout}\nstderr:\n{res.stderr}",
        )

    def test_cli_generates_valid_header_and_passes_gcc(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            hdr = tmp / "generated" / "telemetry_dataset.h"
            res = self._run_cli(
                "--seed",
                "42",
                "--frames-per-profile",
                "3",
                "--out-header",
                str(hdr),
            )
            self.assertEqual(res.returncode, 0, msg=res.stderr)
            self.assertTrue(hdr.is_file())
            content = hdr.read_text(encoding="utf-8")

            for token in (
                "TELEMETRY_DATASET_SEED",
                "42U",
                "TELEMETRY_FRAMES_PER_PROFILE",
                "3U",
                "TELEMETRY_DATASET_FRAME_COUNT",
                "9U",
                "TELEMETRY_PAYLOAD_SIZE",
                "1024U",
                "TELEMETRY_RECORD_SIZE",
                "16U",
                "TELEMETRY_RECORDS_PER_FRAME",
                "64U",
                "telemetry_entropy_profile_t",
                "TELEMETRY_PROFILE_QUIESCENT",
                "TELEMETRY_PROFILE_DYNAMIC",
                "TELEMETRY_PROFILE_CHAOTIC",
                "telemetry_dataset_entry_t",
                "telemetry_profile_name",
                "g_telemetry_dataset",
            ):
                self.assertIn(token, content)

            # Verify header compiles cleanly even when included without referencing g_telemetry_dataset
            unused_c = tmp / "check_unused.c"
            unused_c.write_text('#include "telemetry_dataset.h"\nint main(void) { return 0; }\n', encoding="utf-8")
            self._check_c11_syntax(unused_c, hdr.parent)

            # Verify header compiles cleanly and matches static invariants when exercised
            check_c = tmp / "check_used.c"
            check_c.write_text(
                "\n".join(
                    [
                        '#include "telemetry_dataset.h"',
                        "_Static_assert(TELEMETRY_DATASET_SEED == 42U, \"seed\");",
                        "_Static_assert(TELEMETRY_FRAMES_PER_PROFILE == 3U, \"frames\");",
                        "_Static_assert(TELEMETRY_DATASET_FRAME_COUNT == 9U, \"count\");",
                        "_Static_assert(TELEMETRY_PAYLOAD_SIZE == 1024U, \"payload\");",
                        "_Static_assert(TELEMETRY_RECORD_SIZE == 16U, \"record\");",
                        "_Static_assert(TELEMETRY_RECORDS_PER_FRAME == 64U, \"records_per_frame\");",
                        "_Static_assert(sizeof(g_telemetry_dataset) == 9U * sizeof(telemetry_dataset_entry_t), \"size\");",
                        "int main(void) {",
                        "    const char *name = telemetry_profile_name(g_telemetry_dataset[0].profile);",
                        "    return (name != 0 && g_telemetry_dataset[0].payload[0] == g_telemetry_dataset[0].payload[0]) ? 0 : 1;",
                        "}",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            self._check_c11_syntax(check_c, hdr.parent)

    def test_cli_generates_split_header_and_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            hdr = tmp / "telemetry_dataset.h"
            src = tmp / "telemetry_dataset.c"
            res = self._run_cli(
                "--seed",
                "7",
                "--frames-per-profile",
                "2",
                "--out-header",
                str(hdr),
                "--out-source",
                str(src),
            )
            self.assertEqual(res.returncode, 0, msg=res.stderr)
            self.assertTrue(hdr.is_file())
            self.assertTrue(src.is_file())
            self.assertIn("extern const telemetry_dataset_entry_t", hdr.read_text(encoding="utf-8"))
            self._check_c11_syntax(src, tmp)

            caller = tmp / "caller.c"
            caller.write_text(
                '#include "telemetry_dataset.h"\n'
                "const char *probe(void) { return telemetry_profile_name(g_telemetry_dataset[0].profile); }\n",
                encoding="utf-8",
            )
            self._check_c11_syntax(caller, tmp)

    def test_cli_rejects_invalid_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            hdr = tmp / "should_not_exist.h"

            res_zero = self._run_cli("--frames-per-profile", "0", "--out-header", str(hdr))
            self.assertNotEqual(res_zero.returncode, 0)
            self.assertTrue(res_zero.stderr.strip())
            self.assertFalse(hdr.exists())

            res_missing_cfg = self._run_cli(
                "--config",
                str(tmp / "missing.json"),
                "--out-header",
                str(hdr),
            )
            self.assertNotEqual(res_missing_cfg.returncode, 0)
            self.assertTrue(res_missing_cfg.stderr.strip())
            self.assertFalse(hdr.exists())

            bad_cfg = tmp / "bad.json"
            bad_cfg.write_text('{"quiescent": {"timestamp_step_ms": 0}}', encoding="utf-8")
            res_bad_cfg = self._run_cli(
                "--config",
                str(bad_cfg),
                "--out-header",
                str(hdr),
            )
            self.assertNotEqual(res_bad_cfg.returncode, 0)
            self.assertTrue(res_bad_cfg.stderr.strip())
            self.assertFalse(hdr.exists())

            bad_profile = tmp / "bad_profile.json"
            bad_profile.write_text('{"unknown_profile": {}}', encoding="utf-8")
            res_bad_prof = self._run_cli(
                "--config",
                str(bad_profile),
                "--out-header",
                str(hdr),
            )
            self.assertNotEqual(res_bad_prof.returncode, 0)
            self.assertTrue(res_bad_prof.stderr.strip())
            self.assertFalse(hdr.exists())

            bad_type = tmp / "bad_type.json"
            bad_type.write_text('{"quiescent": {"temp_base_x100": "hot"}}', encoding="utf-8")
            res_bad_type = self._run_cli(
                "--config",
                str(bad_type),
                "--out-header",
                str(hdr),
            )
            self.assertNotEqual(res_bad_type.returncode, 0)
            self.assertTrue(res_bad_type.stderr.strip())
            self.assertFalse(hdr.exists())

            res_neg_seed = self._run_cli("--seed", "-1", "--out-header", str(hdr))
            self.assertNotEqual(res_neg_seed.returncode, 0)
            self.assertTrue(res_neg_seed.stderr.strip())
            self.assertFalse(hdr.exists())


if __name__ == "__main__":
    unittest.main()
