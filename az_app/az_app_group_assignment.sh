#! /bin/bash

# Login
export AZURE_USERID=$1
export AZURE_PASSWORD=$2
export AZURE_GROUP_NAME=$3

printf "\n------------\nUser group assignment\n------------\n"

# Login to Azure with your account
az login -u $AZURE_USERID -p $AZURE_PASSWORD

# Generate auth token for curl, and strip quotes from output
export AUTH_TOKEN=$(az account get-access-token --resource https://graph.microsoft.com | jq .accessToken | tr -d '"')

# Create the group to associate to the app
az ad group create --display-name $AZURE_GROUP_NAME --mail-nickname $AZURE_GROUP_NAME
printf "*** Created group \n"

# Get group objectId
export GROUP_ID=$(az ad group show --group "$AZURE_GROUP_NAME" --query objectId --out tsv)
echo "Group ID: $GROUP_ID"

# Application objectId
export APP_ID=$(az ad app list --filter "displayname eq 'argocd-sso'" | jq .[0].appId | tr -d '"')
export APP_OBJECT_ID=$(az ad app show --id $APP_ID | jq .objectId | tr -d '"')

# Assign group to the app
curl --location --request POST "https://graph.microsoft.com/v1.0/groups/$GROUP_ID/appRoleAssignments" \
--header "Authorization: Bearer $AUTH_TOKEN" \
--header 'Content-Type: application/json' \
--data-raw '{
    "appRoleId": "00000000-0000-0000-0000-000000000000",
    "principalId": "'"$GROUP_ID"'",
    "resourceId": "'"$APP_OBJECT_ID"'"
}'

printf "*** Assigned group to app \n"

printf "\n------------\nDone!\n------------\n"
