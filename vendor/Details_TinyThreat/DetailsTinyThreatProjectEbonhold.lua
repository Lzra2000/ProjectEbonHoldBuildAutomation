-- DetailsTinyThreatProjectEbonhold.lua
-- Project Ebonhold / WotLK 3.3.5a helpers for Details_TinyThreat v1.07.
-- Loaded before Details_TinyThreat.lua (see Details_TinyThreat.toc).

local function TT_EnsureGroupCompat()
	if not IsInGroup then
		function IsInGroup()
			return GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0
		end
	end
	if not IsInRaid then
		function IsInRaid()
			return GetNumRaidMembers() > 0
		end
	end
	if not GetNumSubgroupMembers then
		function GetNumSubgroupMembers()
			return GetNumPartyMembers()
		end
	end
	if not GetNumGroupMembers then
		function GetNumGroupMembers()
			if IsInRaid() then
				return GetNumRaidMembers()
			end
			return GetNumPartyMembers()
		end
	end
end

TT_EnsureGroupCompat()

function TT_EnsureNameCompat()
	if not GetUnitName then
		function GetUnitName(unit, showServerName)
			local name, realm = UnitName(unit)
			if not name then
				return nil
			end
			if showServerName and realm and realm ~= "" then
				return name .. "-" .. realm
			end
			return name
		end
	end
end

-- Stock 3.3.5a only exposes UnitThreatSituation (status 0-3). PE backports
-- UnitDetailedThreatSituation at the client; synthesize coarse values when absent.
local THREAT_PCT_BY_STATUS = {
	[0] = 100,
	[1] = 75,
	[2] = 50,
	[3] = 25,
}

function TT_EnsureThreatCompat()
	if type(UnitDetailedThreatSituation) == "function" or type(UnitThreatSituation) ~= "function" then
		return
	end
	function UnitDetailedThreatSituation(unit, mobUnit)
		local status = UnitThreatSituation(unit, mobUnit)
		if status == nil then
			return nil
		end
		local isTanking = (status == 0)
		local threatpct = THREAT_PCT_BY_STATUS[status] or 0
		local threatvalue = threatpct * 1000
		return isTanking, status, threatpct, threatpct, threatvalue
	end
end

TT_EnsureNameCompat()
TT_EnsureThreatCompat()

function TT_GetNumSubgroupMembers()
	return GetNumSubgroupMembers()
end

function TT_GetNumGroupMembers()
	return GetNumGroupMembers()
end

function TT_SafeUnitDetailedThreatSituation(unit, target)
	local ok, isTanking, status, threatpct, rawthreatpct, threatvalue =
		pcall(UnitDetailedThreatSituation, unit, target)
	if not ok then
		return nil, nil, nil, nil, nil
	end
	return isTanking, status, threatpct, rawthreatpct, threatvalue
end

function TT_SafeUnitGroupRolesAssigned(unitId)
	if type(DetailsFramework) == "table" and type(DetailsFramework.UnitGroupRolesAssigned) == "function" then
		local ok, role = pcall(DetailsFramework.UnitGroupRolesAssigned, unitId)
		if ok and role then
			return role
		end
	end
	return "NONE"
end

function TT_IsDetailsReady()
	return type(_G._detalhes) == "table" and type(_G._detalhes.NewPluginObject) == "function"
end

function TT_SafeGetUnitName(unit, showServerName)
	local ok, name = pcall(GetUnitName, unit, showServerName)
	if not ok then
		return nil
	end
	return name
end
