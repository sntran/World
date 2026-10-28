#!/bin/sh
# Builds edge.com: the release of Xưởng in one file of beam.com
# (https://github.com/sntran/BEAM.com), with only the part that the
# WebAssembly runtime reads (--target wasm32). worker.js serves it with
# the runtime of the npm package beam.com. "npm run build" runs it, also
# in Workers Builds.
#
# BEAM_COM: the path of a beam.com of the version of the npm package, in
# place of "npx beam.com" (which downloads the file of the version of the
# package, checks its SHA-256, and needs Node.js 25 or later).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

beam() {
    if [ -n "${BEAM_COM:-}" ]; then sh "$BEAM_COM" "$@"; else npx beam.com "$@"; fi
}

export MIX_ENV=prod
beam mix local.hex --force --if-missing
beam mix local.rebar --force --if-missing
beam mix deps.get --only prod
beam mix compile
rm -rf _build/prod/rel/xuong
RELEASE_ERTS=false beam mix release --overwrite
beam _build/prod/rel/xuong -o edge.com --target wasm32
