#!/usr/bin/env bash
# Report whether the tools this project needs are installed.
# Warns only; always exits 0 so it never blocks worktree setup.

missing=0

check() {
  local cmd="$1" purpose="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  ok       %-8s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '  MISSING  %-8s needed for %s\n' "$cmd" "$purpose"
    missing=1
  fi
}

echo "Checking requirements:"
check luajit "make test"
check zip "make pico8-preview / site"
check curl "make fetch-lovejs"
check love "make screenshots (optional)"

if [ "$missing" -ne 0 ]; then
  echo "Some tools are missing; related make targets will fail until they are installed."
fi
exit 0
