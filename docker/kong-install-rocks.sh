#!/usr/bin/env sh
set -eu

ROCKS_DIR="${KONG_ROCKS_DIR:-/rocks}"
REQUIRE_ROCKS="${KONG_REQUIRE_ROCKS:-true}"
NATIVE_SOURCE_DIR="${KONG_NATIVE_LIBS_SOURCE_DIR:-$ROCKS_DIR/native}"
NATIVE_LIB_DIR="${KONG_NATIVE_LIB_DIR:-/usr/local/lib/kong-plugins}"
REQUIRE_NATIVE_LIBS="${KONG_REQUIRE_NATIVE_LIBS:-false}"
FOUND_ROCKS=0
FOUND_NATIVE_LIBS=0

if [ -n "${LD_LIBRARY_PATH:-}" ]; then
  export LD_LIBRARY_PATH="$NATIVE_LIB_DIR:$LD_LIBRARY_PATH"
else
  export LD_LIBRARY_PATH="$NATIVE_LIB_DIR"
fi

if [ -n "${KONG_LUA_PACKAGE_CPATH:-}" ]; then
  case "$KONG_LUA_PACKAGE_CPATH" in
    *"$NATIVE_LIB_DIR"*) ;;
    *) export KONG_LUA_PACKAGE_CPATH="$NATIVE_LIB_DIR/?.so;$NATIVE_LIB_DIR/lib?.so;$KONG_LUA_PACKAGE_CPATH" ;;
  esac
else
  export KONG_LUA_PACKAGE_CPATH="$NATIVE_LIB_DIR/?.so;$NATIVE_LIB_DIR/lib?.so;/usr/local/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/?/init.so;;"
fi

if [ -d "$NATIVE_SOURCE_DIR" ]; then
  mkdir -p "$NATIVE_LIB_DIR"

  find "$NATIVE_SOURCE_DIR" \( -type f -o -type l \) \( -name '*.so' -o -name '*.so.*' \) | while IFS= read -r lib; do
    echo "----> installing native library: $lib"
    cp "$lib" "$NATIVE_LIB_DIR/"
  done

  if find "$NATIVE_SOURCE_DIR" \( -type f -o -type l \) \( -name '*.so' -o -name '*.so.*' \) | grep -q .; then
    FOUND_NATIVE_LIBS=1
  fi
else
  echo "----> native library directory not found: $NATIVE_SOURCE_DIR"
fi

if [ "$FOUND_NATIVE_LIBS" = "0" ]; then
  echo "----> no native .so files found in $NATIVE_SOURCE_DIR"

  if [ "$REQUIRE_NATIVE_LIBS" = "true" ]; then
    echo "----> add Linux shared libraries under custom-plugins/<plugin>/native or set KONG_REQUIRE_NATIVE_LIBS=false"
    exit 1
  fi
fi

if [ "$FOUND_NATIVE_LIBS" = "1" ]; then
  if [ -d /etc/ld.so.conf.d ]; then
    echo "$NATIVE_LIB_DIR" > /etc/ld.so.conf.d/kong-plugins-native.conf || true
  fi

  if command -v ldconfig >/dev/null 2>&1; then
    ldconfig || true
  fi
fi

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
    echo "----> add at least one plugin under custom-plugins/ and run 'docker compose up --build'"
    exit 1
  fi
fi

chown -R kong:kong "$NATIVE_LIB_DIR" /usr/local/share/lua /usr/local/lib/lua /usr/local/lib/luarocks 2>/dev/null || true

exec /docker-entrypoint.sh "$@"
