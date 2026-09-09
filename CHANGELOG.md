# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The release workflow folds the `[Unreleased]` section into the tagged
version, so the square brackets are load-bearing -- the action looks for
`[Unreleased]` exactly and fails the build without it.

## [Unreleased]

## [1.0.0] - 2026-09-06

First public release.

Standing near an exit door's reward preview and opening the Codex now lands on
that reward's page, the same way it already works for nearby NPCs, enemies and
items.

- Works on every door reward that has a Codex entry: god boons and Daedalus
  Hammers. Rewards with no Codex entry (health, gold, other consumables) are
  left alone, the same as standing next to anything uncatalogued.
- A Trial of the Gods door, or a cage door with more than one reward, opens the
  right chapter and leaves the entry alone rather than guessing between two
  candidates it cannot tell apart by distance. The two Trial gods are
  highlighted in the list once the chapter opens.
- Never overrides a nearby object vanilla itself already found. Only acts once
  the Codex has been opened at least once, exactly like vanilla's own
  auto-select.
- Two settings, both also readable in the generated `.cfg`.
- Wraps three vanilla functions and writes two `CodexStatus` fields already
  present in every save; see the README's Compatibility section.
