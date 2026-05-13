#!/usr/bin/env sh
set -eu

ROCKS_DIR="${KONG_ROCKS_DIR:-/rocks}"
REQUIRE_ROCKS="${KONG_REQUIRE_ROCKS:-true}"
FOUND_ROCKS=0

if [ -d "$ROCKS_DIR" ]; then
  for rock in "$ROCKS_DIR"/*.rock; do
    if [ ! -e "$rock" ]; then
      continue
    fi

    FOUND_ROCKS=1
    echo "----> installing Kong plugin rock: $rock"
    luarocks install --force "$rock"
  done
else
  echo "----> rocks directory not found: $ROCKS_DIR"
fi

if [ "$FOUND_ROCKS" = "0" ]; then
  echo "----> no .rock files found in $ROCKS_DIR"

  if [ "$REQUIRE_ROCKS" = "true" ]; then
    echo "----> run 'make package' before starting Kong"
    exit 1
  fi
fi

chown -R kong:kong /usr/local/share/lua /usr/local/lib/lua /usr/local/lib/luarocks 2>/dev/null || true

exec /docker-entrypoint.sh "$@"
