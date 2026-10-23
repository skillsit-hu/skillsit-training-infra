#!/bin/bash
CONFIG_FILE=config/main-config.json

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read $CONFIG_FILE"
  exit 1
fi

DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")

docker compose -f watchtower.yaml down
docker compose -f competitors.yaml down
docker compose -f pulldeck.yaml down
docker compose -f sablier.yaml down
docker compose -f mysql.yaml down
docker compose -f packagist.yaml down
docker compose -f gitea-runner.yaml down
GITEA_HOSTNAME=$DOMAIN docker compose -f gitea.yaml down 
docker compose -f verdaccio.yaml down
docker compose -f infra-updater.yaml down
docker compose -f traefik.yaml down

# delete all volumes from the containers
sudo rm -rf ./data

# go through all competitors and remove all images
jq -r '.competitors[].username' "$CONFIG_FILE" | while read -r user; do
  echo $user
  docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep "/$user/" | awk '{print $2}' | sort -u | xargs -r docker rmi -f
done

# remove the framework clones left behind by import_framework.sh
rm -rf laravel vanilla nuxtjs nextjs nextjs-prisma expressjs prisma zurb-foundation vuejs reactjs bootstrap angular tailwindcss
