#!/bin/sh
# Builds site/: the files of https://3d.mkfifo.com (docs/factory.md, "The
# URLs"). Workers Builds runs it ("npm run build") before "wrangler
# deploy", which uploads site/ as the static files of the Worker.
#
# - /: the review page (review/index.html), with the models at /models/.
# - /models/: the files of the catalog (priv/models), which CI checks
#   against the build of the code.
# - /palette.json, /version.json (the commit of the build).
# - /_headers: CORS and the cache of each file.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

rm -rf site
mkdir -p site/models
cp priv/models/* site/models/
cp priv/palette.json site/palette.json

# The review page reads the models at ../priv/models/ in the repository,
# and at /models/ on the site.
sed "s#const base = '../priv/models/';#const base = '/models/';#" review/index.html > site/index.html
if ! grep -q "const base = '/models/';" site/index.html; then
    echo "site.sh: the review page has no line const base = '../priv/models/';" >&2
    exit 1
fi

# The commit names the files that the VM builds in R2, so each deploy
# must have its own. The commit of Workers Builds, else the commit of
# git; a value that is not a commit (a name of a branch) does not count.
# With no commit, the time of the build.
commit() { printf '%s' "$1" | grep -Eq '^[0-9a-f]{7,40}$' && printf '%s' "$1"; }
COMMIT=$(commit "${WORKERS_CI_COMMIT_SHA:-}" || commit "$(git rev-parse HEAD 2>/dev/null)" || date -u +build-%Y%m%d%H%M%S)
printf '{"commit": "%s"}\n' "$COMMIT" > site/version.json

# Each project can read the files from its own site. A correction of
# Xưởng reaches the projects at most 5 minutes after the deploy; a copy
# in a cache serves while the new file comes.
cat > site/_headers <<'HEADERS'
/*
  Access-Control-Allow-Origin: *
  Cache-Control: public, max-age=300, stale-while-revalidate=86400
HEADERS

echo "site.sh: $(ls site/models | wc -l | tr -d ' ') files in site/models, commit $COMMIT"
