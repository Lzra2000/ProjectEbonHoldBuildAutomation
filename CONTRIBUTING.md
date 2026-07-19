# Contributing to EbonBuilds

## Setup

```
git clone https://github.com/Lzra2000/-ProjectEbonHoldBuildAutomation.git
cd -ProjectEbonHoldBuildAutomation
sh scripts/dev-setup.sh      # installs lua5.1, texlive-binaries (texlua), zip
sh scripts/install-hooks.sh  # optional: runs scripts/check.sh before every commit
```

That's it. No build step for day-to-day development -- the repo root is already the addon folder structure `Interface/AddOns/` expects, so you can symlink or copy it straight in and reload.

## Before opening a PR

```
sh scripts/check.sh
```

Runs the same three checks CI runs: Lua 5.1 syntax check, the full test suite (`tests/run.sh`), and a check that every file listed in `EbonBuilds.toc` actually exists. If `scripts/install-hooks.sh` is set up this runs automatically on commit (skip once with `git commit --no-verify`).

The PR template has a short checklist -- FAQ.md entry for user-facing changes, translation keys for new UI strings, that kind of thing.

## Project conventions

- **File header.** Every module starts with:
  ```lua
  -- EbonBuilds: modules/path/File.lua
  -- Responsibility: one line, what this file owns.
  ```
- **Namespace, not globals.** Everything hangs off `EbonBuilds.<Module>`. Internal helpers are `local function` at file scope, not global.
- **Test hooks.** If something needs to be tested but isn't naturally reachable (a closure inside a button's `OnClick`, module-local state), expose it as `EbonBuilds.Module._DoTheThing = DoTheThing` -- see `EbonBuilds.Session`'s test helpers or `EbonBuilds.BuildTabs._TriggerExportAI` for the pattern. Prefix with `_` so it reads as "test/integration only," not part of the real API.
- **Errors that should be visible.** Wrap a handler in `EbonBuilds.ErrorLog.Protect("Source.Name", fn)` if it's reachable from user interaction and isn't trivially safe -- an unprotected error goes straight to WoW's own (usually disabled) Lua error display and never reaches `/ebb errors`. Most of the codebase predates this and isn't wrapped; wrapping more of it as you touch nearby code is welcome.
- **Changelog.** User-facing changes get a `### <version>` entry at the top of `FAQ.md`'s Changelog section. Look at recent entries for the tone: specific about what changed and why, no marketing language.
- **Releases.** Version bumps go through `sh scripts/release.sh <version>` (bumps `EbonBuilds.toc` + `FAQ.md`, runs `scripts/check.sh`, rebuilds `dist/EbonBuilds.zip`, commits, tags) followed by `sh scripts/publish-github-release.sh <version>` (an actual GitHub Release, not just a tag -- see the script for why that's a separate step). Not something a regular PR needs to touch.

## Adding a translation

UI strings go through `EbonBuilds.L["English string"]`, a lookup table that falls back to English for anything untranslated -- see `modules/i18n/Locale.lua`. Currently only `modules/ui/BuildTabs.lua` and `modules/ui/MainWindow.lua` are wired up to it.

**New language:**
```
sh scripts/new-locale.sh itIT
```
Generates `modules/i18n/locales/itIT.lua` pre-filled with every known key (English placeholder as the value). Translate the values, then:
1. Add the file to `EbonBuilds.toc`, right after the other locale files.
2. Add the locale code to `SUPPORTED_LOCALES` in `modules/i18n/Locale.lua` (and `ALIASES` if a short form like `it` should work with `/ebb locale it`).

Game-specific terms (Echo, Build, Banish/Reroll/Freeze/Select, Autopilot) stay in English across every language -- check the existing locale files or `README.*.md` for how a given language already handles that.

**Extending an existing language, or adding `EbonBuilds.L[...]` to a file that isn't wired up yet:** `scripts/check.sh` (via the test suite) will flag any locale file missing a translation for a key that's actually used in `BuildTabs.lua`/`MainWindow.lua` -- run it after adding a new string to see what needs filling in across all six languages at once, instead of finding out one language at a time.

## Reporting bugs

See the README's "Reporting bugs" section -- short version: attach `/ebb errors` output, and `/ebb clicktrace` output if a click seemed to do nothing.
