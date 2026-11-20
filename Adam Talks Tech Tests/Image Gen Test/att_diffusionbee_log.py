# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
ATT image gen test, Diffusion Bee (manual, v1).

Diffusion Bee can't be scripted, so this walks you through the run and logs
the times you type in, into the same CSVs as the scripted tests.
Settings card: diffusionbee_settings.json
"""

import argparse
import json
import statistics
import sys

import att_bench_common as c

BENCH_VERSION = "att-imagegen-diffusionbee v1 (manual)"
SETTINGS_FILE = c.KIT_DIR / "diffusionbee_settings.json"


def ask_time(label):
    while True:
        raw = input(f"  {label} time in seconds (as shown in Diffusion Bee): ").strip()
        try:
            v = float(raw.rstrip("s"))
            if v > 0:
                return v
        except ValueError:
            pass
        print("  Type just the number, like 9.97")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--mac-name")
    ap.add_argument("--condition", default="")
    ap.add_argument("--notes", default="")
    a = ap.parse_args()

    s = json.loads(SETTINGS_FILE.read_text())
    unfilled = [k for k in ("app_version", "model", "image_size", "steps", "guidance_scale")
                if str(s.get(k, "")).startswith("FILL")]
    info = c.machine_info()
    mac = a.mac_name or info.get("mac_name", "unknown")
    app_version = f"Diffusion Bee {s.get('app_version')}"
    c.print_header(f"ATT Image Gen Test - Diffusion Bee ({BENCH_VERSION})", mac, info, app_version)
    if unfilled:
        print(f"NOTE: settings card not filled in yet: {', '.join(unfilled)}\n")

    print("Set Diffusion Bee to EXACTLY this before starting:")
    print(f"  Prompt:          {c.PROMPT}")
    print(f"  Negative prompt: (empty)")
    for k in ("model", "image_size", "steps", "guidance_scale"):
        print(f"  {k.replace('_', ' ').title():<16} {s.get(k)}")
    print(f"  Seed:            {c.SEED}")
    print("  Images:          1")
    print("\n1. Do ONE throwaway generation now (loads the model). Don't log it.")
    input("   Press Return when the throwaway image is done...")

    log = c.Logger(mac, "imagegen-diffusionbee", app_version, BENCH_VERSION,
                   a.condition, source="manual")
    print(f"\n2. Now generate {a.runs} times, back to back, and type each time:")
    times = []
    for n in range(1, a.runs + 1):
        t = ask_time(f"Run {n}")
        times.append(t)
        log.run(str(n), t)

    med, spread = c.stats(times)
    status = "ok"
    if spread > c.VARIANCE_LIMIT:
        print(f"\n  Spread is {spread:.1%} (over 5%). Do 2 more runs:")
        for n in range(len(times) + 1, len(times) + 3):
            t = ask_time(f"Run {n}")
            times.append(t)
            log.run(str(n), t)
        med, spread = c.stats(times)
        if spread > c.VARIANCE_LIMIT:
            status = "high variance"

    w, _, h = str(s.get("image_size", "")).partition("x")
    result = {"runs": times, "median_s": round(med, 2), "min_s": round(min(times), 2),
              "max_s": round(max(times), 2), "spread_pct": round(spread * 100, 1),
              "status": status}
    log.summary(info, "Diffusion Bee", s.get("model"), w, h, s.get("steps"), "",
                result, a.notes)
    print(f"\nMEDIAN: {med:.2f}s  (spread {spread:.1%}, {status})")
    print(f"For column AG on {mac}: {med:.2f}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nStopped. Runs typed so far are already in runs_log.csv.")
