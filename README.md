# Adam Talks Tech - Mac test scripts

The scripts and instructions behind the Mac benchmarks on [Adam Talks Tech](https://adamtalks.tech)
(methods: [How I Test Macs](https://adamtalks.tech/how-i-test-macs/)).

Every test runs the same way on every Mac: from the Mac's own drive, after closing other apps and
waiting until it's cool and idle, and ends with a results box.

**What's here:** the scripts (zsh) and the run order. **Not here:** test footage, AI models, games,
installers and license keys. Those live on the test drives.

## Update a test Mac to the latest scripts

```
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/att-update.zsh | zsh
```

Start with `Adam Talks Tech Tests/00 START HERE - Run Order.txt`.
