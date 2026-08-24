# Work report — 2026-08-23: fixing the build and the CI/CD pipeline

Status: **all changes committed locally, nothing pushed.** Two commits on top
of `57a2111` (plus this report):

```
0fb3f73 fix(build): make the image actually build and actually work
06caa72 fix(ci): standardize pipelines on Docker Hub, re-add working smoke test
```

## TL;DR

- The Docker build is fixed and validated on **linux/amd64, linux/arm64 and
  linux/arm/v7** (full build under qemu + container run + hello-app smoke
  test), and the **`shiny-with-devtools`** target on amd64.
- The CI/CD pipelines are rewritten: standard Docker Hub login + buildx
  multi-arch, a working DooD-aware smoke test re-added, and the broken
  weekly version-checker workflows repaired.
- **Root-cause bonus finding:** every image published to Docker Hub since
  **R4.5.2 (Nov 2025) is broken** — `shiny-server` exits 0 silently and
  serves nothing. The fix is one missing line in the Dockerfile. The
  currently published `latest` tag does not work; users on the R4.5.1-era
  tags are fine.

## What was broken

### 1. The Docker build

#### 1a. `shiny-server` silently exits 0 — no server at all (the big one)

The C++ launcher (`src/launcher.cc` in the shiny-server repo) locates its
install dir via `/proc/<pid>/exe` and then does:

```cpp
std::string nodePath = shinyServerPath + "/ext/node/bin/shiny-server";
...
execv(nodePath.c_str(), newargs);
// falls through to `return 0` if execv fails
```

i.e. it execs the **node binary under the name `shiny-server`** — a copy that
the original `external/node/install-node.sh` creates
(`cp ext/node/bin/node ext/node/bin/shiny-server`). Commit `2184bc2`
("circumvent install_node and make arch detection comply with qemu/bare metal
detection", Sep 2025) replaced that script with a manual node tarball
download **but never re-created the copy**. Result: `execv()` fails with
ENOENT, the code after it is dead-but-reachable, and the launcher exits 0
with **no error and no logs**. The container looks alive for a moment, then
just sits there serving nothing (or exits).

Verified against the *published* `hvalev/shiny-server-arm:latest`:
`shiny-server --version` prints nothing and exits 0, and
`/usr/local/shiny-server/ext/node/bin/` contains no `shiny-server` file.

**Fix:** one line in the Dockerfile after the node download:
`RUN cp /shiny-server/ext/node/bin/node /shiny-server/ext/node/bin/shiny-server`
(with a comment so nobody removes it again).

#### 1b. R 4.5.2 is no longer downloadable

CRAN changed how it serves base R sources. `/src/base/R-4/<version>.tar.gz`
is dead — the directory index still lists the files, but fetching them 404s
on `cran.r-project.org`, `cran.rstudio.com`, `cloud.r-project.org` and the
mirrors (the index is stale). Only the **current release** is served, at the
alias `/src/base/R-latest.{tar.gz,tar.xz}`. The authoritative version marker
is `/src/base/VERSION-INFO.dcf` (`Release: 4.6.1`, `Old-release: 4.5.3`).
So the Dockerfile's `wget .../R-4/4.5.2.tar.gz` failed immediately.

**Fix:** bumped **R 4.5.2 → 4.6.1** (current release), build now:

```
wget https://cran.r-project.org/src/base/R-latest.tar.gz
test -d R-4.6.1        # fails loudly if CRAN's latest != pinned version
```

The `test` is the pin: when 4.7.0 lands, the build breaks *by design* until
`R-version.txt`/Dockerfile are bumped (which the fixed `check_r.yml`
workflow proposes automatically).

#### 1c. `install.packages()` failures were invisible

`R -e "install.packages(...)"` **exits 0 even when packages fail**. In
practice this bit us twice while revalidating:

- shiny's dependency **`fs` failed on missing `libuv1-dev`**
  (`fatal error: uv.h: No such file or directory`) and the image was
  "built" **without shiny at all**.
- the devtools tree's **`stringi`** needs ICU; without `libicu-dev` it falls
  back to compiling a bundled ICU (works, but very slow, especially under
  qemu for the arm builds).

**Fix:** added `libuv1-dev` (shiny stage) and `libicu-dev` (devtools stage),
and appended an explicit verification after each install:
`R -e "stopifnot(all(c('shiny','Cairo') %in% rownames(installed.packages())))"`.

#### 1d. `--with-blas --with-lapack` was a silent no-op

The builder never installed `libblas-dev`/`liblapack-dev`, so R's configure
silently fell back to its bundled `lapack_lite` — the advertised
"Blas and Lapack support" in the README was not actually there. Once the dev
packages were added (making the linking real), the *runtime* image broke
with `error while loading shared libraries: libblas.so.3` (exit 127) because
the runtime libs weren't in the production stage.

**Fix:** `libblas-dev`/`liblapack-dev` in the builder **and**
`libblas3`/`liblapack3` in the runtime image. R now genuinely links against
system BLAS/LAPACK (same reference implementations bookworm/trixie ship).

#### 1e. Smaller hardening

- `libreadline6-dev` → `libreadline-dev` (portable name; on trixie
  `libreadline6-dev` resolves only via a transitional Provides).
- Added `file` to the builder (R configure warns without it).
- `ARG PYTHON=`which python3`` was evaluated **at Dockerfile parse time** in
  the buildkit environment (fragile: can be empty → `--python=""` breaks
  node-gyp). Now runtime `$(which python3)`; python3 moved into the first
  apt block so it exists when cmake runs.
- `R_BUILD_JOBS` / `BUILD_JOBS` / `PKG_CPUS` build args (default **4**, so
  existing runner builds are unchanged; pass
  `--build-arg R_BUILD_JOBS=16` etc. on fast hosts).

### 2. The CI/CD pipeline

#### 2a. `ci` / `build` failed before the build ever started

Every run since May 2026 died at **"Login to Cache Registry"**
(`Error response from daemon: Get "https://***/v2/": http: server gave HTTP
response to HTTPS client`). The pipeline forced `http = true` (plain HTTP)
onto the cache registry via `buildkitd-config-inline` while also
`docker login`-ing to it — a configuration that only works for a plain-HTTP
local registry, not Docker Hub. With the cache registry being Docker Hub,
the build steps were always skipped.

**Fix:** removed the whole private-cache-registry plumbing (masking step,
second login, buildkit override). One standard Docker Hub login now covers
pushing images **and** the buildkit registry cache
(`hvalev/shiny-server-buildcache:latest`, `mode=max`).

#### 2b. The smoke test (removed in PR #165) is back — and DooD-aware

The old attempt failed because the runner is DooD (the runner container
shares the host docker socket): `docker run -p 3838:3838` publishes the port
on the **host**, which is unreachable from inside the runner container. The
smoke test now:

1. builds the amd64 image with `--load`,
2. `docker run -d` (no port publishing),
3. resolves the container's bridge IP via `docker inspect`,
4. polls `http://$IP:3838/hello/` (up to ~7.5 min; first request cold-starts
   R),
5. asserts the response contains "It's Alive",
6. dumps server logs on failure.

`build.yml` does the same against the **published** image after push
(`docker pull --platform linux/arm64... amd64` of `:latest`), so a bad
manifest can never ship silently.

#### 2c. The weekly version checkers

Both `check_r.yml` and `check_shiny.yml` failed at **Set up job** on every
Saturday: `jacobtomlinson/gha-find-replace@v3.0.5` — the tag exists as
**`3.0.5` (no `v` prefix)**. Fixed to `@3.0.5`. Additionally:

- `check_r.yml` detected the latest R by grepping the `/src/base/R-4/`
  index — dead with the CRAN layout change (see 1b). Now reads
  `VERSION-INFO.dcf`.
- Both workflows now guard the update/PR steps on
  `current != release`, so a no-change week is a clean no-op.

#### 2d. `auto-merge.yml`

`gh pr merge --auto` fails with exit 1 when auto-merge is not enabled on the
repository (it currently isn't). The workflow now checks
`autoMergeAllowed` and skips with a hint instead of producing red runs.
(Enable it under Settings → General if you want dependabot PRs to merge on
their own.)

#### 2e. Misc

- `build.yml` now triggers only on auto-release tags (`R*-S*`, e.g.
  `R4.6.1-S1.5.23.1030`) instead of any tag; tags come from
  `github.ref_name` (drops `dhkatz/get-version-action`, which only emits
  Node20 deprecation warnings).
- Restored the explicit persistent buildx builder
  (`name: shiny-builder`, `cleanup: false`, `use: true`, passed to
  `build-push-action`): on the DooD runner the buildkit container and its
  local cache survive between runs, which is what keeps the qemu
  cross-builds tractable (the runner's `cleanup.sh` already prunes that
  cache daily).

## What changed (files)

| File | Change |
|---|---|
| `Dockerfile` | all of §1 (node wrapper fix, R 4.6.1 + `R-latest` + version guard, blas/lapack, libuv1-dev, libicu-dev, install verification, libreadline-dev, `file`, runtime python3, parallelism build args) |
| `shiny-server.conf` | `app_init_timeout 300` (see §3a) |
| `R-version.txt` | `4.5.2` → `4.6.1` |
| `README.md` | version badge; `docker build <git-url>` (unsupported by BuildKit) → clone + build; parallelism build args documented |
| `.github/workflows/ci.yml` | §2a, §2b, §2e |
| `.github/workflows/build.yml` | §2a, §2b, §2e |
| `.github/workflows/check_r.yml` | §2c |
| `.github/workflows/check_shiny.yml` | §2c |
| `.github/workflows/auto-merge.yml` | §2d |

## 3. Extra fixes beyond "make it build"

### 3a. `app_init_timeout` (shiny-server.conf)

Default is 20 s. On Pi-class devices R can take longer than that to
cold-start an app on the first request; shiny-server then kills the attempt,
and **every subsequent request kills a fresh attempt the same way** — the
app can never initialize (infinite 503). Set `app_init_timeout 300;` in the
server block (pure ceiling, no downside on fast hardware). This also matches
the obvious intent of `hello/.shiny_app.conf`'s `app_init_timeout 1800` —
which shiny-server never reads, see §4.

### 3b. `install.packages` verification

Covered in §1c — without it the build "succeeds" on broken images. This is
the class of bug that most likely caused the original smoke-test attempts to
mysteriously fail.

## 4. Validated

| What | How | Result |
|---|---|---|
| `shiny` target, amd64 | `docker build --target shiny` | builds |
| hello app, amd64 | container run, curl `/hello/`, inspect logs, render a Cairo histogram via `Rscript` | passes |
| `shiny` target, linux/arm64 | buildx + qemu, then container run under qemu + curl | passes |
| `shiny` target, linux/arm/v7 | buildx + qemu, then container run under qemu + curl | passes |
| `shiny-with-devtools`, amd64 | `docker build --target shiny-with-devtools`, then `loadNamespace("devtools")` | passes (devtools 2.5.2) |
| updated `shiny-server.conf` | bind-mounted full `/etc/shiny-server` (the README user workflow) on all three archs | parses & serves |
| workflow YAML | `yaml.safe_load` on all files | parses |
| apt package lists (builder / shiny / devtools) | `apt-get -s` on `debian:trixie-20260518` | all resolve |

Test images kept locally for poking: `shiny-local:amd64`,
`shiny-local:arm64`, `shiny-local:armv7`,
`shiny-local:amd64-devtools` (~7.3 GB total; `docker rmi` when done).

## 5. Follow-ups / decisions

1. **Push & publish** when happy: push master, then either
   `workflow_dispatch` on `build.yml` (test run) or let the next
   `R*-S*` tag push do the release build.
2. **Node 20 is EOL** (April 2026). Still pinned at v20.0.0 on purpose
   (minimal risk for this fix). Recommended follow-up: bump to Node 22 with
   its own arm validation pass.
3. **Auto-merge** is not enabled on the repo — enable in Settings if wanted
   (the workflow skips gracefully until then).
4. **`.shiny_app.conf` naming quirk** (pre-existing, untouched):
   shiny-server's per-app config file is `.shinyapp.conf` (no underscore);
   the repo/README use `.shiny_app.conf`, which is ignored (apps work via
   the site config). Also `COPY hello/*` excludes dotfiles, so it isn't
   baked into the image anyway.
5. **Runner env vars** `CACHE_REGISTRY_*` on `gh_runner_shiny` (michiokaku,
   `stack/michiokaku/runners/docker-compose-runners.yml`) are now unused by
   the workflows — can be removed whenever.
6. **Open dependabot PRs** (trixie-20260803, actions/checkout 6→7) will
   conflict with the new Dockerfile/workflows on merge — rerun dependabot
   after merging these changes (or resolve the trivial conflicts).
