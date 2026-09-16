# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The release workflow folds the `[Unreleased]` section into the tagged
version, so the square brackets are load-bearing -- the action looks for
`[Unreleased]` exactly and fails the build without it.

## [Unreleased]

Standing near an exit door's reward preview and opening the Codex lands on
that reward's page, the same way it already works for nearby NPCs, enemies
and items.

- Works on every door reward that has a Codex entry: any god boon, and the
  Daedalus Hammer, which lands on whichever weapon is currently equipped.
- Works on the Rift of Thessaly's steering wheel too, where the choices are
  on the wheel rather than on doors, a Trial of the Gods included.
- A door offering health, mana, darkness, nectar or another consumable has no
  Codex entry to jump to, so it opens Melinoe's own page instead of leaving
  the Codex wherever it was.
- A Trial of the Gods door, or a cage door with more than one reward, opens
  on the first god and marks the other one's name in the list in gold, since
  the two icons cannot be told apart by distance.
- Never overrides a nearby object vanilla itself already found. Only acts
  once the Codex has been opened at least once, exactly like vanilla's own
  auto-select.
- Two settings, both also readable in the generated `.cfg`.
- Wraps three vanilla functions and writes two `CodexStatus` fields already
  present in every save; see the README's Compatibility section.
