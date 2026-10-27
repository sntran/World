#!/bin/sh
# Copy the core of Wings 3D (the mesh, with no window) into wings/.
#
#   sh scripts/wings.sh [COMMIT]
#
# With no COMMIT, the script uses the commit in wings/VERSION. It gets
# the source of dgud/wings at that commit, copies the modules of the
# mesh, removes the lines of the window from wings.hrl, and adds the
# small modules of scripts/wings/ in place of modules of the window.
# Two runs with the same commit give the same files.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
commit=${1:-$(cat "$root/wings/VERSION")}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q
git -C "$tmp" remote add origin https://github.com/dgud/wings
git -C "$tmp" fetch -q --depth 1 origin "$commit"
git -C "$tmp" checkout -q FETCH_HEAD

out="$root/wings"
rm -rf "$out"
mkdir -p "$out/src" "$out/e3d" "$out/intl_tools"

for f in wings.hrl wings_edge.erl wings_face.erl wings_facemat.erl \
  wings_subdiv.erl wings_tesselation.erl wings_util.erl wings_va.erl \
  wings_vertex.erl wings_we.erl wings_we_build.erl; do
  cp "$tmp/src/$f" "$out/src/$f"
done

# e3d with no codecs of images.
for f in "$tmp"/e3d/*.erl "$tmp"/e3d/*.hrl; do
  case "$(basename "$f")" in
    e3d__bmp.erl | e3d__dds.erl | e3d__png.erl | e3d__tga.erl | e3d__tif.erl | e3d_image.erl) ;;
    *) cp "$f" "$out/e3d/" ;;
  esac
done

cp "$tmp/intl_tools/tools.erl" "$tmp/intl_tools/wings_intl.hrl" "$out/intl_tools/"
cp "$tmp/license.terms" "$out/LICENSE"

# No headers of SDL and wx. e3d.hrl is in wings/e3d.
sed -i \
  -e '/-include("sdl_events.hrl")/d' \
  -e '/-include("sdl_keyboard.hrl")/d' \
  -e '/-include("sdl_mouse.hrl")/d' \
  -e '/-include_lib("wx\/include\/gl.hrl")/d' \
  -e '/-include_lib("wx\/include\/glu.hrl")/d' \
  -e '/-include_lib("wx\/include\/wx.hrl")/d' \
  "$out/src/wings.hrl"
sed -i 's|-include_lib("wings/e3d/e3d.hrl")|-include("e3d.hrl")|' "$out"/src/*.erl

cp "$root"/scripts/wings/*.erl "$out/src/"
git -C "$tmp" rev-parse HEAD > "$out/VERSION"
echo "wings/: the core of Wings 3D at $(cat "$out/VERSION")"
