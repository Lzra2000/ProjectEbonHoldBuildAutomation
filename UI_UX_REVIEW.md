# EbonBuilds 2.96 — Stats and Logbook Redesign

Version 2.96 connects analytics and audit into one workflow: Stats identifies patterns, and the Logbook exposes the decisions supporting them.

## Stats
- Four views: Summary, Echoes, Actions, Recommendations.
- Same-build latest/previous-run comparison.
- Weighted-Echo coverage and evidence confidence.
- Sortable Echo analytics with final score, appearance, pick share, DPS, and personal/community counts.
- Evidence-backed recommendations linked to filtered Logbook decisions.

## Logbook
- Compact session navigator plus selected-run summary strip.
- Decision-first columns: Time, Action, Decision, Explanation, Charges.
- Search, action, source, important-only, and level-grouping filters.
- Reusable details panel with honest historical fallbacks.
- Visible-row pooling for long logs.

## Data additions
- New session records include build ID and start level.
- New decision records include build ID, level, source, and compact importance flags.
- Manual Training choices are recorded as manual decisions.

## Compatibility
Existing sessions, builds, and SavedVariables remain readable. Missing historical fields are shown as unavailable rather than reconstructed from current settings.
