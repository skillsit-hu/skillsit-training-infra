# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This repo provisions a WorldSkills-style web development competition environment. It runs Gitea (git, container registry and Actions runners), Traefik, MySQL/phpMyAdmin, a Packagist mirror (Repman), Verdaccio, Watchtower, Pulldeck, Sablier and infra-updater. The repo has two parts:

- Docker Compose files (`*.yaml` in the root).
- `app/`, a TypeScript npm-workspaces project that holds all the provisioning logic. It exposes the logic in three ways:
  - root CLI wrappers (`node init.mjs` …)
  - an Express REST API
  - a React/shadcn admin UI

## Commands

All commands run inside `app/`:

- `npm ci && npm run build`: builds core, then server, then web. **The root `*.mjs` wrappers import `app/packages/core/dist`, so they need this build.**
- `npm test`: Vitest tests for core (`packages/core/test`). Run a single test with `npm test -w @infra/core -- -t "<name>"`.
- `npm run typecheck`
- `npm run dev`: runs core `tsc --watch`, the server via `tsx watch` on :8090, and Vite on :5173 (which proxies `/api` to the server). For local development, set `REPO_DIR=<copy of the repo>` and `DRY_RUN=1`. Dry-run logs every docker/git command and Gitea request instead of executing it.
- Add shadcn components from `packages/web` with `npx shadcn@latest add <name>`.

The operations themselves only work on the Linux competition host. They call `docker`, `git` and, outside a root container, `sudo`.

- Root CLI: `node init.mjs`, `start.mjs`, `stop.mjs`, `clean.mjs`, `create_user.mjs <user> <pass>`, `disable_competitors_gitlogin.mjs`, `setup_users.mjs`. Setting `DRY_RUN=1` works here too.
- `setup.mjs` installs Docker on a fresh Debian host. It is intentionally self-contained and does not use `app/`.
- Admin UI: `docker compose -f admin.yaml up -d --build`.

## Architecture

**`@infra/core`** (`app/packages/core`) has no Express or React dependencies.
- Every operation (`src/ops/`) takes an `OpContext` = `{ repoDir, log, signal?, dryRun? }`. Operations never `chdir`.
- `run()` in `exec.ts` is an async `spawn`. It streams each output line to `ctx.log` and masks the values passed in `secrets`.
- Fatal errors throw `OperationError`. The CLI turns this into exit 1; the server marks the job as failed.
- `ops/index.ts` holds the `OPERATIONS` registry: zod argument schema, CLI positional args, and a `destructive` flag. The server and UI are both driven by this registry.
- `schema.ts` (the config zod schema) and `api.ts` (REST types) are browser-safe subpath exports (`@infra/core/schema`, `@infra/core/api`) that the web app imports.
- The operations are ports of the original bash scripts. Keep their order and behaviour; the old versions are in git history (`git log --all -- init.sh`, commit `bda7a60`).

**`@infra/server`** (`app/packages/server`)
- Login checks credentials against `username`/`password` in `main-config.json`. The session is an HMAC-signed cookie, and the key includes the root password, so changing the password logs everyone out.
- `JobManager` runs **one operation at a time** (a second one gets 409). It keeps the last 50 jobs in memory and appends each job's log to `data-admin/jobs/<id>.log`.
- `GET /api/jobs/:id/events` is SSE: it replays the lines after `?after=<seq>`, then streams live.
- The server also serves `packages/web/dist`.

**`@infra/web`** (`app/packages/web`): Vite, React 19, Tailwind v4, shadcn (radix-nova) and TanStack Query, with Hungarian UI text. Operation labels live in `src/lib/labels.ts`. Config editing keeps a local draft and validates it with the shared zod schema before `PUT /api/config`.

**The admin container (`admin.yaml`)**
- It uses `network_mode: host`, so Gitea's API is still `127.0.0.1:3000`.
- It mounts the repo at the **same absolute path** as on the host (`/home/azureuser/infra`). This is required: `docker compose` runs inside the container, but the host daemon resolves the stacks' relative bind mounts.
- It is not in the start/stop/clean lists, so it survives `clean`.

**Compose stacks**
- `traefik.yaml` creates the `gitea` network, and every other stack declares it `external`, so Traefik must start first.
- Compose variables (`GITEA_HOSTNAME`, `ENTRYPOINT`, `REGISTRATION_TOKEN`, …) are passed in the environment by the operations. They are also written to `.env` at the end of init.
- The stack lists for init/start/stop/clean are all in `core/src/compose-files.ts`. Add new stacks there.

**Competitor deploy loop**
1. `init` imports the framework templates from GitHub into the `frameworks` org. It rewrites `.gitea/workflows/docker-ci.yaml` to use `git.<domain>` and `${{ secrets.PULLDECK_BASE_URL }}`.
2. A competitor push triggers Gitea Actions, which builds and pushes `git.<domain>/<user>/<module>`.
3. Pulldeck (`clara.<domain>`, authenticated with `AUTH_TOKEN` from `.env.clara`) redeploys the container. infra-updater receives Gitea repository webhooks and regenerates `competitors.yaml` and `config/traefik/competitors.yaml`. Sablier starts containers on demand.

## Gotchas

- `writeConfig` is atomic (temp file + rename). infra-updater mounts the whole `config/` dir for exactly this reason.
- The config schema restricts usernames, modules and subdomains to slug characters, and passwords may not contain `'`, `\` or newlines. These values are interpolated into hostnames, compose YAML and SQL.
- `pulldeck.yaml`, `infra-updater.yaml` and `admin.yaml` hard-code `/home/azureuser/infra`.
- The webhook secret is duplicated in `core/src/gitea.ts` (`WEBHOOK_SECRET`) and `infra-updater.yaml`.
- `competitors.yaml`, `config/mysql/competitors.sql` and `.env` are generated (`createUser` appends to the SQL file).
- `config/main-config.json` and `.env.clara` contain real credentials.
- `solutions.yaml` and `content-services.yaml` are standalone stacks that no operation manages.
