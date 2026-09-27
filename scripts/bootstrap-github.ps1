[CmdletBinding()]
param(
    [string]$GitHubOwner = 'sriaishwarya1709',
    [string]$GitHubRepository = 'foundry-agent-cicd',
    [string[]]$GitHubEnvironments = @('dev', 'test', 'prod'),
    [string]$Location = 'eastus2',
    [string]$IdentityResourceGroupName = 'rg-github-identities',
    [string]$IdentityName = 'github-foundry-agent',
    [switch]$SkipGitHubConfiguration
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command 'az' -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found."
}
if (-not $SkipGitHubConfiguration -and -not (Get-Command 'gh' -ErrorAction SilentlyContinue)) {
    throw "Required command 'gh' was not found."
}

$account = az account show --output json | ConvertFrom-Json
if (-not $account.id) {
    throw 'Azure CLI is not authenticated. Run az login first.'
}

$githubEnvironmentsJson = ConvertTo-Json -InputObject $GitHubEnvironments -Compress
$deploymentName = 'github-identity-bootstrap'
$deployment = az deployment sub create `
    --name $deploymentName `
    --location $Location `
    --template-file infra/bootstrap.bicep `
    --parameters `
        location=$Location `
        identityResourceGroupName=$IdentityResourceGroupName `
        identityName=$IdentityName `
        githubOwner=$GitHubOwner `
        githubRepository=$GitHubRepository `
        githubEnvironments=$githubEnvironmentsJson `
    --output json | ConvertFrom-Json

$outputs = $deployment.properties.outputs
$values = [ordered]@{
    AZURE_CLIENT_ID       = $outputs.AZURE_CLIENT_ID.value
    AZURE_PRINCIPAL_ID    = $outputs.AZURE_PRINCIPAL_ID.value
    AZURE_TENANT_ID       = $outputs.AZURE_TENANT_ID.value
    AZURE_SUBSCRIPTION_ID = $outputs.AZURE_SUBSCRIPTION_ID.value
    AZURE_LOCATION        = $outputs.AZURE_LOCATION.value
}

if (-not $SkipGitHubConfiguration) {
    gh auth status | Out-Null
    $repository = "$GitHubOwner/$GitHubRepository"
    foreach ($githubEnvironment in $GitHubEnvironments) {
        gh api `
            --method PUT `
            "repos/$repository/environments/$githubEnvironment" | Out-Null
        foreach ($entry in $values.GetEnumerator()) {
            gh variable set $entry.Key `
                --env $githubEnvironment `
                --repo $repository `
                --body $entry.Value
        }
        Write-Host "Configured GitHub environment '$githubEnvironment' in $repository."
    }
}

$values.GetEnumerator() | Format-Table -AutoSize