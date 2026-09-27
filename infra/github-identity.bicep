param location string
param identityName string
param githubOwner string
param githubRepository string
param githubEnvironments array

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: {
    workload: 'foundry-agent-cicd'
    purpose: 'github-oidc'
  }
}

resource githubFederation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [for githubEnvironment in githubEnvironments: {
  name: 'github-${githubEnvironment}'
  parent: identity
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOwner}/${githubRepository}:environment:${githubEnvironment}'
  }
}]

output clientId string = identity.properties.clientId
output principalId string = identity.properties.principalId