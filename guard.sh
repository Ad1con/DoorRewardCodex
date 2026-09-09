#!/usr/bin/env bash
# Refuse to modify the live plugin while Hades II is running.
#
# The plugin folder in r2modman is a JUNCTION to src/, so every write THERE is a
# write to the running game's mod. Files outside src/ -- tests, docs, .git -- are
# no longer inside the watched folder, which is why the layout was split.
#
# The loader picks up a change within seconds and re-runs the plugin chunk.
#
# On 2026-08-28 that crashed a live RealHecate fight: four reloads in ninety
# seconds, the last three seconds before an EXCEPTION_ACCESS_VIOLATION inside
# Lua's garbage collector (lgc.cpp:451 traversetable). Some of those reloads
# were sabotage cycles -- deliberately broken code -- running in the player's
# actual session. This mod copies the same guard rather than assume it cannot
# happen again.
#
# Source this and call `guard` before any write to main.lua.
guard() {
  if tasklist 2>/dev/null | grep -qi hades2; then
    echo "REFUSING: Hades II is running. This folder is junctioned into the live"
    echo "profile, so editing main.lua hot-reloads it into the running game."
    return 1
  fi
  return 0
}
