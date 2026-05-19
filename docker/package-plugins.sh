#!/usr/bin/env sh
set -eu

WORKDIR="${PLUGIN_WORKDIR:-/workspace}"
PLUGIN_DIR="${PLUGIN_SOURCE_DIR:-$WORKDIR/custom-plugins}"
OUT_DIR="${PLUGIN_OUT_DIR:-$WORKDIR/build/out}"
FOUND_ROCKS=0

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.rock
rm -rf "$OUT_DIR/native"

if [ ! -d "$PLUGIN_DIR" ]; then
  echo "plugin source directory not found: $PLUGIN_DIR" >&2
  exit 1
fi

for plugin_dir in "$PLUGIN_DIR"/*; do
  [ -d "$plugin_dir" ] || continue

  plugin_name="$(basename "$plugin_dir")"

  for rockspec in "$plugin_dir"/*.rockspec; do
    [ -e "$rockspec" ] || continue

    FOUND_ROCKS=1
    echo "----> PACKAGING $plugin_name from $(basename "$rockspec")"

    (
      cd "$plugin_dir"
      rm -f ./*.rock
      luarocks make --pack-binary-rock "$(basename "$rockspec")"
    )

    for rock in "$plugin_dir"/*.rock; do
      [ -e "$rock" ] || continue
      mv "$rock" "$OUT_DIR/"
    done
  done

  for prebuilt_dir in "$plugin_dir/rocks" "$plugin_dir/dist"; do
    [ -d "$prebuilt_dir" ] || continue

    for rock in "$prebuilt_dir"/*.rock; do
      [ -e "$rock" ] || continue
      FOUND_ROCKS=1
      echo "----> COPYING PREBUILT ROCK $rock"
      cp "$rock" "$OUT_DIR/"
    done
  done

  if [ -d "$plugin_dir/native" ]; then
    echo "----> STAGING NATIVE LIBRARIES FROM $plugin_dir/native"
    mkdir -p "$OUT_DIR/native/$plugin_name"
    cp -R "$plugin_dir/native/." "$OUT_DIR/native/$plugin_name/"
  fi
done

if [ "$FOUND_ROCKS" = "0" ]; then
  echo "no source or prebuilt .rock plugins were found under $PLUGIN_DIR" >&2
  exit 1
fi

echo "----> PACKAGED ROCKS IN $OUT_DIR"
ls -la "$OUT_DIR"
