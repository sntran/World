#!/bin/sh
# SSH into a construction shift, as remote-ssh.yml of BEAM.com: the SSH
# server of Erlang :ssh (scripts/remote_ssh.erl of BEAM.com, at a fixed
# commit and SHA-256), behind its WebSocket and a quick tunnel of
# Cloudflare. The URL and the fingerprint of the host key go to the log
# and to the summary of the job. Then, on a computer with beam.com and
# the private key of KEYS:
#
#   beam.com -a ssh remote_ssh.erl -- exec wss://HOST/ KEY FINGERPRINT 'tail -n 20 /tmp/x'
#
# The environment: KEYS (a file in the format of authorized_keys), MINUTES
# (330 by default: the time of the job of the shift).
set -u
: "${KEYS:?}" "${MINUTES:=330}"
TMP=${RUNNER_TEMP:-/tmp}
PORT=8022
BEAM_COM_COMMIT=c335c74b9e1d536d73b6f7504ec43bd688b54680
SSH_SHA256=b9534a3ef160f331fe3004ae57705e44370aeb9a5e3fd0c84d1a77f9c7417257
CF_VERSION=2026.10.7
CF_SHA256=1f99fb518b83dec2ba8d870a7cc991d82a77e6196295a3d2754ba17ab9f91872

check() { [ "$(sha256sum < "$1" | cut -d' ' -f1)" = "$2" ] || { echo "shift ssh: the SHA-256 of $1 is not $2" >&2; exit 1; }; }

curl -fsSL -o "$TMP/remote_ssh.erl" "https://raw.githubusercontent.com/sntran/BEAM.com/$BEAM_COM_COMMIT/scripts/remote_ssh.erl" || exit 1
check "$TMP/remote_ssh.erl" "$SSH_SHA256"
curl -fsSL -o "$TMP/cloudflared" "https://github.com/cloudflare/cloudflared/releases/download/$CF_VERSION/cloudflared-linux-amd64" || exit 1
check "$TMP/cloudflared" "$CF_SHA256"
chmod +x "$TMP/cloudflared"

mkdir -p "$TMP/ssh-work"
REMOTE_SSH_MINUTES=$MINUTES REMOTE_SSH_PORT=$PORT beam.com -a ssh "$TMP/remote_ssh.erl" -- serve "$KEYS" "$GITHUB_WORKSPACE" > "$TMP/remote_ssh.log" 2>&1 &
n=0
until fp=$(grep -Eo 'SHA256:[A-Za-z0-9+/=]+' "$TMP/remote_ssh.log" | head -n 1) && [ -n "$fp" ]; do
    n=$((n + 1)); [ $n -gt 300 ] && { cat "$TMP/remote_ssh.log"; echo "shift ssh: the server did not start" >&2; exit 1; }
    sleep 1
done
"$TMP/cloudflared" tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" > "$TMP/cloudflared.log" 2>&1 &
n=0
until host=$(grep -Eo '[a-z0-9-]+\.trycloudflare\.com' "$TMP/cloudflared.log" | head -n 1) && [ -n "$host" ]; do
    n=$((n + 1)); [ $n -gt 120 ] && { cat "$TMP/cloudflared.log"; echo "shift ssh: the tunnel did not start" >&2; exit 1; }
    sleep 1
done
echo "shift ssh: wss://$host/ $fp"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '### SSH\n\n`wss://%s/` with the host key `%s`\n' "$host" "$fp" >> "$GITHUB_STEP_SUMMARY"
wait
