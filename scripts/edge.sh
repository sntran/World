#!/bin/sh
# Builds edge.com: the release of World in one file of beam.com
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
rm -rf _build/prod/rel/world
RELEASE_ERTS=false beam mix release --overwrite
beam _build/prod/rel/world -o edge.com --target wasm32

# Cloudflare refuses a Worker of more than 64 MiB (before compression):
# the deploy then does not reach the site, and the dry run of CI does not
# see it. edge.com is most of the Worker, so stop at 60 MiB.
size=$(wc -c < edge.com)
limit=$((60 * 1024 * 1024))
if [ "$size" -gt "$limit" ]; then
    echo "edge.com is $size bytes, more than $limit: the Worker can be more than 64 MiB" >&2
    exit 1
fi
