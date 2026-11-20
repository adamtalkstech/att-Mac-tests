# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
ATT image gen test, Draw Things (v1).

Talks to the Draw Things app through its built-in API server (Settings >
API Server / HTTP Server, port 7860). Draw Things must be open with the
server on and the test model selected. Times each image from request to
finished image.

  --show-config   print and save the app's current settings (for the card)
  --dry-run       fake the server to check the logging
"""

import argparse
import base64
import datetime as dt
import json
import sys
import time
import urllib.error
import urllib.request

import att_bench_common as c

BENCH_VERSION = "att-imagegen-drawthings v1"
SETTINGS_FILE = c.KIT_DIR / "drawthings_settings.json"


def http(method, url, payload=None, timeout=900):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read() or b"{}")


class Server:
    def __init__(self, base, dry_run=False):
        self.base, self.dry_run = base.rstrip("/"), dry_run

    def config(self):
        if self.dry_run:
            return {"model": "dry_model.ckpt", "steps": 8}
        return http("GET", self.base + "/")

    def txt2img(self, payload):
        if self.dry_run:
            time.sleep(0.05)
            return {"images": []}
        return http("POST", self.base + "/sdapi/v1/txt2img", payload)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tests", default="standard,stress")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--mac-name")
    ap.add_argument("--condition", default="")
    ap.add_argument("--notes", default="")
    ap.add_argument("--url", default="http://127.0.0.1:7860")
    ap.add_argument("--cooldown", type=int, default=30)
    ap.add_argument("--show-config", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    srv = Server(a.url, a.dry_run)
    try:
        cfg_now = srv.config()
    except (urllib.error.URLError, ConnectionError, TimeoutError) as e:
        sys.exit(f"Can't reach Draw Things at {a.url} ({e}).\n"
                 "Open Draw Things, turn on Settings > API Server (HTTP, port 7860), "
                 "and select the test model.")

    info = c.machine_info()
    mac = a.mac_name or info.get("mac_name", "unknown")

    if a.show_config:
        out = c.RESULTS_DIR / f"drawthings_config_{c.safe_name(mac)}.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(cfg_now, indent=2))
        print(json.dumps(cfg_now, indent=2))
        print(f"\nSaved to {out}")
        return

    settings = json.loads(SETTINGS_FILE.read_text())
    tests = [t.strip() for t in a.tests.split(",") if t.strip()]
    missing = [t for t in tests if t not in settings["tests"]]
    if missing:
        sys.exit(f"{missing} not in drawthings_settings.json")

    loaded_model = str(cfg_now.get("model", "unknown"))
    want = settings.get("model", "")
    if want and want != loaded_model:
        sys.exit(f"Draw Things has '{loaded_model}' selected, the settings card says "
                 f"'{want}'. Pick the right model in the app and run again.")

    c.keep_awake()
    app_version = f"Draw Things {settings.get('app_version', '?')} / {loaded_model}"
    c.print_header(f"ATT Image Gen Test - Draw Things ({BENCH_VERSION})", mac, info, app_version)
    stamp = dt.datetime.now()
    (c.RESULTS_DIR / "images").mkdir(parents=True, exist_ok=True)

    for i, test in enumerate(tests):
        t = settings["tests"][test]
        payload = {"prompt": c.PROMPT, "negative_prompt": "", "seed": c.SEED,
                   "width": t["width"], "height": t["height"], "steps": t["steps"],
                   "batch_size": 1, "batch_count": 1, **settings.get("extra", {})}
        print(f"=== Draw Things {test}: {t['width']}x{t['height']}, {t['steps']} steps, "
              f"{loaded_model} ===")
        log = c.Logger(mac, f"imagegen-drawthings-{test}", app_version, BENCH_VERSION,
                       a.condition)
        img_path = c.RESULTS_DIR / "images" / \
            f"{c.safe_name(mac)}_drawthings_{test}_{stamp:%Y%m%d-%H%M}.png"

        def run_once(n, save=False):
            t0 = time.perf_counter()
            resp = srv.txt2img(payload)
            elapsed = time.perf_counter() - t0
            imgs = resp.get("images") or []
            if not imgs and not a.dry_run:
                raise RuntimeError(f"No image returned: {str(resp)[:200]}")
            if save and imgs:
                img_path.write_bytes(base64.b64decode(imgs[0]))
            return elapsed

        result = {"status": "ok"}
        try:
            warm = run_once(0)
            log.run("warmup", warm, "not counted")
            print(f"  warm-up (not counted): {warm:.2f}s")
            result = c.timed_series(lambda n: run_once(n, save=(n == 1)), a.runs, log)
            result["warmup_s"] = round(warm, 2)
        except Exception as e:
            result = {"status": f"FAILED: {type(e).__name__}: {e}"[:300]}
            log.run("failed", 0.0, result["status"])
            print(f"  {result['status']}\n")
        log.summary(info, "Draw Things", loaded_model, t["width"], t["height"], t["steps"],
                    settings.get("quantize_note", ""), result, a.notes)
        print(f"  {mac}  Draw Things {test}: {result.get('median_s', result['status'])}\n")
        if i < len(tests) - 1 and a.cooldown and not a.dry_run:
            print(f"Cooling down {a.cooldown}s...\n")
            time.sleep(a.cooldown)


if __name__ == "__main__":
    main()
