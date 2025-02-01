# Deploy Data API Builder in Azure Container Apps

This project illustrates the ability to run a Data API Builder app from within Azure Container Apps.

## Overview

This repo has everything needed to build a simple [Data API Builder (DAB)](https://learn.microsoft.com/en-us/azure/data-api-builder/overview) application and deploy it to an [Azure Container App (ACA)](https://learn.microsoft.com/en-us/azure/container-apps/overview). At a high level, the DAB application will connect to a SQL database that has been loaded up with the [AdventureWorksLT](https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver16&tabs=ssms#deploy-new-sample-database) sample data.

There are two primary components in this repo to accomplish this:

* [Dockerfile](./dab/Dockerfile) - Contains the main DAB configuration in a simple format that results in a containerized API app.  
* [Bicep](./infra/main.bicep) - IaC code that provisions a serverless hyperscale SQL Server and database along with the Azure Container App which then loads the container image.  
<br/>

> [!IMPORTANT] 
> This repo and the instructions here assume that you are running these steps in a Linux environment. Possible scenarios for this include
> [GitHub Codespaces](https://github.com/features/codespaces), [Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers), or 
> [WSL](https://learn.microsoft.com/en-us/windows/wsl/about).

## Setup Variables

Creating resuable variables in a `.env` file makes the script execution easier. Simply rename the [.env-sample](./.env-sample) to `.env` and set your own values in the file.

```bash

# Rename the .env-sample file
mv .env-sample .env

# Edit and save the file after providing the following data values
# TENANT_ID - This should be your Azure Entra Tenant ID, which might be required to login to Azure
# SUBSCRIPTION_ID - The Azure Subscription ID that you will use to deploy into
# BASE_NAME - A valid identifier that will be used to build out resource names in Bicep
# LOCATION - The Azure region you want to deploy to
# CONTAINER_NAME - The name of the container to create/use
# CONTAINER_TAG - The name of the container tag to create/use
# DATABASE_NAME - The name of the database to create/use
# DUMMY_SA_PASSWORD - A dummy password to use when running and connecting to a local SQL container instance
# DOCKER_USERNAME - Your username for accessing Docker Hub
# DOCKER_PASSWORD - Your password or PAT token for accessing Docker Hub

# Apply the variables within your session
source .env

```

## Design and Development

Using DAB is similar to any other development task where the "inner loop" is key to being able to quickly iterate on using DAB to expose and test APIs against a database. In this demo, we use a containerized version of Microsoft SQL Server to run the AdventureWorksLT database. You can view the details of this container and how it works by examining [this repo](https://github.com/cwiederspan/adventureworkslt-mssql-container). Once DAB creates the `dab-config.json` file, containerizing and running locally can be kicked-off using `docker compose`. The primary component of all of this is the simple [Dockerfile](./Dockerfile) that simply copies the `dab-config.json` file into the official [data-api-builder](https://mcr.microsoft.com/en-us/artifact/mar/azure-databases/data-api-builder/tags) container.

```bash

# Initialize the DAB tool and setup locally
dotnet tool run dab -- init --database-type "mssql" --connection-string "@env('DATABASE_CONNECTION_STRING')"

# Construct your API surface area with DAB commands
dotnet tool run dab -- add Customer --source "SalesLT.Customer" --permissions "anonymous:*"     # <= Allow writes to this table
dotnet tool run dab -- add Address --source "SalesLT.Address" --permissions "anonymous:read"
dotnet tool run dab -- add CustomerAddress --source "SalesLT.CustomerAddress" --permissions "anonymous:read"
dotnet tool run dab -- add SalesOrderHeader --source "SalesLT.SalesOrderHeader" --permissions "anonymous:read"
dotnet tool run dab -- add SalesOrderDetail --source "SalesLT.SalesOrderDetail" --permissions "anonymous:read"
dotnet tool run dab -- add Product --source "SalesLT.Product" --permissions "anonymous:read"
dotnet tool run dab -- add ProductCategory --source "SalesLT.ProductCategory" --permissions "anonymous:read"
dotnet tool run dab -- add ProductModel --source "SalesLT.ProductModel" --permissions "anonymous:read"
dotnet tool run dab -- add ProductModelProductDescription --source "SalesLT.ProductModelProductDescription" --permissions "anonymous:read"
dotnet tool run dab -- add ProductDescription --source "SalesLT.ProductDescription" --permissions "anonymous:read"

# Now run the application with Docker Compose
docker compose up

```

## Containerization

Using the `dab-config.json` file that was constructed above, use Docker to build a container that can be pushed up to Docker Hub (or some other container registry). 

```bash

# Log into Docker Hub
docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD

# Build the container
docker build . -t $DOCKER_USERNAME/$CONTAINER_NAME:$CONTAINER_TAG

# Push the container
docker push $DOCKER_USERNAME/$CONTAINER_NAME:$CONTAINER_TAG

```

## Azure Resource Provisioning

The [Bicep](./infra/main.bicep) file can be used to easily provision the SQL Server, its database, and the Azure Container App that then loads up the container image that we built and pushed above.

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

There is also a [GitHub Action](./.github/workflows/pipeline.yaml) file you can use to automate most of the above steps if desired. To do so, you need to provision an Azure service principal that the pipeline can use to access your resource group. You must also setup the appropriate secrets and variables in GitHub to match what you have in the `.env` file, which you can do through the [GitHub CLI](https://cli.github.com/) commands.

```bash

# Create an App Registration/Service Principal
AZURE_CREDS=$(az ad sp create-for-rbac --name $BASE_NAME-sp --sdk-auth --role contributor --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$BASE_NAME)

# Setup the GitHub Action variables using the GitHub CLI
gh secret set AZURE_CREDENTIALS -a actions -b"$AZURE_CREDS"
gh secret set DOCKER_PASSWORD -a actions -b"$DOCKER_PASSWORD"

gh variable set BASE_NAME -b"$BASE_NAME"
gh variable set LOCATION -b"$LOCATION"
gh variable set CONTAINER_NAME -b"$CONTAINER_NAME"
gh variable set CONTAINER_TAG -b"$CONTAINER_TAG"
gh variable set DATABASE_NAME -b"$DATABASE_NAME"
gh variable set DOCKER_USERNAME -b"$DOCKER_USERNAME"

```

## Clean Up

The easiest way to clean up is by deleting the resource group that was created.

```bash

# Delete the Resource Group
az group delete --name $BASE_NAME

# Find the App Registration/Service Principal if you created one in the Bonus Content section
APP_ID=$(az ad app list --filter "displayname eq '$BASE_NAME-sp'" -o tsv --query "[].{appId:appId}")

# Delete it
az ad app delete --id $APP_ID

```