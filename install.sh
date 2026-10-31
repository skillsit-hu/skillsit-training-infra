#!/bin/sh
# Brings a fresh host up to the admin UI: installs Docker if needed, writes config/main-config.json,
# starts the base layer (Traefik + admin UI) and prints the admin address. Everything else happens in the UI.
#
#   sudo sh install.sh
#
# Non-interactive: INFRA_DOMAIN, INFRA_ROOT_USER, INFRA_ROOT_PASSWORD, INFRA_LETSENCRYPT (1/0) and INFRA_ACME_EMAIL
# skip the questions (INFRA_KEEP_CONFIG=1 keeps an existing config).

set -eu

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E sh "$0" "$@"
fi

cd "$(dirname "$0")"
INFRA_DIR=$(pwd -P)
# uid:gid of the repo directory (ls -n is portable; stat's flags differ between GNU and BSD/macOS)
REPO_OWNER=$(ls -nd . | awk '{ print $3 ":" $4 }')
CONFIG=config/main-config.json
ADMIN_ENV=.admin.env
# Compose projects of the base layer; must match BASE_PROJECT in skillsit-training-admin
# (packages/core/src/compose-files.ts) and the `name:` in traefik.yaml / admin.yaml.
# Passed with -p, never exported (COMPOSE_PROJECT_NAME beats `name:`).
TRAEFIK_PROJECT=infra-traefik
ADMIN_PROJECT=infra-admin

say() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

ask() { # ask <prompt> <default> -> REPLY
  [ -t 0 ] || [ -n "$2" ] || die "No terminal to ask: $1 (set INFRA_DOMAIN, INFRA_ROOT_USER, INFRA_ROOT_PASSWORD)"
  if [ -n "$2" ]; then printf '%s [%s]: ' "$1" "$2"; else printf '%s: ' "$1"; fi
  read -r REPLY || REPLY=
  [ -n "$REPLY" ] || REPLY=$2
}

ask_secret() { # ask_secret <prompt> -> REPLY
  [ -t 0 ] || die "No terminal to ask: $1 (set INFRA_ROOT_PASSWORD)"
  printf '%s: ' "$1"
  stty -echo 2>/dev/null || true
  read -r REPLY || REPLY=
  stty echo 2>/dev/null || true
  printf '\n'
}

random() { # random <length>
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"
}

json_string() { # value -> "value" (backslashes and newlines are rejected earlier)
  printf '"%s"' "$(printf '%s' "$1" | sed 's/"/\\"/g')"
}

# Same rules as packages/core/src/schema.ts in skillsit-training-admin
valid_domain() { printf '%s' "$1" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'; }
valid_user() { printf '%s' "$1" | grep -Eq '^[a-zA-Z0-9][a-zA-Z0-9_-]*$'; }
valid_password() { [ -n "$1" ] && ! printf '%s' "$1" | grep -q "['\\\\]"; }
valid_email() { [ -z "$1" ] || printf '%s' "$1" | grep -Eq '^[^@[:space:]"\\]+@[^@[:space:]"\\]+\.[^@[:space:]"\\]+$'; }

# --- Docker -----------------------------------------------------------------------------------------------

install_docker() {
  [ -r /etc/os-release ] || die "Unknown distribution; install Docker manually: https://docs.docker.com/engine/install/"
  . /etc/os-release
  case "$ID" in
    debian | ubuntu) ;;
    *) die "Automatic install supports Debian and Ubuntu only (found: $ID). Install Docker manually." ;;
  esac
  apt-get update
  apt-get install -y ca-certificates curl git
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
    "$(dpkg --print-architecture)" "$ID" "$VERSION_CODENAME" >/etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

if ! command -v docker >/dev/null 2>&1; then
  ask "Docker is not installed. Install it now? (y/n)" "y"
  case "$REPLY" in
    y | Y | yes) install_docker ;;
    *) die "Docker is required." ;;
  esac
fi
docker compose version >/dev/null 2>&1 || die "The docker compose plugin is missing."
docker info >/dev/null 2>&1 || die "The Docker daemon is not running."

# --- Configuration ----------------------------------------------------------------------------------------

keep=
if [ -f "$CONFIG" ]; then
  if [ "${INFRA_KEEP_CONFIG:-}" = 1 ]; then
    keep=1
  elif [ -z "${INFRA_DOMAIN:-}" ]; then
    ask "$CONFIG already exists. Keep it? (y = keep, n = create a new one)" "y"
    case "$REPLY" in y | Y | yes) keep=1 ;; esac
  fi
fi

if [ -n "$keep" ]; then
  DOMAIN=$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG" | head -n 1)
  ROOT_USER=$(sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG" | head -n 1)
  ROOT_PASSWORD=
  [ -n "$DOMAIN" ] || die "Could not read the domain from $CONFIG"
  say "Keeping $CONFIG (domain: $DOMAIN)."
else
  DOMAIN=$(printf '%s' "${INFRA_DOMAIN:-}" | tr 'A-Z' 'a-z')
  while ! valid_domain "$DOMAIN"; do
    [ -z "$DOMAIN" ] || say "Invalid domain: $DOMAIN"
    ask "Domain of the competition (e.g. comp.example.com)" ""
    DOMAIN=$(printf '%s' "$REPLY" | tr 'A-Z' 'a-z')
  done

  ROOT_USER=${INFRA_ROOT_USER:-}
  while ! valid_user "$ROOT_USER"; do
    [ -z "$ROOT_USER" ] || say "Only letters, digits, '-' and '_' are allowed."
    ask "Root (admin) username" "root"
    ROOT_USER=$REPLY
  done

  ROOT_PASSWORD=${INFRA_ROOT_PASSWORD:-}
  generated=
  while ! valid_password "$ROOT_PASSWORD"; do
    [ -z "$ROOT_PASSWORD" ] || say "The password must not contain ' or \."
    ask_secret "Root password (empty = generate one)"
    if [ -z "$REPLY" ]; then
      ROOT_PASSWORD=$(random 16)
      generated=1
      break
    fi
    if ! valid_password "$REPLY"; then
      say "The password must not contain ' or \\."
      continue
    fi
    first=$REPLY
    ask_secret "Repeat the password"
    if [ "$REPLY" = "$first" ]; then ROOT_PASSWORD=$first; else say "The passwords do not match."; fi
  done

  # Let's Encrypt needs public DNS for every host and port 80 reachable from the internet
  LETSENCRYPT=${INFRA_LETSENCRYPT:-}
  if [ -z "$LETSENCRYPT" ]; then
    if [ -t 0 ]; then
      ask "Request Let's Encrypt certificates for every host? (needs public DNS and port 80) (y/n)" "y"
    else
      REPLY=n
    fi
    case "$REPLY" in y | Y | yes) LETSENCRYPT=1 ;; *) LETSENCRYPT=0 ;; esac
  fi
  ACME_EMAIL=${INFRA_ACME_EMAIL:-}
  if [ "$LETSENCRYPT" = 1 ] && [ -z "${INFRA_ACME_EMAIL+set}" ] && [ -t 0 ]; then
    printf "E-mail for Let's Encrypt expiry notices (optional): "
    read -r ACME_EMAIL || ACME_EMAIL=
  fi
  while ! valid_email "$ACME_EMAIL"; do
    say "Invalid e-mail: $ACME_EMAIL"
    [ -t 0 ] || die "Invalid INFRA_ACME_EMAIL"
    printf "E-mail for Let's Encrypt expiry notices (optional): "
    read -r ACME_EMAIL || ACME_EMAIL=
  done
  if [ "$LETSENCRYPT" = 1 ]; then le_json=true; else le_json=false; fi

  cat >"$CONFIG" <<EOF
{
  "domain": $(json_string "$DOMAIN"),
  "enableHttps": true,
  "letsencrypt": $le_json,
  "acmeEmail": $(json_string "$ACME_EMAIL"),
  "username": $(json_string "$ROOT_USER"),
  "password": $(json_string "$ROOT_PASSWORD"),
  "modules": [],
  "competitors": []
}
EOF
  say "Wrote $CONFIG."
fi

# Same derivation as deriveConfig/routingEnv in skillsit-training-admin: init and start bring Traefik up with
# these values too, and any difference would make compose recreate it.
CERT_RESOLVER=
if grep -Eq '"enableHttps"[[:space:]]*:[[:space:]]*"?false' "$CONFIG"; then
  REGISTRY_PORT=5000
else
  REGISTRY_PORT=443
  if grep -Eq '"letsencrypt"[[:space:]]*:[[:space:]]*true' "$CONFIG"; then CERT_RESOLVER=letsencrypt; fi
fi
ACME_EMAIL=$(sed -n 's/.*"acmeEmail"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG" | head -n 1)

if [ ! -f "$ADMIN_ENV" ]; then
  umask 077
  cat >"$ADMIN_ENV" <<EOF
INFRA_DIR=$INFRA_DIR
ADMIN_SESSION_SECRET=$(random 48)
ADMIN_PORT=8090
EOF
  umask 022
fi

# This script runs as root; hand what it (or an earlier root run, or the admin container) wrote back to the
# owner of the repository.
for f in "$CONFIG" "$ADMIN_ENV" pulldeck.env .env competitors.yaml config/mysql/competitors.sql data-admin; do
  [ -e "$f" ] && chown -R "$REPO_OWNER" "$f"
done
chmod 644 "$CONFIG"
chmod 600 "$ADMIN_ENV"

ADMIN_PORT=$(sed -n 's/^ADMIN_PORT=//p' "$ADMIN_ENV")
ADMIN_PORT=${ADMIN_PORT:-8090}

# --- DNS --------------------------------------------------------------------------------------------------

if command -v getent >/dev/null 2>&1 && ! getent hosts "admin.$DOMAIN" >/dev/null 2>&1; then
  say ""
  say "Warning: admin.$DOMAIN does not resolve. Create a wildcard DNS record (*.$DOMAIN -> this server's IP)."
  say "Until then the UI is only reachable through the local port (see below)."
  say ""
fi

# --- Base layer -------------------------------------------------------------------------------------------

# The shared network belongs to no compose project, so no `down` can remove it.
docker network inspect gitea >/dev/null 2>&1 || docker network create gitea >/dev/null

# Earlier versions ran Traefik in the `infra` project; its container name would clash with the new project.
old_project=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' traefik 2>/dev/null || true)
if [ -n "$old_project" ] && [ "$old_project" != "$TRAEFIK_PROJECT" ]; then
  say "Moving Traefik from compose project '$old_project' to '$TRAEFIK_PROJECT'..."
  docker rm -f traefik >/dev/null
fi

# Optional, from .admin.env (the admin container gets it too, for init and start)
ACME_CA_SERVER=$(sed -n 's/^ACME_CA_SERVER=//p' "$ADMIN_ENV")

say "Starting Traefik..."
[ -z "$CERT_RESOLVER" ] || say "Let's Encrypt is on: certificates are requested on the first request to each host."
GITEA_HOSTNAME=$DOMAIN REGISTRY_PORT=$REGISTRY_PORT CERT_RESOLVER=$CERT_RESOLVER ACME_EMAIL=$ACME_EMAIL \
  ACME_CA_SERVER=$ACME_CA_SERVER docker compose -p "$TRAEFIK_PROJECT" -f traefik.yaml up -d

say "Pulling and starting the admin UI..."
# A locally built ADMIN_IMAGE (not in any registry) is used as is
docker compose -p "$ADMIN_PROJECT" --env-file "$ADMIN_ENV" -f admin.yaml pull --ignore-pull-failures
GITEA_HOSTNAME=$DOMAIN CERT_RESOLVER=$CERT_RESOLVER \
  docker compose -p "$ADMIN_PROJECT" --env-file "$ADMIN_ENV" -f admin.yaml up -d

printf 'Waiting for the admin UI'
i=0
until docker exec infra-admin node -e "fetch('http://127.0.0.1:8090/api/auth/me').then(() => process.exit(0), () => process.exit(1))" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -lt 30 ] || { printf '\n'; die "The admin UI did not start; see: docker logs infra-admin"; }
  printf '.'
  sleep 2
done
printf '\n\n'

say "The admin UI is running:"
say "  https://admin.$DOMAIN"
say "  fallback: ssh -L $ADMIN_PORT:127.0.0.1:$ADMIN_PORT <this server>, then http://localhost:$ADMIN_PORT"
say ""
if [ -n "$keep" ]; then
  say "Log in with the root user from $CONFIG."
else
  say "Login: $ROOT_USER"
  if [ -n "${generated:-}" ]; then say "Password (generated, write it down): $ROOT_PASSWORD"; fi
fi
say ""
say "Next: add modules and competitors under Konfiguráció, then run Inicializálás on the Áttekintés page."
