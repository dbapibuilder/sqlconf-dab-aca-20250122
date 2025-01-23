# SQL Conf 2025

The project illustrates the ability to run a Data API Builder app from within Azure Container Apps.

```bash

# Setup Environment Variables
source .env

# Login to Azure
az login -t $TENANT_ID

# Create a Resource Group
az group create --name $BASE_NAME --location $LOCATION

# Create a Service Principal
az ad sp create-for-rbac --name $BASE_NAME-sp --sdk-auth --role contributor --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$BASE_NAME

# Create the SQL Server and Database
az deployment group create -g $BASE_NAME \
--template-file ./infra/main.bicep \
--parameters \
baseName=$BASE_NAME \
location=$LOCATION \
databaseName=AdventureWorks

```