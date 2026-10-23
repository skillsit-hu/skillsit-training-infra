#!/bin/bash

# Check if the correct number of arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <GITEA_URL> <USERNAME> <PASSWORD>"
    exit 1
fi

# Set variables from script arguments
GITEA_URL="$1"
USERNAME="$2"
PASSWORD="$3"
TOKEN_NAME="CreateOrganizationScript"

echo "Requesting personal access token from $GITEA_URL..." >&2

# Delete existing token
delete_response=$(curl -s -k --connect-timeout 10 --max-time 30 -X DELETE -H "Content-Type: application/json" \
    -u "$USERNAME:$PASSWORD" \
    "$GITEA_URL/api/v1/users/$USERNAME/tokens/$TOKEN_NAME")

# Create a new personal access token
response=$(curl -s -k --connect-timeout 10 --max-time 30 -X POST -H "Content-Type: application/json" \
    -u "$USERNAME:$PASSWORD" \
        -d '{
          "name": "'"$TOKEN_NAME"'",
          "scopes": ["read:admin", "write:organization", "write:repository", "write:user"]
        }' \
    "$GITEA_URL/api/v1/users/$USERNAME/tokens")

# Gitea 1.21 returns the secret in "sha1". Keep only that value on stdout.
new_token=$(printf '%s' "$response" | jq -r '.sha1 // .token // empty' | tr -d '[:space:]')

# Check if the token was successfully created
if [ -z "$new_token" ] || [ "$new_token" = "null" ]; then
    echo "Failed to create token. Response: $response" >&2
    exit 1
fi

echo "$new_token"
