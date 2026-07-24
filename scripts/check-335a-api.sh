#!/usr/bin/env sh
# Greps core/ and modules/ for WoW API calls that don't exist in 3.3.5a
# (WotLK, build 12340) -- added in later expansions and easy to reach for
# by habit or by an LLM trained mostly on modern/retail addon code.
#
# Caught live: modules/vendor/AutoSell.lua used Region:SetShown() (added
# in Cataclysm 4.0.1) for a 3.3.5a-only client, which is silently
# tolerated by the test stub (unknown methods resolve to a no-op there)
# so scripts/check.sh's test suite passed while the real client threw
# "attempt to call method 'SetShown' (a nil value)".
#
#   sh scripts/check-335a-api.sh
set -eu
cd "$(dirname "$0")/.."

# pattern | why it's wrong for 3.3.5a | fix
BLOCKLIST='
:SetShown\(|Region:SetShown, added Cataclysm 4.0.1|use if cond then f:Show() else f:Hide() end
:GetShown\(|Region:GetShown, added Cataclysm 4.0.1|use f:IsShown()
C_Timer\.|C_Timer namespace, added Mists of Pandaria 5.0.4|use EbonBuilds.Scheduler or a CreateFrame("Frame") OnUpdate ticker
IsInGroup\(|added Mists of Pandaria 5.0.4|use GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0
IsInRaid\(|added Mists of Pandaria 5.0.4|use GetNumRaidMembers() > 0
GetNumGroupMembers\(|added Mists of Pandaria 5.0.4, replaced GetNumPartyMembers/GetNumRaidMembers|use GetNumPartyMembers()/GetNumRaidMembers()
GetNumSubgroupMembers\(|added Mists of Pandaria 5.0.4|use GetNumPartyMembers()
UnitIsGroupLeader\(|added Mists of Pandaria 5.0.4|use IsPartyLeader()/IsRaidLeader()
UnitIsGroupAssistant\(|added Mists of Pandaria 5.0.4|use IsRaidOfficer()
'

found=0
echo "$BLOCKLIST" | while IFS='|' read -r pattern reason fix; do
    [ -z "$pattern" ] && continue
    # FAQContent.lua is generated prose (display strings for the in-game
    # FAQ), not executable code -- a changelog entry that happens to
    # mention an API name by name is not a call to it.
    matches=$(grep -rn -E "$pattern" core modules --include="*.lua" \
        --exclude="FAQContent.lua" 2>/dev/null || true)
    if [ -n "$matches" ]; then
        echo "NOT AVAILABLE IN 3.3.5a: $pattern"
        echo "  $reason"
        echo "  fix: $fix"
        echo "$matches" | sed 's/^/    /'
        echo ""
        echo "1" > /tmp/.check-335a-api-found
    fi
done

if [ -f /tmp/.check-335a-api-found ]; then
    rm -f /tmp/.check-335a-api-found
    echo "" >&2
    echo "FAILED: post-3.3.5a API call(s) found." >&2
    echo "Re-run: sh scripts/check.sh --only api" >&2
    echo "Or:     sh scripts/check-335a-api.sh" >&2
    echo "Docs:   docs/dev-testing.md" >&2
    exit 1
fi
echo "OK: no known post-3.3.5a API calls found."
