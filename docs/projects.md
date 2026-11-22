# A new project

This guide tells how a project of mine gets models from the factory of
World, with the construction shifts for the parts that do not fit the
edge. `docs/factory.md` has the details of each URL and of the shifts.

## Who can ask

| Caller | What it gets |
|---|---|
| A job of GitHub Actions of a repository of my account (`sntran`), with its ID token | A project. Its name is the name of the repository, in small letters (`sntran/Vung_Tau` is `vung_tau`). A part that fits the edge builds at once. Only a part that does not fit the edge waits for a construction shift, and the request can start a shift. No secret. |
| A job of a repository of another account, or a request with no token | A public request. Each part that fits the edge builds at once, and each file of an order comes. A part that does not fit the edge gives 422 (ask for the whole file of the order instead), and the request starts no shift. |
| A request with a wrong token (an old ID token, another audience) | A public request, as above. |

A part of a sculpture fits the edge when the estimate of the memory of
its build is 20 MB or less, and the estimate of its faces (`tile.faces`
of the parts list) is 150,000 or fewer. The maps take the most memory,
so in practice a sculpture with no maps and few faces fits, and a part
with maps does not (`docs/factory.md`, "Three orders at one time, with
the record"). A person fits at mid and far, and not at near.
A part of a project that fits by its estimates, and that the guard of
the memory of the edge stops (`World.Guard`), also waits for a shift; a
public request gets the error of the guard (422). So does a part whose
build at the edge ended the VM: it waits for a shift from then on.

The Worker checks the ID token (`oidc.js`): its signature by GitHub,
the issuer, the audience, the time, and the number of the account of
the owner of the repository (`repository_owner_id`, not only its name).
So a repository of another account with the same name is not a project.

Do not give `WORLD_TOKEN` to a project. It is my key for a caller that
is not a job of GitHub Actions, and it can also pause, resume, cancel or
change each construction of each project (`docs/factory.md`, "The
control key"). A project needs no secret.

## The workflow

```yaml
permissions:
  contents: read
  # The ID token of the job, which proves the project to the factory.
  id-token: write

jobs:
  models:
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: 24
      - run: node tools/world-parts.mjs
        env:
          WORLD_URL: https://world.mkfifo.workers.dev
```

- `id-token: write` lets the job ask GitHub for an ID token. Ask for a
  new token for each request: a token is good for some minutes only.
- The audience of the token is `https://world.mkfifo.com`, also when the
  job asks the address on workers.dev.
- The address is `https://world.mkfifo.workers.dev`. The zone
  mkfifo.com gives the runners of GitHub a challenge that a job cannot
  answer (`docs/factory.md`, "The secrets").

The ID token, in a script of the job:

```js
async function idToken() {
  const url = `${process.env.ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${encodeURIComponent('https://world.mkfifo.com')}`;
  const r = await fetch(url, { headers: { authorization: `bearer ${process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN}` } });
  return (await r.json()).value;
}
```

## Ask for all the parts of a list at one time

A model is its parts list (`/o/HASH.elements.json`, and `.mid.` and
`.far.`): each part has its key and its URL `/p/KEY.glb`. Get the list,
then ask for each part of the list at the same time. Then one shift
builds the parts that do not fit the edge, each node one part for each
of its cores, at the same time. A part that you ask for one at a time
waits for the part before it.

## Ask again

A request can get an answer that is not the file yet. Ask again until
the file comes or a limit of time ends (for example 45 minutes: a shift
takes some minutes to start), then fail with the keys that did not
come.

| Answer | What to do |
|---|---|
| 202 with `retry-after` | The part or the list builds on (in the edge, or in a shift). Ask again after `retry-after` seconds. |
| 503 with `retry-after` | The VM of the edge stopped (an order that needs more memory, or a deploy). The next request starts it again. Ask again after `retry-after` seconds. |
| A stream that breaks (`POST /builds` with `accept: text/event-stream`) | Connect again to `/builds/ID/events` with `Last-Event-ID`: the stream sends the events after it. |
| A connection that fails, or a 5xx with no `retry-after` | Ask again after some seconds, with a longer wait each time. |
| 422 | The order or the part has an error. Do not ask again: correct the order. |

```js
async function get(url, until) {
  for (let wait = 5; ; wait = Math.min(wait * 2, 60)) {
    const r = await fetch(url, { headers: { authorization: `Bearer ${await idToken()}` } }).catch(() => null);
    if (r && r.status === 200) return r;
    if (r && r.status < 500 && r.status !== 202) throw new Error(`${url}: ${r.status} ${await r.text()}`);
    const after = Number(r?.headers.get('retry-after') ?? wait);
    if (Date.now() + after * 1000 > until) throw new Error(`${url}: no file in the limit of time`);
    await r?.arrayBuffer();
    await new Promise((done) => setTimeout(done, after * 1000));
  }
}

const until = Date.now() + 45 * 60_000;
const list = await (await get(`${process.env.WORLD_URL}/o/${hash}.mid.elements.json`, until)).json();
const parts = await Promise.allSettled(list.parts.map((p) => get(`${process.env.WORLD_URL}${p.url}`, until)));
```

## Pin a commit of World

The factory builds each file with the commit of World that it runs
(`/version.json`, and the header `x-world-commit` of each file). A new
deploy of World can change the files of an order. A part does not
change: its key is a hash of its data and of the version of its rule, so
the same key is the same file, for ever. The version of a rule comes
from its source (`docs/factory.md`, "One key in each folder"), so the
factory, a job of CI and a clone of the same commit in any folder give
the same keys.

Each part got a new key one time, with the deploy of pull request #67
(the version from the source). Do not lock a key made before that
deploy: get the parts lists again from the factory, and lock their keys.

So keep a lock in the project, as Vũng Tàu does (`data/world/lock.json`,
its plan 0023, R3, and plan 0027, D4):

- the commit of World (`x-world-commit`);
- for each order and each level, the hash of the order and the SHA-256
  of its parts list;
- the SHA-256 of each part file.

A check in CI compares each file with the lock, with no network. A new
lock comes in one commit, after a look at the models. To build the same
files with no factory, clone World at the commit of the lock and use
`mix world.order` (`docs/factory.md`, "The server on a computer").

## A builder in a workspace

A builder that is not a job of GitHub Actions (an agent in a workspace,
a tool on a computer) has no ID token, so its requests are public. It
gets the files of an order, and each part that fits the edge, as any
caller does. For the parts that do not fit, it does not ask the factory
itself: it starts the workflow of its project, and takes the files from
the run.

1. The project has a workflow with `workflow_dispatch`, with the ID
   token of its job (above, "The workflow"). The job asks for the parts
   lists and the parts, waits for each part (a shift starts when a part
   does not fit the edge), and keeps them as an artifact of the run
   (`actions/upload-artifact`), or commits them to a branch.
2. The builder starts the run (`gh workflow run`, or the API of GitHub
   with the token of its own account), waits for its end (`gh run
   watch`), and takes the artifact (`gh run download`).
3. The builder checks each part with the lock of the project, as a
   check in CI does (below, "Pin a commit of World").

So the token of the project stays in the job, and the builder needs no
secret of World.

## The orders that the factory refuses for memory

The edge has the room of one VM in an isolate of 128 MB, and the guard
of the memory (`WORLD_MEMORY_MB`, 60 MB) stops each build that needs
more. The factory then answers 422, "needs more memory than the factory
has (60 MB)", for:

- the whole file of a large model at a level (`/o/HASH.glb`,
  `.mid.glb`, `.far.glb`): most models with sculptures at near (for
  example the scooter of the catalog, before its files came from the
  catalog), and large buildings at each level;
- the check of an order with a pose (`joints`) whose model the check
  builds at far (`POST /orders`), when that model is large: the check
  of the joints needs the model. With no pose, the check keeps the check
  of the data of the order when the build at far needs more memory: the
  order is good, and its parts list and its parts give the errors of its
  build;
- a parts list, when the model is too large for its list.

A model of the catalog with no change is not in this list: for the
order `{"blueprint": "catalog", "options": {"name": NAME}}` with no
colors and no pose, the factory gives the files of `priv/models` of its
commit at each level with no build, also to a public caller
(`handler.js`). `mix world.build` checks that each of these files is the
build of the order at the same commit, so a clone (`mix world.order`)
gives the same bytes.

What a project does then:

1. It asks for the parts list of the order at that level
   (`/o/HASH.LEVEL.elements.json`), and it gets each part alone
   (`/p/KEY.glb`), with its place in the list. Each part fits in its own
   build.
2. A part that does not fit the edge (`docs/factory.md`, "Three orders
   at one time, with the record") comes from a construction shift, for
   a request of a job of GitHub Actions of the project with its ID token
   (above, "Who can ask"). A builder with no ID token starts that job
   (above, "A builder in a workspace").
3. When the parts list itself gets 422, the project asks for a lower
   level, or it makes the model smaller (fewer edits, larger cells, a
   smaller bake).

## The limits

- **6 starts of a shift each day (UTC), for all the projects.** The edge
  starts a shift when a part of a project waits and no shift takes it
  (`shift.js`). All my projects share these starts.
- **One shift at a time.** A start while a shift runs waits for its end
  (the concurrency group of `shift.yml`). The parts of all the projects
  go to the same shift, in the order of their requests.
- A shift goes home after 60 minutes with no work, or 15 minutes before
  the end of its time (5.5 hours at most). A request can ask for a
  shorter shift with the header `x-world-shift-hours` (0.5 to 5.5).
- A shift starts in about one minute when the build of its commit is in
  the cache, else in 3 to 5 minutes.
- `GET /census` gives the starts of the day that are used (`shifts`:
  the day, the starts, the limit and the time of the last start), and
  the summary of a shift gives the parts of each project.
