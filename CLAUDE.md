# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This repo provisions a WorldSkills-style web development competition environment: Gitea (git, container registry, Actions runners), Traefik, MySQL/phpMyAdmin, a Packagist mirror (Repman), Verdaccio, Pulldeck and Sablier.

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

  The questions can be skipped with `INFRA_DOMAIN`, `INFRA_ROOT_USER`, `INFRA_ROOT_PASSWORD`, `INFRA_LETSENCRYPT` (1/0) and `INFRA_ACME_EMAIL` (or `INFRA_KEEP_CONFIG=1`). Re-running it is also how the admin image gets updated.
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
- The admin container is on the `gitea` network and has no Traefik labels. It writes its own route to `config/traefik/admin.yaml` (gitignored) from `main-config.json`: when the server starts, on every config save and in init. A changed domain or Let's Encrypt setting therefore applies without recreating the container, which the admin cannot do to itself.
- It reaches Gitea's API directly at `http://gitea:3000` (`GITEA_API_URL`). The public hostname goes through Traefik, which can hang once the runners start.
- It mounts this repo at the same absolute path as on the host (`INFRA_DIR`). `docker compose` runs inside the container, but the host daemon resolves the stacks' relative bind mounts, so the paths must match. `pulldeck.yaml` uses `${INFRA_DIR}` for the same reason.

**TLS.**
- Traefik defines the `letsencrypt` resolver (HTTP-01 on `web`). Every HTTPS router opts in with `tls.certresolver=${CERT_RESOLVER:-}`.
  - `CERT_RESOLVER` is `letsencrypt` when `enableHttps` and `letsencrypt` are both on in `main-config.json`, and empty otherwise. Empty means the default certificate from `config/traefik/config.yaml`.
  - The router on the HTTP entrypoint (`competitor-db`) does not take part.
- The variable comes from `install.sh`, or from `routingEnv()` in the admin (init, start). Both derive it the same way, so `up` on Traefik does not recreate it needlessly.
- The admin's `syncCompetitors` writes it into the competitor routes (`config/traefik/competitors.yaml`).
- ACME needs exact hostnames, so routers use `Host(\`x.${GITEA_HOSTNAME}\`)`, not `HostRegexp`.
- Competitor hosts are `<user>-<module>`, lowercase, with `_` replaced by `-`, because Let's Encrypt rejects `_`. This is `competitorHost()` in the admin.
- Certificates live in the `infra-traefik_letsencrypt` volume, which clean never removes, because of the Let's Encrypt rate limits. Setting `ACME_CA_SERVER` in `.admin.env` switches to the staging CA.

**Competitor deploy loop.**
1. `init` imports the framework templates from GitHub into the `frameworks` org and rewrites `.gitea/workflows/docker-ci.yaml` (registry host, `${{ secrets.PULLDECK_BASE_URL }}`).
2. A push triggers Gitea Actions, which builds `git.<domain>/<user>/<module>` and pushes it to the Gitea registry.
3. Pulldeck (`clara.<domain>`, `AUTH_TOKEN` from `pulldeck.env`) redeploys the container. Gitea's system webhook for repository events calls the admin (`http://infra-admin:8090/api/hooks/gitea`, allowed by `GITEA__webhook__ALLOWED_HOST_LIST` in `gitea.yaml`). The admin runs `syncCompetitors`, which regenerates `competitors.yaml` and `config/traefik/competitors.yaml` from the competitors' repositories and pushes a placeholder image for new ones. Sablier starts the containers on demand.
   - This replaced the separate infra-updater service. A container of it left over from an older install is removed by the next init (`--remove-orphans`).

## Gotchas

- Secret files are gitignored:
  - `config/main-config.json` is written by `install.sh` and the UI; `config/main-config.example.json` is the template.
  - `pulldeck.env` is written by `init` and only read by pulldeck.
  - `.admin.env` is separate from `.env` because `init` overwrites `.env`.
- `install.sh` and the admin container run as root and chown the files they write to the repo directory's owner. `main-config.json` is 644; `pulldeck.env` and `.admin.env` are 600. Re-running `install.sh` also repairs the ownership of the generated files.
- Service data (gitea-db, competitor MySQL, repman + postgres, verdaccio, runners) lives in named volumes (`infra_<name>`), not bind mounts under `./data`. MySQL/Postgres chown their data dir on start, which Docker Desktop on macOS refuses for bind mounts. Clean removes the volumes with `down -v`. Only config files are bind-mounted.
- Values duplicated across this repo and skillsit-training-admin:
  - the compose project names `infra` (`exec.ts`) and `infra-traefik` (`install.sh`, `traefik.yaml`, `compose-files.ts`);
  - the admin's container name and port in the webhook URL (`admin.yaml`, `gitea.yaml` `ALLOWED_HOST_LIST`, `WEBHOOK_URL` in `gitea.ts`).
  - the config validation rules (`install.sh`, `schema.ts`).
- `competitors.yaml`, `config/mysql/competitors.sql` and `.env` are generated files.
- `core.autocrlf` is on in the Windows checkout. `*.sh` must stay LF (`.gitattributes`); otherwise `install.sh` fails when run from WSL on the Windows working copy. The Windows checkout also has `core.fileMode=false`, so a `chmod` there is not recorded; set the executable bit with `git update-index --chmod=+x <file>` (`install.sh` is stored as 100755).
