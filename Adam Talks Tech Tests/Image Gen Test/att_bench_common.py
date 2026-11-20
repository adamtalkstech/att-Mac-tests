"""
Shared pieces for the ATT image tests: machine info, the kit folder,
and logging to the same CSVs so every test lands in one place.

Every result goes to:
  results/runs_log.csv  one row per run (matches the sheet's Runs Log tab)
  results/summary.csv   one row per Mac per test (median etc.)
"""

import csv
import datetime as dt
import json
import os
import platform
import statistics
import subprocess
from pathlib import Path

PROMPT = "a cat working on a laptop with nachos on the side"
SEED = 42
VARIANCE_LIMIT = 0.05  # spread over 5% of the median = add 2 runs (once)

KIT_DIR = Path(__file__).resolve().parent
RESULTS_DIR = Path(os.environ.get("ATT_RESULTS_DIR", KIT_DIR / "results"))

RUNS_HEADER = ["date", "time", "mac", "test", "run", "value", "unit",
               "condition", "app_version", "bench_version", "source", "notes"]

SUMMARY_HEADER = ["date", "mac", "model_id", "chip", "cpu_cores", "gpu_cores",
                  "ram_gb", "macos", "power", "low_power_mode", "test", "app",
                  "model", "width", "height", "steps", "quantize", "seed",
                  "load_s", "warmup_s", "runs_s", "median_s", "min_s", "max_s",
                  "spread_pct", "status", "app_version", "bench_version",
                  "condition", "source", "notes"]


def sh(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout.strip()
    except Exception:
        return ""


def machine_info():
    if platform.system() != "Darwin":
        return {"mac_name": platform.node()}
    info = {
        "mac_name": sh(["scutil", "--get", "ComputerName"]) or platform.node(),
        "model_id": sh(["sysctl", "-n", "hw.model"]),
        "chip": sh(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "cpu_cores": sh(["sysctl", "-n", "hw.ncpu"]),
        "ram_gb": "",
        "gpu_cores": "",
        "macos": sh(["sw_vers", "-productVersion"]),
        "macos_build": sh(["sw_vers", "-buildVersion"]),
        "power": "",
        "low_power_mode": "",
    }
    mem = sh(["sysctl", "-n", "hw.memsize"])
    if mem.isdigit():
        info["ram_gb"] = str(round(int(mem) / 1024**3))
    try:
        disp = json.loads(sh(["system_profiler", "SPDisplaysDataType", "-json"]) or "{}")
        for gpu in disp.get("SPDisplaysDataType", []):
            if gpu.get("sppci_cores"):
                info["gpu_cores"] = str(gpu["sppci_cores"])
                break
    except Exception:
        pass
    batt = sh(["pmset", "-g", "batt"])
    if "AC Power" in batt:
        info["power"] = "AC"
    elif "Battery Power" in batt:
        info["power"] = "BATTERY"
    for line in sh(["pmset", "-g"]).splitlines():
        if "lowpowermode" in line:
            info["low_power_mode"] = line.split()[-1]
    return info


def keep_awake():
    """Stop the Mac sleeping until this script exits."""
    if platform.system() == "Darwin":
        subprocess.Popen(["caffeinate", "-dims", "-w", str(os.getpid())])


def print_header(title, mac, info, app_version):
    print(f"\n{title}")
    print(f"Mac: {mac} | {info.get('chip','')} | GPU cores {info.get('gpu_cores','?')} | "
          f"{info.get('ram_gb','?')}GB | macOS {info.get('macos','')} | power {info.get('power','?')}")
    print(f"Software: {app_version}")
    if info.get("power") == "BATTERY":
        print("WARNING: running on battery. Plug in for comparable results.")
    if info.get("low_power_mode") == "1":
        print("WARNING: Low Power Mode is on. Turn it off for comparable results.")
    print(f"Results folder: {RESULTS_DIR}\n")


def safe_name(s):
    return "".join(c if c.isalnum() or c in "-_" else "_" for c in s)


def _append(path, header, row):
    path.parent.mkdir(parents=True, exist_ok=True)
    new = not path.exists()
    with path.open("a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(header)
        w.writerow(row)


class Logger:
    def __init__(self, mac, test, app_version, bench_version, condition="",
                 source="script"):
        self.mac, self.test = mac, test
        self.app_version, self.bench_version = app_version, bench_version
        self.condition, self.source = condition, source

    def run(self, run_label, value, notes=""):
        now = dt.datetime.now()
        _append(RESULTS_DIR / "runs_log.csv", RUNS_HEADER, [
            now.strftime("%Y-%m-%d"), now.strftime("%H:%M:%S"), self.mac, self.test,
            run_label, f"{value:.2f}", "s", self.condition, self.app_version,
            self.bench_version, self.source, notes])

    def summary(self, info, app, model, width, height, steps, quantize, result, notes=""):
        _append(RESULTS_DIR / "summary.csv", SUMMARY_HEADER, [
            dt.date.today().isoformat(), self.mac, info.get("model_id", ""),
            info.get("chip", ""), info.get("cpu_cores", ""), info.get("gpu_cores", ""),
            info.get("ram_gb", ""), info.get("macos", ""), info.get("power", ""),
            info.get("low_power_mode", ""), self.test, app, model, width, height,
            steps, quantize, SEED, result.get("load_s", ""), result.get("warmup_s", ""),
            " ".join(f"{t:.2f}" for t in result.get("runs", [])),
            result.get("median_s", ""), result.get("min_s", ""), result.get("max_s", ""),
            result.get("spread_pct", ""), result.get("status", ""), self.app_version,
            self.bench_version, self.condition, self.source, notes])


def stats(times):
    med = statistics.median(times)
    spread = (max(times) - min(times)) / med if med else 0.0
    return med, spread


def timed_series(run_once, runs, log, label_prefix="  "):
    """Run `run_once()` (returns seconds) `runs` times, add 2 more if the
    spread is over 5%. Returns a result dict."""
    times = []

    def one(n):
        t = run_once(n)
        times.append(t)
        log.run(str(n), t)
        print(f"{label_prefix}run {n}: {t:.2f}s")

    for n in range(1, runs + 1):
        one(n)
    med, spread = stats(times)
    status = "ok"
    if len(times) >= 2 and spread > VARIANCE_LIMIT:
        print(f"{label_prefix}spread {spread:.1%} is over 5%, adding 2 runs")
        for n in range(len(times) + 1, len(times) + 3):
            one(n)
        med, spread = stats(times)
        if spread > VARIANCE_LIMIT:
            status = "high variance"
    print(f"{label_prefix}MEDIAN: {med:.2f}s  (spread {spread:.1%})\n")
    return {"runs": times, "median_s": round(med, 2), "min_s": round(min(times), 2),
            "max_s": round(max(times), 2), "spread_pct": round(spread * 100, 1),
            "status": status}
