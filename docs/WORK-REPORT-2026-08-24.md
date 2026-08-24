# Work report — 2026-08-24: Node 22, a working per-app conf, README touch-up

Status: **changes local only, nothing pushed** (master is already pushed from the
2026-08-23 session and the user is validating the pipeline; push these when
that's done). Committed separately: `fix(ci): run smoke test on the runner's
own network` (the pipeline fix from §4).

## TL;DR

- **Node 20 (EOL since April 2026) → v22.23.2** on all three architectures.
  Node 24 (the current LTS line) does not ship `linux-armv7l` binaries anymore,
  so 22 is the newest line that can cover arm/v7 — the image's reason for
  existing. Validated amd64, arm64, arm/v7 (build + run + hello smoke test)
  and the `shiny-with-devtools` target (amd64).
- **Per-app conf fix + correction of the previous report.** shiny-server
  1.5.23 actually reads **`.shiny_app.conf`** — *with* the underscore, the name
  the repo and README always used. The "naming quirk" in the 2026-08-23 report
  (§4) was wrong. What was *really* broken: the file was never baked into the
  image (`COPY hello/*` drops dotfiles), and its content (a copy-paste of the
  site-conf format) parsed but did nothing. Rewritten into the effective
  format and baked in; proven empirically.
- **README validated end-to-end** (documented workflow reproduced in a temp
  folder against the new local image, including the `init.sh` library install,
  `init_done` gating and restart) and three stale spots fixed in the
  original voice.

## What changed

### 1. Node 20 → 22 (EOL)

Node 20 reached EOL in April 2026. The image's npm tree (incl. `@posit/shiny`)
declares `engines: node >= 18, npm >= 10`, so the newer LTS lines qualify —
**but** `nodejs.org/dist` no longer serves `linux-armv7l` tarballs for Node 24
(verified: `node-v24.19.0-linux-armv7l.tar.xz` → 404), and arm/v7 is a
first-class platform of this image. So all three arches move to the newest
Node 22 ("Jod") release, **v22.23.2** (maintenance LTS until April 2027),
pinned once via `ENV V_Node` (declared right before the node download so a
future bump invalidates only the tail of the build, not the multi-hour R
build).

### 2. Per-app conf: the real story (`.shiny_app.conf`)

Code archaeology of the *installed* shiny-server 1.5.23.1030
(`lib/config/app-config.js`, `lib/router/local-config-router.js`,
`lib/router/config-router-util.js`, `config/shiny-server-rules.config`):

- `findConfig_p()` does `path.join(appDir, ".shiny_app.conf")` — **underscore**.
  The no-underscore `.shinyapp.conf` name (quoted in newer shiny-server docs)
  is what the previous report got from; for the pinned 1.5.x the repo/README
  name was right all along.
- It is only consulted when `allow_app_override` is enabled in the server
  config — it is, in our `shiny-server.conf`.
- The file is parsed with the same nginx-style parser against
  `shiny-server-rules.config`, in *application* scope: `app_init_timeout`,
  `app_idle_timeout`, `frame_options`, `simple_scheduler`, ... are honoured;
  a parse error is rethrown by the router (a malformed file fails the app).
- The parsed file is then whitelisted to `appDefaults` / `scheduler` /
  `frame_options` — so the old hello file (a copy of `run_as` + `server{}` +
  `location{}`) parsed fine but contributed **nothing**.
- Two silent-fallback paths make "the app still starts" a *non*-proof that the
  file is read: a missing file and — in `AppConfig.readConfig_p` — a parse
  error both resolve to `null` and fall back to the base config.

**Proof it works:** with `frame_options deny;` in `.shiny_app.conf` the
response carries `x-frame-options: DENY`; the same run without the file sends
no header (default `allow`).

Changes:

- `hello/.shiny_app.conf` rewritten to the effective format, keeping the
  original intent (long cold-start timeouts): `app_init_timeout 1800;`
  `app_idle_timeout 1800;`
- `Dockerfile`: `COPY hello/*` → `COPY hello/` — the glob silently dropped the
  dotfile, so the per-app conf never reached the image. Comment added so
  nobody "simplifies" it back.

### 3. README

Reproduced the documented user workflow in a temp folder against the new
local image:

| Step | Result |
|---|---|
| folder structure + copy conf/init.sh/hello | ok |
| first run: `init.sh` installs the example libs (`shinyjs`, `filelock`), creates `init_done` | ok (verified in R) |
| `http://localhost:3838/hello/` → "It's Alive" | ok |
| `docker restart`: init skipped (`init_done`), app serves, libs persist | ok |
| docker-compose snippet (`docker compose config`) | parses |

Fixes (minimal, original voice):

- "each app **will need** to have its own configuration file" → it's
  **optional**, with the correct name spelled out (and what it does when
  present).
- "leaves a 4.5GB builder image behind post-build" → with modern BuildKit the
  intermediate stage only lives in the build cache (`docker builder prune`).
- The "Node.js (DEPRECATED...)" section described `determine_arch.sh`, which
  no longer exists in the repo → replaced with a short section documenting the
  actual pinning (`ENV V_Node`, per-arch tarball) and *why* it's 22 and not 24.

## Validated

| What | How | Result |
|---|---|---|
| Node version | `node --version` + shiny-server banner in container | `v22.23.2`, "Shiny Server v1.5.23.0 (Node.js v22.23.2)" |
| `shiny` target, amd64 | full build (R from source, -j16) + run + `curl /hello/` | passes |
| `shiny` target, linux/arm64 | full build under qemu + container run under qemu + `GET /hello/` | passes |
| `shiny` target, linux/arm/v7 | full build under qemu + container run under qemu + `GET /hello/` | passes |
| `shiny-with-devtools`, amd64 | build + `loadNamespace("devtools")` | passes (devtools 2.5.2) |
| per-app conf is read & applied | `frame_options deny;` → `X-Frame-Options: DENY` header; control run sends none | passes |
| final `hello/.shiny_app.conf` | parses + app serves (bind-mounted against existing image) | passes |
| README workflow | temp-folder reproduction incl. `init.sh` install/persist/restart | passes |

Local test images (prune when done): `shiny-local-node22:amd64`,
`shiny-local-node22:final:amd64` (has the fixed hello conf baked in),
`shiny-local-node22:arm64`, `shiny-local-node22:armv7`,
`shiny-local-node22:amd64-devtools` — plus the 2026-08-23 set
(`shiny-local:{amd64,arm64,armv7,amd64-devtools}`).

## 4. Bonus: why the pushed pipeline's smoke test hung for hours

The 2026-08-23 push went through build and push fine, but the ci job then
sat in the smoke test stage forever ("IP printed, then nothing").

**Root cause** (found live on the runner host):

- The runner container sits on a user-defined bridge network; the smoke
  container (plain `docker run`) landed on the default bridge.
- The host's firewall **drops traffic between separate docker bridges**
  (verified with listener containers: same-bridge probes connect instantly,
  cross-bridge probes black-hole). Container egress to the internet works,
  which is why the build itself was fine.
- The old smoke test then curled that cross-bridge IP with **no
  `--max-time`**, so every attempt hung ~2 min and the 90-iteration loop
  pointed at a 4320-minute job timeout — "stuck" instead of "failed".

**Fix** (`ci.yml` + `build.yml`, committed separately):

- detect the runner's own network from the runner container (`docker
  inspect`), run the smoke container **on that network**, and address it by
  **container name** via docker's built-in DNS (also removes the old
  multi-network `range`-template IP ambiguity);
- keep a bridge-IP fallback for hosts without the restriction;
- `curl --max-time 30` in the polling loop so dead endpoints fail fast.

Validated live on the runner: smoke container on the runner network,
reachable by name from inside the runner, serves "It's Alive".

Side finding: the runner host does not define `CACHE_REGISTRY_*` at all,
so the spotifyd runner's (which still uses them in its pipeline) resolve
empty there — pre-existing, untouched, but worth knowing.

## Follow-ups / decisions

1. **Push** these commits once the user's pipeline validation is green
   (the ci-smoke fix needs to ride along so the re-run doesn't hang again).
2. **Done (was deferred, done ahead of the re-push):** removed the
   now-unused `CACHE_REGISTRY_*` env vars from the `gh_runner_shiny` runner
   service (the spotifyd runner keeps them; its pipeline still uses the
   registry). Runner force-recreated and reconnected cleanly.
3. **Dependabot PRs** (trixie-20260803, actions/checkout 6→7) still need
   rebasing on top of the pushed commits — user is on it.
4. **Future node bumps:** one line (`ENV V_Node`). When Node 23+/24 ever
   brings back armv7l tarballs — or if arm/v7 support is dropped — the pin can
   follow the current LTS line again.
5. There is no shiny-server 2.x: `v1.5.23.1030` is the newest upstream
   tag, so the image is pinned to the latest release. If a 2.x ever lands,
   re-check the per-app conf file name first (newer shiny-server docs show
   `.shinyapp.conf` without the underscore) before touching
   `hello/.shiny_app.conf` or the README.
6. Runner-host firewall (drops inter-bridge container traffic) was left
   as-is on purpose — it's host hardening, not something to change from a
   repo. If it ever turns out to be misconfigured, the smoke tests now
   work around it either way.
