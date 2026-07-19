# EbonBuilds

**[English](README.md)** | [Deutsch](README.de.md) | [Русский](README.ru.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | [Français](README.fr.md) | [Polski](README.pl.md)

A World of Warcraft (3.3.5a) addon for **ProjectEbonhold** that automates echo picks (Banish / Reroll / Freeze / Select) based on a build you define, and tunes itself over time from real gameplay data.

Requires **ProjectEbonhold** or **ProjectEbonhold Enhanced**. Some features additionally use **[Details!](https://www.curseforge.com/wow/addons/details)** damage meter if installed.

## What it does

- **Define a build**: per-echo weights, quality/family/novelty bonuses, locked slots, banned echoes.
- **Automation**: evaluates every echo choice screen against your build and acts (banish/reroll/freeze/select) so you don't have to.
- **Tuning Advisor**: compares your Banish/Reroll/Freeze thresholds against what your build actually gets offered (not a theoretical model), suggests better values, and can auto-tune them gradually over time.
- **Whole-run budget pacing**: thresholds automatically get stricter as Banish/Reroll/Freeze charges run low, so you don't burn your last charges on borderline offers.
- **DPS & appearance-rate tracking**: with Details! installed, tracks real DPS per active echo; always tracks how often each echo actually appears on a choice screen. Both can optionally sync with other players of the same class.
- **Manual Training Mode**: suspend automation for a build, pick manually, and EbonBuilds learns from your choices, generating weight suggestions from what you actually preferred.
- **Weight & bonus suggestions**: DPS data and manual picks both feed into per-echo weight suggestions, and (experimentally) Quality/Family bonus suggestions.
- **Stats workspace**: Summary, Echoes, Actions, and Recommendations views with same-build run comparison, evidence confidence, and Apply/Undo/Dismiss workflows for recommendations.
- **Logbook**: a decision-first audit trail of every automation action — time, action, decision, explanation, charges — with search, filters, and a detail inspector.
- **Per-quality weights**: echo weights can differ per quality rank (Common through Epic), including negative values and per-echo protection.
- **EchoWishlist export**: generates `EWL1` import strings compatible with the EchoWishlist addon.
- **Export (AI)**: a full plain-text dump of your build's settings, every echo available to your class with real effect descriptions, and all tuning data — meant to be pasted into an AI chat for analysis.
- **Tome Atlas**: community-sourced drop locations for echo tomes.
- **Public Builds**: browse and import builds shared by other players.

See [`FAQ.md`](FAQ.md) for detailed explanations of every feature and the full version history.

## Installation

This repository's root *is* the addon folder (`EbonBuilds.toc`, `core/`, `modules/` sit at the top level, not nested inside a subfolder).

**Via Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Via ZIP download:** GitHub's "Download ZIP" names the extracted folder after the branch (e.g. `EbonBuilds-main`) — rename it to exactly `EbonBuilds` before placing it in `Interface/AddOns/`, so the folder name matches `EbonBuilds.toc`.

Then restart the game or `/reload`.

## Commands

Every command starts with `/ebb`. A full in-game reference is also available via `/ebb showcase`.

| Command | Description |
|---|---|
| `/ebb` | Open or close the main window |
| `/ebb faq` (or `/ebb help`) | Full in-game guide |
| `/ebb showcase` (or `/ebb commands`) | This command list, in-game |
| `/ebb tuning` (or `/ebb advisor`) | Tuning Advisor: thresholds, auto-tune, DPS/appearance sharing |
| `/ebb cleartraining` | Wipe the active build's Manual Training data |
| `/ebb atlas` (or `/ebb tomes`) | Tome Atlas |
| `/ebb affix` | Affixes reference |
| `/ebb autosell` | Toggle auto-selling 0-copper junk at vendors |
| `/ebb bagdots` | Toggle colored dots on bag items missing an affix |
| `/ebb debug` | Toggle detailed automation decision logging |
| `/ebb debuglog` (or `/ebb log`) | View the captured debug log |
| `/ebb errors` | View caught errors, for bug reports |
| `/ebb clicktrace` | Log every UI button click, for "nothing happened" reports |
| `/ebb locale` (or `/ebb language`) | Show the current UI language and list available ones |
| `/ebb locale <code>` | Switch the UI language (e.g. `/ebb locale de`); requires `/reload` |

## Localization

The build editor's tabs, buttons, and tooltips are translated into German, Spanish, French, Polish, Brazilian Portuguese, and Russian, matching the languages this README is already available in. EbonBuilds picks a translation automatically from your client's own language, or you can override it with `/ebb locale <code>`.

Translation strings live in `modules/i18n/locales/*.lua`, one file per language, each mapping the original English string to its translation. Adding a language: run `sh scripts/new-locale.sh <code>` to generate a starting file pre-filled with every known key, then translate the values -- see `CONTRIBUTING.md` for the rest of the steps. Game-specific terms (Echo, Build, Banish/Reroll/Freeze/Select, Autopilot) are kept in English across all languages, matching the existing README translations -- follow that convention rather than translating them.

Only the build editor is translated so far; the rest of the addon's UI still falls back to English (missing keys never error, they just show the English text). Extending coverage to more views is just adding more `EbonBuilds.L["..."]` call sites and the matching translation-table entries.

## Reporting bugs

Attach `/ebb errors` output or an `/ebb debug` log to your report — it's the single fastest way to get something fixed instead of guessed at.

## Development

See `CONTRIBUTING.md` for setup, the pre-PR checklist, and project conventions. Quick version:

- Pure Lua, WotLK 3.3.5a API (Interface 30300).
- One-time setup: `sh scripts/dev-setup.sh` installs the toolchain (`lua5.1`, `texlive-binaries` for the test suite, `zip`).
- `sh scripts/check.sh` runs the full local check suite (syntax check, test suite, `.toc` file verification) — the same checks as `.github/workflows/lua-syntax.yml`, in one command.
- `sh scripts/install-hooks.sh` wires up a pre-commit hook that runs `scripts/check.sh` automatically (skip once with `git commit --no-verify`).
- `sh scripts/build-dist.sh` packages `EbonBuilds.toc`, `FAQ.md`, `core/`, and `modules/` into `dist/EbonBuilds.zip`, ready to drop into `Interface/AddOns/`.
- `sh scripts/release.sh <version>` is the release helper: refuses to run unless `FAQ.md` has changed since the last tag, bumps the version in `EbonBuilds.toc` and `FAQ.md`, runs the check suite, rebuilds `dist/EbonBuilds.zip`, then commits and tags (does not push).
- `GITHUB_TOKEN=... sh scripts/publish-github-release.sh <version>` publishes an actual GitHub Release (the page under `/releases`, with notes) for an already-pushed tag — pushing a tag alone only creates a git ref, not a Release. Pulls the title/notes straight from the matching `### <version>` section of `FAQ.md`.
- For day-to-day development the repo root itself already *is* the addon folder structure expected by `Interface/AddOns/` — the dist zip is only needed for a clean shareable release build.
