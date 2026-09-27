targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Short environment name used to create deterministic resource names.')
param environmentName string

@description('Azure region for the Foundry resources and model deployment.')
param location string = 'eastus2'

@description('Object ID that receives permission to manage and invoke agents. Set by azd locally and by GitHub OIDC in CI.')
param principalId string

@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'ServicePrincipal'

@description('Foundry project names to create under the shared Foundry account.')
param projectNames array = [
  'dev'
]

@description('Model catalog name and deployment name used by the prompt agent.')
param modelName string = 'gpt-4.1-mini'

@description('Model deployment capacity in thousands of tokens per minute.')
param modelCapacity int = 10

var token = toLower(uniqueString(subscription().id, environmentName))
var resourceGroupName = 'rg-${environmentName}'
var foundryAccountName = 'aif-${take(environmentName, 20)}-${token}'
var logAnalyticsName = 'log-${take(environmentName, 24)}-${token}'
var appInsightsName = 'appi-${take(environmentName, 23)}-${token}'
var tags = {
  'azd-env-name': environmentName
  workload: 'foundry-agent-cicd'
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module resources 'resources.bicep' = {
  name: 'foundry-agent-resources'
  scope: resourceGroup
  params: {
    location: location
    foundryAccountName: foundryAccountName
    projectNames: projectNames
    modelName: modelName
    modelCapacity: modelCapacity
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    principalId: principalId
    principalType: principalType
    tags: tags
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_AI_ACCOUNT_NAME string = foundryAccountName
output AZURE_AI_PROJECT_NAMES string = join(projectNames, ',')
output AZURE_AI_PROJECT_ENDPOINTS_JSON string = string(resources.outputs.projectEndpoints)
output AZURE_AI_MODEL_DEPLOYMENT_NAME string = modelName
output APPLICATIONINSIGHTS_CONNECTION_STRING string = resources.outputs.applicationInsightsConnectionString
output APPLICATIONINSIGHTS_RESOURCE_ID string = resources.outputs.applicationInsightsResourceId