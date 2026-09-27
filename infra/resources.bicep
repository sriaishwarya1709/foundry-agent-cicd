param location string
param foundryAccountName string
param projectNames array
param modelName string
param modelCapacity int
param logAnalyticsName string
param appInsightsName string
param principalId string
param principalType string
param tags object

var foundryUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
)
var monitoringMetricsPublisherRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '3913510d-42f4-4e42-8a64-420c390055eb'
)

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    DisableLocalAuth: true
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryAccountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryAccountName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: false
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  name: modelName
  parent: foundry
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

resource projects 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = [for projectName in projectNames: {
  name: projectName
  parent: foundry
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    displayName: projectName
    description: 'Prompt agent promotion target for ${projectName}'
  }
}]

resource appInsightsConnections 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = [for (projectName, index) in projectNames: {
  name: '${foundry.name}/${projectName}/${appInsightsName}'
  properties: {
    category: 'AppInsights'
    target: appInsights.id
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: appInsights.properties.ConnectionString
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: appInsights.id
    }
  }
  dependsOn: [
    projects[index]
  ]
}]

resource projectMonitoringPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (projectName, index) in projectNames: {
  name: guid(appInsights.id, projects[index].id, monitoringMetricsPublisherRoleId)
  scope: appInsights
  properties: {
    principalId: projects[index].identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: monitoringMetricsPublisherRoleId
  }
}]

resource principalFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (projectName, index) in projectNames: {
  name: guid(projects[index].id, principalId, foundryUserRoleId)
  scope: projects[index]
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: foundryUserRoleId
  }
}]

output projectEndpoints array = [for (projectName, index) in projectNames: projects[index].properties.endpoints['AI Foundry API']]
output applicationInsightsConnectionString string = appInsights.properties.ConnectionString
output applicationInsightsResourceId string = appInsights.id