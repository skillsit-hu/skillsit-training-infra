#!/bin/bash

# Check if the correct number of arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <BASE_URL> <USERNAME> <PASSWORD>"
    exit 1
fi

# Set variables from script arguments
BASE_URL="$1"
USERNAME="$2"
PASSWORD="$3"
WEBHOOK_SECRET="GFW8Mq5ANOsK"

# Create a new webhook
response=$(curl -s -k -X POST -H "Content-Type: application/json" \
    -u "$USERNAME:$PASSWORD" \
    -d '{
    	"type": "gitea",
    	"branch_filter": "*",
    	"config": {
        	"content_type": "json",
        	"url": "https://infra-updater.'$BASE_URL'/update",
        	"secret": "'$WEBHOOK_SECRET'",
        	"is_system_webhook": "true"
    	},
    	"events": [
        	"repository"
    	],
    	"authorization_header": "",
    	"active": true
        }' \
    "https://git.$BASE_URL/api/v1/admin/hooks")

echo "done"
