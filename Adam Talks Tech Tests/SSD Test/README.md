# ATT SSD Test Suite v1.0

You run one script from Terminal. It runs the same tests with the same settings on every drive and saves the results to a CSV.

## One-time setup (per Mac)

1. Install fio: `brew install fio`
2. Optional, for drive temperatures: `brew install smartmontools`. Many USB enclosures won't report a temp, and that's fine.
3. Copy this "SSD Test" folder into the Mac's Downloads.

## Running it

```
zsh ~/Downloads/"SSD Test"/att-ssd-test.zsh
```

It lists your external drives so you can pick one. Then it asks for the drive name, port and cable. At the end it asks whether the drive works with iPhone and iPad, plus any notes.

Full version, with your copy tests:

```
zsh ~/Downloads/"SSD Test"/att-ssd-test.zsh --volume /Volumes/U35 --name "Oyen U35 Bolt Plus 4TB" \
  --source "/path/to/ATT SSD Testset 100GB" --source "/path/to/ATT SSD Testset 500GB"
```

Quick check (1 run, no sustained write, no copies, about 5 minutes):

```
zsh ~/Downloads/"SSD Test"/att-ssd-test.zsh --quick
```

It asks for your password once so it can clear the Mac's file cache between tests. Otherwise the reads would come from RAM and look fake.

## What it tests

| # | Test | What it shows | Sheet column |
|---|------|---------------|--------------|
| 1 | Sequential write + read: 5GB file, 1MB blocks, 3 runs, median logged | Same kind of number as Blackmagic and AJA | Write / Read |
| 2 | Random 4K at QD1 and QD32, 30s each | How snappy it feels for apps, libraries and lots of small files | New |
| 3 | Sustained 500GB write, speed logged every second | Where the fast cache runs out, the speed after that, and heat slowdown in the last minute | New |
| 4 | Real-world copies of your test folders (optional `--readback` copies them back too) | Your 100GB / 500GB transfer times | 100GB / 500GB Transfer |

It also records the host Mac, chip, RAM, macOS version, link speed, port, cable, file system, free space and drive temps.

## Where results go

`Desktop > ATT SSD Tests`
- `att-ssd-results.csv` gets one row per run, every drive, ready to paste into the sheet
- `runs/<date>_<drive>/` holds the summary, raw fio files, and `sustained-per-second.csv`, which is ready to chart (speed over GB written)

## Rules for official runs (so drives compare fairly)

- Use one reference Mac and the same port for every drive. The script logs both.
- Plug it in. Reboot, wait 2 minutes, and close everything else.
- Format the drive APFS and test it mostly empty. Free space gets logged.
- Use the drive's own cable when it comes with one, and log it.
- Keep the same two copy folders for every drive. They need to sit on something faster than the drive being tested, like the internal SSD of a big Mac Studio.
- Don't change the settings at the top of the script. If something has to change, bump `SUITE_VERSION` so old and new rows don't get mixed.
- Laptops: plugged in, lid open.

## Good to know

- fio numbers land close to Blackmagic but not exactly on it. Run Blackmagic once on a drive you already know (like the U34) next to this script so you know the offset before swapping the sheet over.
- On macOS a single test can only use 16 requests at a time, so QD32 runs as 4 jobs x 8.
- The script only writes inside `ATT-SSD-Test` on the drive and deletes it when it finishes, even if you stop it with Control-C. It refuses to run on internal drives.
- Spotlight indexing is turned off on the test drive during the run, then turned back on.
- A TB5 drive takes about 15 minutes total. A slow USB drive that drops to around 300 MB/s after its cache can take 30+ minutes.
- Not yet run on a Mac. The first real run is the test of the Mac-only parts (drive detection, cache clearing, Spotlight, link speed).
