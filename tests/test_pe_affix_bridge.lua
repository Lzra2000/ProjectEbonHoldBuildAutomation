-- PE affix bridge tests
unpack = unpack or table.unpack
local function fail(m) io.stderr:write('PE_AFFIX_BRIDGE FAIL: '..tostring(m)..'\n') os.exit(1) end
local function assertTrue(v,m) if not v then fail(m) end end
local function assertEq(a,b,m) if a~=b then fail((m or 'neq')..': '..tostring(a)..' vs '..tostring(b)) end end
local loadedAddons={} function IsAddOnLoaded(n) return loadedAddons[n]==true end
function LoadAddOn() end function ShowUIPanel() end
MerchantFrame={IsShown=function() return false end}
local addon={}
local chunk,err=loadfile('modules/integration/ProjectEbonholdAffixBridge.lua')
if not chunk then fail(err) end
local ok,e=pcall(chunk,'EbonBuilds',addon) if not ok then fail(e) end
local B=addon.ProjectEbonholdAffixBridge
assertTrue(not B.IsProjectEbonholdLoaded(),'no pe')
local ok2,r=B.OpenExtractionUi() assertTrue(not ok2 and r=='missing-pe','missing')
loadedAddons.ProjectEbonhold=true
ExtractionService={RequestLearnedAffixes=function() end}
EbonholdExtractionFrame={Show=function() end,Hide=function() end,sidePanel={searchBox={SetText=function() end}}}
ExtractionUI={ShowSidePanel=function() end}
ok2,r=B.OpenExtractionUi({affixName='X'}) assertTrue(ok2,'open')
print('PE_AFFIX_BRIDGE OK')
