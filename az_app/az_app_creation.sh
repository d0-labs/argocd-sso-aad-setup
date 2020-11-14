#! /bin/bash

# Set up your own details
export AZURE_USERID=$1
export AZURE_PASSWORD=$2
export ARGOCD_SERVER=$3
export AZURE_APP_PASSWORD=$4

printf "\n------------\nBegin App Creation\n------------\n"

# Login to Azure with your account
az login -u $AZURE_USERID -p $AZURE_PASSWORD

# Generate userid's access token (required for curl), and strip quotes from the output
export AUTH_TOKEN=$(az account get-access-token --resource https://graph.microsoft.com | jq .accessToken | tr -d '"')

printf "\n*** Access token generated \n"

# Create an Azure app, set its password, 
export APP_DETAILS=$(az ad app create --display-name argocd-sso --reply-urls "https://$ARGOCD_SERVER/argo-cd/auth/callback" --password $AZURE_APP_PASSWORD --required-resource-accesses @required_resource_accesses.json); echo $APP_DETAILS

# Get the application ID from the APP_DETAILS
export OBJECT_ID=$(echo $APP_DETAILS | jq .objectId | tr -d '"')
export APP_ID=$(echo $APP_DETAILS | jq .appId | tr -d '"')

# TODO: Need to add role assignment: https://social.msdn.microsoft.com/Forums/sqlserver/en-US/b9f8fd47-14f3-49fa-9f0f-d6c0493f8821/create-an-enterprise-application-from-azure-cli-20?forum=WindowsAzureAD
# possibly this: https://github.com/MicrosoftDocs/azure-docs/issues/33494#issuecomment-582543624
# az ad sp create --id $APP_ID

printf "\n*** App creation completed. ObjectId is %s\n" $OBJECT_ID

# Give Azure some time for app creation. Increase this # if needed
sleep 5

# Set up optional claims, disable ID token implicit grant + set groupMembershipClaims to ApplicationGroup
curl --location --request PATCH "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
--header "Authorization: Bearer $AUTH_TOKEN" \
--header 'Content-Type: application/json' \
--data-raw '{
"optionalClaims": {
    "accessToken": [
        {
            "additionalProperties": [],
            "essential": false,
            "name": "groups",
            "source": null
        }
    ],
    "idToken": [
        {
            "additionalProperties": [],
            "essential": false,
            "name": "groups",
            "source": null
        }
    ],
    "saml2Token": [
        {
            "additionalProperties": [],
            "essential": false,
            "name": "groups",
            "source": null
        }
    ]
},
"groupMembershipClaims": "ApplicationGroup",
"web": {
        "implicitGrantSettings": {
            "enableIdTokenIssuance": false
        }
    }
}'

printf "\n*** Disabled ID token implicit grant, and updated group membership claim \n"

# Get the OAUTH permission ID
export OAUTH_PERMISSION_ID=$(curl --location --request GET "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" --header "Authorization: Bearer $AUTH_TOKEN" | jq .api.oauth2PermissionScopes[0].id | tr -d '"'); echo $OAUTH_PERMISSION_ID

# First, we must Disable oauth2Permission scopes
curl --location --request PATCH "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
--header "Authorization: Bearer $AUTH_TOKEN" \
--header 'Content-Type: application/json' \
--data-raw '{
    "api": {
        "acceptMappedClaims": null,
        "knownClientApplications": [],
        "requestedAccessTokenVersion": null,
        "oauth2PermissionScopes": [
            {
                "adminConsentDescription": "Allow the application to access something on behalf of the signed-in user.",
                "adminConsentDisplayName": "Access something",
                "id": "'"$OAUTH_PERMISSION_ID"'",
                "isEnabled": false,
                "type": "User",
                "userConsentDescription": "Allow the application to access soemthing on your behalf.",
                "userConsentDisplayName": "Access something",
                "value": "user_impersonation"
            }
        ],
        "preAuthorizedApplications": []
    }
}'

printf "*** Disabled oauth2Permission scopes \n"
sleep 5

# Now we can nuke oauth2Permission scopes
curl --location --request PATCH "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
--header "Authorization: Bearer $AUTH_TOKEN" \
--header 'Content-Type: application/json' \
--data-raw '{
    "api": {
        "acceptMappedClaims": null,
        "knownClientApplications": [],
        "requestedAccessTokenVersion": null,
        "oauth2PermissionScopes": [],
        "preAuthorizedApplications": []
    }
}'

printf "*** Deleted oauth2Permission scopes \n"

# Create service principal for app
export APP_SP_OBJECT_ID=$(az ad sp create --id $APP_ID | jq .objectId | tr -d '"')
echo "SP App object ID: $APP_SP_OBJECT_ID"

sleep 5

# Make it an Enterprise app
curl --location --request PATCH "https://graph.microsoft.com/v1.0/servicePrincipals/$APP_SP_OBJECT_ID" \
--header "Authorization: Bearer $AUTH_TOKEN" \
--header 'Content-Type: application/json' \
--data-raw '{
    "tags": [
        "WindowsAzureActiveDirectoryIntegratedApp"
    ]
}'
printf "*** Created enterprise app \n"

printf "\n------------\nDone!\n------------\n"
