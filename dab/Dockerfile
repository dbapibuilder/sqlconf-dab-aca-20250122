FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /config

RUN dotnet new tool-manifest
RUN dotnet tool install Microsoft.DataApiBuilder

RUN dotnet tool run dab -- init --database-type "mssql" --connection-string "@env('DATABASE_CONNECTION_STRING')"

RUN dotnet tool run dab -- add Customer --source "SalesLT.Customer" --permissions "anonymous:*"

RUN dotnet tool run dab -- add Address --source "SalesLT.Address" --permissions "anonymous:read"
RUN dotnet tool run dab -- add CustomerAddress --source "SalesLT.CustomerAddress" --permissions "anonymous:read"

RUN dotnet tool run dab -- add SalesOrderHeader --source "SalesLT.SalesOrderHeader" --permissions "anonymous:read"
RUN dotnet tool run dab -- add SalesOrderDetail --source "SalesLT.SalesOrderDetail" --permissions "anonymous:read"

RUN dotnet tool run dab -- add Product --source "SalesLT.Product" --permissions "anonymous:read"
RUN dotnet tool run dab -- add ProductCategory --source "SalesLT.ProductCategory" --permissions "anonymous:read"
RUN dotnet tool run dab -- add ProductModel --source "SalesLT.ProductModel" --permissions "anonymous:read"
RUN dotnet tool run dab -- add ProductModelProductDescription --source "SalesLT.ProductModelProductDescription" --permissions "anonymous:read"
RUN dotnet tool run dab -- add ProductDescription --source "SalesLT.ProductDescription" --permissions "anonymous:read"

FROM mcr.microsoft.com/azure-databases/data-api-builder

COPY --from=build /config /App