-- Fake game globals for DoorRewardCodex. Rather than stub the functions the
-- mod wraps, this reproduces the real bodies of SelectNearbyUnlockedEntry and
-- the row-building part of CodexOpenChapter (see rule 5, MODDING_HADES2.md
-- section 3) against a real slice of CodexData, so the suite exercises the
-- actual matching and formatting rules rather than a belief about them.
--
-- This table IS `game` as the plugin sees it (dofile'd, then handed to
-- M.install as `rom.game`), so every function below that stands in for a real
-- game global reads and writes G.* fields explicitly -- never bare globals --
-- the same discipline main.lua itself follows and for the same reason:
-- LuaENVY-ENVY isolation means a bare name resolves to nothing real.

local G = {}

-- ---------------------------------------------------------------- state ----

local nextObjectId = 900000
local function nextId()
    nextObjectId = nextObjectId + 1
    return nextObjectId
end

G.CurrentRun = { Hero = { ObjectId = nextId(), Weapons = {} } }
G.GameState = { ScreensViewed = { Codex = true }, CodexEntriesViewed = {} }
G.SessionState = { CodexDebugUnlocked = false }
G.MapState = { OfferedExitDoors = {}, ShipWheels = {} }
G.ActiveEnemies = {}

-- Real chapter/entry shapes, copied from CodexData.lua so the matching loop
-- and the row-building loop run against data with the same structure vanilla
-- ships -- UnlockGameStateRequirements included, not summarized away.
G.CodexData = {
    ChthonicGods = {
        Entries = {
            -- CodexData.lua:540-552. Used as "the thing already selected by
            -- proximity" in the "vanilla found something" tests.
            NPC_Hecate_01 = {
                Entries = {
                    { UnlockGameStateRequirements = { { PathTrue = { "GameState", "TextLinesRecord", "HecateGift01" } } },
                      Text = "CodexData_Hecate_01" },
                },
                Image = "Codex_Portrait_Hecate",
            },
            -- CodexData.lua:585-599. Selene's entry is named after her FIRST
            -- reward type; her later doors say TalentDrop / TalentBigDrop.
            SpellDrop = {
                Entries = {
                    { UnlockGameStateRequirements = { { PathTrue = { "GameState", "TextLinesRecord", "SeleneGift01" } } },
                      Text = "CodexData_Selene_01" },
                },
                Image = "Codex_Portrait_Selene",
            },
        },
    },
    OlympianGods = {
        Entries = {
            -- CodexData.lua:1373-1389.
            AphroditeUpgrade = {
                Entries = {
                    { UnlockGameStateRequirements = { { PathTrue = { "GameState", "TextLinesRecord", "AphroditeGift01" } } },
                      Text = "CodexData_Aphrodite_01" },
                },
                Image = "Codex_Portrait_Aphrodite",
                BoonInfoAllowPinning = true,
            },
            -- CodexData.lua:1287 (structure only; requirement text is this
            -- suite's own, the real one differs in wording, not shape).
            ZeusUpgrade = {
                Entries = {
                    { UnlockGameStateRequirements = { { PathTrue = { "GameState", "TextLinesRecord", "ZeusGift01" } } },
                      Text = "CodexData_Zeus_01" },
                },
                Image = "Codex_Portrait_Zeus",
                BoonInfoAllowPinning = true,
            },
            -- HermesUpgrade is both the CHOSEN REWARD TYPE (RewardLogic.lua:
            -- 362-367) and the Codex entry name -- the fallback in
            -- handleSingleReward (ForceLootName or ChosenRewardType) resolves
            -- it without any special-casing.
            HermesUpgrade = {
                Entries = {
                    { UnlockGameStateRequirements = { { PathTrue = { "GameState", "TextLinesRecord", "HermesGift01" } } },
                      Text = "CodexData_Hermes_01" },
                },
                Image = "Codex_Portrait_Hermes",
                BoonInfoAllowPinning = true,
            },
        },
    },
    Weapons = {
        Entries = {
            -- CodexData.lua:1630-1650 (structure only; SumOf list trimmed).
            WeaponDagger = {
                Entries = {
                    { UnlockGameStateRequirements = { { Path = { "GameState", "WeaponKills" }, SumOf = { "WeaponDagger" }, Comparison = ">=", Value = 400 } },
                      Text = "CodexData_WeaponDagger_01" },
                },
                Image = "Codex_Portrait_WeaponDagger",
                BoonInfoLootName = "WeaponUpgrade",
            },
            WeaponAxe = {
                Entries = {
                    { UnlockGameStateRequirements = { { Path = { "GameState", "WeaponKills" }, SumOf = { "WeaponAxe" }, Comparison = ">=", Value = 400 } },
                      Text = "CodexData_WeaponAxe_01" },
                },
                Image = "Codex_Portrait_WeaponAxe",
                BoonInfoLootName = "WeaponUpgrade",
            },
        },
    },
}

-- CodexOrdering.lua:1-6 (chapter list trimmed to the chapters this suite
-- uses). Order within a chapter matches CodexData.lua:11-13, 23-26.
G.CodexOrdering = {
    ChthonicGods = { "NPC_Hecate_01", "SpellDrop" },
    OlympianGods = { "ZeusUpgrade", "AphroditeUpgrade", "HermesUpgrade" },
    Weapons = { "WeaponDagger", "WeaponAxe" },
}

G.CodexStatus = { SelectedChapterName = "ChthonicGods", SelectedEntryNames = { ChthonicGods = "NPC_Hecate_01" } }

-- ConsumableData.lua:686-780. A Path of Stars pickup carries Selene's Codex
-- name as its GenusName, which is how vanilla's nearby-select reaches her page
-- from a drop on the ground. TalentBigDrop inherits it from TalentDrop; the
-- game resolves InheritFrom at load, so the field is on both at runtime.
G.ConsumableData = {
    TalentDrop = { GenusName = "SpellDrop", DoorIcon = "TalentDropPreview" },
    TalentBigDrop = { GenusName = "SpellDrop", DoorIcon = "TalentDropPreview", AddTalentPoints = 5 },
}

-- ----------------------------------------------------------- eligibility ----

-- IsGameStateEligible (RequirementsLogic.lua:9) is a large, generic
-- requirements evaluator used across the whole game, not something specific
-- to this feature. Faking it -- keyed by the REQUIREMENTS TABLE ITSELF, which
-- is a real object living on the real CodexData slice above -- lets each test
-- say which entries are unlocked without reimplementing an engine subsystem
-- this mod does not modify. Defaults to locked, matching a fresh save.
G.eligibility = {}
function G.IsGameStateEligible(source, requirements, args)
    if G.eligibility[requirements] ~= nil then
        return G.eligibility[requirements]
    end
    return false
end

-- Unlocks the sub-entry requirements object(s) for a CodexData entry, however
-- many chapters it takes to find it -- test setup, not part of the mod.
function G.unlockEntry(entryName)
    for _, chapterData in pairs(G.CodexData) do
        local entryData = chapterData.Entries[entryName]
        if entryData ~= nil then
            for _, subEntryData in ipairs(entryData.Entries) do
                if subEntryData.UnlockGameStateRequirements ~= nil then
                    G.eligibility[subEntryData.UnlockGameStateRequirements] = true
                end
            end
        end
    end
end

-- ------------------------------------------------------------- distance ----

-- GetDistance (used via GetDistance({Id=.., DestinationId=..}), confirmed
-- against real call sites e.g. EncounterLogic.lua:1273) is a native engine
-- call with no Lua body to copy. Faked as an explicit lookup so each test
-- states its own geometry instead of this harness guessing at one.
G.distances = {}
function G.GetDistance(args)
    local forId = G.distances[args.Id]
    if forId == nil then return 99999 end
    return forId[args.DestinationId] or 99999
end

-- Vanilla's own group search (CodexLogic.lua:130). Faked as a single settable
-- id: nil means "nothing nearby", matching every door-reward test, and a test
-- that needs vanilla to find something sets it directly.
G.nearbyId = nil
function G.GetClosest(args)
    return G.nearbyId
end

function G.GetName(args)
    return G.namedObjects and G.namedObjects[args.Id] or nil
end

-- --------------------------------------------------------------- ModUtil ----

G.wrapped = {}
G.ModUtil = {
    Path = {
        Wrap = function(name, wrapper)
            local base = G[name]
            if base == nil then
                error("ModUtil.Path.Wrap called on a global the harness does not define: " .. tostring(name))
            end
            G.wrapped[name] = (G.wrapped[name] or 0) + 1
            G[name] = function(...) return wrapper(base, ...) end
        end,
    },
}

-- ------------------------------------------------------- Codex utilities ----
-- Copied verbatim -- these are plain table helpers, not the algorithm under
-- test, and copying them costs nothing.

-- UtilityLogic.lua:54-65.
function G.ShallowCopyTable(t)
    if t == nil then return nil end
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

-- UtilityLogic.lua:254-267.
function G.OverwriteTableKeys(tableToOverwrite, tableToTake)
    if tableToTake == nil then return end
    for key, value in pairs(tableToTake) do
        if value == "nil" then
            tableToOverwrite[key] = nil
        else
            tableToOverwrite[key] = value
        end
    end
end

-- UtilityLogic.lua:472-479.
function G.IsEmpty(tableArg)
    if tableArg == nil then return true end
    return next(tableArg) == nil
end

-- Applies language-specific font overrides in the real game (UtilityLogic.lua
-- area); irrelevant to row selection and marking, so left as identity.
function G.ApplyLocalizedProperties(t) return t end

function G.DebugAssert(args) end

-- --------------------------------------------------- SelectNearbyUnlockedEntry ----
-- Copied from CodexLogic.lua:123-164, the exact function this mod wraps --
-- adapted only to read every game field through G.* rather than as a bare
-- global, matching how main.lua itself must read `game.*` under ENVY
-- isolation (see that file's header). The nearby-object resolution
-- (nearbyGenusName / GetName), the WeaponUpgrade special case and the
-- matching loop are otherwise byte-for-byte vanilla, which is what proves the
-- mod is matching against real rules rather than a belief about them.
function G.SelectNearbyUnlockedEntry()
    if not G.GameState.ScreensViewed.Codex then
        return
    end

    local nearbyId = G.GetClosest({ Id = G.CurrentRun.Hero.ObjectId, DestinationNames = { "NPCs", "ConsumableItems", "Loot", "EnemyTeam" }, Distance = 600 })
    local nearbyGenusName = nil
    if nearbyId ~= nil then
        if G.ActiveEnemies[nearbyId] ~= nil then
            nearbyGenusName = G.ActiveEnemies[nearbyId].CodexName or G.ActiveEnemies[nearbyId].GenusName
        elseif G.MapState.ActiveObstacles ~= nil and G.MapState.ActiveObstacles[nearbyId] ~= nil then
            nearbyGenusName = G.MapState.ActiveObstacles[nearbyId].GenusName
        end
    end

    local nearbyName = nearbyGenusName or G.GetName({ Id = nearbyId })
    if nearbyName == "WeaponUpgrade" then
        for weaponName in pairs(G.CurrentRun.Hero.Weapons) do
            if G.CodexData.Weapons.Entries[weaponName] then
                nearbyName = weaponName
                break
            end
        end
    end
    if nearbyName ~= nil then
        for chapterName, chapterData in pairs(G.CodexData) do
            for entryName, entryData in pairs(chapterData.Entries) do
                if entryName == nearbyName then
                    for i, subEntryData in ipairs(entryData.Entries) do
                        if subEntryData.UnlockGameStateRequirements ~= nil and G.IsGameStateEligible(subEntryData, subEntryData.UnlockGameStateRequirements) then
                            G.CodexStatus.SelectedChapterName = chapterName
                            G.CodexStatus.SelectedEntryNames[chapterName] = nearbyName
                            return
                        end
                    end
                end
            end
        end
    end
end

-- --------------------------------------------------------- CodexOpenChapter ----
-- A faithful slice of CodexLogic.lua:328-455: the "already open" gate, the
-- row-building loop with its three text formats, and the closing selected-
-- entry format re-application. Left out are the parts this mod neither reads
-- nor is asserted against -- tab-highlight animation (Move/SetAlpha on the
-- button), CodexScreenOpenChapterPresentation, cursor teleport, and
-- CodexOpenEntry's detail-pane body. Their absence is a scope choice, not an
-- attempt to make the row-building behave differently than it really does.
function G.IsScreenOpen(name) return true end
function G.CodexCloseChapter(screen, chapterName, chapterData, args) end -- CodexLogic.lua:558, teardown only

G.textBoxesCreated = {}
G.textBoxModifications = {}
function G.CreateTextBox(args)
    G.textBoxesCreated[#G.textBoxesCreated + 1] = args
end
function G.ModifyTextBox(args)
    G.textBoxModifications[#G.textBoxModifications + 1] = args
end

local nextComponentId = 800000
function G.CreateScreenComponent(args)
    nextComponentId = nextComponentId + 1
    return { Id = nextComponentId }
end
function G.AttachLua(args) end

function G.CodexOpenChapter(screen, button, args)
    args = args or {}
    local firstOpen = args.FirstOpen

    if not G.IsScreenOpen("Codex") then
        return
    end

    if button.ChapterName == G.CodexStatus.SelectedChapterName and not firstOpen then
        return -- CodexLogic.lua:338-341, "Already open"
    end

    G.CodexCloseChapter(screen, G.CodexStatus.SelectedChapterName, G.CodexData[G.CodexStatus.SelectedChapterName], args)
    G.CodexStatus.SelectedChapterName = button.ChapterName

    local entryX, entryY = 0, 0
    local numEntries = #(G.CodexOrdering[button.ChapterName] or {})

    screen.NumItems = 0
    screen.Components = screen.Components or {}
    local firstEntryName = nil

    for i = 1, numEntries do
        local entryName = G.CodexOrdering[button.ChapterName][i]
        local entryData = button.ChapterData.Entries[entryName]
        if entryData == nil then
            G.DebugAssert({ Condition = false, Text = "Missing entry" })
            break
        end

        local text = nil
        local requirements = entryData.UnlockGameStateRequirements
        if requirements == nil and not G.IsEmpty(entryData.Entries) then
            requirements = entryData.Entries[1].UnlockGameStateRequirements
        end
        if requirements == nil or G.SessionState.CodexDebugUnlocked or G.IsGameStateEligible(entryData, requirements) then
            text = entryName
        end
        if text ~= nil then
            local entry = G.CreateScreenComponent({ Name = "ButtonCodexEntry", X = entryX, Y = entryY })
            screen.Components[entryName] = entry
            entry.ChapterName = button.ChapterName
            entry.EntryName = entryName
            entry.EntryData = entryData
            G.AttachLua({ Id = entry.Id, Table = entry })

            local entryTextFormat = G.ApplyLocalizedProperties(G.ShallowCopyTable(screen.EntryTextFormat))

            firstEntryName = firstEntryName or entryName
            G.CodexStatus.SelectedEntryNames[button.ChapterName] = G.CodexStatus.SelectedEntryNames[button.ChapterName] or entryName

            if entryName == G.CodexStatus.SelectedEntryNames[button.ChapterName] then
                G.OverwriteTableKeys(entryTextFormat, screen.SelectedFormat)
            end

            if not G.GameState.CodexEntriesViewed[entryName] then
                G.OverwriteTableKeys(entryTextFormat, screen.UnreadUnselectedFormat)
            end

            entryTextFormat.Id = entry.Id
            entryTextFormat.Text = text
            G.CreateTextBox(entryTextFormat)

            screen.NumItems = screen.NumItems + 1
            entry.EntryIndex = screen.NumItems
        else
            if G.CodexStatus.SelectedEntryNames[button.ChapterName] == entryName then
                G.CodexStatus.SelectedEntryNames[button.ChapterName] = nil
            end
        end
    end

    local selectedEntryName = G.CodexStatus.SelectedEntryNames[button.ChapterName] or firstEntryName
    if selectedEntryName ~= nil and screen.Components[selectedEntryName] == nil then
        selectedEntryName = firstEntryName
    end
    if selectedEntryName ~= nil and screen.Components[selectedEntryName] ~= nil then
        local selectedFormat = G.ShallowCopyTable(screen.SelectedFormat)
        selectedFormat.Id = screen.Components[selectedEntryName].Id
        G.ModifyTextBox(selectedFormat)
    end
end

-- ------------------------------------------------------------ ScreenData ----
-- CodexData.lua:108-163, trimmed to the fields the row loop reads.
G.ScreenData = {
    Codex = {
        EntryTextFormat = { Color = { 46, 34, 43, 225 } },
        UnreadUnselectedFormat = { Color = { 242, 209, 161, 255 } },
        SelectedFormat = { Color = { 81, 224, 160, 255 } },
    },
}

-- --------------------------------------------------------- CloseCodexScreen ----
-- CodexLogic.lua:633-667, reduced to the guard this mod's wrap depends on.
-- The real function also tears down every screen component and runs several
-- presentation calls; none of that is exercised or asserted on here.
function G.CloseCodexScreen(screen, button)
    if screen == nil or screen.CloseTriggered then
        return
    end
    screen.CloseTriggered = true
end

-- Builds a fresh Codex screen table the way OpenCodexScreen would, minus the
-- presentation calls this suite does not exercise.
function G.newCodexScreen()
    return {
        Components = {},
        EntryTextFormat = G.ScreenData.Codex.EntryTextFormat,
        UnreadUnselectedFormat = G.ScreenData.Codex.UnreadUnselectedFormat,
        SelectedFormat = G.ScreenData.Codex.SelectedFormat,
    }
end

-- Button the way OpenCodexScreen resolves one from screen.Components (CodexLogic.lua:214-217).
function G.chapterButton(chapterName)
    return { ChapterName = chapterName, ChapterData = G.CodexData[chapterName] }
end

-- ---------------------------------------------------------------- helpers ----

-- Registers a door in MapState.OfferedExitDoors and gives it a distance from
-- the hero, the way AssignRoomToExitDoor (RoomLogic.lua:4098-4101) and the
-- hero's own position would.
function G.addDoor(room, distanceFromHero)
    local door = { ObjectId = nextId(), Room = room }
    G.MapState.OfferedExitDoors[door.ObjectId] = door
    G.distances[G.CurrentRun.Hero.ObjectId] = G.distances[G.CurrentRun.Hero.ObjectId] or {}
    G.distances[G.CurrentRun.Hero.ObjectId][door.ObjectId] = distanceFromHero
    return door
end

-- Registers a Thessaly steering wheel in MapState.ShipWheels the way the ship
-- encounter does (RoomLogic.lua:1387-1431): the reward is on the wheel, and
-- its Room is the current room, not the destination.
function G.addWheel(chosenRewardType, forceLootName, distanceFromHero)
    local wheel = { ObjectId = nextId(), Room = G.CurrentRun.CurrentRoom,
                    ChosenRewardType = chosenRewardType, ForceLootName = forceLootName }
    G.MapState.ShipWheels[wheel.ObjectId] = wheel
    G.distances[G.CurrentRun.Hero.ObjectId] = G.distances[G.CurrentRun.Hero.ObjectId] or {}
    G.distances[G.CurrentRun.Hero.ObjectId][wheel.ObjectId] = distanceFromHero
    return wheel
end

return G
