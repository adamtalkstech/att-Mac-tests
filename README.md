# Adam Talks Tech - Mac test scripts

**These scripts are for Adam Talks Tech's own Mac testing only.** They're public so the test Macs
(including review loaners) can pull the latest version with one command and no sign-in. They're
not a product or a general-purpose benchmark tool, and there's no support, issue tracking or
pull requests. If you run them yourself, you're on your own.

Heads-up if you do look at them: the scripts quit other open apps before a test, ask for your
Mac password for some steps (power readings, clearing the file cache), and expect a test folder
and files that only exist on the Adam Talks Tech test drives.

Results and methods are published on [Adam Talks Tech](https://adamtalks.tech)
(see [How I Test Macs](https://adamtalks.tech/how-i-test-macs/)).

## What's here and what isn't

- **Here:** the test scripts (zsh) and the step-by-step run order.
- **Not here:** test footage, AI models, games, installers, results and license keys. Those live on
  the test drives only.

## Update a test Mac to the latest scripts

The test folder has to be in `~/Downloads` already (dragged from a test drive). Then:

```
curl -fsSL https://raw.githubusercontent.com/adamtalkstech/att-mac-tests/main/att-update.zsh | zsh
```

It only replaces scripts and instructions. Results, models, games and apps aren't touched.

Start with `Adam Talks Tech Tests/00 START HERE - Run Order.txt`.

---
© 2026 Adam Talks Tech. All rights reserved. Shared for Adam Talks Tech test Macs only.
