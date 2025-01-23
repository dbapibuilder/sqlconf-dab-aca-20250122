extension graphV1

@description('The base name of the resources to create.')
param baseName string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The name of the database to create within the SQL server.')
param databaseName string

@description('The Entra object ID that will be added to the SQL administrator group.')
param myEntraUserId string

@description('The local IP address of the user who can connect to SQL server.')
param myIpAddress string

resource muid 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${baseName}-muid'
  location: location
}

resource adminGroup 'Microsoft.Graph/groups@v1.0' = {
  uniqueName: '${baseName}-sql-admin-group'
  displayName: '${baseName}-sql-admin-group'
  description: 'A group for assigning admin rights to demo SQL servers.'
  mailEnabled: false
  mailNickname: '${baseName}-sql-admin-group'
  securityEnabled: true
  members: [
    muid.properties.principalId
    myEntraUserId
  ]
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
      administratorType: 'ActiveDirectory'
      principalType: 'Group'
      azureADOnlyAuthentication: true
      login: adminGroup.uniqueName
      sid: adminGroup.id
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
  resource AllowMyIpAddress 'firewallRules@2024-05-01-preview' = {
    name: 'AllowMyIpAddress'
    properties: {
      startIpAddress: myIpAddress
      endIpAddress: myIpAddress
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
          image: 'cwiederspan/adventureworksdab:latest'
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
