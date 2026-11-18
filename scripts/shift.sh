#!/bin/sh
# The work of a construction shift on its runner (.github/workflows/
# shift.yml, docs/factory.md, "Construction shifts"):
#
# - tcp-proxy.mjs of beam.com: the local port 4370 is a WebSocket to
#   WORLD_URL/.tcp/4370, the distribution of the node of the edge;
# - the node of the shift (World.Shift, World.Crew): it joins the node
#   world@127.0.0.1 of the edge with the cookie WORLD_COOKIE, builds the
#   parts that the edge gives it, puts each GLB in R2 (scripts/
#   order-store.mjs with WORLD_R2_*), and stops at WORLD_SHIFT_UNTIL or
#   after WORLD_SHIFT_IDLE minutes with no work;
# - each 5 minutes, the issues whose parts are built (scripts/
#   shift-issues.mjs check);
# - at the end, the summary of the shift in $GITHUB_STEP_SUMMARY.
set -u
: "${WORLD_URL:=https://world.mkfifo.com}" "${WORLD_COOKIE:?}" "${WORLD_SHIFT_UNTIL:?}"
TMP=${RUNNER_TEMP:-/tmp}
ws=$(printf '%s' "$WORLD_URL" | sed 's#^http#ws#')/.tcp/4370

node node_modules/beam.com/runtime/tcp-proxy.mjs 4370 "$ws" > "$TMP/tcp-proxy.log" 2>&1 &
proxy=$!
issues=
if [ -n "${GH_TOKEN:-}" ]; then
    (while sleep 300; do node scripts/shift-issues.mjs check || true; done) &
    issues=$!
fi

export WORLD_NODE=shift4372@127.0.0.1 WORLD_JOIN=world@127.0.0.1
export WORLD_SHIFT_SUMMARY="$TMP/shift-summary.md"
# The node: no epmd (World.Epmd takes the port from the name: world is
# 4370, the port of the proxy), no connection to other nodes, and a port
# of this computer only.
ERL_FLAGS="-start_epmd false -epmd_module Elixir.World.Epmd -connect_all false -kernel inet_dist_use_interface {127,0,0,1}" \
    MIX_ENV=prod mix.com run --no-halt
status=$?

kill "$proxy" ${issues:+"$issues"} 2>/dev/null
if [ -f "$WORLD_SHIFT_SUMMARY" ]; then
    cat "$WORLD_SHIFT_SUMMARY"
    [ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$WORLD_SHIFT_SUMMARY" >> "$GITHUB_STEP_SUMMARY"
fi
echo "shift: the node stopped with the status $status"
exit "$status"
