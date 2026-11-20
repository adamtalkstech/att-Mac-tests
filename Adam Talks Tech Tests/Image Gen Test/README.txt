ATT IMAGE TESTS
================

Copy this whole folder to the test SSD. Format the SSD as APFS and keep the
same drive name on every Mac (the frozen software remembers its path).

ONE TIME (Mac Studio, with internet)
1. Double-click "Prep This Drive.command". It puts uv, Python, the frozen
   mflux software and the Z-Image Turbo model on the drive (several GB).
2. Fill in diffusionbee_settings.json from the Diffusion Bee app.
3. Open Draw Things, pick the test model, turn on Settings > API Server
   (HTTP, port 7860). Run "Run Image Tests.command", option 4. Copy the model
   name and app version into drawthings_settings.json.
   (Also install the model on each Mac; Draw Things keeps models inside the app.)

ON EACH MAC
- Plug in power, Low Power Mode off, cool Mac.
- Double-click "Run Image Tests.command" and pick a test.
  1  mflux standard + stress (fully automatic, about the length of a coffee)
  2  adds the full precision RAM test
  3  Draw Things (app open, API server on, test model selected)
  5  Diffusion Bee (it walks you through it, you type the 3 times)

First time on a Mac, macOS may block the .command file: right-click > Open.

RESULTS (in results/ on the drive)
- runs_log.csv   every run, same columns as the sheet's Runs Log tab
- summary.csv    one row per Mac per test: chip, GPU cores, RAM, macOS,
                 power, median, spread
- images/        first image of each test, to check every Mac made the same one
- session_*.json full detail

Every test: 1 warm-up (never counted), 3 timed runs, 2 more if they're over
5% apart, median reported. Seed 42, same prompt as always:
"a cat working on a laptop with nachos on the side"
