-- =============================================================================
-- DoorRewardCodex (v1.0.0) -- opens the Codex on a door's reward, not just on
-- nearby NPCs and items.
-- =============================================================================
-- Walking near an NPC, enemy or item and opening the Codex already lands on
-- that thing's page: SelectNearbyUnlockedEntry() (CodexLogic.lua:123) searches
-- groups NPCs/ConsumableItems/Loot/EnemyTeam within 600 units. Exit door reward
-- previews are the one case it misses -- they spawn into group Combat_UI, which
-- is not searched, and GetName on one returns "RoomRewardPreview" rather than
-- the reward (RewardPresentation.lua:65). This mod closes that gap using
-- vanilla's own function, radius and matching. See DESIGN.md (repo root, not
-- shipped) for the full citations and the decisions behind every branch below.
--
-- Two hooks, in order:
--   1. SelectNearbyUnlockedEntry -- let vanilla run first; only when it wrote
--      nothing, walk MapState.OfferedExitDoors (RoomLogic.lua:319) for the
--      closest door within the same 600 units and resolve its reward the way
--      vanilla resolves a nearby object's name (CodexLogic.lua:141-163). A
--      Devotion door or a room.CageRewards door offers more than one candidate
--      with nothing to disambiguate by proximity (RewardPresentation.lua:101-
--      125), so those open on the first and mark the rest (hook two). A
--      reward with no Codex entry at all (health, mana, darkness, nectar)
--      lands on Melinoe's own page -- vanilla's own default (CodexData.lua:
--      176-177), not a value this mod invented.
--   2. CodexOpenChapter -- when hook one flagged a split, re-format the
--      matching rows with SPLIT_ROW_FORMAT once the base call has built them
--      (CodexLogic.lua:404-426), through the same ModifyTextBox call vanilla
--      itself uses to flag an unread row. No marker object: UnreadStarId is dead code,
--      never assigned and its config commented out (CodexData.lua:92).
--
-- CloseCodexScreen clears the split flag so a later open never marks stale
-- rows (CodexLogic.lua:633).
--
-- CodexStatus is saved (SaveLogic.lua:9). This mod writes only the two fields
-- vanilla itself writes, with values vanilla itself produces -- see the
-- README's Compatibility section.
--
-- Every game read/write below goes through `game` (== rom.game), never a bare
-- global -- LuaENVY-ENVY isolates this plugin's own globals (DESIGN.md).
-- =============================================================================

local mods = rom.mods
mods["LuaENVY-ENVY"].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

local modutil = mods["SGG_Modding-ModUtil"]
local reload = mods["SGG_Modding-ReLoad"]

local LOG_PREFIX = "[DoorRewardCodex] "

-- Vanilla's own search radius (CodexLogic.lua:130).
local SEARCH_DISTANCE = 600

-- =============================================================================
-- Logging
-- =============================================================================

-- Deliberately rom.log.info for warnings too. In this ReturnOfModding build
-- rom.log.error RAISES rather than logs, so reporting a handled failure through
-- it turns that failure fatal. Severity is carried in the text instead.
local function logAlways(message)
    if rom and rom.log and rom.log.info then
        rom.log.info(LOG_PREFIX .. tostring(message))
    end
end

local function logWarn(message)
    if rom and rom.log and rom.log.info then
        rom.log.info(LOG_PREFIX .. "WARNING: " .. tostring(message))
    end
end

-- =============================================================================
-- Settings
-- =============================================================================

local settings = {
    values = {
        Enabled = true,
        MarkSplitRewards = true,
    },
    entries = {},
    file = nil,
    persistent = false,
}

local CONFIG_DESCRIPTIONS = {
    Enabled = "Master switch. Off leaves the Codex completely vanilla.",
    MarkSplitRewards = "On a two-god door, highlight both gods in the list once the chapter opens. Off still opens the right chapter.",
}

-- Bind with rom.config.config_file, not Chalk -- house style across this
-- author's mods.
local function loadSettings()
    local ok, err = pcall(function()
        if rom.config == nil or rom.config.config_file == nil then
            logWarn("rom.config unavailable; settings will not persist between sessions")
            return
        end
        local configDir = rom.paths and rom.paths.config and rom.paths.config() or nil
        if configDir == nil then
            logWarn("config directory unavailable; settings will not persist between sessions")
            return
        end

        local guid = (_PLUGIN and _PLUGIN.guid) or "Adicon-DoorRewardCodex"
        local path = rom.path.combine(configDir, guid .. ".cfg")
        local file = rom.config.config_file:new(path, true)

        for key, default in pairs(settings.values) do
            -- The label answers when a change starts mattering: both keys are
            -- read at the moment the Codex opens, so a change is live at once.
            settings.entries[key] = file:bind("General (applies immediately)", key, default,
                                              CONFIG_DESCRIPTIONS[key] or "")
        end

        -- Only adopt a stored value whose type matches the default, so a
        -- hand-edited .cfg cannot put a string where a boolean is expected.
        for key, entry in pairs(settings.entries) do
            local stored = entry:get()
            if type(stored) == type(settings.values[key]) then
                settings.values[key] = stored
            end
        end

        settings.file = file
        settings.persistent = true
    end)

    if not ok then
        logWarn("config load failed, using in-memory settings: " .. tostring(err))
    end
end

-- =============================================================================
-- Resolving a reward name to a Codex entry -- vanilla's own algorithm
-- =============================================================================

-- Mirrors SelectNearbyUnlockedEntry's WeaponUpgrade special case exactly
-- (CodexLogic.lua:141-148): a Daedalus Hammer door has no loot name of its
-- own, so it maps to whichever of the hero's weapons has a Codex entry.
local function resolveWeaponUpgradeName(game, name)
    if name ~= "WeaponUpgrade" then
        return name
    end
    for weaponName in pairs(game.CurrentRun.Hero.Weapons or {}) do
        if game.CodexData.Weapons.Entries[weaponName] then
            return weaponName
        end
    end
    return name
end

-- Mirrors SelectNearbyUnlockedEntry's matching loop exactly (CodexLogic.lua:
-- 149-163): find the chapter/entry pair named `name`, and only return it if at
-- least one of its sub-entries is currently unlocked. A reward with no Codex
-- entry -- health, gold, mana, darkness, nectar, other consumables -- simply
-- matches nothing here; the caller decides what a non-match means (below,
-- that is Melinoe's own page).
local function findCodexMatch(game, name)
    if name == nil then
        return nil, nil
    end
    name = resolveWeaponUpgradeName(game, name)
    for chapterName, chapterData in pairs(game.CodexData) do
        for entryName, entryData in pairs(chapterData.Entries) do
            if entryName == name then
                for _, subEntryData in ipairs(entryData.Entries) do
                    if subEntryData.UnlockGameStateRequirements ~= nil
                        and game.IsGameStateEligible(subEntryData, subEntryData.UnlockGameStateRequirements) then
                        return chapterName, name
                    end
                end
            end
        end
    end
    return nil, nil
end

-- =============================================================================
-- Finding the door
-- =============================================================================

-- Walks MapState.OfferedExitDoors (RoomLogic.lua:319), a table keyed by
-- object id, rather than searching a group -- door previews are in no group
-- SelectNearbyUnlockedEntry's own GetClosest call reaches.
--
-- The Rift of Thessaly has no doors. Its ship encounter puts the choice on
-- one or two steering wheels (RoomLogic.lua:1387-1431), kept in
-- MapState.ShipWheels, and the reward lives on the wheel obstacle itself:
-- ChosenRewardType and ForceLootName are set on it, and its .Room is the
-- CURRENT room, not the next one. Reported 2026-09-16: the Codex sat on
-- whatever it last showed, because nothing here knew a wheel from a wall.
-- Both tables are walked; the closest of either wins.
local function closestOfferedDoor(game)
    local heroId = game.CurrentRun.Hero.ObjectId
    local closest, closestDistance, closestIsWheel = nil, nil, false
    local function consider(object, isWheel)
        local distance = game.GetDistance({ Id = heroId, DestinationId = object.ObjectId })
        if distance ~= nil and distance <= SEARCH_DISTANCE
            and (closestDistance == nil or distance < closestDistance) then
            closest, closestDistance, closestIsWheel = object, distance, isWheel
        end
    end
    for _, door in pairs(game.MapState.OfferedExitDoors or {}) do consider(door, false) end
    for _, wheel in pairs(game.MapState.ShipWheels or {}) do consider(wheel, true) end
    return closest, closestIsWheel
end

-- =============================================================================
-- The split flag -- state carried between the two hooks
-- =============================================================================

-- Set by handleDoorRewards when a door has more than one candidate reward with
-- nothing to disambiguate by proximity (a Devotion door, or room.CageRewards).
-- Cleared when the Codex closes (see the CloseCodexScreen wrap below) so a
-- later open never marks rows left over from a previous door. Kept on this
-- plugin's own local table, never on a game object.
local splitFlag = nil

-- Devotion always offers two Olympian boons -- confirmed against the game,
-- not assumed -- so the chapter needs no resolution. See DESIGN.md.
local DEVOTION_CHAPTER = "OlympianGods"

-- Vanilla's own default landing page (CodexData.lua:176-177,
-- ScreenData.Codex.DefaultChapter / DefaultEntry) -- Melinoe's own entry, used
-- unconditionally by CodexInit before anything has ever been selected. Used as
-- the fallback for a door reward with no Codex entry of its own (health, gold,
-- mana, darkness, nectar and other consumables). See DESIGN.md.
local FALLBACK_CHAPTER = "ChthonicGods"
local FALLBACK_ENTRY = "PlayerUnit"

-- The row format for the other god of a split. Vanilla's unread format is a
-- parchment color with a dark drop shadow, easy to miss beside the selected
-- row's green. This is a gold with the shadow turned into a soft gold halo
-- (blur up, offsets zero, shadow the same hue): the same ModifyTextBox
-- fields vanilla's own formats use, nothing the text box does not already
-- support. See CodexData.lua:128-162 for the three formats it sits beside.
local SPLIT_ROW_FORMAT = {
    Color = { 255, 214, 96, 255 },
    DataProperties = {
        ShadowBlur = 8,
        ShadowRed = 255, ShadowGreen = 190, ShadowBlue = 60, ShadowAlpha = 1,
        ShadowOffsetX = 0, ShadowOffsetY = 0,
    },
}

local function handleSingleReward(game, room)
    local name = room.ForceLootName or room.ChosenRewardType
    local chapterName, entryName = findCodexMatch(game, name)
    -- One line per resolution, so "it opened on the wrong page" can be read
    -- off the log: what the door said, and what the Codex had for it.
    if chapterName == nil then
        logAlways(("door reward %s (type %s): no unlocked Codex entry, opening Melinoe's page")
            :format(tostring(name), tostring(room.ChosenRewardType)))
        chapterName, entryName = FALLBACK_CHAPTER, FALLBACK_ENTRY
    else
        logAlways(("door reward %s (type %s): opening %s / %s")
            :format(tostring(name), tostring(room.ChosenRewardType), chapterName, entryName))
    end
    game.CodexStatus.SelectedChapterName = chapterName
    game.CodexStatus.SelectedEntryNames[chapterName] = entryName
end

-- Lands on the first god's page and marks the second god's row, so the
-- Codex opens on something rather than on whichever Olympian was last read
-- (the earlier build set only the chapter, and the game then showed its
-- last selection). "First" is LootAName, the order the door preview draws
-- them in. If the first god has no entry, it falls back to the old behavior:
-- chapter only, both rows marked.
local function handleDevotionReward(game, room)
    local encounter = room.Encounter or {}
    game.CodexStatus.SelectedChapterName = DEVOTION_CHAPTER
    local chapterA, entryA = findCodexMatch(game, encounter.LootAName)
    if chapterA == DEVOTION_CHAPTER and entryA ~= nil then
        game.CodexStatus.SelectedEntryNames[DEVOTION_CHAPTER] = entryA
        splitFlag = { chapter = DEVOTION_CHAPTER, names = { encounter.LootBName } }
    else
        splitFlag = { chapter = DEVOTION_CHAPTER, names = { encounter.LootAName, encounter.LootBName } }
    end
    logAlways(("split door (Devotion): chapter=%s, gods=%s/%s, opened on %s")
        :format(DEVOTION_CHAPTER, tostring(encounter.LootAName), tostring(encounter.LootBName),
                tostring(game.CodexStatus.SelectedEntryNames[DEVOTION_CHAPTER])))
end

-- room.CageRewards is a list of { RewardType, ForceLootName } entries
-- (InteractLogic.lua:1457-1462), unlike Devotion not guaranteed to be gods or
-- to share a chapter. Resolve every candidate, take the chapter of the first
-- one that resolves, and mark whichever others land in that same chapter.
-- Falls back to Melinoe's page if none resolve. See DESIGN.md for the policy
-- behind "first that resolves."
local function handleCageRewards(game, room)
    local chapter, first = nil, nil
    local marked = {}
    for _, cageReward in ipairs(room.CageRewards) do
        local rewardName = cageReward.ForceLootName or cageReward.RewardType
        local chapterName, entryName = findCodexMatch(game, rewardName)
        if chapterName ~= nil and chapter == nil then
            chapter, first = chapterName, entryName
        elseif chapterName ~= nil and chapterName == chapter then
            marked[#marked + 1] = entryName
        end
    end
    if chapter == nil then
        game.CodexStatus.SelectedChapterName = FALLBACK_CHAPTER
        game.CodexStatus.SelectedEntryNames[FALLBACK_CHAPTER] = FALLBACK_ENTRY
        return
    end
    -- Same shape as Devotion: open on the first, mark the rest.
    game.CodexStatus.SelectedChapterName = chapter
    game.CodexStatus.SelectedEntryNames[chapter] = first
    splitFlag = { chapter = chapter, names = marked }
    logAlways(("split door (CageRewards): chapter=%s, opened on %s, marked=%s")
        :format(chapter, tostring(first), table.concat(marked, ",")))
end

local function handleDoorRewards(game)
    local door, isWheel = closestOfferedDoor(game)
    if door == nil then
        logAlways("no door or wheel within " .. SEARCH_DISTANCE .. "; leaving the Codex as it was")
        return
    end

    game.CodexStatus.SelectedEntryNames = game.CodexStatus.SelectedEntryNames or {}

    -- A wheel carries its own reward. A Trial of the Gods on a wheel keeps
    -- its two gods where SetupRoomReward wrote them (RewardLogic.lua:267-273):
    -- on the Encounter of the room it was handed, which for a wheel is the
    -- CURRENT room -- wheel.Room -- so the Devotion path reads the same
    -- fields it reads for a door. Reported 2026-09-16: a two-god wheel landed
    -- on Melinoe's page because it went down the single-reward path.
    -- Anything else on a wheel is a single reward; hand it over as the "room"
    -- that path reads. Cage rewards never come on a wheel.
    if isWheel then
        if door.ChosenRewardType == "Devotion" and door.Room ~= nil then
            handleDevotionReward(game, door.Room)
        else
            handleSingleReward(game, { ForceLootName = door.ForceLootName,
                                       ChosenRewardType = door.ChosenRewardType })
        end
        return
    end

    local room = door.Room
    if room == nil then
        return
    end

    if room.ChosenRewardType == "Devotion" then
        handleDevotionReward(game, room)
    elseif room.CageRewards ~= nil then
        handleCageRewards(game, room)
    else
        handleSingleReward(game, room)
    end
end

-- =============================================================================
-- Install
-- =============================================================================

local function installHooks(game)
    local ModUtil = game.ModUtil
    if ModUtil == nil or ModUtil.Path == nil or ModUtil.Path.Wrap == nil then
        logWarn("ModUtil.Path.Wrap unavailable; hooks not installed")
        return false
    end

    -- Let vanilla run first. If it selected something, its answer wins and
    -- this mod does nothing -- the player is standing next to an actual
    -- object, which is more specific than a door across the room. Snapshot-
    -- and-compare rather than reimplementing vanilla's own search; see
    -- DESIGN.md for the one edge case that trade-off accepts.
    ModUtil.Path.Wrap("SelectNearbyUnlockedEntry", function(base)
        if not settings.values.Enabled then
            return base()
        end

        local prevChapter = game.CodexStatus.SelectedChapterName
        local prevEntry = game.CodexStatus.SelectedEntryNames and game.CodexStatus.SelectedEntryNames[prevChapter]

        base()

        local vanillaChangedSomething = game.CodexStatus.SelectedChapterName ~= prevChapter
            or (game.CodexStatus.SelectedEntryNames and game.CodexStatus.SelectedEntryNames[prevChapter]) ~= prevEntry
        if vanillaChangedSomething then
            logAlways(("vanilla found something nearby and opened %s / %s; standing down")
                :format(tostring(game.CodexStatus.SelectedChapterName),
                        tostring(game.CodexStatus.SelectedEntryNames
                            and game.CodexStatus.SelectedEntryNames[game.CodexStatus.SelectedChapterName])))
            return
        end

        -- Vanilla's own gate (CodexLogic.lua:126-128). Do not bypass it: the
        -- auto-select only starts once the player has opened the Codex once.
        if not game.GameState.ScreensViewed.Codex then
            return
        end

        local ok, err = pcall(handleDoorRewards, game)
        if not ok then
            logWarn("could not resolve a door reward, leaving the Codex as vanilla left it: " .. tostring(err))
        end
    end)

    -- Rows are built here (CodexLogic.lua:404-426). Re-format the ones hook one
    -- flagged, once the base call has finished building every row in the
    -- chapter, through the ModifyTextBox call vanilla uses for its own
    -- formats (:501), with this mod's SPLIT_ROW_FORMAT.
    ModUtil.Path.Wrap("CodexOpenChapter", function(base, screen, button, args)
        base(screen, button, args)

        if not settings.values.Enabled or not settings.values.MarkSplitRewards then
            return
        end
        if splitFlag == nil or button.ChapterName ~= splitFlag.chapter then
            return
        end

        local ok, err = pcall(function()
            for _, entryName in ipairs(splitFlag.names) do
                local component = entryName ~= nil and screen.Components[entryName] or nil
                if component ~= nil then
                    local fmt = game.ShallowCopyTable(SPLIT_ROW_FORMAT)
                    fmt.Id = component.Id
                    game.ModifyTextBox(fmt)
                end
            end
        end)
        if not ok then
            logWarn("could not mark the split reward's rows: " .. tostring(err))
        end
    end)

    -- Clears the flag so a later open never marks rows left over from a door
    -- the player is no longer standing near.
    ModUtil.Path.Wrap("CloseCodexScreen", function(base, screen, button)
        base(screen, button)
        splitFlag = nil
    end)

    return true
end

-- =============================================================================
-- Boot
-- =============================================================================

loadSettings()

-- Runs ONCE. A second copy of any of these wraps would nest another wrapper
-- around the same global every time an unrelated mod reloads.
local function on_ready(game)
    if installHooks(game) then
        logAlways(("installed; enabled=%s, mark split rewards=%s")
            :format(tostring(settings.values.Enabled), tostring(settings.values.MarkSplitRewards)))
    end
end

-- Runs on load AND on every hot reload, so it must be safe to repeat. Only
-- re-reads settings; it installs nothing.
local function on_reload()
    loadSettings()
    logAlways(("settings reloaded; enabled=%s, mark split rewards=%s")
        :format(tostring(settings.values.Enabled), tostring(settings.values.MarkSplitRewards)))
end

if reload ~= nil and type(reload.auto_single) == "function" then
    local loader = reload.auto_single()
    modutil.once_loaded.game(function()
        local ok, err = pcall(function()
            local game = rom.game
            if game == nil then
                logWarn("rom.game is nil; not installing")
                return
            end
            loader.load(function() on_ready(game) end, on_reload)
        end)
        if not ok then
            logWarn("install failed, plugin inactive: " .. tostring(err))
        end
    end)
else
    -- ReLoad is a declared dependency, but a profile can be missing it. Falling
    -- back costs hot reload and nothing else.
    logWarn("SGG_Modding-ReLoad unavailable; installing without hot reload")
    modutil.once_loaded.game(function()
        local ok, err = pcall(function()
            local game = rom.game
            if game == nil then
                logWarn("rom.game is nil; not installing")
                return
            end
            on_ready(game)
        end)
        if not ok then
            logWarn("install failed, plugin inactive: " .. tostring(err))
        end
    end)
end

-- Exposed for the test suite only. The game ignores the return value of a
-- plugin chunk, so this costs nothing at runtime.
return {
    settings = settings,
}
