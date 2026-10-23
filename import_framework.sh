#!/bin/bash

# Check if the correct number of arguments are provided
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <GITEA_TOKEN> <USERNAME> <PASSWORD> <GITEA_URL> <GITHUB_URL> <REPO_NAME>"
    exit 1
fi

# Set variables from script arguments
GITEA_TOKEN="$1"
USERNAME="$2"
PASSWORD="$3"
GITEA_URL="$4"
GITHUB_URL="$5"
REPO_NAME="$6"
WORKFLOW_FILE=".gitea/workflows/docker-ci.yaml"
REGISTRY_HOST="git.sitc.skillsit.eu"
PULLDECK_URL="https://pulldeck.sitc.skillsit.eu"
ORG_NAME="frameworks"
GITEA_API="http://127.0.0.1:3000"

# Clone the repository. A previous failed import leaves this directory behind.
rm -rf "$REPO_NAME"
git clone "$GITHUB_URL" "$REPO_NAME" || exit 1
cd "$REPO_NAME" || exit

# Point the Gitea Action at this competition's registry.
if [ ! -f "$WORKFLOW_FILE" ]; then
    echo "Workflow file $WORKFLOW_FILE not found in $REPO_NAME."
    exit 1
fi
# The pulldeck URL comes from each user's PULLDECK_BASE_URL secret (set in init.sh / create_user.sh).
sed -i -e "s|$REGISTRY_HOST|$GITEA_URL|g" -e "s|$PULLDECK_URL|\${{ secrets.PULLDECK_BASE_URL }}|g" "$WORKFLOW_FILE"

# Configure git
git config user.name "Digitalent"
git config user.email "info@skillsit.hu"

# Commit the changes
git add "$WORKFLOW_FILE"
git commit -m "Update Docker registry URL in Gitea Action"

# Create the repository on Gitea under the "frameworks" organization
create_repo_response=$(curl -s -k --connect-timeout 10 --max-time 60 -X POST "$GITEA_API/api/v1/orgs/$ORG_NAME/repos" \
-H "Authorization: token $GITEA_TOKEN" \
-H "Content-Type: application/json" \
-d '{
  "name": "'"$REPO_NAME"'",
  "private": false,
  "template": true
}')

# Check if the repository was created successfully
if echo "$create_repo_response" | grep -q '"id":'; then
    echo "Repository $REPO_NAME created in the $ORG_NAME organization on Gitea."
else
    echo "Failed to create repository on Gitea: $create_repo_response"
    exit 1
fi

# Add Gitea remote and push the changes
git remote add gitea "https://$USERNAME:$PASSWORD@$GITEA_URL/$ORG_NAME/$REPO_NAME.git"
GIT_TERMINAL_PROMPT=0 git push gitea main

# Output response for debugging
echo "Repository $REPO_NAME pushed to the $ORG_NAME organization on Gitea with updated GitHub Action!"
