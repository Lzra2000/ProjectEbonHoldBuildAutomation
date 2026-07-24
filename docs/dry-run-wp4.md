# WP4 dry-run / simulation — client stepping stone (#53)

**Status:** partial (EbonBuilds client); server transcript API pending  
**Parent:** [#49](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/49) · [#53](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/53)  
**Design:** [`automation-server-redesign.md`](automation-server-redesign.md) §2 (simulation / dry-run) + §6 (test plan)  
**Builds on:** WP1 `BoardStateMachine`, WP2 tie-breaks, WP3 `IntentQueue`, `BoardDecision` freeze-first oracle

## What shipped in EbonBuilds

| Piece | Location |
|---|---|
| Pure evaluator (snapshot → policy verdict) | `modules/automation/DryRun.lua` |
| Policy verb mapping (`select` / `freeze` / `banish` / `reroll` / `wait`) | `AutomationDryRun.NormalizePolicyAction`, `Evaluate` |
| Transcript parser + replay harness | `ParseTranscript`, `Replay`, `ApplySimulatedEvent` |
| DebugLog / Logbook line hooks | `ParseDebugLogBoard`, `ParseDebugLogAction`, `ParseDebugLogLifecycle` |
| Checked-in #38-class fixture | `tests/fixtures/dry_run_issue38_class.txt` |
| Unit tests | `tests/test_dry_run.lua` |

### Evaluate API (today)

```lua
local verdict = EbonBuilds.AutomationDryRun.Evaluate({
    threshold = 120,
    freezeResources = 2,
    canReroll = true,
    slots = {
        { index = 1, spellId = 101, score = 160 },
        { index = 2, spellId = 102, score = 130 },
    },
})
-- verdict.action      -> "freeze" | "select" | ...
-- verdict.boardState  -> OPEN | FROZEN_PENDING | CONFIRMED | SPENT (derived)
-- verdict.targetSlot  -> 1-based slot index or -1
-- verdict.reasonCode  -> machine token for CI / Logbook
```

No `ProjectAPI.Request*` calls are made. This is safe for CI and offline bisect tools.

### Transcript schema (v1)

Fixture files use line directives (UTF-8, `#` comments). One **step** begins with `@board` or a pasted `Board:` DebugLog line.

| Directive | Purpose |
|---|---|
| `@board threshold=120 freezeResources=2 canReroll=1` | Board-level params (`pickIsAcceptable`, `pendingFreezeSlot`, `boardState`, …) |
| `1:101:160` or `slot=2:102:130:frozen:carried` | Slot row: `index:spellId:score[:flags…]` |
| `@event type=pending_freeze slot=2 spell=102` | Simulated runtime signal before evaluate |
| `@expect action=FREEZE target=2 boardState=OPEN` | Assertion on the verdict |
| `@assert no_reroll_in=FROZEN_PENDING,CONFIRMED` | Lifecycle invariant |

**Flags:** `frozen`, `carried`, `guaranteed`, `avoided`, `protected`, `banish`, `thisboard`.

### Converting a Logbook / DebugLog paste

1. Enable `/ebb debug`, reproduce the choice screen, copy `/ebb debuglog`.
2. Keep lines that start with `Board:`, `Frozen:`, `Board lifecycle:`, `Action:`.
3. Wrap them in a fixture step or call `AutomationDryRun.ParseLine` per line.
4. For scores the log omitted, add an `@board` block with explicit `index:spellId:score` rows (or attach weights in `Evaluate`).
5. Add `@expect` rows from the recorded `Action:` line and lifecycle state.
6. Run: `lua5.1 tests/test_dry_run.lua` or `sh tests/run.sh --only dry_run`.

Example DebugLog fragment (parsed automatically when embedded in a step):

```
Board: [1] Echo 101(101)=160, [2] Echo 102(102)=130
Frozen: 0/2
Board lifecycle: OPEN (fresh_board, derived)
Action: FREEZE -- freeze actions take priority over selection
```

## Still required from ProjectEbonhold / server core

These items complete [#53](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/53) acceptance criteria; they are **not** in this client PR:

1. **Authoritative dry-run endpoint** — HTTP/admin or Eluna console preferred; accepts transcript + constraints + build weights; returns JSON/lines `{step, boardState, action, reasonCode}` **without mutating run state**.
2. **Server policy oracle** — when `GetCapabilities().serverPolicy == true`, replay should compare client `BoardDecision` vs server verdict (debug mode per redesign doc).
3. **Published ranks + offerId in replay output** — tie-break vectors from [#51](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/51) should appear in dry-run responses for bisect.
4. **GM/dev gate for in-game AddonMsg dry-run** — if forced onto `AAM0x9`, hard size limits and no live resource spend.
5. **Full Logbook export schema** — session history rows as machine-readable transcript (offerId, resource counters, pending flags) so players need not hand-edit fixtures.
6. **CI job against server sim** — mirror `tests/fixtures/dry_run_issue38_class.txt` on ProjectEbonhold core once endpoint exists.

### Suggested PE / server surface (sketch)

```
POST /admin/automation/dry-run
{
  "transcript": "...",
  "constraints": "v=1;minScore=19;...",
  "weights": { "101": 160, "102": 130 }
}

-> { "steps": [ { "boardState": "FROZEN_PENDING", "action": "wait", "reasonCode": "freeze_lock_pending" } ] }
```

EbonBuilds client dry-run remains the **fallback oracle** when `serverPolicy == false`.

## Compatibility

| Client | Server | Behavior |
|---|---|---|
| This PR | Current PE | Client `AutomationDryRun.Evaluate` / transcript replay only |
| Future client | PE with server dry-run | Server verdict primary; client compare behind debug flag |
| CI | No PE | Lua tests + fixtures; no live character |

Existing suites (`test_freeze_first.lua`, `test_board_state_machine.lua`, …) must stay green; new coverage is in `test_dry_run.lua`.
