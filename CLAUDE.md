# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This repo provisions a WorldSkills-style web development competition environment: Gitea (git, container registry, Actions runners), Traefik, MySQL/phpMyAdmin, a Packagist mirror (Repman), Verdaccio, Pulldeck, Sablier and infra-updater.

It has three parts:
- Docker Compose files (`*.yaml`) in the repo root.
- `install.sh`, which bootstraps a fresh host.
- `app/`, a TypeScript npm-workspaces project holding all provisioning logic. The logic is exposed three ways: an admin UI (React/shadcn) backed by an Express REST API, and root CLI wrappers (`node init.mjs` …).

## Commands

All of these run inside `app/`:
- `npm ci && npm run build`: builds core, then server, then web. The root `*.mjs` wrappers import `app/packages/core/dist`, so they only work after this build.
- `npm test`: Vitest tests for core (`packages/core/test`). Run a single test with `npm test -w @infra/core -- -t "<name>"`.
- `npm run typecheck`
- `npm run dev`: core `tsc --watch`, the server via `tsx watch` on :8090, and Vite on :5173 (it proxies `/api`).
  - For local development, set `REPO_DIR=<copy of the repo>` and `DRY_RUN=1`. Dry-run logs every docker/git command and Gitea request instead of executing it.
  - Run it inside WSL with a Linux Node. With the Windows Node, the Windows `docker.exe` gets spawned instead.
- shadcn components: from `packages/web`, run `npx shadcn@latest add <name>`.

On the host:
- `sudo sh install.sh` (POSIX sh) installs Docker if it is missing and asks for the domain and root password. It then:
  - writes `config/main-config.json` and `.admin.env`;
  - creates the `gitea` network and starts `traefik.yaml` as compose project `infra-traefik`;
  - starts `admin.yaml` as project `infra-admin`.
  
  The questions can be skipped with `INFRA_DOMAIN`, `INFRA_ROOT_USER` and `INFRA_ROOT_PASSWORD` (or `INFRA_KEEP_CONFIG=1`).
- Admin UI: `https://admin.<domain>`, with `127.0.0.1:8090` as a fallback over an SSH tunnel.
- The operations run on the Linux host because they call `docker` and `git`. The CLI also works outside the container: `node init.mjs`, `start.mjs`, `stop.mjs`, `clean.mjs`, `create_user.mjs <user> <pass>`, `disable_competitors_gitlogin.mjs`, `setup_users.mjs`.

## Architecture

**`@infra/core`** (`app/packages/core`) has no Express or React dependency.
- Every operation in `src/ops/` takes an `OpContext` (`{ repoDir, log, signal?, dryRun? }`) and never calls `chdir`.
- `run()` in `exec.ts` is an async `spawn`. It streams lines to `ctx.log` and masks any value passed in `secrets`.
- `compose()` always sets `COMPOSE_PROJECT_NAME=infra` and `INFRA_DIR=<repoDir>`.
- Fatal errors throw `OperationError`.
- `ops/index.ts` holds the `OPERATIONS` registry. Each entry has a zod argument schema, its CLI positional args, a `destructive` flag, and a `docker` flag (`ensureDocker` pre-check). The server and the UI are both driven by this registry.
- `schema.ts` (config schema) and `api.ts` (REST types) are browser-safe subpath exports, used by the web app.
- The ops are ports of the original bash scripts, so keep their order and behaviour. The originals are in commit `bda7a60`.

**`@infra/server`** (`app/packages/server`)
- Login checks against `username`/`password` in `main-config.json`. The session is an HMAC-signed cookie whose key includes the root password, so a password change logs everyone out.
- `trust proxy` is 1, because Traefik is the single proxy in front.
- `JobManager` runs one operation at a time (409 otherwise). It keeps the last 50 jobs in memory and also writes each job's log to `data-admin/jobs/<id>.log`.
- `GET /api/jobs/:id/events` is SSE: it replays the lines after `?after=<seq>`, then streams live.

**`@infra/web`** (`app/packages/web`) uses Vite, React 19, Tailwind v4, shadcn (radix-nova) and TanStack Query. The UI text is Hungarian; operation labels live in `src/lib/labels.ts`.

**Base layer vs. infra stacks.**
- `traefik.yaml` and `admin.yaml` form the base layer. `install.sh` starts it, and `stop`/`clean` never touch it (`BASE_FILES` in `core/src/compose-files.ts`; all stack lists live in that file). `init` still runs `up -d` on Traefik, which applies a changed HTTPS setting.
- Traefik and the admin are separate compose projects (`infra-traefik`, `infra-admin`; `name:` in the files, `-p` in `install.sh`, `BASE_PROJECT` in `compose()`). Anything in the `infra` project can be removed by init's `gitea.yaml up --remove-orphans`, and `down` on a compose file without services (e.g. an empty `competitors.yaml`) acts on the whole project; clean skips such files (`hasServices`). `COMPOSE_PROJECT_NAME` beats the top-level `name:`, so never export it around these calls.
- The `gitea` network is created with `docker network create` (`install.sh`, `ensureBaseLayer`) and is `external` in every compose file, so no project owns or removes it. `ensureBaseLayer` also removes a Traefik container left in the old `infra` project.
- The admin container is on the `gitea` network. Traefik routes `HostRegexp(^admin\..+$)` to it.
- It reaches Gitea's API directly at `http://gitea:3000` (`GITEA_API_URL`). The public hostname goes through Traefik, which can hang once the runners start.
- It mounts the repo at the same absolute path as on the host (`INFRA_DIR`). `docker compose` runs inside the container, but the host daemon resolves the stacks' relative bind mounts, so the paths must match. `pulldeck.yaml` and `infra-updater.yaml` use `${INFRA_DIR}` for the same reason.

**Competitor deploy loop.**
1. `init` imports the framework templates from GitHub into the `frameworks` org and rewrites `.gitea/workflows/docker-ci.yaml` (registry host, `${{ secrets.PULLDECK_BASE_URL }}`).
2. A push triggers Gitea Actions, which builds `git.<domain>/<user>/<module>` and pushes it to the Gitea registry.
3. Pulldeck (`clara.<domain>`, `AUTH_TOKEN` from `pulldeck.env`) redeploys the container. infra-updater receives Gitea repository webhooks and regenerates `competitors.yaml` and `config/traefik/competitors.yaml`. Sablier starts containers on demand.

## Gotchas

- Secret files are gitignored:
  - `config/main-config.json` is written by `install.sh` and the UI; `config/main-config.example.json` is the template.
  - `pulldeck.env` is written by `init` and only read by pulldeck: `AUTH_TOKEN` is generated on the first init and then kept, and `DOCKER_USERNAME`/`DOCKER_PASSWORD` are set to the root user.
  - `.admin.env` is separate from `.env` because `init` overwrites `.env`.
- `install.sh` and the admin container run as root. Write files into the repo with `writeRepoFile`/`appendRepoFile` (`core/src/files.ts`), which chown them to the repo directory's owner. `main-config.json` is 644 because infra-updater reads it; `pulldeck.env` and `.admin.env` are 600. Re-running `install.sh` also repairs the ownership of the generated files.
- Service data (gitea-db, competitor MySQL, repman + postgres, verdaccio, runners) lives in named volumes (`infra_<name>`), not bind mounts under `./data`. MySQL/Postgres chown their data dir on start, which Docker Desktop on macOS refuses for bind mounts. Clean removes them with `down -v`. Only config files are bind-mounted.
- `writeConfig` is atomic (temp file + rename). infra-updater mounts the whole `config/` dir, so it picks up the new file.
- The config schema restricts usernames, modules and subdomains to slug characters, and passwords may not contain `'`, `\` or newlines. These values end up in hostnames, compose YAML and SQL. `install.sh` repeats the same rules.
- The webhook secret is duplicated in `core/src/gitea.ts` (`WEBHOOK_SECRET`) and `infra-updater.yaml`. The compose project name `infra` is duplicated in `exec.ts`, `install.sh` and `infra-updater.yaml` (`DOCKER_PROJECT_NAME`).
- `competitors.yaml`, `config/mysql/competitors.sql` and `.env` are generated files.
- `core.autocrlf` is on in the Windows checkout. `*.sh` must stay LF (`.gitattributes`); otherwise `install.sh` fails when run from WSL on the Windows working copy. The Windows checkout also has `core.fileMode=false`, so a `chmod` there is not recorded; set the executable bit with `git update-index --chmod=+x <file>` (`install.sh` is stored as 100755).
