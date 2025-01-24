# Deploy Data API builder in Azure Container Apps

This project illustrates the ability to run a Data API Builder app from within Azure Container Apps.

## Overview

This repo has everything needed to build a simple [Data API Builder (DAB)](https://learn.microsoft.com/en-us/azure/data-api-builder/overview) 
application and deploy it to an [Azure Container App (ACA)](https://learn.microsoft.com/en-us/azure/container-apps/overview). At a high level,
the DAB application will connect to a SQL database that has been loaded up with the [AdventureWorksLT](https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver16&tabs=ssms#deploy-new-sample-database)
sample data.

There are two primary components in this repo to accomplish this:

* [Dockerfile](./dab/Dockerfile) - Contains the main DAB configuration in a simple format that results in a containerized API app.  
* [Bicep](./infra/main.bicep) - IaC code that provisions a serverless hyperscale SQL Server and database along with the Azure Container App which then loads the container image.  
<br/>

> [!IMPORTANT] 
> This repo and the instructions here assume that you are running these steps in a Linux environment. Possible scenarios for this include
> [GitHub Codespaces](https://github.com/features/codespaces), [Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers), or 
> [WSL](https://learn.microsoft.com/en-us/windows/wsl/about).

## Setup Variables

Creating resuable variables in a `.env` file makes the script execution easier. Simply rename the [.env-sample](./.env-sample) to `.env` and set 
your own values in the file.

```bash

# Rename the .env-sample file
mv .env-sample .env

# TENANT_ID - This should be your Azure Entra Tenant ID, which might be required to login to Azure
# SUBSCRIPTION_ID - The Azure Subscription ID that you will use to deploy into
# BASE_NAME - A valid identifier that will be used to build out resource names in Bicep
# LOCATION - The Azure region you want to deploy to
# CONTAINER_NAME - The name of the container to create/use
# CONTAINER_TAG - The name of the container tag to create/use
# DATABASE_NAME - The name of the database to create/use
# DOCKER_USERNAME - Your username for accessing Docker Hub
# DOCKER_PASSWORD - Your password or PAT token for accessing Docker Hub

# Apply the variables to within your session
source .env

```

## Containerization

The [Dockerfile](./dab/Dockerfile) contains a sampling of `dab` commands that curate the exposure of APIs over the database. In this case, there
are many ways you could approach this, but for simplicity's sake, they have been added directly to the Dockerfile. This makes it easy to build 
the container and push it to a container registry, Docker Hub in this case.

```bash

# Log into Docker Hub
docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD

# Build the container
docker build ./dab -f ./dab/Dockerfile -t $DOCKER_USERNAME/$CONTAINER_NAME:$CONTAINER_TAG

# Push the container
docker push $DOCKER_USERNAME/$CONTAINER_NAME:$CONTAINER_TAG

```

## Azure Resource Provisioning

The [Bicep](./infra/main.bicep) file can be used to easily provision the SQL Server, its database, and the Azure Container App that then loads
up the container image that we built and pushed above.

```bash

# Login to Azure (using the TENANT_ID is optional)
az login -t $TENANT_ID

# Create a Resource Group to deploy into
az group create --name $BASE_NAME --location $LOCATION

# Execute the Bicep file to provision the Azure resources
az deployment group create -g $BASE_NAME \
--template-file ./infra/main.bicep \
--parameters \
baseName=$BASE_NAME \
location=$LOCATION \
databaseName=$DATABASE_NAME \
containerUri=$DOCKER_USERNAME/$CONTAINER_NAME:$CONTAINER_TAG

```

## Bonus Content

There is also a [GitHub Action](./.github/workflows/pipeline.yaml) file you can use to automate most of the above steps if desired. To do so,
you need to provision an Azure service principal that the pipeline can use to access your resource group.

```bash

# Create a Service Principal
az ad sp create-for-rbac --name $BASE_NAME-sp --sdk-auth --role contributor --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$BASE_NAME

# TODO: Setup the GitHub Action variables


```