#!/bin/sh
# Runs every Lua spec file in a busted process of its own, several at once, and adds up what busted reports.
# One process per file keeps a slow file from holding up a whole group, and keeps one file's state out of
# the next. `make test-lua` and `make coverage-lua` call it.
#
#   LUA=<interpreter> BUSTED=<busted> [SPECS=tests/lua] [OUT=build/lua-tests] [JOBS=n] [COVERAGE=1] \
#     sh tests/lua/run-specs.sh
#
# JOBS defaults to the machine's cores. Each file's output goes to OUT/<file>.log. A file fails when busted
# exits non-zero or prints no result line. With COVERAGE=1 each process writes its luacov counts to
# OUT/<file>.stats (through LUACOV_STATS, which .luacov reads), and they are added up into luacov.stats.out.
set -u

name_of() { printf '%s' "$1" | tr '/' '_'; }

if [ "${1:-}" = "--one" ]; then
  name=$(name_of "$2")
  : > "$OUT/$name.rc"
  if [ "$COVERAGE" = 1 ]; then
    LUACOV_STATS="$OUT/$name.stats"
    export LUACOV_STATS
    : > "$LUACOV_STATS"
    "$BUSTED" --lua="$LUA" --coverage "$2" > "$OUT/$name.log" 2>&1
  else
    "$BUSTED" --lua="$LUA" "$2" > "$OUT/$name.log" 2>&1
  fi
  echo $? > "$OUT/$name.rc"
  exit 0
fi

SPECS=${SPECS:-tests/lua}
OUT=${OUT:-build/lua-tests}
LUA=${LUA:-luajit}
BUSTED=${BUSTED:-busted}
COVERAGE=${COVERAGE:-}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}
export SPECS OUT LUA BUSTED COVERAGE

mkdir -p "$OUT" || exit 1
list="$OUT/files.txt"
find "$SPECS" -name '*_spec.lua' | sort > "$list"
if [ ! -s "$list" ]; then
  echo "run-specs: no spec file (*_spec.lua) under $SPECS"
  exit 1
fi

start=$(date +%s)
# Each file's process exits 0 and leaves its result in its .rc, so a non-zero xargs means the run itself broke
# off: files it never started would be read from an earlier run's output.
if ! xargs -P "$JOBS" -n 1 sh "$0" --one < "$list"; then
  echo "run-specs: the run broke off before every file had run"
  exit 1
fi

esc=$(printf '\033')
files=0 ok=0 failed=0 errors=0 pending=0 bad=0
: > "$OUT/times.txt"
while read -r f; do
  name=$(name_of "$f")
  files=$((files + 1))
  rc=$(cat "$OUT/$name.rc" 2>/dev/null)
  line=$(sed "s/${esc}\[[0-9;]*m//g" "$OUT/$name.log" |
    grep -E '^[0-9]+ success(es)? / [0-9]+ failures? / [0-9]+ errors? / [0-9]+ pending' | tail -1)
  if [ -n "$line" ]; then
    set -- $(printf '%s\n' "$line" | sed -E 's#^([0-9]+)[^/]*/ ([0-9]+)[^/]*/ ([0-9]+)[^/]*/ ([0-9]+).*#\1 \2 \3 \4#')
    ok=$((ok + $1)) failed=$((failed + $2)) errors=$((errors + $3)) pending=$((pending + $4))
    printf '%s %s\n' "$(printf '%s\n' "$line" | sed -E 's#.*: ([0-9.]+) seconds.*#\1#')" "$f" >> "$OUT/times.txt"
  fi
  if [ -z "$line" ] || [ "$rc" != 0 ]; then
    bad=$((bad + 1))
    reason="exit ${rc:-none}"
    [ -n "$line" ] || reason="$reason, no result line"
    echo "---- $f failed ($reason)"
    cat "$OUT/$name.log"
  fi
done < "$list"

echo "slowest files (s):"
sort -rn "$OUT/times.txt" | head -5 | sed 's/^/  /'
echo "lua tests: $files files, $ok successes, $failed failures, $errors errors, $pending pending" \
  "($(( $(date +%s) - start )) s, $JOBS at once)"
[ "$bad" -eq 0 ] || exit 1

if [ "$COVERAGE" = 1 ]; then
  sed "s#/#_#g; s#^#$OUT/#; s#\$#.stats#" "$list" | "$LUA" "$(dirname "$0")/merge-coverage.lua" luacov.stats.out
fi
