# EbonBuilds — FAQ

*This file covers frequently asked questions and feature explanations. For the full version history, see* [`CHANGELOG.md`](CHANGELOG.md)*. Also available in-game via* `/ebb faq`*.*

---


## FAQ

### My reroll behavior feels different after updating. Is that a bug?
No — two intentional changes affect it:

1. **The peak score no longer includes the novelty bonus.** Previously the peak was inflated at run start (when everything is novel), which made percentage thresholds progressively unreachable as the run consumed novelty — freeze and reroll would quietly stop firing mid-run. The peak is now a stable reference for the whole run. Your percentage settings now mean what they say, but the absolute thresholds shifted.
2. Old builds get the new settings keys backfilled automatically on login (Classic reroll mode, so behavior stays as-is until you opt in to Smart mode).

If your thresholds feel off, press **Reset thresholds to default** once (it actually persists now — see below) and re-tune.

### I pressed "Reset thresholds to default" and nothing changed. Why?
That was a real bug, fixed in 2.0. Previously, every change in the Settings tab (including Reset) only lived in a temporary editing copy and was silently discarded unless you also pressed Save on the form tab. **Now all Settings-tab changes persist immediately** when editing an existing build: sliders (on release), reset button, reroll mode, family whitelist, ban list, and ban-all mode.

### What is Smart Reroll and should I use it?
A new opt-in reroll mode (button in the Automation tab: *"Reroll mode: Classic (sum) / Smart (expected value)"*).

- **Classic** (default): reroll when the *sum* of all three offered scores is below *Auto-reroll %* of the peak, unless the guard blocks it.
- **Smart**: reroll when the *best* offered echo is worse than X% of what an average reroll's best offer would be worth — computed exactly from your weights across every echo and quality tier your class can roll.

Smart mode is immune to the classic mode's two failure modes: a single mega-weighted echo skewing the peak, and quality-bonus noise inflating the sum. Frozen and carried echoes are ignored on both sides of the comparison (they survive a reroll anyway). **Recommended: Smart mode at 95%** — that literally means "only reroll when this screen is worse than an average roll," which is never a losing trade statistically.

### What are good Classic-mode settings?
If you stay on Classic: Auto-reroll (sum) ~25–30%, Reroll guard ~30%, Auto-freeze ~15–20%, Auto-banish ~5%. The Settings tab now shows a live warning when your guard sits below your freeze threshold (junk echoes would block rerolls that could find freeze-worthy ones) or when banish sits at/above freeze.

### My weighted class-specific echoes were ignored by automation. Fixed?
Yes (2.0). Weights are stored under the database name (e.g. *"Warrior - Voidsteel Bulwark"*), but automation looked them up under the in-game spell name (*"Voidsteel Bulwark"*) — so class-prefixed echoes silently scored with weight 0. All lookups now go through one canonical name function, and a regression test pins it.

### Automation froze an echo and then immediately picked it. Fixed?
Yes (2.0). Selecting now excludes echoes frozen this round — the whole point of spending the freeze charge is to take something else on this screen and collect the frozen echo later. Carried echoes from previous screens remain selectable, as intended.

### How do I report a problem so it can actually be fixed?
1. `/ebb debug` — turns on decision tracing (confirmation in chat)
2. Play until the problem happens
3. `/ebb debuglog` — opens a window with the full trace, pre-selected: Ctrl+C and paste it in your report

The log shows the peak, every threshold as an absolute number, every offered echo with score/weight/frozen state, and the reason behind every action or non-action. It's plain text, capped at the last 500 lines, and costs nothing while disabled.

### The Missing tab showed duplicates / owned echoes as missing. Fixed?
Yes (2.0): quality-tier grouping works now (one entry per echo line, owning any tier removes the line from Missing), the list no longer empties after every level-1 reset, and an empty spellbook at login shows "Requesting data..." instead of listing everything as missing.

### Why are there 6 locked-echo slots now?
The addon supports 6 locked slots everywhere (wizard, editor, overview, sync, export/import). Note: whether the **server** honors a 6th lock is a Project Ebonhold question — the addon side is ready.

### What do the colors mean?
Standard WoW rarity colors everywhere: white Common, green Uncommon, blue Rare, purple Epic, orange Legendary — on echo names in the table, picker, wizard, logbook, and as rings around locked-echo icons in build cards. Class colors follow the standard palette.

---

### How does the Tome Atlas work? (new in 2.2)
An AtlasLoot-style **community drop database** for echo tomes. When you loot a tome, the addon records the mob and zone automatically and shares the observation with other EbonBuilds users (over the sync channel and guild). Data from other players arrives live as drops happen and whenever anyone syncs (Public Builds > Reload). Duplicate reports merge via max-count, so nothing ever double-counts.

**Using it:** open via the *Tome Atlas* button in the left panel or `/ebb atlas`. Search by tome, mob, or zone. Toggle *"Show: Missing only"* to hide everything you already collected (matched against your Echoes spellbook — any quality tier counts as collected). The `(x3)` behind a source shows how often the community saw that drop.

**For new players:** filter to *Missing only* and farm the zones with the most entries — that's your collection route.

### What changed about syncing in 2.3?
Reliability and efficiency, same protocol on the wire (old versions stay compatible):

- **Lost transfers recover.** Previously a single dropped message meant that build silently never arrived. Now the receiver notices a stalled transfer, asks the sender to retransmit (up to 2 attempts), and falls back to other players offering the same build.
- **No duplicate downloads.** When several players offer the same build during one sync, it is requested from only one of them.
- **Flood protection.** Responders answer at most one sync request per player per 30 seconds.
- **Feedback.** A toast summarizes each sync ("Sync complete: N build(s) received"), and with `/ebb debug` enabled the full sync traffic appears in the debug log.
- Retransmit requests can only ever re-send **public** builds you own -- a forged request cannot extract private data.

### What is Smart mode? (extended in 2.4)
Toggle in the Automation tab. In Smart mode every automation decision is measured against **expected values computed exactly from your weights** instead of percentages of the peak: rerolls compare the best offer against an average reroll (default 95%, automatically paced by remaining charges from 100% down to 60%), banish removes cards worth less than an average random card (default 60%), and freeze saves cards beating the expected best of a future screen (default 110%). Classic mode remains the default and unchanged.

### How do build chat links work? (new in 2.4)
Open a build and press **Chat Link** — a token like `[EbonBuilds: Pyro Mage V2]` lands in your chat box and can be sent anywhere (say, guild, party, whisper). Other EbonBuilds users see it as a clickable link: clicking opens the build if they already have it, otherwise it is fetched automatically from any online player who owns it. Only **public** builds are ever served. Players without the addon simply see the plain text.

### Where should I farm for missing tomes? (new in 2.4)
The Tome Atlas now shows a **"Best farming"** line ranking zones by how many of *your* missing tomes have known sources there. Filter, fly, farm.

### My Tome Atlas contributions never seemed to reach anyone. Fixed?
Yes (2.5). If you had zero public builds, the sync responder returned before ever reaching the tome-sharing step -- your drop observations never went out. Fixed, and the Tome Atlas view now has its own **Sync** button next to the filter, so refreshing atlas data no longer requires a detour through Public Builds.

### The Tome Atlas search box and buttons overlapped. Fixed?
Yes (2.6). The search row and the count/filter/sync row now anchor to a single reference frame instead of independent fixed offsets, so they can't drift into each other again. The search box also has real placeholder text now ("Search tome, mob, or zone...").

### Can I see the full drop list for a tome, not just the top 3?
Yes (2.6). Hover any tome row: the tooltip shows the item itself (icon, quality) plus every known source, not just the three shown inline.

### What are Affixes, and how is that different from Echoes?
Project Ebonhold has two separate progression systems. **Echoes** are the run-based perks EbonBuilds has always been about. **Affixes** are a permanent, character-bound unlock applied to gear (weapon procs, armor stats) -- a different system entirely, previously only visible through third-party tooltip-scanning tools. EbonBuilds now reads it directly from the server's own data feed, so there's no guessing involved.

### How do I use the Affixes tab? (new in 2.7)
Open via the **Affixes** button in the left panel or `/ebb affix`. Every known affix is listed with a green dot (learned) or red dot (missing). Search by name, toggle *"Show: Missing only"*, and hover any entry for its full tooltip, weapon/armor restriction, apply cost, and use count. Press **Refresh** to request an updated list from the server (throttled to avoid spamming it).

### The Missing tab said "Requesting data..." forever. Fixed?
Yes (2.9). The tab reads your spellbook's "Echoes" category to know what you own -- but that category only exists once you've learned at least one echo, so a fresh character (or one who just reset) has no such tab, and the check used to wait for something that would never arrive. It now retries automatically every 1.5s, and after 15 seconds gives up waiting and shows the full list anyway. If that fallback triggers, it's logged in `/ebb debuglog` for reference.

### My build disappeared after logging in later. What happened?
This was a real bug, fixed in 2.11 -- not something you did wrong. Saving a build compares its stored author name to your current character name to decide whether it's yours or someone else's. `UnitName("player")` can occasionally come back from the game in a different format (with or without the realm attached) after a reconnect. That mismatch made the addon think your OWN build belonged to someone else, "forked" it into a new slot, and removed the old one.

**Nothing was truly deleted.** The build kept existing under a different id, tagged with a "copied from `<your name>`" note. If you still have a build like that, it's yours -- rename it and clear the copied-from note via Edit Build. The comparison is now realm-suffix-tolerant, so this can't happen again.

### What do /ebb autosell, /ebb bagdots, /ebb errors and /ebb clicktrace do? (new in 2.12)
Four small standalone tools:

- **`/ebb autosell`** — toggle. Auto-sells 0-copper junk items while a vendor window is open. An item carrying an affix you haven't learned yet is always protected, even if it sells for nothing. Off by default; opt in explicitly.
- **`/ebb bagdots`** — toggle. Draws a colored dot on bag items whose gear affix you're missing: red for a brand-new affix line, purple for a rank you're missing on one you already partly have. On by default.
- **`/ebb errors`** — opens a small always-on error log (last 20 entries), separate from `/ebb debug`. Useful as a first step when something breaks and you don't have debug tracing already running.
- **`/ebb clicktrace`** — diagnostic for "I clicked a button and nothing happened." Logs every themed button click and view transition, so a bug report can show whether the click even reached EbonBuilds or was intercepted before that.

### Why did Reload get faster / show fewer builds? (2.13)
The Public Builds **Reload** button now only requests builds for the class currently selected in the dropdown (your own class by default), instead of every class from every peer on every reload. Switch the dropdown to "All Classes" if you want the old everything-at-once behavior back. This cuts sync traffic and page count dramatically on classes many players share builds for.

### What do the checkboxes in the gear-icon Settings dialog do? (new in 2.16)
That's the small "EbonBuilds Settings" popup (gear icon next to the window's close button, not the per-build Automation tab). It now covers:

- **Action delay** — how long automation waits before acting on a new echo screen. Very low values may cause the addon to malfunction.
- **Toast duration** — how long pick/reroll/freeze/banish notifications stay on screen.
- **Auto-sell junk at vendors** — same as `/ebb autosell`, now with a persistent checkbox instead of only a slash command.
- **Bag affix dots** — same as `/ebb bagdots`, likewise now a checkbox here.

The dialog scrolls if it ever grows past the window (same fix as the FAQ window in 2.14), so more settings can be added here later without risk of overflow.

### Why do I get a popup saying my build's name is taken? (new in 2.18)
Public Builds used to fill up with dozens of near-identical entries -- the same title from many different authors, e.g. "[WIP] Scourgebeast's Solo DK v1.1" by five different people. The actual cause: importing someone's public build, then making even a tiny edit and saving, silently forks your copy under your own name (an existing, intentional data-loss protection from 2.11) -- but it used to keep the original title and public status, so every edited import quietly added another duplicate to the list.

As of 2.18, saving (or creating) a build checks whether its exact title is already public under a *different* author. If so:
- Your copy is automatically un-published (not deleted -- just no longer shared).
- A popup explains the name is taken and who it belongs to.
- Rename it (Edit Build) and it can be made public again under its own name.

This is a best-effort, client-side check -- there's no central registry, so it's based on what your own client has seen. Existing duplicates already in Public Builds are also cleaned up automatically: the browser (and what gets relayed to other players) now collapses same-titled entries down to the earliest-known one.

### The Missing tab only showed what I don't have. Now what? (2.19)
The Missing tab now works like the Affixes tab: a green or red dot on each icon shows learned vs. not-learned status, and a **Show: All / Show: Missing only** toggle switches between "everything for my class" and the classic missing-only view. Owned echoes show "Learned" in green where the drop source used to be; missing ones are unchanged (drop source, score). A count label at the top reads "X learned, Y missing" (or just "Y missing" when the filter is on).

### Tome Atlas: category system and non-tome items (new in 2.20)
Two changes:

1. **Non-tome items could show up in the Atlas.** Local loot was always filtered to actual tomes before recording, but data arriving from *other players* via sync went straight in unvalidated -- a bug on a peer's end could inject any item into everyone's Atlas. Both the write path (`Merge`, the network-received one) and the read path (`List`, so anything already-stored gets cleaned up immediately too) now check the item name is actually a tome.
2. **New: Group by Tome / Zone / Mob**, plus a Zone filter dropdown. "By Tome" is the classic view (one row per tome, its sources). "By Zone" shows one row per zone with every tome known to drop there. "By Mob" shows one row per mob with everything it drops. The zone dropdown narrows any of the three views to a single zone. Search still matches tome, mob, or zone text in every mode.

### I deleted a build I imported and it vanished from Public Builds too. Fixed?
Yes (2.21). Importing a public build used to delete Public Builds' cached copy of the original, on the (wrong) assumption that was needed to hide it from the browse list -- it isn't; the list already hides anything you have an up-to-date local copy of on its own. That deletion's only real effect was that if you later deleted your imported copy, the original public build was gone from your Public Builds list entirely until someone synced it to you again. The cache is no longer deleted on import, so deleting your local copy now makes the original reappear immediately.

### EbonBuilds won't even enable / greyed out in the addon list with ProjectEbonhold Enhanced. Fixed?
Yes (2.22). The `.toc` declared a hard `## Dependencies: ProjectEbonhold` -- WoW's client won't let you enable an addon at all if a hard dependency's exact folder name isn't found, and "ProjectEbonhold Enhanced" ships under a different folder name even though it provides the same API. Switched to `## OptionalDeps: ProjectEbonhold, ProjectEbonholdEnhanced`, which still makes sure whichever one you have loads first (so EbonBuilds sees it), but no longer blocks enabling EbonBuilds if the folder name doesn't match exactly. No more manually editing the `.toc` by hand after every update.

### Sync is flooding my chat with "[EbonBuilds Sync] Build ... stored in remote" spam. Fixed?
Yes (2.23). Several internal sync diagnostics (one line per build received, one line per REQ broadcast, channel-index bookkeeping) were printing to general chat unconditionally instead of only when `/ebbsync verbose` is on -- always been there, but the 2.15 staggered all-classes sync made it much worse, since a single "All Classes" Reload can now pull in dozens of builds and fires the REQ-sent line up to 10x (once per class) instead of once. All of that moved behind the existing verbose toggle; real problems (a build failing to assemble) now go to `/ebb errors` instead of the chat window. Command output (`/ebbsync status`, `/ebbsync reset`, etc.) and cooldown/actionable messages are unaffected -- you'll still see those.

### The game froze / hung after syncing with Tome Atlas open. Fixed?
Yes (2.24), most likely cause found and fixed. Tome Atlas (and Public Builds) re-rendered its entire list synchronously on every single incoming synced entry -- normally one build/tome is no big deal, but a real sync can stream in dozens to 100+ in a burst over a few seconds, especially since 2.15's staggered all-classes sync. Each render re-scans your spellbook and rebuilds/sorts the whole list (worse in "Group: Zone"/"Group: Mob" mode), so doing that dozens of times in rapid succession is exactly the kind of thing that makes a client stutter hard or lock up. Both views now coalesce bursty refresh requests into at most one actual render every 0.3s, however many sync messages arrive in between.

### How do I know a Settings toggle actually saved?
As of 2.24, clicking Save in the gear-icon Settings dialog shows a toast confirming what was saved (e.g. "Settings saved (Auto-sell ON, Bag dots OFF)") -- previously it just closed the popup with no feedback at all.

### The Missing tab has no way to re-check what I've learned. New?
Fixed (2.25): a **Refresh** button next to Show: All/Missing only. Unlike Affixes' Refresh (which asks the server), this one is a local spellbook re-scan -- Echoes come straight from your own client's spellbook, no server round-trip needed. Previously the only way to force a re-check was leaving the tab and coming back.

If the tab says "0 learned" and that looks wrong: the count only reflects what your current character's spellbook "Echoes" category actually contains right now. A fresh character (or one who just reset) legitimately shows 0 until the server grants that category. Try Refresh first; if it's still 0 after you know you've picked up an echo, that's worth a bug report (`/ebb errors`).

### New: Apply to Character (2.26)
Build Overview has a new **Apply to Character** button. It sends this build's locked echoes to the server's native Active Echo Loadout (`ProjectEbonhold.PerkService.SetActiveEchoLoadout`) -- the game's own echo-pick screen then highlights choices that match, directly in-game, without needing to alt-tab to EbonBuilds while picking. Needs at least one locked echo in the build; works on both ProjectEbonhold and ProjectEbonhold Enhanced.

### Why is "learned" detection more reliable now? (2.26)
The Missing tab and Tome Atlas both used to determine what you've learned by scanning your spellbook's "Echoes" tab -- it works, but needs the tab to actually be populated (hence the old retry-and-wait behavior) and matches by spell name. As of 2.26 both now prefer `ProjectEbonhold.PerkService.GetDiscoveredEchoes()`, an authoritative, spellId-keyed list backed by a SavedVariables cache -- available instantly, no waiting. The spellbook scan is kept as an automatic fallback for servers without that API.

### Why couldn't I see my own public build in Public Builds?
It used to be deliberately hidden there (you already have it in your left sidebar, so browsing it again seemed redundant) -- but that also meant there was no easy way to confirm a build actually published successfully. As of 2.29, your own public builds show up in Public Builds too, tagged **(You)** next to your name, with the Import button replaced by a disabled "Yours" label. If it's not there after making a build public, that's a real sign something's wrong (check the title-collision popup from 2.18 -- your build gets auto-unpublished if the exact title is already public under someone else).

### Tuning Advisor: self-calibrating thresholds (2.33, Smart mode support in 2.34)
`/ebb tuning` opens a window comparing your Banish/Reroll/Freeze thresholds against what your build has actually been offered, not just the theoretical scoring model. EbonBuilds records the score (as % of peak) of every echo automation evaluates, always-on and lightweight, into a per-character sample buffer. Once it has at least 30 samples, the advisor computes what threshold your CURRENT setting actually corresponds to (e.g. "rejects ~13% of real offers") and suggests a value to hit a sensible target (~15% for Banish, ~45% for Reroll, ~10% for Freeze), with an Apply button that writes it straight to your active build.

Works with **both Classic and Smart (EV) mode**, covering Banish, Reroll, and Freeze in both. Smart mode's fields are a % of mean/evBest3/EV rather than peak directly -- the advisor converts through the current mean/peak, evBest3/peak, or EV/peak ratio so both modes analyze against comparable underlying data (cross-checked: a Classic and a Smart suggestion targeting the same percentile land on the same real threshold). Smart Reroll's suggestion (2.48) uses its own sample stream with each evaluation's charge-pacing multiplier divided back out, since its live threshold moves with remaining charges -- the same pacing behavior as before, just now something the advisor can actually analyze. "Clear Collected Data" is worth using after a major reweight, since old samples reflect the previous weighting.

### Continuous auto-tune (2.35) -- do I have to keep clicking Apply?
Not if you don't want to. `/ebb tuning` has a **Continuous auto-tune** checkbox (off by default). Turn it on and thresholds nudge themselves toward their suggested value automatically -- a small gradual step (25% of the gap) every ~20 newly-recorded offers, never an instant jump. You'll get a toast every time it actually adjusts something, so you're never left wondering why automation's behavior changed. It's deliberately gradual and rate-limited so it can't overreact to a short noisy streak; simulated tests show it converges smoothly to a stable value over a few hundred samples rather than oscillating.

### Whole-run budget pacing (2.36)
Automation now spends its Banish/Reroll/Freeze charges with the REST OF THE RUN in mind, not just the current offer in isolation. Smart Reroll already did this (get pickier as reroll charges run low); as of 2.36, Banish, Freeze, and Classic Reroll all get the same treatment:

- **Banish**: with plenty of charges left, banishes anything below the usual threshold; with few left, only banishes clearly-bad echoes, so the last few aren't burned early on borderline picks.
- **Reroll** (Classic mode, previously had no pacing at all): same idea -- pickier as charges run low.
- **Freeze**: with plenty of charges left, freezes anything above the usual threshold; with few left, only freezes genuinely excellent finds.

All three use the same shared curve (`ChargePacing`), just with per-lever comfort caps and conservativeness. `/ebb debug` now also shows the pacing multiplier actually applied to each threshold in the EVAL header, for troubleshooting.

Known limitation: the Tuning Advisor's "current threshold rejects/catches X%" figure is computed against the *base* (unpaced) threshold value -- it's still a useful approximation, but not perfectly exact now that the real applied threshold shifts with remaining charges throughout a run.

### Export (AI) -- new button (2.38, full class echo list + descriptions in 2.39)
Next to the regular Export button (build edit screen, any tab) is a new **Export (AI)** button. Regular Export produces a compact Base64 string meant for another EbonBuilds client to Import -- not something a human or a general AI chat can read. Export (AI) instead produces a plain-text dump: quality/family/novelty bonuses, automation thresholds (with mode-appropriate labels), locked echoes, banned echoes, and -- as of 2.39 -- **every echo your class can get, not just the ones you've weighted**, each with its quality, family, current weight, and actual effect description (pulled from the real spell tooltip where cached; otherwise a note to hover it once in-game first). If you've collected any Tuning Advisor data, that's included too. Meant to be copied and pasted into an external AI chat to ask for tuning suggestions on which echoes are actually worth weighting for your spec; it isn't a format EbonBuilds can import back in.

### Track DPS by echo (2.40) -- needs Details!
`/ebb tuning` has a second checkbox: **Track DPS by echo**, off by default, requires the Details! damage meter addon. When on, every 10 seconds while you're in combat it samples your current DPS (via Details' documented public API) and credits it to every echo you currently have active. Over time this builds a rough real-performance average per echo -- shown in Export (AI) alongside the theoretical scoring once you've collected some data.

This is deliberately approximate, not a controlled measurement: echoes stack together and fight difficulty/duration/execution vary a lot run to run, so it can't isolate any single echo's true causal effect. Treat it as a rough supplementary signal to combine with the scoring model and Tuning Advisor data, not a replacement for either. If Details! isn't installed, the checkbox tells you and won't enable.

