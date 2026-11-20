# /// script
# requires-python = ">=3.11,<3.14"
# dependencies = ["mflux==0.24.0"]
#
# [tool.uv]
# # Freezes every dependency (MLX included) to what existed on this date,
# # so every Mac gets the exact same software stack.
# exclude-newer = "2026-11-12T00:00:00Z"
# ///
"""
ATT image gen test, mflux (v1). Fully scripted, runs on the GPU through MLX.

Same prompt as Diffusion Bee, fixed model, size, steps and seed. Times only
the image generation; model load and one warm-up run are logged separately
and never counted.

  --prefetch   download the model onto the drive and exit (used by prep)
  --dry-run    fake generation to check the logging
"""

import argparse
import datetime as dt
import json
import platform
import sys
import time

import att_bench_common as c

BENCH_VERSION = "att-imagegen-mflux v1"
MODEL_NAME = "Z-Image Turbo"

# Locked settings. Change only by bumping BENCH_VERSION.
TESTS = {
    "standard": dict(width=1024, height=1024, steps=9, quantize=8),
    "stress": dict(width=2048, height=2048, steps=9, quantize=8),
    "fullprecision": dict(width=1024, height=1024, steps=9, quantize=None),
}


def version_of(name):
    try:
        from importlib.metadata import version
        return version(name)
    except Exception:
        return "unknown"


class Generator:
    def __init__(self, dry_run=False):
        self.dry_run, self.models = dry_run, {}

    def load(self, quantize):
        if quantize in self.models:
            return 0.0
        t0 = time.perf_counter()
        if self.dry_run:
            time.sleep(0.1)
            self.models[quantize] = "dry"
        else:
            from mflux.models.z_image import ZImageTurbo
            self.models[quantize] = ZImageTurbo(quantize=quantize)
        return time.perf_counter() - t0

    def generate(self, cfg, save_path=None):
        model = self.models[cfg["quantize"]]
        t0 = time.perf_counter()
        if self.dry_run:
            time.sleep(0.05 * cfg["width"] / 1024)
            return time.perf_counter() - t0
        image = model.generate_image(prompt=c.PROMPT, seed=c.SEED,
                                     num_inference_steps=cfg["steps"],
                                     width=cfg["width"], height=cfg["height"])
        elapsed = time.perf_counter() - t0  # image is fully decoded here
        if save_path:
            image.save(str(save_path))
        return elapsed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tests", default="standard,stress")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--mac-name")
    ap.add_argument("--condition", default="")
    ap.add_argument("--notes", default="")
    ap.add_argument("--cooldown", type=int, default=30)
    ap.add_argument("--prefetch", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if a.prefetch:
        print("Downloading Z-Image Turbo onto the drive (one time, several GB)...")
        Generator(a.dry_run).load(8)
        print("Model is on the drive.")
        return

    tests = [t.strip() for t in a.tests.split(",") if t.strip()]
    if any(t not in TESTS for t in tests):
        sys.exit(f"Tests must be from {list(TESTS)}")
    if not a.dry_run and (platform.system() != "Darwin" or platform.machine() != "arm64"):
        sys.exit("This test needs an Apple silicon Mac.")

    c.keep_awake()
    info = c.machine_info()
    mac = a.mac_name or info.get("mac_name", "unknown")
    app_version = f"mflux {version_of('mflux')} / mlx {version_of('mlx')}"
    c.print_header(f"ATT Image Gen Test - mflux ({BENCH_VERSION})", mac, info, app_version)
    stamp = dt.datetime.now()
    (c.RESULTS_DIR / "images").mkdir(parents=True, exist_ok=True)

    gen = Generator(a.dry_run)
    session = {"bench": BENCH_VERSION, "mac": mac, "machine": info, "tests": []}

    for i, test in enumerate(tests):
        cfg = TESTS[test]
        q = cfg["quantize"]
        print(f"=== mflux {test}: {cfg['width']}x{cfg['height']}, {cfg['steps']} steps, "
              f"{'8-bit' if q else 'full precision'} ===")
        log = c.Logger(mac, f"imagegen-mflux-{test}", app_version, BENCH_VERSION, a.condition)
        result = {"status": "ok"}
        try:
            load_s = gen.load(q)
            print(f"  model load: {load_s:.1f}s")
            warm = gen.generate(cfg)
            log.run("warmup", warm, "not counted")
            print(f"  warm-up (not counted): {warm:.2f}s")
            img = c.RESULTS_DIR / "images" / f"{c.safe_name(mac)}_mflux_{test}_{stamp:%Y%m%d-%H%M}.png"
            result = c.timed_series(
                lambda n: gen.generate(cfg, save_path=img if n == 1 and not a.dry_run else None),
                a.runs, log)
            result.update(load_s=round(load_s, 2), warmup_s=round(warm, 2))
        except Exception as e:  # out of memory, missing model, etc.
            result = {"status": f"FAILED: {type(e).__name__}: {e}"[:300]}
            log.run("failed", 0.0, result["status"])
            print(f"  {result['status']}\n")
        log.summary(info, "mflux", MODEL_NAME, cfg["width"], cfg["height"], cfg["steps"],
                    q if q else "none", result, a.notes)
        session["tests"].append({"test": test, **cfg, **result})
        if i < len(tests) - 1 and a.cooldown and not a.dry_run:
            print(f"Cooling down {a.cooldown}s...\n")
            time.sleep(a.cooldown)

    (c.RESULTS_DIR / f"session_mflux_{c.safe_name(mac)}_{stamp:%Y%m%d-%H%M%S}.json").write_text(
        json.dumps(session, indent=2, default=str))
    print("=== For the Mac Tests sheet (median seconds) ===")
    for r in session["tests"]:
        print(f"  {mac}  mflux {r['test']}: {r.get('median_s', r['status'])}")


if __name__ == "__main__":
    main()
