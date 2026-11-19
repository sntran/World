#!/bin/sh
# The work of a construction shift on its runner (.github/workflows/
# shift.yml, docs/factory.md, "Construction shifts"):
#
# - the join (scripts/shift-join.mjs): the ID token of the job goes to
#   the edge, which gives the name of the node of this runner, a cookie
#   for that node only, and the pass of the shift for the store;
# - tcp-proxy.mjs of beam.com: the local port 4370 is a WebSocket to
#   WORLD_URL/.tcp/4370, the distribution of the node of the edge;
# - the node of the shift (World.Shift, World.Crew): it joins the node of
#   the edge with its cookie, builds the parts that the edge gives it,
#   puts each GLB in R2 through the store of the Worker with its pass
#   (scripts/order-store.mjs), and stops at WORLD_SHIFT_UNTIL or after
#   WORLD_SHIFT_IDLE minutes with no work;
# - each 5 minutes, the issues whose parts are built (scripts/
#   shift-issues.mjs check);
# - a new join when the node stops with the exit status 75 (no connection
#   to the edge for 2 minutes: its VM started again with no pass of this
#   node), while the shift has time left;
# - after each node, the summary of the shift in $GITHUB_STEP_SUMMARY.
set -u
: "${WORLD_URL:=https://world.mkfifo.com}" "${WORLD_SHIFT_UNTIL:?}"
TMP=${RUNNER_TEMP:-/tmp}
export WORLD_URL
ws=$(printf '%s' "$WORLD_URL" | sed 's#^http#ws#')/.tcp/4370

node node_modules/beam.com/runtime/tcp-proxy.mjs 4370 "$ws" > "$TMP/tcp-proxy.log" 2>&1 &
proxy=$!
issues=
if [ -n "${GH_TOKEN:-}" ]; then
    (while sleep 300; do node scripts/shift-issues.mjs check || true; done) &
    issues=$!
fi

export WORLD_SHIFT_SUMMARY="$TMP/shift-summary.md"
# (With no ID token, a test on this computer, WORLD_STORE_TOKEN is the
# bearer of the join; a join gives the pass in that name, so each join
# gets the first bearer.)
bearer=${WORLD_STORE_TOKEN:-}
status=0
while :; do
    joined=$(WORLD_STORE_TOKEN=$bearer node scripts/shift-join.mjs) || { status=1; break; }
    eval "$joined"
    export WORLD_STORE_URL="$WORLD_URL/store"
    echo "shift: the node $WORLD_NODE joins $WORLD_JOIN"
    # The node: no epmd (World.Epmd takes the port from the name: world is
    # 4370, the port of the proxy), no connection to other nodes, and a port
    # of this computer only.
    ERL_FLAGS="-start_epmd false -epmd_module Elixir.World.Epmd -connect_all false -kernel inet_dist_use_interface {127,0,0,1}" \
        MIX_ENV=prod mix.com run --no-halt
    status=$?
    if [ -f "$WORLD_SHIFT_SUMMARY" ]; then
        cat "$WORLD_SHIFT_SUMMARY"
        [ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$WORLD_SHIFT_SUMMARY" >> "$GITHUB_STEP_SUMMARY"
        rm -f "$WORLD_SHIFT_SUMMARY"
    fi
    # 75: no connection to the edge for 2 minutes (World.Shift: its VM
    # started again with no pass of this node). A new join, while the
    # shift has more than 2 minutes left.
    [ "$status" -eq 75 ] && [ "$(date +%s)" -lt "$((WORLD_SHIFT_UNTIL - 120))" ] || break
    echo "shift: no connection to the edge; a new join"
done

kill "$proxy" ${issues:+"$issues"} 2>/dev/null
echo "shift: the node stopped with the status $status"
exit "$status"
