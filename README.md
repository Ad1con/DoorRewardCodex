# DoorRewardCodex

**Opens the Codex on an exit door's reward, not just on nearby NPCs and items.**

Standing near a character, enemy or item and opening the Codex already lands
on that thing's page. Vanilla's one exception is the icons on an exit door
showing what waits in the next room. This mod closes that gap. Stand near a
door showing a boon, open the Codex, and it opens on that god's page.

Works on every door reward that has a Codex entry: any god boon and the
Daedalus Hammer. Health, gold and other consumables have no Codex entry, so a
door offering one of those leaves the Codex exactly where it was, the same as
standing next to anything uncatalogued.

A Trial of the Gods door, or any door offering more than one reward at once,
switches to the right chapter but does not guess which of the two gods to
open, since the two icons sit too close together to tell apart by distance.
Both gods are highlighted in the list once the chapter opens instead.

## Settings

The config file is `Adicon-DoorRewardCodex.cfg`, in your profile's
`ReturnOfModding\config` folder.

Edit the file with the game **closed**. Hades II rewrites it from memory on
exit, so changes made while it is running are discarded.

| Setting | Default | What it does |
|---|---|---|
| `Enabled` | `true` | Master switch. Set to `false` for vanilla. |
| `MarkSplitRewards` | `true` | On a two-god door, highlight both gods in the list. Off still opens the right chapter. |

## How it works

Vanilla already switches the Codex to whatever is nearby through one
function, `SelectNearbyUnlockedEntry`. It searches a 600-unit radius around
the hero and never looks at exit doors, because a door's reward preview is a
UI icon attached to the door rather than a world object with a name of its
own.

This mod lets that function run first. If it finds something, its answer wins
and this mod does nothing, since standing next to an actual object is more
specific than a door across the room. Only when vanilla finds nothing does
this mod look at the closest offered door within the same 600 units and read
the reward stored on that door's room, resolving it to a Codex entry the same
way vanilla resolves a nearby object's name.

Full citations, file and line, are in the header comment of `src/main.lua`.

## Compatibility (Why does this write to my save?)

This mod writes to your save. `CodexStatus` records which Codex chapter and
entry are currently selected, and it is part of every save file whether or
not this mod is installed. This mod writes the same two fields vanilla itself
writes, every time the Codex opens, with values vanilla itself already uses:
an existing chapter name and an existing entry name. Removing this mod leaves
a page name the game reads normally. The most that can happen is the Codex
opening on a different page once.

Modifies no game files. It reads `CodexData` and the doors offered in the
current room, and wraps three vanilla functions (`SelectNearbyUnlockedEntry`,
`CodexOpenChapter`, `CloseCodexScreen`).

## Credits

Hades II is by [Supergiant Games](https://www.supergiantgames.com/). This is
an unofficial fan mod, not endorsed by or affiliated with them. The icon is
the Codex's own chapter icon for the Olympian Gods, extracted from the game's
files with `deppth2` and upscaled from its native size.

Built on [ReturnOfModding / Hell2Modding](https://github.com/SGG-Modding).
This mod cannot load without `LuaENVY-ENVY` and `SGG_Modding-ModUtil` -- the
environment isolation and the function wrapping are both theirs.
`SGG_Modding-ReLoad` gives it hot reload during development; nothing at
runtime depends on it.

Thank you to the Hades Modding community. Your work is astounding.

Built by Adicon, with Claude.
