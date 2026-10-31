# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This repo provisions a WorldSkills-style web development competition environment: Gitea (git, container registry, Actions runners), Traefik, MySQL/phpMyAdmin, a Packagist mirror (Repman), Verdaccio, Pulldeck, Sablier and infra-updater.

It has two parts:
- Docker Compose files (`*.yaml`) in the repo root.
- `install.sh`, which bootstraps a fresh host.

The provisioning logic (init, start, stop, clean, users) lives in a separate repo, [skillsit-training-admin](https://github.com/skillsit-hu/skillsit-training-admin). That repo holds an Express API and a React UI, published as the image `ghcr.io/skillsit-hu/skillsit-training-admin`. It was split out of this repo's former `app/` directory. The admin container mounts this repo and runs `docker compose` on the files here. Its stack lists (`packages/core/src/compose-files.ts`) must follow any compose file that is added, renamed or removed here.

## Commands

On the host:
- `sudo sh install.sh` (POSIX sh) installs Docker if it is missing and asks for the domain and root password. It then:
  - writes `config/main-config.json` and `.admin.env`;
  - creates the `gitea` network and starts `traefik.yaml` as compose project `infra-traefik`;
  - pulls the admin image and starts `admin.yaml` as project `infra-admin`.

  The questions can be skipped with `INFRA_DOMAIN`, `INFRA_ROOT_USER` and `INFRA_ROOT_PASSWORD` (or `INFRA_KEEP_CONFIG=1`). Re-running it is also how the admin image gets updated.
- `ADMIN_IMAGE` in `.admin.env` overrides the image, for a pinned tag or a locally built one. `install.sh` pulls with `--ignore-pull-failures`, so a local-only image works.
- Admin UI: `https://admin.<domain>`, with `127.0.0.1:8090` as a fallback over an SSH tunnel. Every operation is started from the UI; there is no CLI.

## Architecture

**Base layer vs. infra stacks.**
- `traefik.yaml` and `admin.yaml` form the base layer. `install.sh` starts it, and `stop`/`clean` never touch it. `init` still runs `up -d` on Traefik, which applies a changed HTTPS setting.
- Traefik and the admin are separate compose projects (`infra-traefik`, `infra-admin`; `name:` in the files, `-p` in `install.sh`). The other stacks run in project `infra`.
  - Anything in the `infra` project can be removed by init's `gitea.yaml up --remove-orphans`.
  - `down` on a compose file without services (e.g. an empty `competitors.yaml`) acts on the whole project, so clean skips such files.
  - `COMPOSE_PROJECT_NAME` beats the top-level `name:`, so never export it around these calls.
- The `gitea` network is created with `docker network create` (by `install.sh` and by init) and is `external` in every compose file, so no project owns or removes it.
- The admin container is on the `gitea` network. Traefik routes `HostRegexp(^admin\..+$)` to it.
- It reaches Gitea's API directly at `http://gitea:3000` (`GITEA_API_URL`). The public hostname goes through Traefik, which can hang once the runners start.
- It mounts this repo at the same absolute path as on the host (`INFRA_DIR`). `docker compose` runs inside the container, but the host daemon resolves the stacks' relative bind mounts, so the paths must match. `pulldeck.yaml` and `infra-updater.yaml` use `${INFRA_DIR}` for the same reason.

**Competitor deploy loop.**
1. `init` imports the framework templates from GitHub into the `frameworks` org and rewrites `.gitea/workflows/docker-ci.yaml` (registry host, `${{ secrets.PULLDECK_BASE_URL }}`).
2. A push triggers Gitea Actions, which builds `git.<domain>/<user>/<module>` and pushes it to the Gitea registry.
3. Pulldeck (`clara.<domain>`, `AUTH_TOKEN` from `pulldeck.env`) redeploys the container. infra-updater receives Gitea repository webhooks and regenerates `competitors.yaml` and `config/traefik/competitors.yaml`. Sablier starts containers on demand.

## Gotchas

- Secret files are gitignored:
  - `config/main-config.json` is written by `install.sh` and the UI; `config/main-config.example.json` is the template.
  - `pulldeck.env` is written by `init` and only read by pulldeck.
  - `.admin.env` is separate from `.env` because `init` overwrites `.env`.
- `install.sh` and the admin container run as root and chown the files they write to the repo directory's owner. `main-config.json` is 644 because infra-updater reads it; `pulldeck.env` and `.admin.env` are 600. Re-running `install.sh` also repairs the ownership of the generated files.
- Service data (gitea-db, competitor MySQL, repman + postgres, verdaccio, runners) lives in named volumes (`infra_<name>`), not bind mounts under `./data`. MySQL/Postgres chown their data dir on start, which Docker Desktop on macOS refuses for bind mounts. Clean removes the volumes with `down -v`. Only config files are bind-mounted.
- Values duplicated across this repo and skillsit-training-admin:
  - the webhook secret (`infra-updater.yaml`, `gitea.ts`);
  - the compose project names `infra` (`infra-updater.yaml` `DOCKER_PROJECT_NAME`, `exec.ts`) and `infra-traefik` (`install.sh`, `traefik.yaml`, `compose-files.ts`);
  - the config validation rules (`install.sh`, `schema.ts`).
- `competitors.yaml`, `config/mysql/competitors.sql` and `.env` are generated files.
- `core.autocrlf` is on in the Windows checkout. `*.sh` must stay LF (`.gitattributes`); otherwise `install.sh` fails when run from WSL on the Windows working copy. The Windows checkout also has `core.fileMode=false`, so a `chmod` there is not recorded; set the executable bit with `git update-index --chmod=+x <file>` (`install.sh` is stored as 100755).
