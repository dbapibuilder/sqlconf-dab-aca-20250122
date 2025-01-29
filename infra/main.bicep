@description('The base name of the resources to create.')
param baseName string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The name of the database to create within the SQL server.')
param databaseName string

@description('The full container Uri (with tag) to use for the Azure Container App.')
param containerUri string

resource muid 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${baseName}-muid'
  location: location
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${baseName}-law'
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-apm'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource sqlServer 'Microsoft.Sql/servers@2024-05-01-preview' = {
  name: '${baseName}-sql'
  location: location
  properties: {
    administrators: {
      azureADOnlyAuthentication: true
      administratorType: 'ActiveDirectory'
      principalType: 'Application'
      login: muid.name
      sid: muid.properties.clientId
      tenantId: muid.properties.tenantId
    }
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
  resource AllowAllWindowsAzureIps 'firewallRules@2024-05-01-preview' = {
    name: 'AllowAllWindowsAzureIps'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }
}

resource sqlDB 'Microsoft.Sql/servers/databases@2024-05-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: 'HS_S_Gen5'
    tier: 'Hyperscale'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    sampleName: 'AdventureWorksLT'
    highAvailabilityReplicaCount: 0
  }
}

resource environment 'Microsoft.App/managedEnvironments@2022-03-01' = {
  name: '${baseName}-env'
  location: location
  properties: {
    daprAIInstrumentationKey: appInsights.properties.InstrumentationKey
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource containerApp 'Microsoft.App/containerApps@2022-03-01' ={
  name: '${baseName}-aca'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${muid.id}': {}
    }
  }
  properties:{
    managedEnvironmentId: environment.id
    configuration: {
      ingress: {
        targetPort: 5000
        external: true
      }
    }
    template: {
      containers: [
        {
          image: containerUri
          name: 'dab-adventureworks'
          env: [
            {
              name: 'DATABASE_CONNECTION_STRING'
              value: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDB.name};Persist Security Info=False;User ID=${muid.properties.clientId};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Managed Identity;'
            }
          ]
        }
      ]
    }
  }
}

output appUrl string = containerApp.properties.configuration.ingress.fqdn
