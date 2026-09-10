# DoorRewardCodex -- design notes

Repo-only. Not shipped (`thunderstore.toml` copies only `CHANGELOG.md`,
`LICENSE` and `src`). This is where the *why* behind `src/main.lua` lives, so
the shipped file's header comment can stay short. See `DOOR_REWARD_CODEX_SPEC.md`
and `DOOR_REWARD_CODEX_RESEARCH.md` for the citations the initial build was
made against (2026-09-06); later entries below record what changed after
playtesting started.

## Why every game read goes through `game.*`, never a bare global

`LuaENVY-ENVY` gives each plugin's top-level chunk its own environment table
(`setfenv`), so a bare `CodexStatus` inside this plugin's own file would read
*this plugin's* private table, not the game's -- there is nothing there, and
it silently reads `nil` rather than erroring, which is the worse failure mode.
`rom.game`, threaded through `on_ready(game)` / `installHooks(game)`, is the
actual reference to the game's real global table. RealHecate's `main.lua`
follows the same discipline (`game.ActiveEnemies`, `game.EnemyData`, ...) and
was the reason to check this before writing a line of logic here -- an early
draft used bare globals throughout and would have thrown or silently no-op'd
against the real game the first time it ran, while passing every test that
also used bare globals for its fakes. The fix touched both `main.lua` and
`test/harness.lua` at once, which is exactly the trap: a test written with the
same mistaken assumption as the code agrees with it.

## The snapshot-and-compare, and the edge case it accepts

Hook one snapshots `CodexStatus.SelectedChapterName` and
`SelectedEntryNames[thatChapter]` before calling `base()`, then compares after.
If either changed, vanilla found something and this mod does nothing further.

This has one known blind spot, accepted rather than fixed: if vanilla's own
match happens to resolve to the *same* chapter and entry already selected
(the player is standing next to the literal thing already open), the
before/after comparison sees no change and cannot tell that apart from
"vanilla found nothing." The spec is explicit that the alternative --
reimplementing vanilla's own search to predict its answer -- is worse, since
that duplicated logic would need to be kept in sync with vanilla by hand
forever. The blind spot only matters when a door is *also* in range and would
otherwise win, which is a narrow coincidence; a test exists for the ordinary
case (`2.x` in the suite) using an object whose resolution differs from the
codex's current default specifically so the comparison has something real to
detect.

## `findCodexMatch` is `SelectNearbyUnlockedEntry`'s own loop, extracted

`CodexLogic.lua:149-163` matches `entryName == nearbyName` via a `pairs`
double loop rather than direct table indexing. `findCodexMatch` keeps that
literal shape rather than simplifying to `chapterData.Entries[name]`, even
though the two are behaviorally identical for unique entry names (and entry
names are unique -- `CodexOrdering` never repeats one across chapters). The
reason to keep the loop is not correctness, it is fidelity: a direct-index
rewrite is a second place this mod's understanding of "how vanilla matches"
could drift from the real thing without a test noticing, and the loop costs
nothing extra to keep.

## Devotion vs. `room.CageRewards`: two structurally different splits, one policy

Devotion always offers exactly two Olympian boons
(`room.Encounter.LootAName` / `LootBName`), confirmed by Caleb, so its chapter
is hardcoded (`OlympianGods`) rather than resolved -- there is nothing to
resolve.

`room.CageRewards` (`InteractLogic.lua:1457-1462`) is a list of
`{ RewardType, ForceLootName }` entries with no such guarantee: 2-5 rewards,
not necessarily gods, not necessarily sharing a chapter. The policy chosen
here: resolve every candidate through `findCodexMatch`, take the chapter of
the FIRST one that resolves (in list order), and mark whichever *other*
candidates land in that same chapter. If none resolve, it falls back to
Melinoe's page, the same as an unmatched single reward -- see below.

This is a judgment call the spec leaves open (it only pins "behaves as a
split, not a single" as the required, tested behavior). The alternative
considered and rejected: picking the chapter with the most matching
candidates rather than the first. That reads better when cage rewards are
heavily lopsided toward one chapter, but it also means a door's Codex page can
change based on iteration order of a `pairs`-free but still order-sensitive
count, for a scenario (multi-chapter cage rewards) that has not been observed
in practice. First-match is simpler, deterministic from the room's own
`CageRewards` array order, and errs toward changing the Codex less rather
than more -- consistent with the mod's overall bias of doing nothing when
uncertain.

## The Melinoe fallback (added after 1.0.0's first playtest)

Caleb's report, 2026-09-09: gods and the Hammer worked; a door offering
health, mana, darkness or nectar did nothing when the Codex opened. That was
1.0.0 working exactly as built and tested (`8.1`/`8.2` at the time, and the
`14.x` robustness tests) -- there is genuinely no Codex chapter for any
consumable, confirmed by grepping the shipped `CodexData.lua` in full for
every internal name involved (`MaxHealthDrop`, `MaxManaDrop`, and the resource
keys behind "Bones," "Ash" and "Nectar" in `ResourceData.lua`) and finding none
of them anywhere in it. But "correct" and "wanted" are not the same thing, and
his call was to land somewhere rather than nowhere: fall back to Melinoe's own
page, `ChthonicGods` / `PlayerUnit` -- which is not a value this mod invented,
it is `ScreenData.Codex.DefaultChapter` / `DefaultEntry` (`CodexData.lua:176-
177`), the exact pair `CodexInit` itself uses before anything has ever been
selected. Safe by construction for the same reason every other value this mod
writes is: it is not merely *a* vanilla-legal value, it is the specific one
vanilla defaults to.

One correction worth recording because it shaped nothing but could easily have
shaped a wrong choice: Melinoe's own entry (`CodexData.lua:602-645`) was
guessed to be "a general list of boon rewards." It is not -- it is two short
lore lines about her (`CodexData_Melinoe_01`/`_02`), unlocked by
`CompletedRunsCache >= 0` (true from the start of any save) and a
Chronos-related flag. There is no "which boons pair with this weapon/hero"
page anywhere in the Codex data as far as this mod's reading of it goes. The
fallback was implemented anyway, on its own merits (it is vanilla's own
default, which is reason enough), with the guess about its content corrected
rather than left standing.

Applies to both the single-reward path and the `CageRewards` path when
nothing in the list resolves. Devotion is unaffected -- it always resolves
(confirmed always Olympians), so there is no "nothing matched" case for it to
fall into.

## The Hammer already lands on whatever weapon is currently equipped

Caleb asked for confirmation that a Hammer door should land on "the
weapon/aspect currently being used in that run," rather than change anything.
Checked rather than assumed: `EquipPlayerWeapon` (`CombatLogic.lua:4711-4769`)
sets only the newly-equipped weapon's name true in `CurrentRun.Hero.Weapons`
(plus that weapon's own `SecondaryWeapon` alias) and explicitly nils every
other name in `WeaponSets.HeroPrimaryWeapons` -- the same six weapon names
`CodexData`'s Weapons chapter uses (`WeaponSets.lua:40-48`). So
`CurrentRun.Hero.Weapons` never holds more than the one currently-equipped
weapon, and `resolveWeaponUpgradeName`'s loop over it -- vanilla's own code,
copied verbatim from `CodexLogic.lua:141-148` -- already resolves to that
weapon. Aspects are a separate concept (tracked elsewhere, not a different
weapon name), so they do not factor in; the Codex's Weapons chapter is
per-weapon, not per-aspect, regardless. No code changed here.

## No ImGui overlay panel

RealHecate ships one because its settings are visual dials (colors, sizes,
opacity) worth tuning by eye without a restart. This mod has two booleans with
no visual tuning loop -- a `.cfg` edit and a relaunch is not a meaningfully
worse experience for either of them, and the settings table in the spec says
"resist adding more." Building a panel for two checkboxes would be scope the
mod does not need.

## No hot-reload-sensitive state

The only piece of state that survives across a reload is `splitFlag`, a plain
local. A hot reload re-runs the whole chunk, which re-initializes it to `nil`
-- the same state a closed Codex leaves it in. There is nothing here like
RealHecate's `HooksRegistered` hazard because `on_ready` (where the wraps are
installed) is documented by `ReLoad.auto_single()` to run once regardless of
how many times `on_reload` fires afterward, and this mod follows that
existing, tested contract rather than re-deriving it.

## Why `CloseCodexScreen` needed its own wrap rather than reusing an existing one

The mod already wraps two functions on the codex's open path
(`SelectNearbyUnlockedEntry`, `CodexOpenChapter`). Clearing `splitFlag` on
*close* could not piggyback on either of those, since neither runs when the
screen closes -- a third, minimal wrap was the only option, and it does
nothing else, matching the "do not bypass, do not gold-plate" shape of the
other two.
