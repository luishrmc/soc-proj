"""Pure synthetic telemetry profile generators for ESP32 Embedded Dataset.

Produces 16-byte packed little-endian Telemetry Records (64 records = 1024-byte
Telemetry Frame payload) across Quiescent, Dynamic, and Chaotic Entropy Profiles.
"""

from __future__ import annotations

from copy import deepcopy
from enum import IntEnum
import json
import math
from pathlib import Path
import random
import struct
from typing import Any, NamedTuple

RECORD_FORMAT = "<IhhhhHH"
RECORD_SIZE = 16
RECORDS_PER_FRAME = 64
PAYLOAD_SIZE = RECORD_SIZE * RECORDS_PER_FRAME  # 1024 bytes (ADR-020)

_INT16_MIN = -32768
_INT16_MAX = 32767
_UINT16_MIN = 0
_UINT16_MAX = 65535
_UINT32_MAX = 0xFFFFFFFF


class EntropyProfile(IntEnum):
    """Statistical entropy regime governing Telemetry Frame payload redundancy."""

    QUIESCENT = 0
    DYNAMIC = 1
    CHAOTIC = 2

    @property
    def label(self) -> str:
        """Return canonical GLOSSARY.md title-case profile name."""
        return _PROFILE_LABELS[self]

    @property
    def key(self) -> str:
        """Return lowercase JSON configuration key for this profile."""
        return _PROFILE_LABELS[self].lower()


_PROFILE_LABELS: dict[EntropyProfile, str] = {
    EntropyProfile.QUIESCENT: "Quiescent",
    EntropyProfile.DYNAMIC: "Dynamic",
    EntropyProfile.CHAOTIC: "Chaotic",
}


class TelemetryRecord(NamedTuple):
    """Canonical 16-byte packed little-endian Telemetry Record."""

    timestamp_ms: int
    temp_c_x100: int
    vib_x: int
    vib_y: int
    vib_z: int
    vcc_mv: int
    status_flags: int

    def pack(self) -> bytes:
        """Serialize record into 16 packed little-endian bytes."""
        return struct.pack(
            RECORD_FORMAT,
            self.timestamp_ms,
            self.temp_c_x100,
            self.vib_x,
            self.vib_y,
            self.vib_z,
            self.vcc_mv,
            self.status_flags,
        )


DEFAULT_PROFILE_CONFIG: dict[str, dict[str, Any]] = {
    "quiescent": {
        "timestamp_step_ms": 10,
        "temp_base_x100": 2500,
        "temp_jitter": 1,
        "vib_jitter": 1,
        "vcc_base_mv": 3300,
        "vcc_jitter": 1,
        "status_flags": 0x0001,
    },
    "dynamic": {
        "timestamp_step_ms": 10,
        "timestamp_jitter_ms": 3,
        "temp_base_x100": 3800,
        "temp_amplitude": 800,
        "temp_jitter": 60,
        "vib_amplitude": 1400,
        "vib_jitter": 220,
        "vcc_base_mv": 3300,
        "vcc_droop_mv": 150,
        "vcc_jitter": 25,
        "status_flags_pool": [0x0001, 0x0003, 0x0005, 0x0007],
    },
    "chaotic": {
        "timestamp_step_min_ms": 1,
        "timestamp_step_max_ms": 50000,
        "temp_min_x100": -4000,
        "temp_max_x100": 12500,
        "vib_min": _INT16_MIN,
        "vib_max": _INT16_MAX,
        "vcc_min_mv": 1800,
        "vcc_max_mv": 5000,
        "status_flags_min": _UINT16_MIN,
        "status_flags_max": _UINT16_MAX,
    },
}


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))


def _validate_int_range(
    cfg: dict[str, Any],
    min_key: str,
    max_key: str,
    abs_low: int,
    abs_high: int,
    profile_key: str,
) -> None:
    lo = cfg[min_key]
    hi = cfg[max_key]
    if not isinstance(lo, int) or isinstance(lo, bool):
        raise ValueError(f"{profile_key}.{min_key} must be an integer")
    if not isinstance(hi, int) or isinstance(hi, bool):
        raise ValueError(f"{profile_key}.{max_key} must be an integer")
    if lo > hi:
        raise ValueError(f"{profile_key}: {min_key} ({lo}) > {max_key} ({hi})")
    if lo < abs_low or hi > abs_high:
        raise ValueError(
            f"{profile_key}: [{min_key}, {max_key}] must lie within [{abs_low}, {abs_high}]"
        )


def _validate_non_negative_int(cfg: dict[str, Any], key: str, profile_key: str) -> None:
    val = cfg[key]
    if not isinstance(val, int) or isinstance(val, bool) or val < 0:
        raise ValueError(f"{profile_key}.{key} must be a non-negative integer")


def _validate_positive_int(cfg: dict[str, Any], key: str, profile_key: str) -> None:
    val = cfg[key]
    if not isinstance(val, int) or isinstance(val, bool) or val <= 0:
        raise ValueError(f"{profile_key}.{key} must be a positive integer")


def _validate_int_bounds(
    cfg: dict[str, Any],
    key: str,
    abs_low: int,
    abs_high: int,
    profile_key: str,
) -> None:
    val = cfg[key]
    if not isinstance(val, int) or isinstance(val, bool) or val < abs_low or val > abs_high:
        raise ValueError(f"{profile_key}.{key} must be an integer in [{abs_low}, {abs_high}]")


def merge_profile_config(overrides: dict[str, Any] | None = None) -> dict[str, dict[str, Any]]:
    """Merge optional profile parameter overrides with defaults and validate invariants."""
    merged = deepcopy(DEFAULT_PROFILE_CONFIG)
    if overrides is None:
        return merged

    if not isinstance(overrides, dict):
        raise ValueError("Profile configuration root must be a JSON object")

    for profile_key, params in overrides.items():
        if profile_key not in merged:
            raise ValueError(f"Unknown profile in config: {profile_key!r}")
        if not isinstance(params, dict):
            raise ValueError(f"Config for profile {profile_key!r} must be a JSON object")
        for param_key, param_val in params.items():
            if param_key not in merged[profile_key]:
                raise ValueError(f"Unknown parameter {param_key!r} in profile {profile_key!r}")
            merged[profile_key][param_key] = param_val

    q = merged["quiescent"]
    _validate_positive_int(q, "timestamp_step_ms", "quiescent")
    _validate_int_bounds(q, "temp_base_x100", _INT16_MIN, _INT16_MAX, "quiescent")
    _validate_non_negative_int(q, "temp_jitter", "quiescent")
    _validate_non_negative_int(q, "vib_jitter", "quiescent")
    _validate_int_bounds(q, "vcc_base_mv", _UINT16_MIN, _UINT16_MAX, "quiescent")
    _validate_non_negative_int(q, "vcc_jitter", "quiescent")
    _validate_int_bounds(q, "status_flags", _UINT16_MIN, _UINT16_MAX, "quiescent")

    d = merged["dynamic"]
    _validate_positive_int(d, "timestamp_step_ms", "dynamic")
    _validate_non_negative_int(d, "timestamp_jitter_ms", "dynamic")
    _validate_int_bounds(d, "temp_base_x100", _INT16_MIN, _INT16_MAX, "dynamic")
    _validate_non_negative_int(d, "temp_amplitude", "dynamic")
    _validate_non_negative_int(d, "temp_jitter", "dynamic")
    _validate_non_negative_int(d, "vib_amplitude", "dynamic")
    _validate_non_negative_int(d, "vib_jitter", "dynamic")
    _validate_int_bounds(d, "vcc_base_mv", _UINT16_MIN, _UINT16_MAX, "dynamic")
    _validate_non_negative_int(d, "vcc_droop_mv", "dynamic")
    _validate_non_negative_int(d, "vcc_jitter", "dynamic")
    pool = d["status_flags_pool"]
    if not isinstance(pool, list) or not pool or not all(
        isinstance(x, int) and not isinstance(x, bool) and _UINT16_MIN <= x <= _UINT16_MAX
        for x in pool
    ):
        raise ValueError("dynamic.status_flags_pool must be a non-empty list of uint16 integers")

    c = merged["chaotic"]
    _validate_int_range(c, "timestamp_step_min_ms", "timestamp_step_max_ms", 1, 1_000_000, "chaotic")
    _validate_int_range(c, "temp_min_x100", "temp_max_x100", _INT16_MIN, _INT16_MAX, "chaotic")
    _validate_int_range(c, "vib_min", "vib_max", _INT16_MIN, _INT16_MAX, "chaotic")
    _validate_int_range(c, "vcc_min_mv", "vcc_max_mv", _UINT16_MIN, _UINT16_MAX, "chaotic")
    _validate_int_range(
        c, "status_flags_min", "status_flags_max", _UINT16_MIN, _UINT16_MAX, "chaotic"
    )

    return merged


def load_profile_config(config_path: str | Path | None) -> dict[str, dict[str, Any]]:
    """Load and validate an optional JSON configuration file."""
    if config_path is None:
        return merge_profile_config(None)

    path = Path(config_path)
    try:
        raw_text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ValueError(f"Unable to read config file {path}: {exc}") from exc

    try:
        parsed = json.loads(raw_text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in config file {path}: {exc}") from exc

    return merge_profile_config(parsed)


def _generate_quiescent_records(
    frame_index: int, rng: random.Random, cfg: dict[str, Any]
) -> list[TelemetryRecord]:
    step_ms = cfg["timestamp_step_ms"]
    base_ts = frame_index * RECORDS_PER_FRAME * step_ms
    records: list[TelemetryRecord] = []
    for idx in range(RECORDS_PER_FRAME):
        ts = (base_ts + idx * step_ms) & _UINT32_MAX
        temp = _clamp(
            cfg["temp_base_x100"] + rng.randint(-cfg["temp_jitter"], cfg["temp_jitter"]),
            _INT16_MIN,
            _INT16_MAX,
        )
        vx = _clamp(rng.randint(-cfg["vib_jitter"], cfg["vib_jitter"]), _INT16_MIN, _INT16_MAX)
        vy = _clamp(rng.randint(-cfg["vib_jitter"], cfg["vib_jitter"]), _INT16_MIN, _INT16_MAX)
        vz = _clamp(rng.randint(-cfg["vib_jitter"], cfg["vib_jitter"]), _INT16_MIN, _INT16_MAX)
        vcc = _clamp(
            cfg["vcc_base_mv"] + rng.randint(-cfg["vcc_jitter"], cfg["vcc_jitter"]),
            _UINT16_MIN,
            _UINT16_MAX,
        )
        flags = _clamp(cfg["status_flags"], _UINT16_MIN, _UINT16_MAX)
        records.append(TelemetryRecord(ts, temp, vx, vy, vz, vcc, flags))
    return records


def _generate_dynamic_records(
    frame_index: int, rng: random.Random, cfg: dict[str, Any]
) -> list[TelemetryRecord]:
    step_ms = cfg["timestamp_step_ms"]
    ts_jitter = cfg["timestamp_jitter_ms"]
    ts = (100_000 + frame_index * RECORDS_PER_FRAME * step_ms) & _UINT32_MAX
    pool = cfg["status_flags_pool"]
    records: list[TelemetryRecord] = []
    for idx in range(RECORDS_PER_FRAME):
        delta = max(1, step_ms + rng.randint(-ts_jitter, ts_jitter))
        ts = (ts + delta) & _UINT32_MAX
        phase = (frame_index * RECORDS_PER_FRAME + idx) * 0.25
        temp = _clamp(
            int(
                cfg["temp_base_x100"]
                + cfg["temp_amplitude"] * math.sin(phase * 0.35)
                + rng.randint(-cfg["temp_jitter"], cfg["temp_jitter"])
            ),
            _INT16_MIN,
            _INT16_MAX,
        )
        amp = cfg["vib_amplitude"]
        jit = cfg["vib_jitter"]
        vx = _clamp(int(amp * math.sin(phase)) + rng.randint(-jit, jit), _INT16_MIN, _INT16_MAX)
        vy = _clamp(
            int(amp * math.cos(phase * 1.3 + 0.7)) + rng.randint(-jit, jit),
            _INT16_MIN,
            _INT16_MAX,
        )
        vz = _clamp(
            int(amp * math.sin(phase * 1.9 + 1.4)) + rng.randint(-jit, jit),
            _INT16_MIN,
            _INT16_MAX,
        )
        load_factor = abs(math.sin(phase))
        vcc = _clamp(
            int(cfg["vcc_base_mv"] - cfg["vcc_droop_mv"] * load_factor)
            + rng.randint(-cfg["vcc_jitter"], cfg["vcc_jitter"]),
            _UINT16_MIN,
            _UINT16_MAX,
        )
        flags = pool[(idx // 8 + rng.randint(0, len(pool) - 1)) % len(pool)]
        records.append(TelemetryRecord(ts, temp, vx, vy, vz, vcc, flags))
    return records


def _generate_chaotic_records(
    frame_index: int, rng: random.Random, cfg: dict[str, Any]
) -> list[TelemetryRecord]:
    del frame_index
    ts = rng.randint(10_000, 0x7FFF_FFFF)
    records: list[TelemetryRecord] = []
    for _ in range(RECORDS_PER_FRAME):
        ts = (
            ts + rng.randint(cfg["timestamp_step_min_ms"], cfg["timestamp_step_max_ms"])
        ) & _UINT32_MAX
        temp = rng.randint(cfg["temp_min_x100"], cfg["temp_max_x100"])
        vx = rng.randint(cfg["vib_min"], cfg["vib_max"])
        vy = rng.randint(cfg["vib_min"], cfg["vib_max"])
        vz = rng.randint(cfg["vib_min"], cfg["vib_max"])
        vcc = rng.randint(cfg["vcc_min_mv"], cfg["vcc_max_mv"])
        flags = rng.randint(cfg["status_flags_min"], cfg["status_flags_max"])
        records.append(TelemetryRecord(ts, temp, vx, vy, vz, vcc, flags))
    return records


_PROFILE_GENERATORS = {
    EntropyProfile.QUIESCENT: _generate_quiescent_records,
    EntropyProfile.DYNAMIC: _generate_dynamic_records,
    EntropyProfile.CHAOTIC: _generate_chaotic_records,
}


def generate_frame_payload(
    profile: EntropyProfile,
    frame_index: int,
    rng: random.Random,
    config: dict[str, dict[str, Any]] | None = None,
) -> bytes:
    """Synthesize a fixed 1024-byte Telemetry Frame payload (64 packed records)."""
    if frame_index < 0:
        raise ValueError(f"frame_index must be >= 0, got {frame_index}")

    resolved_cfg = config if config is not None else merge_profile_config(None)
    generator = _PROFILE_GENERATORS[profile]
    records = generator(frame_index, rng, resolved_cfg[profile.key])
    payload = b"".join(record.pack() for record in records)
    if len(payload) != PAYLOAD_SIZE:
        raise AssertionError(f"Expected {PAYLOAD_SIZE} bytes, generated {len(payload)}")
    return payload


def generate_dataset(
    seed: int = 42,
    frames_per_profile: int = 10,
    config: dict[str, dict[str, Any]] | None = None,
) -> list[tuple[EntropyProfile, bytes]]:
    """Generate the ordered Embedded Dataset across Quiescent, Dynamic, and Chaotic profiles."""
    if not isinstance(frames_per_profile, int) or isinstance(frames_per_profile, bool):
        raise ValueError("frames_per_profile must be an integer")
    if frames_per_profile < 1:
        raise ValueError(f"frames_per_profile must be >= 1, got {frames_per_profile}")

    resolved_cfg = config if config is not None else merge_profile_config(None)
    rng = random.Random(seed)
    dataset: list[tuple[EntropyProfile, bytes]] = []
    for profile in (EntropyProfile.QUIESCENT, EntropyProfile.DYNAMIC, EntropyProfile.CHAOTIC):
        for frame_idx in range(frames_per_profile):
            payload = generate_frame_payload(profile, frame_idx, rng, resolved_cfg)
            dataset.append((profile, payload))
    return dataset
