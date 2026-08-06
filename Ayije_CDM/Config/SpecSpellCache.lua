local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
local API = CDM.API

local HIDE_BY_DEFAULT_FLAG = Enum.CooldownSetSpellFlags and Enum.CooldownSetSpellFlags.HideByDefault
local function IsHiddenByDefault(info)
    return info and info.flags and HIDE_BY_DEFAULT_FLAG and FlagsUtil and FlagsUtil.IsSet
        and FlagsUtil.IsSet(info.flags, HIDE_BY_DEFAULT_FLAG) or false
end

-- 12.1 splits cooldowns across more categories; each cache folds in the
-- item-backed ones that belong to it. Missing members are skipped on 12.0.
local function CategoryGroup(...)
    local evc = Enum and Enum.CooldownViewerCategory
    local list = {}
    if not evc then return list end
    for i = 1, select("#", ...) do
        local value = evc[select(i, ...)]
        if value ~= nil then
            list[#list + 1] = value
        end
    end
    return list
end

local CATS_ESSENTIAL = CategoryGroup("Essential", "SpecAgnosticEssential", "EquipSlotEssential")
local CATS_UTILITY   = CategoryGroup("Utility")
local CATS_BUFF      = CategoryGroup("TrackedBuff", "SpecAgnosticTracked", "EquipSlotTracked")

local specCacheScheduled = false
local specEssentialCache = {}
local specUtilityCache = {}
local specBuffSpellCache = {}

local function EnsureStorage()
    local db = Ayije_CDMDB
    if not db then return nil end
    if not db.global then db.global = {} end
    if not db.global.sharedSpecCaches then db.global.sharedSpecCaches = {} end
    local s = db.global.sharedSpecCaches
    if not s.specEssentialCache then s.specEssentialCache = {} end
    if not s.specUtilityCache then s.specUtilityCache = {} end
    if not s.specBuffSpellCache then s.specBuffSpellCache = {} end
    return s
end

local function CollectCategories(cats)
    if not cats or not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return nil
    end

    local result, seen = {}, {}
    for _, cat in ipairs(cats) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cooldownID in ipairs(ids) do
                if not seen[cooldownID] then
                    seen[cooldownID] = true
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                    if info and CDM.CONST.IsViewerEntryVisible(info) then
                        local spellID = CDM.CONST.ResolveViewerEntryIdentity(info)
                        result[#result + 1] = {
                            cooldownID = cooldownID,
                            spellID = spellID,
                            baseSpellID = info.spellID,
                            hidden = IsHiddenByDefault(info),
                            charges = info.charges or false,
                        }
                    end
                end
            end
        end
    end

    return #result > 0 and result or nil
end

local function RefreshSpecSpellCache()
    specCacheScheduled = false
    local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
    if not specID then return end
    specEssentialCache[specID] = CollectCategories(CATS_ESSENTIAL)
    specUtilityCache[specID]   = CollectCategories(CATS_UTILITY)
    specBuffSpellCache[specID] = CollectCategories(CATS_BUFF)

    local storage = EnsureStorage()
    if storage then
        storage.specEssentialCache[specID] = specEssentialCache[specID]
        storage.specUtilityCache[specID]   = specUtilityCache[specID]
        storage.specBuffSpellCache[specID] = specBuffSpellCache[specID]
    end
end

local function ScheduleRefresh()
    if specCacheScheduled then return end
    specCacheScheduled = true
    C_Timer.After(0, RefreshSpecSpellCache)
end

function API:GetSpecEssentialCache(specID)
    local cached = specEssentialCache[specID]
    if cached then return cached end
    local storage = EnsureStorage()
    return storage and storage.specEssentialCache[specID]
end

function API:GetSpecUtilityCache(specID)
    local cached = specUtilityCache[specID]
    if cached then return cached end
    local storage = EnsureStorage()
    return storage and storage.specUtilityCache[specID]
end

function API:GetSpecBuffSpellCache(specID)
    local cached = specBuffSpellCache[specID]
    if cached then return cached end
    local storage = EnsureStorage()
    return storage and storage.specBuffSpellCache[specID]
end

CDM:RegisterEvent("PLAYER_ENTERING_WORLD", ScheduleRefresh)
CDM:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED", ScheduleRefresh)
CDM:RegisterSpecStateHandler(ScheduleRefresh)
CDM:RegisterTalentDataHandler(ScheduleRefresh)
