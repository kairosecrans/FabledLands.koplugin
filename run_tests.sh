#!/usr/bin/env bash
# Runs the Fabled Lands plugin test suites.
#
# Uses the LuaJIT bundled inside the KoReader AppImage if it has been
# extracted, otherwise whatever Lua interpreter is on PATH. The suites load
# no KoReader modules, so any Lua 5.1+ will do.

set -uo pipefail
cd "$(dirname "$0")"

LUA="${LUA:-}"
if [ -z "$LUA" ]; then
    for candidate in \
        "$PWD/../squashfs-root/usr/lib/koreader/luajit" \
        "$(command -v luajit 2>/dev/null)" \
        "$(command -v lua5.1 2>/dev/null)" \
        "$(command -v lua 2>/dev/null)"
    do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then LUA="$candidate"; break; fi
    done
fi

if [ -z "$LUA" ]; then
    echo "No Lua interpreter found. Set LUA=/path/to/luajit and retry." >&2
    exit 1
fi

echo "Using $LUA"
status=0
for spec in spec/*_spec.lua; do
    echo
    echo "== $spec"
    "$LUA" "$spec" || status=1
done

echo
if [ "$status" -eq 0 ]; then echo "All suites passed."; else echo "Failures above."; fi
exit "$status"
