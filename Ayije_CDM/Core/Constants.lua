local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

CDM.CONST = {
    FONT_PATH = "Fonts\\FRIZQT__.TTF",
    FONT_OUTLINE = "OUTLINE",

    SHADOW_OFFSET = {
        x = 1,
        y = -1,
    },

    SHADOW_COLOR = {
        r = 0,
        g = 0,
        b = 0,
        a = 1,
    },

    WHITE = {
        r = 1,
        g = 1,
        b = 1,
        a = 1,
    },

    GOLD = {
        r = 1,
        g = 0.82,
        b = 0,
        a = 1,
    },

    SWIPE_COLOR = {
        r = 0,
        g = 0,
        b = 0,
        a = 0.6,
    },

    TEX_WHITE8X8 = "Interface\\Buttons\\WHITE8X8",

    STRATA_MAIN = "MEDIUM",
    STRATA_OVERLAY = "HIGH",

    VIEWERS = {
        ESSENTIAL = "EssentialCooldownViewer",
        UTILITY = "UtilityCooldownViewer",
        BUFF = "BuffIconCooldownViewer",
        BUFF_BAR = "BuffBarCooldownViewer",
    },

    SOUL_CLEAVE_SPELL_ID = 228477,
    MAELSTROM_WEAPON_SPELL_ID = 344179,
    DEVOURER_VOID_METAMORPHOSIS_SPELL_ID = 1217607,
    DEVOURER_RESOURCE_AURA_SPELL_ID = 1225789,
    DEVOURER_COLLAPSING_STAR_SPELL_ID = 1227702,
    DEVOURER_SOUL_GLUTTON_TALENT_SPELL_ID = 1247534,
    FERAL_OVERFLOWING_POWER_SPELL_ID = 405189,
    TIP_OF_THE_SPEAR_SPELL_ID = 260286,
    FLURRY_SPELL_ID = 44614,
    FIRE_BLAST_SPELL_ID = 108853,
    GCD_SPELL_ID = 61304,
    ITEM_COOLDOWN_GCD_MIN = 1.5,
}

-- Trinket slots referenced from cooldown groups / the ungrouped cooldown order
-- are stored as sentinel IDs far above any real spell or item ID
-- (slot 13 -> 900000013, slot 14 -> 900000014).
CDM.CONST.TRINKET_SENTINEL_BASE = 900000000
CDM.CONST.TRINKET_SLOT_IDS = { 13, 14 }

function CDM.CONST.GetTrinketSentinelForSlot(slotID)
    return CDM.CONST.TRINKET_SENTINEL_BASE + slotID
end

function CDM.CONST.GetTrinketSlotFromSentinel(id)
    if id == CDM.CONST.TRINKET_SENTINEL_BASE + 13 then return 13 end
    if id == CDM.CONST.TRINKET_SENTINEL_BASE + 14 then return 14 end
    return nil
end

-- Custom cooldown items referenced from cooldown groups / the ungrouped
-- cooldown order are stored as sentinel IDs (itemID + base) so they can never
-- collide with real spell IDs. Custom cooldown spells use their spell ID as-is.
CDM.CONST.CUSTOM_ITEM_SENTINEL_BASE = 910000000
CDM.CONST.CUSTOM_ITEM_SENTINEL_MAX = 920000000

function CDM.CONST.GetCustomItemSentinelForItem(itemID)
    return CDM.CONST.CUSTOM_ITEM_SENTINEL_BASE + itemID
end

function CDM.CONST.GetCustomItemIDFromSentinel(id)
    if type(id) == "number"
        and id > CDM.CONST.CUSTOM_ITEM_SENTINEL_BASE
        and id < CDM.CONST.CUSTOM_ITEM_SENTINEL_MAX then
        return id - CDM.CONST.CUSTOM_ITEM_SENTINEL_BASE
    end
    return nil
end

-- The stable identity for a cooldown viewer entry.
--
-- Patch 12.1's consumable entries (potions / healthstones) have no spellID at
-- all -- their only identity is spellCategoryID -- so this returns nil for
-- them and they are skipped by the pickers. Those consumables are covered by
-- the Custom Cooldowns module instead, which tracks them by item ID.
--
-- Deliberately does NOT consult `linkedSpellID` (singular). Blizzard's
-- CooldownViewerItemDataMixin:GetSpellID() checks it first, but that field is
-- written onto the mixin's own cached cooldownInfo by RefreshLinkedSpell() to
-- track which linked aura is currently active. It is transient state and is
-- absent from a fresh GetCooldownViewerCooldownInfo() result, so keying a
-- stored identity on it would make group membership change as auras come and
-- go. The plural `linkedSpellIDs` array is the static candidate list and is
-- handled by the existing matching passes.
function CDM.CONST.ResolveViewerEntryIdentity(info)
    if not info then return nil end
    local sid = info.overrideTooltipSpellID
        or info.overrideSpellID
        or info.spellID
    -- Viewer spell IDs can be secret values; they must never reach a table key
    -- or comparison. Matches GetEffectiveCooldownSpellID in Core/Style.lua.
    if CDM.IsSafeNumber(sid) then return sid end
    return nil
end

local VIEWERS = CDM.CONST.VIEWERS
CDM.CONST.COOLDOWN_VIEWER_NAMES = { VIEWERS.ESSENTIAL, VIEWERS.UTILITY }
CDM.CONST.ALL_VIEWER_NAMES = {
    VIEWERS.ESSENTIAL,
    VIEWERS.UTILITY,
    VIEWERS.BUFF,
    VIEWERS.BUFF_BAR,
}

CDM.CONST.VIEWERS_WITH_OVERRIDE = {
    [VIEWERS.ESSENTIAL] = true,
    [VIEWERS.UTILITY] = true,
}

-- Patch 12.1 added item-backed cooldown viewer categories: trinkets arrive as
-- EquipSlot*, and potions / healthstones / racials as SpecAgnostic*. Every
-- member is looked up by name and skipped when absent, so these tables stay
-- correct on 12.0 clients that only know the original four.
local function BuildCategoryList(...)
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

-- Categories whose entries render as cooldown icons (Essential-style rows).
CDM.CONST.VIEWER_CATEGORIES_COOLDOWN = BuildCategoryList(
    "Essential",
    "Utility",
    "SpecAgnosticEssential",
    "EquipSlotEssential"
)

-- Categories whose entries render as tracked buffs (BuffIcon / BuffBar rows).
CDM.CONST.VIEWER_CATEGORIES_BUFF = BuildCategoryList(
    "TrackedBuff",
    "TrackedBar",
    "SpecAgnosticTracked",
    "EquipSlotTracked"
)

-- Every category the addon knows about, cooldowns first.
CDM.CONST.VIEWER_CATEGORIES_ALL = BuildCategoryList(
    "Essential",
    "Utility",
    "TrackedBuff",
    "TrackedBar",
    "SpecAgnosticEssential",
    "SpecAgnosticTracked",
    "EquipSlotEssential",
    "EquipSlotTracked"
)

-- Item-backed categories only. Used to detect whether the client provides
-- native trinket/consumable tracking, which supersedes the Trinkets module.
CDM.CONST.VIEWER_CATEGORIES_EQUIP_SLOT = BuildCategoryList(
    "EquipSlotEssential",
    "EquipSlotTracked"
)

-- 12.1 marks some viewer entries invisible; they must never reach a picker.
function CDM.CONST.IsViewerEntryVisible(info)
    return info ~= nil and info.isInvisible ~= true
end

-- True when the running client exposes native equipment-slot cooldown
-- tracking and the player's spec actually has entries in it.
function CDM.CONST.HasNativeEquipSlotTracking()
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then
        return false
    end
    for _, cat in ipairs(CDM.CONST.VIEWER_CATEGORIES_EQUIP_SLOT) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids and #ids > 0 then
            return true
        end
    end
    return false
end

CDM.CONST.STAGGER_TIERS = {
    { enabled = "tier1Enabled", threshold = "tier1Threshold", color = "moderateColor" },
    { enabled = "tier2Enabled", threshold = "tier2Threshold", color = "heavyColor"    },
    { enabled = "tier3Enabled", threshold = "tier3Threshold", color = "tier3Color"    },
    { enabled = "tier4Enabled", threshold = "tier4Threshold", color = "tier4Color"    },
}

CDM.CONST.BAR_KEYS_SUPPORTING_TICKS = {
    Mana = true, Rage = true, Energy = true, Focus = true, RunicPower = true,
    LunarPower = true, Maelstrom = true, Insanity = true, Fury = true,
}
CDM.CONST.MAX_TICKS_PER_BAR = 5

CDM.CONST.TRACKER_FRAME_ACCESSORS = {
    "GetTrinketIconFrames",
    "GetCustomCooldownIconFrames",
}


CDM.CONST.DOT_OVERRIDE_SPELLS = {
    -- Druid
    [8921]   = true, -- Moonfire                  -- Balance
    [155625] = true, -- Moonfire                  -- Feral
    [33763]  = true, -- Lifebloom                 -- Restoration
    [93402]  = true, -- Sunfire
    [1822]   = true, -- Rake
    [1079]   = true, -- Rip
    [155722] = true, -- Rake (Stealthed)          -- Feral

    -- Priest
    [589]    = true, -- Shadow Word: Pain         -- Shadow
    [34914]  = true, -- Vampiric Touch            -- Shadow
    [335467] = true, -- Shadow Word: Madness      -- Shadow
    [204197] = true, -- Purge the Wicked          -- Discipline

    -- Warlock
    [980]    = true, -- Agony                     -- Affliction
    [172]    = true, -- Corruption                -- Affliction
    [1259790] = true, -- Unstable Affliction       -- Affliction
    [348]    = true, -- Immolate                  -- Destruction
    [445468]  = true, -- Wither                   -- Destruction

    -- Rogue
    [1943]   = true, -- Rupture                   -- Assassination
    [121411] = true, -- Crimson Tempest           -- Assassination
}

function CDM.CONST.IsEmptyTable(t)
    return type(t) == "table" and next(t) == nil
end

function CDM.CONST.ApplyShadow(fontString)
    local c = CDM.CONST.SHADOW_COLOR
    local o = CDM.CONST.SHADOW_OFFSET
    fontString:SetShadowColor(c.r, c.g, c.b, c.a)
    fontString:SetShadowOffset(o.x, o.y)
end

function CDM.CONST.GetConfigValue(key, defaultValue)
    local db = CDM.db
    if db then
        local v = db[key]
        if v ~= nil then return v end
    end
    local df = CDM.defaults
    if df then
        local v = df[key]
        if v ~= nil then return v end
    end
    return defaultValue
end


local baseFontCache = {
    fontPath = nil,
    fontOutline = nil,
}

local cachedLSM = nil
local function GetLSM()
    if cachedLSM then return cachedLSM end
    cachedLSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    return cachedLSM
end

function CDM.CONST.ResolveOutlineFlags(raw)
    if raw == nil or raw == "" or raw == "NONE" then return "" end
    if raw == "SLUG" then return "OUTLINE SLUG" end
    return raw
end

function CDM.CONST.RefreshBaseFontCache()
    local db = CDM.db
    local defaults = CDM.defaults or {}
    local textFontName = (db and db.textFont) or defaults.textFont or "Friz Quadrata TT"
    local LSM = GetLSM()
    baseFontCache.fontPath = (LSM and LSM:Fetch("font", textFontName)) or CDM.CONST.FONT_PATH
    local rawOutline = (db and db.textFontOutline) or defaults.textFontOutline or "OUTLINE"
    baseFontCache.fontOutline = CDM.CONST.ResolveOutlineFlags(rawOutline)
end

function CDM.CONST.GetBaseFontPath()
    if not baseFontCache.fontPath then
        CDM.CONST.RefreshBaseFontCache()
    end
    return baseFontCache.fontPath
end

function CDM.CONST.GetBaseFontOutline()
    if not baseFontCache.fontPath then
        CDM.CONST.RefreshBaseFontCache()
    end
    return baseFontCache.fontOutline
end

CDM.CONST.DesaturationCurve = C_CurveUtil.CreateCurve()
CDM.CONST.DesaturationCurve:SetType(Enum.LuaCurveType.Step)
CDM.CONST.DesaturationCurve:AddPoint(0, 0)
CDM.CONST.DesaturationCurve:AddPoint(0.001, 1)

