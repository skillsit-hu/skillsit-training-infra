#!/bin/bash

CONFIG_FILE=config/main-config.json

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read $CONFIG_FILE"
  exit 1
fi

# Read settings from config/main-config.json
DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")
ENABLE_HTTPS=$(jq -r '.enableHttps' "$CONFIG_FILE")
USERNAME=$(jq -r '.username' "$CONFIG_FILE")
PASSWORD=$(jq -r '.password' "$CONFIG_FILE")
MODULES=$(jq -r '.modules | join(" ")' "$CONFIG_FILE")

export GITEA_HOSTNAME=$DOMAIN
export ENABLE_HTTPS=$ENABLE_HTTPS
export MYSQL_ROOT_PASSWORD=$PASSWORD

if [ "$ENABLE_HTTPS" = "true" ]; then
  export ENTRYPOINT=websecure
  export GITEA_PROTOCOL=https
  export REGISTRY_PORT=443
else
  export ENTRYPOINT=web
  export GITEA_PROTOCOL=http
  export REGISTRY_PORT=5000
fi

# create various config and creation files
# Start Traefik and Gitea using Docker Compose
REGISTRY_PORT=$REGISTRY_PORT GITEA_HOSTNAME=$DOMAIN GITEA_PROTOCOL=$GITEA_PROTOCOL ENTRYPOINT=$ENTRYPOINT ENABLE_HTTPS=$ENABLE_HTTPS docker compose -f traefik.yaml up -d --remove-orphans
GITEA_HOSTNAME=$DOMAIN GITEA_PROTOCOL=$GITEA_PROTOCOL ENTRYPOINT=$ENTRYPOINT ENABLE_HTTPS=$ENABLE_HTTPS docker compose -f gitea.yaml up -d

# Wait for Gitea to start
function wait_for_gitea() {
  local retries=10
  local wait=5
  local count=0

  until curl -s http://localhost:3000/api/v1/version > /dev/null; do
    if [ $count -ge $retries ]; then
      echo "Gitea did not become ready in time."
      exit 1
    fi
    echo "Waiting for Gitea to be ready..."
    sleep $wait
    count=$((count + 1))
  done
}

# Wait for Gitea to start
wait_for_gitea

# Create a new Gitea user using the username and password from the passwd file
docker exec gitea su -c "/app/gitea/gitea admin user create --username $USERNAME --password $PASSWORD --email $USERNAME@example.com --admin" git

# Generate a registration token for the Gitea runner
REGISTRATION_TOKEN=$(docker exec gitea su -c '/app/gitea/gitea actions generate-runner-token' git)
export REGISTRATION_TOKEN=$REGISTRATION_TOKEN

echo "Registration Token: $REGISTRATION_TOKEN"

# Start the Gitea runner with the registration token
REGISTRATION_TOKEN=$REGISTRATION_TOKEN docker compose -f gitea-runner.yaml up -d

#### START GTI PREP
# API calls stay on the local Gitea port. The public hostname goes through
# Traefik, and curl to it has no timeout, so init looks frozen after the runners start.
GITEA_API="http://127.0.0.1:3000"
GITEA_URL="$GITEA_PROTOCOL://git.$DOMAIN"

# Pulldeck is served at clara.<domain> (see pulldeck.yaml) and checks AUTH_TOKEN from .env.clara
PULLDECK_BASE_URL="$GITEA_PROTOCOL://clara.$DOMAIN"
PULLDECK_TOKEN=$(grep '^AUTH_TOKEN=' .env.clara | cut -d= -f2-)
if [ -z "$PULLDECK_TOKEN" ]; then
  echo "AUTH_TOKEN not found in .env.clara"
  exit 1
fi

echo "Creating Gitea access token..."
GITEA_TOKEN=$(./create_pat.sh "$GITEA_API" "$USERNAME" "$PASSWORD")
if [ -z "$GITEA_TOKEN" ]; then
  echo "Failed to create Gitea access token."
  exit 1
fi

# create org for demo repos
response=$(curl -s -k --connect-timeout 10 --max-time 60 -X POST "$GITEA_API/api/v1/orgs" \
    -H "Content-Type: application/json" \
    -H "Authorization: token $GITEA_TOKEN" \
    -d '{
        "username": "frameworks",
        "full_name": "frameworks"
    }')

./create_organisation.sh "$GITEA_TOKEN" "$GITEA_API" "images"
./create_organisation.sh "$GITEA_TOKEN" "$GITEA_API" "frameworks"

./create_team.sh "$GITEA_TOKEN" "$GITEA_API" "frameworks" "competitors" "false"

./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-laravel.git" "laravel"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-vanilla.git" "vanilla"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-nuxtjs.git" "nuxtjs"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-nextjs.git" "nextjs"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-nextjs-prisma.git" "nextjs-prisma"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-expressjs.git" "expressjs"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-prisma.git" "prisma"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-zurb-foundation.git" "zurb-foundation"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-vuejs.git" "vuejs"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-reactjs.git" "reactjs"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-bootstrap.git" "bootstrap"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-angular.git" "angular"
./import_framework.sh $GITEA_TOKEN $USERNAME $PASSWORD "git.$DOMAIN" "https://github.com/sitc2026-templates/ws26-tailwindcss.git" "tailwindcss"

docker pull nginx:latest > /dev/null 2>&1
docker login -u $USERNAME -p $PASSWORD git.$DOMAIN > /dev/null 2>&1

# Generate competitors.yaml
cat <<EOF > competitors.yaml
services:
EOF

cat <<EOF > config/mysql/competitors.sql
EOF

# initialize the basic modules
jq -r '.competitors[] | [.username, .password, .subdomain] | @tsv' "$CONFIG_FILE" | while IFS=$'\t' read -r user pass sub; do

  docker exec gitea su -c '/app/gitea/gitea admin user create --username '$user' --password '$pass' --email '$user@example.com' --must-change-password=false' git
  ./add_user_to_team.sh "$GITEA_API" "$GITEA_TOKEN" "frameworks" "competitors" "$user"

  # Create user-level secrets for this user
  echo "Creating user-level secrets for $user..."
  
  # Create USER secret
  curl -s -k -X PUT \
    -u "$user:$pass" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$user\"}" \
    "$GITEA_API/api/v1/user/actions/secrets/USER"
  
  # Create PASS secret  
  curl -s -k -X PUT \
    -u "$user:$pass" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$pass\"}" \
    "$GITEA_API/api/v1/user/actions/secrets/PASS"
  
  echo "✓ Created USER and PASS secrets for $user"

  # Create Pulldeck secrets
  curl -s -k -X PUT \
    -u "$user:$pass" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$PULLDECK_BASE_URL\"}" \
    "$GITEA_API/api/v1/user/actions/secrets/PULLDECK_BASE_URL"

  curl -s -k -X PUT \
    -u "$user:$pass" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$PULLDECK_TOKEN\"}" \
    "$GITEA_API/api/v1/user/actions/secrets/PULLDECK_TOKEN"

  echo "✓ Created Pulldeck secrets for $user"

  for module in $MODULES; do
    echo "Processing module: $module for $user"

  cat <<EOF >> competitors.yaml
  ${user}_${module}:
    image: git.${DOMAIN}/${user}/${module}:latest
    container_name: ${user}_${module}
    restart: always
    networks:
      - gitea
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${user}_${module}.rule=Host(\`${sub}-${module}.$DOMAIN\`)"
      - "traefik.http.routers.${user}_${module}.entrypoints=${ENTRYPOINT}"
      - "traefik.http.routers.${user}_${module}.tls=${ENABLE_HTTPS}"
      - "traefik.http.services.${user}_${module}.loadbalancer.server.port=80"
      - "com.centurylinklabs.watchtower.enable=true"
EOF
    
    echo "pushing inital container"
    docker tag nginx:latest git.$DOMAIN/$user/$module:latest
    docker push git.$DOMAIN/$user/$module #> /dev/null 2>&1

  cat <<EOF >> config/mysql/competitors.sql
  CREATE DATABASE IF NOT EXISTS \`${user}_${module}\`;
  CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$pass';
  GRANT ALL PRIVILEGES ON *.* TO '$user'@'%';
EOF

  done
done

cat <<EOF >> competitors.yaml

networks:
  gitea:
    external: true
EOF

# Start MySQL with the admin password as the root password
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD docker compose -f mysql.yaml up -d

# Start Packagist mirror for Laravel vendor package caching
DOMAIN=$DOMAIN ENTRYPOINT=$ENTRYPOINT ENABLE_HTTPS=$ENABLE_HTTPS docker compose -f packagist.yaml up -d

# Start watchtower
USERNAME=$USERNAME PASSWORD=$PASSWORD DOMAIN=$DOMAIN docker compose -f watchtower.yaml up -d


# Start Verdaccio for package caching
docker compose -f verdaccio.yaml up -d

# Configure Verdaccio storage permissions to allow package uploads
chmod 777 -R ./data/verdaccio

# Start competitors work
docker compose -f competitors.yaml up -d

# Start Pulldeck so the Gitea Actions can redeploy competitors' containers
docker compose -f pulldeck.yaml up -d

# Start Sablier, which starts competitors' containers on demand (used by infra-updater's Traefik routes)
docker compose -f sablier.yaml up -d

# Start infra updater
docker compose -f infra-updater.yaml up -d

# Create infra updater webhook
./create_webhook.sh $DOMAIN $USERNAME $PASSWORD

# Write out environment variables to .env
cat <<EOF > .env
DOMAIN="$DOMAIN"
ENABLE_HTTPS="$ENABLE_HTTPS"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
MODULES="$MODULES"
GITEA_HOSTNAME="$GITEA_HOSTNAME"
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
ENTRYPOINT="$ENTRYPOINT"
GITEA_PROTOCOL="$GITEA_PROTOCOL"
REGISTRY_PORT="$REGISTRY_PORT"
REGISTRATION_TOKEN="$REGISTRATION_TOKEN"
EOF

echo "..all done!"
