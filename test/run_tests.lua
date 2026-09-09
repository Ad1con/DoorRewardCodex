-- DoorRewardCodex test suite. Run from this directory:
--     lua run_tests.lua
--     luajit run_tests.lua
--
-- Both interpreters, always. The game ships LuaJIT and the two differ in ways
-- that have bitten sibling mods before.

local PLUGIN = "../src/main.lua"
local HARNESS = "./harness.lua"
local M = dofile("./mocks.lua")

local passed, failed = 0, 0
local failures = {}

-- Assertions must FAIL, not raise: a regression that makes a value nil must
-- read as one red line, not abort the run and hide every later section.
local function check(name, condition, detail)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    detail = detail and tostring(detail) or nil
    if detail and #detail > 140 then
      detail = detail:sub(1, 137) .. "..."
    end
    failures[#failures + 1] = name .. (detail and ("  -- " .. detail) or "")
  end
end

-- Guarded index, so asserting on a field of something that turned out nil is a
-- failure rather than a crash.
local function at(t, k)
  if type(t) ~= "table" then return nil end
  return t[k]
end

local function logsContain(needle)
  for _, line in ipairs(M.logs or {}) do
    if tostring(line):find(needle, 1, true) then return true end
  end
  return false
end

-- Boots the plugin against fresh fakes.
--
-- With no arguments this is EXACTLY the shipping configuration: the mock
-- config store starts empty, so every key binds to the plugin's own default.
-- Tests that need a non-default value pass it in `initial` and thereby state
-- what they depend on, rather than inheriting it.
local function boot(initial, opts)
  opts = opts or {}
  local G = dofile(HARNESS)
  M.install(G, opts.configOpts, initial, { noReload = opts.noReload })
  if opts.noModUtil then G.ModUtil = nil end
  local plugin = dofile(PLUGIN)
  if M.pendingGameLoad then M.pendingGameLoad() end
  return G, plugin
end

-- The last ModifyTextBox call that touched a given component id, or nil if
-- none did. Replaying in order rather than a single lookup table because a
-- later call can supersede an earlier one on the same id.
local function lastModificationFor(G, id)
  local last = nil
  for _, call in ipairs(G.textBoxModifications) do
    if call.Id == id then last = call end
  end
  return last
end

local function sameColor(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

-- =============================================================================
-- 1. What actually ships
-- =============================================================================
do
  local G, plugin = boot()
  local v = at(at(plugin, "settings"), "values")

  check("1.1 ships enabled", at(v, "Enabled") == true, tostring(at(v, "Enabled")))
  check("1.2 ships marking split rewards", at(v, "MarkSplitRewards") == true, tostring(at(v, "MarkSplitRewards")))
  check("1.3 settings persist when rom.config is available",
        at(at(plugin, "settings"), "persistent") == true)
  check("1.4 exactly the three globals are wrapped, once each",
        at(G.wrapped, "SelectNearbyUnlockedEntry") == 1
        and at(G.wrapped, "CodexOpenChapter") == 1
        and at(G.wrapped, "CloseCodexScreen") == 1,
        "SNUE=" .. tostring(at(G.wrapped, "SelectNearbyUnlockedEntry"))
        .. " COC=" .. tostring(at(G.wrapped, "CodexOpenChapter"))
        .. " CCS=" .. tostring(at(G.wrapped, "CloseCodexScreen")))
  local extraWraps = 0
  for name in pairs(G.wrapped) do
    if name ~= "SelectNearbyUnlockedEntry" and name ~= "CodexOpenChapter" and name ~= "CloseCodexScreen" then
      extraWraps = extraWraps + 1
    end
  end
  check("1.5 and nothing else", extraWraps == 0, tostring(extraWraps))
  check("1.6 every setting has a description in the .cfg",
        M.bound.Enabled ~= nil and M.bound.Enabled.description ~= ""
        and M.bound.MarkSplitRewards ~= nil and M.bound.MarkSplitRewards.description ~= "")
end

-- =============================================================================
-- 2. Vanilla wins when vanilla finds something (case 1)
-- =============================================================================
do
  local G = boot()
  -- Vanilla finds Zeus nearby and switches chapter AND entry away from the
  -- ChthonicGods/NPC_Hecate_01 default -- a change the snapshot-and-compare
  -- in hook one can actually observe (spec section 3.1). Matching an object
  -- that resolves to the value already selected would make "vanilla changed
  -- nothing" and "vanilla matched but agreed with the default" indistinguishable,
  -- which is a known, accepted limit of that technique -- not what this test
  -- is for.
  G.nearbyId = G.CurrentRun.Hero.ObjectId + 1
  G.ActiveEnemies[G.nearbyId] = { GenusName = "ZeusUpgrade" }
  G.unlockEntry("ZeusUpgrade")

  -- A door is ALSO in range with a different reward. If the mod ran its own
  -- search regardless of vanilla's result, this is what it would switch to --
  -- so seeing it NOT switch is what proves hook one deferred to vanilla.
  G.unlockEntry("AphroditeUpgrade")
  G.addDoor({ ChosenRewardType = "Boon", ForceLootName = "AphroditeUpgrade" }, 100)

  G.SelectNearbyUnlockedEntry()

  check("2.1 vanilla's own match wins",
        G.CodexStatus.SelectedChapterName == "OlympianGods",
        tostring(G.CodexStatus.SelectedChapterName))
  check("2.2 and the mod did not overwrite the entry vanilla chose",
        G.CodexStatus.SelectedEntryNames.OlympianGods == "ZeusUpgrade",
        tostring(G.CodexStatus.SelectedEntryNames.OlympianGods))
end

-- =============================================================================
-- 3. A single boon door in range, vanilla finds nothing (case 2)
-- =============================================================================
do
  local G = boot()
  G.unlockEntry("AphroditeUpgrade")
  G.addDoor({ ChosenRewardType = "Boon", ForceLootName = "AphroditeUpgrade" }, 300)

  G.SelectNearbyUnlockedEntry()

  check("3.1 the chapter switches to the god's chapter",
        G.CodexStatus.SelectedChapterName == "OlympianGods",
        tostring(G.CodexStatus.SelectedChapterName))
  check("3.2 and the entry is set to that god",
        G.CodexStatus.SelectedEntryNames.OlympianGods == "AphroditeUpgrade",
        tostring(G.CodexStatus.SelectedEntryNames.OlympianGods))
end

-- =============================================================================
-- 4. The same door, but out of range (case 3)
-- =============================================================================
do
  local G = boot()
  G.unlockEntry("AphroditeUpgrade")
  G.addDoor({ ChosenRewardType = "Boon", ForceLootName = "AphroditeUpgrade" }, 601)

  G.SelectNearbyUnlockedEntry()

  check("4.1 a door beyond 600 units changes nothing",
        G.CodexStatus.SelectedChapterName == "ChthonicGods",
        tostring(G.CodexStatus.SelectedChapterName))
  check("4.2 and the original entry is untouched",
        G.CodexStatus.SelectedEntryNames.ChthonicGods == "NPC_Hecate_01")
end

-- =============================================================================
-- 5. A Devotion door -- chapter only (case 4)
-- =============================================================================
do
  local G = boot()
  G.unlockEntry("ZeusUpgrade")
  G.unlockEntry("AphroditeUpgrade")
  G.addDoor({ ChosenRewardType = "Devotion", Encounter = { LootAName = "ZeusUpgrade", LootBName = "AphroditeUpgrade" } }, 200)

  G.SelectNearbyUnlockedEntry()

  check("5.1 the chapter switches to OlympianGods",
        G.CodexStatus.SelectedChapterName == "OlympianGods",
        tostring(G.CodexStatus.SelectedChapterName))
  check("5.2 the entry is NOT set for OlympianGods",
        G.CodexStatus.SelectedEntryNames.OlympianGods == nil,
        tostring(G.CodexStatus.SelectedEntryNames.OlympianGods))
  check("5.3 the previous chapter's entry survives untouched",
        G.CodexStatus.SelectedEntryNames.ChthonicGods == "NPC_Hecate_01")
end

-- =============================================================================
-- 6. A Devotion door -- both rows re-formatted, no others (case 5)
-- =============================================================================
do
  local G = boot()
  G.unlockEntry("ZeusUpgrade")
  G.unlockEntry("AphroditeUpgrade")
  G.unlockEntry("HermesUpgrade")
  G.addDoor({ ChosenRewardType = "Devotion", Encounter = { LootAName = "ZeusUpgrade", LootBName = "AphroditeUpgrade" } }, 200)

  G.SelectNearbyUnlockedEntry()

  local screen = G.newCodexScreen()
  G.CodexOpenChapter(screen, G.chapterButton("OlympianGods"), { FirstOpen = true })

  local unreadColor = G.ScreenData.Codex.UnreadUnselectedFormat.Color
  local zeus = screen.Components.ZeusUpgrade
  local aphrodite = screen.Components.AphroditeUpgrade
  local hermes = screen.Components.HermesUpgrade

  check("6.1 Zeus's row exists", zeus ~= nil)
  check("6.2 Aphrodite's row exists", aphrodite ~= nil)
  check("6.3 Hermes's row exists", hermes ~= nil)

  check("6.4 Zeus's row carries the unread-unselected color",
        sameColor(at(lastModificationFor(G, at(zeus, "Id")), "Color"), unreadColor))
  check("6.5 Aphrodite's row carries the unread-unselected color",
        sameColor(at(lastModificationFor(G, at(aphrodite, "Id")), "Color"), unreadColor))

  local hermesLast = lastModificationFor(G, at(hermes, "Id"))
  check("6.6 Hermes's row does NOT carry it",
        hermesLast == nil or not sameColor(hermesLast.Color, unreadColor))

  -- No component outside the two named entries was ever given that color.
  local markedIds = { [at(zeus, "Id")] = true, [at(aphrodite, "Id")] = true }
  local strayMarks = 0
  for _, call in ipairs(G.textBoxModifications) do
    if sameColor(call.Color, unreadColor) and not markedIds[call.Id] then
      strayMarks = strayMarks + 1
    end
  end
  check("6.7 and no other row anywhere was marked", strayMarks == 0, tostring(strayMarks))
end

-- =============================================================================
-- 7. room.CageRewards behaves as a split, not a single (case 6)
-- =============================================================================
do
  local G = boot()
  G.unlockEntry("AphroditeUpgrade")
  G.unlockEntry("ZeusUpgrade")
  G.addDoor({ CageRewards = {
      { RewardType = "Boon", ForceLootName = "AphroditeUpgrade" },
      { RewardType = "Boon", ForceLootName = "ZeusUpgrade" },
  } }, 250)

  G.SelectNearbyUnlockedEntry()

  check("7.1 the chapter switches to OlympianGods",
        G.CodexStatus.SelectedChapterName == "OlympianGods",
        tostring(G.CodexStatus.SelectedChapterName))
  check("7.2 the entry is NOT set, exactly like a Devotion door",
        G.CodexStatus.SelectedEntryNames.OlympianGods == nil,
        tostring(G.CodexStatus.SelectedEntryNames.OlympianGods))
end

-- =============================================================================
-- 8. A reward with no Codex entry -- health, gold (case 7)
-- =============================================================================
do
  local G = boot()
  G.addDoor({ ChosenRewardType = "MaxHealthDrop" }, 100)

  G.SelectNearbyUnlockedEntry()

  check("8.1 nothing changes", G.CodexStatus.SelectedChapterName == "ChthonicGods",
        tostring(G.CodexStatus.SelectedChapterName))
  check("8.2 and the entry survives untouched",
        G.CodexStatus.SelectedEntryNames.ChthonicGods == "NPC_Hecate_01")
end

-- =============================================================================
-- 9. A hammer door resolves through WeaponUpgrade (case 8)
-- =============================================================================
do
  local G = boot()
  G.CurrentRun.Hero.Weapons = { WeaponDagger = true }
  G.unlockEntry("WeaponDagger")
  G.addDoor({ ChosenRewardType = "WeaponUpgrade" }, 150)

  G.SelectNearbyUnlockedEntry()

  check("9.1 the chapter switches to Weapons",
        G.CodexStatus.SelectedChapterName == "Weapons", tostring(G.CodexStatus.SelectedChapterName))
  check("9.2 the entry is the hero's actual weapon",
        G.CodexStatus.SelectedEntryNames.Weapons == "WeaponDagger",
        tostring(G.CodexStatus.SelectedEntryNames.Weapons))
end

-- Same door, but the hero carries a different weapon -- proves the mapping
-- reads the hero's own loadout rather than a fixed weapon name.
do
  local G = boot()
  G.CurrentRun.Hero.Weapons = { WeaponAxe = true }
  G.unlockEntry("WeaponAxe")
  G.addDoor({ ChosenRewardType = "WeaponUpgrade" }, 150)

  G.SelectNearbyUnlockedEntry()

  check("9.3 a different weapon resolves to its own entry",
        G.CodexStatus.SelectedEntryNames.Weapons == "WeaponAxe",
        tostring(G.CodexStatus.SelectedEntryNames.Weapons))
end

-- =============================================================================
-- 10. GameState.ScreensViewed.Codex false -- the mod does nothing (case 9)
-- =============================================================================
do
  local G = boot()
  G.GameState.ScreensViewed.Codex = false
  G.unlockEntry("AphroditeUpgrade")
  G.addDoor({ ChosenRewardType = "Boon", ForceLootName = "AphroditeUpgrade" }, 100)

  G.SelectNearbyUnlockedEntry()

  check("10.1 nothing changes before the Codex has ever been opened",
        G.CodexStatus.SelectedChapterName == "ChthonicGods",
        tostring(G.CodexStatus.SelectedChapterName))
  check("10.2 and the entry is untouched",
        G.CodexStatus.SelectedEntryNames.ChthonicGods == "NPC_Hecate_01")
end

-- =============================================================================
-- 11. Enabled = false -- the Codex is byte-identical to vanilla (case 10)
-- =============================================================================
do
  local G = boot({ Enabled = false })
  G.unlockEntry("AphroditeUpgrade")
  G.addDoor({ ChosenRewardType = "Boon", ForceLootName = "AphroditeUpgrade" }, 100)

  G.SelectNearbyUnlockedEntry()

  check("11.1 disabled means no door search happens at all",
        G.CodexStatus.SelectedChapterName == "ChthonicGods",
        tostring(G.CodexStatus.SelectedChapterName))
  check("11.2 and the entry is untouched",
        G.CodexStatus.SelectedEntryNames.ChthonicGods == "NPC_Hecate_01")

  -- And even a Devotion door, which the mod would otherwise flag for hook two,
  -- leaves no trace to mark.
  G.addDoor({ ChosenRewardType = "Devotion", Encounter = { LootAName = "ZeusUpgrade", LootBName = "AphroditeUpgrade" } }, 50)
  G.SelectNearbyUnlockedEntry()
  local screen = G.newCodexScreen()
  G.CodexOpenChapter(screen, G.chapterButton("OlympianGods"), { FirstOpen = true })
  local unreadColor = G.ScreenData.Codex.UnreadUnselectedFormat.Color
  local marked = 0
  for _, call in ipairs(G.textBoxModifications) do
    if sameColor(call.Color, unreadColor) then marked = marked + 1 end
  end
  check("11.3 and hook two marks nothing either", marked == 0, tostring(marked))
end

-- =============================================================================
-- 12. MarkSplitRewards = false -- chapter still switches, no rows marked (case 11)
-- =============================================================================
do
  local G = boot({ MarkSplitRewards = false })
  G.unlockEntry("ZeusUpgrade")
  G.unlockEntry("AphroditeUpgrade")
  G.addDoor({ ChosenRewardType = "Devotion", Encounter = { LootAName = "ZeusUpgrade", LootBName = "AphroditeUpgrade" } }, 200)

  G.SelectNearbyUnlockedEntry()
  check("12.1 the chapter still switches", G.CodexStatus.SelectedChapterName == "OlympianGods",
        tostring(G.CodexStatus.SelectedChapterName))

  local screen = G.newCodexScreen()
  G.CodexOpenChapter(screen, G.chapterButton("OlympianGods"), { FirstOpen = true })

  local unreadColor = G.ScreenData.Codex.UnreadUnselectedFormat.Color
  local marked = 0
  for _, call in ipairs(G.textBoxModifications) do
    if sameColor(call.Color, unreadColor) then marked = marked + 1 end
  end
  check("12.2 but no row is reformatted", marked == 0, tostring(marked))
end

-- =============================================================================
-- 13. The split flag is cleared on Codex close (case 12)
-- =============================================================================
do
  local G = boot()
  G.unlockEntry("ZeusUpgrade")
  G.unlockEntry("AphroditeUpgrade")
  G.addDoor({ ChosenRewardType = "Devotion", Encounter = { LootAName = "ZeusUpgrade", LootBName = "AphroditeUpgrade" } }, 200)
  G.SelectNearbyUnlockedEntry()

  local screen = G.newCodexScreen()
  G.CodexOpenChapter(screen, G.chapterButton("OlympianGods"), { FirstOpen = true })
  local unreadColor = G.ScreenData.Codex.UnreadUnselectedFormat.Color
  local zeusId = screen.Components.ZeusUpgrade.Id
  check("13.1 sanity: the row was marked before closing",
        sameColor(at(lastModificationFor(G, zeusId), "Color"), unreadColor))

  G.CloseCodexScreen(screen, nil)

  -- Reopen on a different chapter and back, the way clicking two tabs would,
  -- so CodexOpenChapter's own "already open" gate does not just skip the
  -- rebuild -- CodexLogic.lua:338-341.
  G.textBoxModifications = {}
  local weaponsScreen = G.newCodexScreen()
  G.CodexOpenChapter(weaponsScreen, G.chapterButton("Weapons"), {})
  local olympianScreen = G.newCodexScreen()
  G.CodexOpenChapter(olympianScreen, G.chapterButton("OlympianGods"), {})

  local marked = 0
  for _, call in ipairs(G.textBoxModifications) do
    if sameColor(call.Color, unreadColor) then marked = marked + 1 end
  end
  check("13.2 the next open marks nothing -- the flag did not survive the close",
        marked == 0, tostring(marked))
end

-- =============================================================================
-- 14. Robustness -- a resolution failure must not break the Codex
-- =============================================================================
do
  local G = boot()
  -- A malformed door: CageRewards present but empty. ipairs sees nothing, so
  -- the handler should simply find no chapter and leave the Codex alone,
  -- without raising.
  G.addDoor({ CageRewards = {} }, 50)
  local ok = pcall(G.SelectNearbyUnlockedEntry)
  check("14.1 an empty CageRewards list does not raise", ok == true)
  check("14.2 and nothing changed", G.CodexStatus.SelectedChapterName == "ChthonicGods")
end

do
  local G = boot(nil, { noModUtil = true })
  check("14.3 no ModUtil is reported, not raised", logsContain("ModUtil.Path.Wrap unavailable"))
  check("14.4 and nothing was wrapped", next(G.wrapped) == nil)
end

-- A guard you can see is not a guard you have seen fire (MODDING_HADES2.md
-- section 3, rule 7). 14.1/14.2 above never actually raise -- ipairs on an
-- empty table just does nothing -- so they cannot be evidence the pcall in
-- hook one does anything. This forces a real crash (indexing a number has no
-- meaning in Lua) so the guard has to catch something to pass.
do
  local G = boot()
  G.addDoor({ CageRewards = { 42 } }, 50)

  local ok = pcall(G.SelectNearbyUnlockedEntry)
  check("14.5 a real crash inside resolution does not escape the hook", ok == true)
  check("14.6 and it is logged", logsContain("could not resolve a door reward"))
  check("14.7 and the Codex is left exactly as it was", G.CodexStatus.SelectedChapterName == "ChthonicGods",
        tostring(G.CodexStatus.SelectedChapterName))
end

-- =============================================================================
-- 15. Packaging -- the files that ship
-- =============================================================================
local function readFile(path)
  local f = io.open(path, "r")
  if f == nil then return nil end
  local t = f:read("*a"); f:close(); return t
end

do
  local toml = readFile("../thunderstore.toml")
  local mf = readFile("../src/manifest.json")
  check("15.1 thunderstore.toml exists", toml ~= nil)
  check("15.2 src/manifest.json exists", mf ~= nil)

  local tv = toml and toml:match('versionNumber%s*=%s*"([^"]+)"') or nil
  local mv = mf and mf:match('"version_number"%s*:%s*"([^"]+)"') or nil
  check("15.3 both declare a version", tv ~= nil and mv ~= nil,
        tostring(tv) .. " / " .. tostring(mv))
  check("15.4 and the versions agree", tv == mv,
        "toml=" .. tostring(tv) .. " manifest=" .. tostring(mv))

  check("15.5 namespace matches the manifest",
        toml and toml:match('namespace%s*=%s*"([^"]+)"') == "Adicon")
  check("15.6 name matches the manifest",
        toml and toml:match('\nname%s*=%s*"([^"]+)"') == "DoorRewardCodex")
end

do
  local toml = readFile("../thunderstore.toml") or ""
  local mf = readFile("../src/manifest.json") or ""
  local tomlDeps = {}
  for name, ver in toml:gmatch('\n([%w_]+%-[%w_]+)%s*=%s*"([%d%.]+)"') do
    tomlDeps[name] = ver
  end
  local missing = {}
  for full in mf:gmatch('"([%w_]+%-[%w_]+%-[%d%.]+)"') do
    local name, ver = full:match("^(.-)%-([%d%.]+)$")
    if name and tomlDeps[name] ~= ver then
      missing[#missing + 1] = full .. " vs " .. tostring(tomlDeps[name])
    end
  end
  check("15.7 every manifest dependency matches the toml",
        #missing == 0, table.concat(missing, ", "))
end

do
  local cl = readFile("../CHANGELOG.md") or ""
  check("15.8 CHANGELOG has an ## [Unreleased] heading, brackets included",
        cl:match("##%s*%[Unreleased%]") ~= nil)
end

do
  local toml = readFile("../thunderstore.toml") or ""
  local sources = {}
  for src in toml:gmatch('source%s*=%s*"([^"]+)"') do
    sources[#sources + 1] = src
  end
  check("15.9 the build copies exactly three things", #sources == 3,
        table.concat(sources, ", "))

  local allowed = { ["./CHANGELOG.md"] = true, ["./LICENSE"] = true, ["./src"] = true }
  local unexpected = {}
  for _, src in ipairs(sources) do
    if not allowed[src] then unexpected[#unexpected + 1] = src end
  end
  check("15.10 and nothing beyond CHANGELOG, LICENSE and src",
        #unexpected == 0, table.concat(unexpected, ", "))
end

do
  for _, f in ipairs({ "../icon.png", "../README.md", "../CHANGELOG.md",
                       "../LICENSE", "../src/main.lua", "../guard.sh" }) do
    check("15.11 build input exists: " .. f, readFile(f) ~= nil)
  end
end

-- =============================================================================

print(("DoorRewardCodex: %d passed, %d failed"):format(passed, failed))
for _, f in ipairs(failures) do print("  FAIL  " .. f) end
if failed > 0 then os.exit(1) end
