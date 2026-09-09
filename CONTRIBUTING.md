# Contributing

## Tests

```bash
cd test && lua run_tests.lua
```

Run them on both interpreters — the game ships LuaJIT, and the two differ in
ways that have caught real bugs in sibling mods.

```bash
winget install DEVCOM.Lua
winget install LuaJIT.LuaJIT
```

## Sabotage every new test

After writing a test, reintroduce the bug it is meant to catch and confirm that
test goes red, then revert. It takes thirty seconds.

This is not ceremony. Several tests in sibling projects passed while asserting
nothing useful, and sabotage is what found them — including one that had
encoded a bug as the requirement, and a set that quietly went vacuous when a
default changed.

## Do not edit while the game is running

`plugins/Adicon-DoorRewardCodex` in r2modman is a junction to `src/`, so every
save there is a live edit to the running game. The loader picks it up within
seconds and re-runs the plugin chunk.

Source `guard.sh` and call `guard` before any write to `src/`:

```bash
. ./guard.sh && guard || exit 1
```

Hot-reloading mid-game crashed a live RealHecate session during that mod's
development — four reloads in ninety seconds, the last three seconds before an
access violation inside Lua's garbage collector. Some of those reloads were
sabotage cycles, which write deliberately broken code. This mod inherits the
same guard rather than assume it is immune.

## Layout

`src/` is what ships. Everything else — tests, docs, `guard.sh` — does not.
`thunderstore.toml` maps `./src` to `./plugins` at build time.
