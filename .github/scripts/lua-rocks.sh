#!/usr/bin/env bash
# The pinned Lua test toolchain (.github/lua-rocks.txt). CI: .github/actions/lua-toolchain/action.yml. See docs/operations/local-setup.md.
#   lua-rocks.sh install   install every pin at its exact version in file order (one retry), then verify;
#                          a pass skips a pin that is the only installed version of its rock, so the retry resumes
#                          where the first pass failed (a rock with other versions beside it is reinstalled; luarocks
#                          then removes the others)
#   lua-rocks.sh verify    the installed rocks must equal the pins: nothing extra, missing, or at another version
# LUAROCKS overrides the luarocks command, e.g. LUAROCKS="luarocks --lua-version=5.1 --lua-dir=$(brew --prefix luajit)".
# LUA_ROCKS_RETRY_DELAY is the wait in seconds before the retry (default 10).
# Bash 3.2 compatible (macOS system bash).
set -euo pipefail

pins="$(cd "$(dirname "$0")/.." && pwd)/lua-rocks.txt"
read -r -a luarocks <<< "${LUAROCKS:-luarocks}"

# The pins as "name version" lines; a malformed line is an error, not a skipped rock.
pinned() {
  local name version extra
  while read -r name version extra || [ -n "$name" ]; do
    name="${name%$'\r'}" version="${version%$'\r'}" extra="${extra%$'\r'}" # a CRLF checkout
    case "$name" in '' | '#'*) continue ;; esac
    if [ -z "$version" ] || [ -n "$extra" ]; then
      echo "lua-rocks: malformed line in $pins: $name $version $extra" >&2
      return 1
    fi
    echo "$name $version"
  done < "$pins"
}

# The installed rocks as sorted "name version" lines.
installed_rocks() {
  "${luarocks[@]}" list --porcelain | awk -F '\t' 'NF >= 2 { print $1 " " $2 }' | LC_ALL=C sort
}

install_pass() {
  local name version installed
  installed="$(installed_rocks)" || installed="" # an unreadable tree: install everything; verify has the last word
  while read -r name version; do
    if printf '%s\n' "$installed" | awk -v n="$name" -v v="$version" \
      '$1 == n { count++; if ($2 == v) found = 1 } END { exit !(found && count == 1) }'; then
      continue
    fi
    "${luarocks[@]}" install "$name" "$version" < /dev/null || return 1
  done <<< "$list"
}

verify() {
  local want installed
  want="$(printf '%s\n' "$list" | LC_ALL=C sort)"
  installed="$(installed_rocks)" || { echo "lua-rocks: luarocks list failed" >&2; return 1; }
  if [ "$installed" != "$want" ]; then
    echo "lua-rocks: installed rocks differ from $pins (- pinned, + installed):" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$installed") | sed -n 's/^< /- /p; s/^> /+ /p' >&2 || true
    return 1
  fi
  echo "lua-rocks: $(printf '%s\n' "$list" | wc -l | tr -d ' ') pinned rocks verified"
}

list="$(pinned)"
[ -n "$list" ] || { echo "lua-rocks: no pins in $pins" >&2; exit 1; }
case "${1:-}" in
  install)
    if ! install_pass; then
      delay="${LUA_ROCKS_RETRY_DELAY:-10}"
      echo "lua-rocks: install failed; retrying install once in ${delay}s" >&2
      sleep "$delay"
      if ! install_pass; then
        echo "lua-rocks: install failed twice; giving up" >&2
        exit 1
      fi
    fi
    verify
    ;;
  verify)
    verify
    ;;
  *)
    echo "usage: $0 install|verify" >&2
    exit 2
    ;;
esac
