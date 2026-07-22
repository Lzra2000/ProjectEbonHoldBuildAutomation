# Freeze-first automation audit

## Baseline audit

The supplied `EbonBuilds_24.zip` and repository archive contained identical
addon code. The sequencing defects were concentrated in
`modules/automation/Automation.lua`:

- `Automation.Evaluate` performed a direct locked-Echo selection pre-check
  before any preservation pass.
- Its visible action order was banish, reroll, freeze, then `TrySelect`.
- Reroll safety used `freezeRoundActive`, a local request-side boolean, instead
  of counting the board's confirmed `choice.isFrozen` / `choice.isCarried`
  slots. A board that arrived with a frozen Echo could therefore reroll.
- Frozen state was split between the per-choice booleans and
  `locallyFrozenIndices`. There was no explicit `frozenCount`, frozen-ID set,
  board capacity, or pending freeze identity.
- The freeze gate used remaining run resources as its only capacity check. It
  did not independently enforce the two-frozen-Echo board limit.
- `CommitDecision` counted a freeze and mutated `usedFreezes` as soon as the
  local request was accepted. It did not wait for the server-visible board.
- `SubmitAction` treated request acceptance as completion, while the scheduled
  reevaluation could select or reroll before the frozen slot was confirmed.
- The `PerkUI.Show` hook cleared `locallyFrozenIndices` and
  `freezeRoundActive`, even when the show/update represented the same board.
- There was no board fingerprint, so delayed actions retained stale slot
  indices when an offer changed.
- Selection, banish, reroll, and freeze decisions were spread across separate
  early-return blocks inside `Automation.Evaluate`, which allowed the priority
  order to conflict.

`modules/integration/ProjectEbonholdAPI.lua` exposes request acceptance and a
read-only `GetCurrentChoice`; it does not expose a reliable acknowledgement
callback. Confirmation therefore has to come from re-reading the complete
choice board, not from the request return value.

## Implemented design

`modules/automation/BoardDecision.lua` is the pure O(n) decision layer. It
receives already-scored slots and applies the visible priority order:

1. validate and stabilize the board;
2. wait for any pending freeze;
3. choose the best legal selection target;
4. freeze the strongest qualifying non-selected target while capacity remains;
5. select only after no unsecured freeze candidate remains;
6. consider banish or reroll only on a zero-frozen board with no acceptable
   pick under the build's existing reroll policy.

`modules/automation/Automation.lua` remains the reader/executor. Its lightweight
state record stores confirmed frozen slots and IDs, a maximum capacity of two,
the pending freeze slot and Echo ID, confirmation polls, an uncertainty guard,
and full/identity fingerprints. Freeze requests are confirmed only when the
same slot and Echo ID reappear on the unchanged board and either report a
frozen/carried flag or the authoritative server Freeze counter advances from
the pre-request snapshot. Resource-confirmed current-board freezes count toward
capacity and remain ineligible for selection or another Freeze. A changed
fingerprint cancels stale actions; a failed confirmation enters recovery and
blocks rerolling.

The redesign does not add a runtime evaluator, tooltip parsing, combat-log
analysis, search, runtime simulation, or `OnUpdate` work. Existing scores,
thresholds, locked slots, and Echo policies remain authoritative. Protection
continues to guard banish/family handling but does not make a below-threshold
Echo valuable enough to freeze.

The runtime also distinguishes an Echo frozen during the current board from a
server-carried Echo on the next board. The former is excluded from selection
until the board identity changes, preventing Freeze and Select from targeting
the same Echo in one turn. The latter is once again a legal choice and competes
normally by its effective score, including the build's configured frozen-Echo
penalty. This prevents a valuable carried Echo from being skipped indefinitely
for lower-valued fresh offers.

When a new run begins at level 1, it arms a one-shot 2.5-second minimum delay
for the first automatic server action. The armed delay intentionally survives
an instant level-50 boost, then is consumed by the first valid automation
board. A session reconstructed above level 1 cannot re-arm it. Subsequent
boards and freeze confirmations use the normal configured evaluation delay.

If normal freeze confirmation polls expire, the addon does not remain uncertain
for the life of the board. It performs two short, read-only stable-board polls
without repeating the freeze request. A late frozen result is accepted; two
stable unfrozen reads resolve the request as failed, retain duplicate-freeze
suppression for that slot, and allow the safe decision flow to continue.
