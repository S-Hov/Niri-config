#!/usr/bin/env python3
"""Safe userspace fan curve for Lenovo 83LV using upstream lenovo_wmi_other."""

from __future__ import annotations

import argparse
import json
import logging
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

PRODUCT = "83LV"
HWMON_NAME = "lenovo_wmi_other"
DEFAULT_CONFIG = Path("/etc/legion-fan-curve.json")
NVIDIA_PCI = Path("/sys/bus/pci/devices/0000:01:00.0/power/runtime_status")


@dataclass(frozen=True)
class Fan:
    name: str
    input_path: Path
    target_path: Path
    minimum: int
    maximum: int


def read_text(path: Path) -> str:
    return path.read_text(encoding="ascii").strip()


def read_int(path: Path) -> int:
    return int(read_text(path))


def validate_machine() -> None:
    product = read_text(Path("/sys/class/dmi/id/product_name"))
    if product != PRODUCT:
        raise RuntimeError(f"expected Lenovo {PRODUCT}, detected {product!r}")


def find_hwmon(name: str) -> Path:
    for path in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
        try:
            if read_text(path / "name") == name:
                return path
        except (OSError, ValueError):
            continue
    raise RuntimeError(f"hwmon device {name!r} was not found")


def discover_fans() -> list[Fan]:
    hwmon = find_hwmon(HWMON_NAME)
    fans: list[Fan] = []
    for input_path in sorted(hwmon.glob("fan*_input")):
        stem = input_path.name.removesuffix("_input")
        target_path = hwmon / f"{stem}_target"
        min_path = hwmon / f"{stem}_min"
        max_path = hwmon / f"{stem}_max"
        if not all(path.exists() for path in (target_path, min_path, max_path)):
            continue
        minimum, maximum = read_int(min_path), read_int(max_path)
        if minimum < 500 or maximum <= minimum or maximum > 10000:
            raise RuntimeError(f"unsafe constraints for {stem}: {minimum}..{maximum}")
        fans.append(Fan(stem, input_path, target_path, minimum, maximum))
    if len(fans) != 3:
        raise RuntimeError(f"expected 3 constrained WMI fans, found {len(fans)}")
    return fans


def discover_temperature(name: str, label: str) -> Path | None:
    try:
        hwmon = find_hwmon(name)
    except RuntimeError:
        return None
    for input_path in sorted(hwmon.glob("temp*_input")):
        label_path = input_path.with_name(input_path.name.replace("_input", "_label"))
        try:
            if label_path.exists() and read_text(label_path).lower() == label.lower():
                return input_path
        except OSError:
            continue
    return None


def read_temperature(path: Path | None) -> float | None:
    if path is None:
        return None
    try:
        value = read_int(path) / 1000.0
    except (OSError, ValueError):
        return None
    return value if 0.0 < value < 120.0 else None


def nvidia_temperature() -> float | None:
    try:
        if NVIDIA_PCI.exists() and read_text(NVIDIA_PCI) == "suspended":
            return None
        result = subprocess.run(
            [
                "/usr/bin/nvidia-smi",
                "--query-gpu=temperature.gpu",
                "--format=csv,noheader,nounits",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=2.0,
        )
        if result.returncode != 0:
            return None
        value = float(result.stdout.splitlines()[0].strip())
        return value if 0.0 < value < 120.0 else None
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
        return None


def load_config(path: Path) -> dict:
    config = json.loads(path.read_text(encoding="utf-8"))
    curve = config.get("curve")
    if not isinstance(curve, list) or len(curve) < 2:
        raise ValueError("curve must contain at least two points")
    previous_temp = -1.0
    previous_percent = -1.0
    for point in curve:
        if not isinstance(point, list) or len(point) != 2:
            raise ValueError("every curve point must be [temperature, percent]")
        temp, percent = map(float, point)
        if temp <= previous_temp or percent < previous_percent:
            raise ValueError("curve temperatures must increase and speed must not decrease")
        if not 0.0 <= percent <= 100.0:
            raise ValueError("curve percentage must be in 0..100")
        previous_temp, previous_percent = temp, percent
    if float(curve[-1][1]) != 100.0:
        raise ValueError("last curve point must request 100 percent")
    emergency = float(config["emergency_temperature_c"])
    if not 80.0 <= emergency <= 95.0:
        raise ValueError("emergency temperature must be in 80..95 C")
    return config


def interpolate(curve: list[list[float]], temperature: float) -> float:
    points = [(float(t), float(p)) for t, p in curve]
    if temperature <= points[0][0]:
        return points[0][1]
    for (t0, p0), (t1, p1) in zip(points, points[1:]):
        if temperature <= t1:
            ratio = (temperature - t0) / (t1 - t0)
            return p0 + ratio * (p1 - p0)
    return points[-1][1]


def target_for(fan: Fan, percent: float) -> int:
    target = fan.minimum + (fan.maximum - fan.minimum) * percent / 100.0
    return max(fan.minimum, min(fan.maximum, int(target // 100 * 100)))


def set_targets(fans: list[Fan], targets: list[int]) -> None:
    if len(fans) != len(targets):
        raise ValueError("fan/target count mismatch")
    written: list[Fan] = []
    try:
        for fan, target in zip(fans, targets):
            fan.target_path.write_text(f"{target}\n", encoding="ascii")
            written.append(fan)
    except Exception:
        for fan in written:
            try:
                fan.target_path.write_text("0\n", encoding="ascii")
            except OSError:
                pass
        raise


def reset_to_auto(fans: list[Fan] | None = None) -> None:
    candidates = fans
    if candidates is None:
        try:
            candidates = discover_fans()
        except Exception as error:
            logging.error("cannot discover fans for reset: %s", error)
            return
    for fan in candidates:
        try:
            fan.target_path.write_text("0\n", encoding="ascii")
        except OSError as error:
            logging.error("cannot reset %s: %s", fan.name, error)


def preflight() -> int:
    validate_machine()
    fans = discover_fans()
    logging.info("testing constrained WMI fan targets")
    try:
        targets = [target_for(fan, 50.0) for fan in fans]
        set_targets(fans, targets)
        time.sleep(5.0)
        for fan, target in zip(fans, targets):
            readback = read_int(fan.target_path)
            actual = read_int(fan.input_path)
            logging.info("%s target=%d readback=%d actual=%d", fan.name, target, readback, actual)
            if readback != target or actual <= 0:
                raise RuntimeError(f"preflight verification failed for {fan.name}")
        return 0
    finally:
        reset_to_auto(fans)


def run(config_path: Path) -> int:
    validate_machine()
    config = load_config(config_path)
    fans = discover_fans()
    cpu_path = discover_temperature("k10temp", "Tctl")
    igpu_path = discover_temperature("amdgpu", "edge")
    if cpu_path is None:
        raise RuntimeError("required CPU Tctl sensor was not found")

    stopping = False

    def request_stop(signum: int, _frame: object) -> None:
        nonlocal stopping
        logging.info("received signal %d; returning fans to firmware auto", signum)
        stopping = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    filtered: float | None = None
    last_targets: list[int] | None = None
    last_write = 0.0
    last_log = 0.0
    last_nvidia_poll = 0.0
    cached_nvidia: float | None = None
    sensor_failures = 0

    poll = float(config["poll_seconds"])
    refresh = float(config["refresh_seconds"])
    nvidia_poll = float(config["nvidia_poll_seconds"])
    fall_alpha = float(config["fall_smoothing"])
    log_interval = float(config["log_interval_seconds"])
    emergency = float(config["emergency_temperature_c"])
    if not 0.5 <= poll <= 10.0 or not 5.0 <= refresh <= 60.0:
        raise ValueError("unsafe polling/refresh interval")
    if not 0.05 <= fall_alpha <= 1.0:
        raise ValueError("fall_smoothing must be in 0.05..1.0")

    logging.info("controller started for %s with %d fans", PRODUCT, len(fans))
    try:
        while not stopping:
            now = time.monotonic()
            cpu = read_temperature(cpu_path)
            igpu = read_temperature(igpu_path)
            if now - last_nvidia_poll >= nvidia_poll:
                cached_nvidia = nvidia_temperature()
                last_nvidia_poll = now

            temperatures = [value for value in (cpu, igpu, cached_nvidia) if value is not None]
            if cpu is None or not temperatures:
                sensor_failures += 1
                if sensor_failures >= 3:
                    raise RuntimeError("required temperature sensor failed three times")
                time.sleep(poll)
                continue
            sensor_failures = 0
            raw_max = max(temperatures)
            if filtered is None or raw_max >= filtered:
                filtered = raw_max
            else:
                filtered += fall_alpha * (raw_max - filtered)

            percent = 100.0 if raw_max >= emergency else interpolate(config["curve"], filtered)
            targets = [target_for(fan, percent) for fan in fans]
            if targets != last_targets or now - last_write >= refresh:
                set_targets(fans, targets)
                last_targets = targets
                last_write = now

            if now - last_log >= log_interval:
                actual = [read_int(fan.input_path) for fan in fans]
                logging.info(
                    "cpu=%.1f igpu=%s nvidia=%s control=%.1f speed=%.1f%% target=%s actual=%s",
                    cpu,
                    f"{igpu:.1f}" if igpu is not None else "n/a",
                    f"{cached_nvidia:.1f}" if cached_nvidia is not None else "n/a",
                    filtered,
                    percent,
                    targets,
                    actual,
                )
                last_log = now
            time.sleep(poll)
        return 0
    finally:
        reset_to_auto(fans)
        logging.info("fans returned to firmware auto")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--reset", action="store_true")
    group.add_argument("--preflight", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if args.reset:
        validate_machine()
        reset_to_auto()
        return 0
    if args.preflight:
        return preflight()
    return run(args.config)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        logging.exception("fatal controller error: %s", error)
        raise SystemExit(1)

