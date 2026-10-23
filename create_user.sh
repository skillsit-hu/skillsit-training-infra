#!/bin/bash

# Check if the correct number of arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <USERNAME> <USER_PASSWORD>"
    exit 1
fi

# Set variables from script arguments
USERNAME="$1"
USER_PASSWORD="$2"

CONFIG_FILE=config/main-config.json

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to read $CONFIG_FILE"
    exit 1
fi

DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")
ROOT_USERNAME=$(jq -r '.username' "$CONFIG_FILE")
ROOT_PASSWORD=$(jq -r '.password' "$CONFIG_FILE")

# Add user to config
tmp=$(mktemp)
jq --arg user "$USERNAME" --arg pass "$USER_PASSWORD" \
  '.competitors += [{"username": $user, "password": $pass, "subdomain": $user}]' \
  "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"

# Create user in Gitea
docker exec gitea su -c '/app/gitea/gitea admin user create --username '$USERNAME' --password '$USER_PASSWORD' --email '$USERNAME@example.com' --must-change-password=false' git

# Add user to teams
GITEA_URL="https://git.$DOMAIN"
GITEA_TOKEN=$(./create_pat.sh $GITEA_URL $ROOT_USERNAME $ROOT_PASSWORD)
./add_user_to_team.sh $GITEA_URL $GITEA_TOKEN "frameworks" "competitors" $USERNAME

# Create user-level secrets for this user
  # Create USER secret
  curl -s -k -X PUT \
    -u "$USERNAME:$USER_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$USERNAME\"}" \
    "$GITEA_URL/api/v1/user/actions/secrets/USER"

  # Create PASS secret
  curl -s -k -X PUT \
    -u "$USERNAME:$USER_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$USER_PASSWORD\"}" \
    "$GITEA_URL/api/v1/user/actions/secrets/PASS"

  # Create Pulldeck secrets (pulldeck is served at clara.<domain>, token is AUTH_TOKEN from .env.clara)
  PULLDECK_TOKEN=$(grep '^AUTH_TOKEN=' .env.clara | cut -d= -f2-)

  curl -s -k -X PUT \
    -u "$USERNAME:$USER_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"https://clara.$DOMAIN\"}" \
    "$GITEA_URL/api/v1/user/actions/secrets/PULLDECK_BASE_URL"

  curl -s -k -X PUT \
    -u "$USERNAME:$USER_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$PULLDECK_TOKEN\"}" \
    "$GITEA_URL/api/v1/user/actions/secrets/PULLDECK_TOKEN"

echo "CREATE USER IF NOT EXISTS '$USERNAME'@'%' IDENTIFIED BY '$USER_PASSWORD';" >> config/mysql/competitors.sql
echo "GRANT ALL PRIVILEGES ON *.* TO '$USERNAME'@'%';" >> config/mysql/competitors.sql
docker compose -f mysql.yaml exec competitor_db mysql --user=$ROOT_USERNAME --password=$ROOT_PASSWORD -e "CREATE USER IF NOT EXISTS '$USERNAME'@'%' IDENTIFIED BY '$USER_PASSWORD';GRANT ALL PRIVILEGES ON *.* TO '$USERNAME'@'%';"
