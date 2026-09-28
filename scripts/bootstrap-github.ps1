#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$GitHubOwner = 'sriaishwarya1709',
    [string]$GitHubRepository = 'foundry-agent-cicd',
    [string[]]$GitHubEnvironments = @('dev', 'test', 'prod'),
    [string]$Location = 'eastus2',
    [string]$SubscriptionId,
    [string]$IdentityResourceGroupName = 'rg-github-identities',
    [string]$IdentityName = 'github-foundry-agent',
    [switch]$SkipGitHubConfiguration
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if (-not (Get-Command 'az' -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found."
}
if (-not $SkipGitHubConfiguration -and -not (Get-Command 'gh' -ErrorAction SilentlyContinue)) {
    throw "Required command 'gh' was not found."
}

$accountArguments = @('account', 'show', '--output', 'json')
if ($SubscriptionId) {
    $accountArguments += @('--subscription', $SubscriptionId)
}
$account = az @accountArguments | ConvertFrom-Json
if (-not $account.id) {
    throw 'Azure CLI is not authenticated. Run az login first.'
}
$SubscriptionId = $account.id

$deploymentName = 'github-identity-bootstrap'
$parameterFile = Join-Path ([System.IO.Path]::GetTempPath()) "foundry-agent-bootstrap-$([guid]::NewGuid()).json"
$parameters = @{
    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters     = @{
        location                  = @{ value = $Location }
        identityResourceGroupName = @{ value = $IdentityResourceGroupName }
        identityName              = @{ value = $IdentityName }
        githubOwner               = @{ value = $GitHubOwner }
        githubRepository          = @{ value = $GitHubRepository }
        githubEnvironments        = @{ value = $GitHubEnvironments }
    }
}

try {
    $parameters | ConvertTo-Json -Depth 5 | Set-Content -Path $parameterFile -Encoding utf8
    $deployment = az deployment sub create `
        --subscription $SubscriptionId `
        --name $deploymentName `
        --location $Location `
        --template-file infra/bootstrap.bicep `
        --parameters "@$parameterFile" `
        --output json | ConvertFrom-Json
}
finally {
    Remove-Item $parameterFile -ErrorAction SilentlyContinue
}

$outputs = $deployment.properties.outputs
if (-not $outputs.AZURE_CLIENT_ID.value -or -not $outputs.AZURE_PRINCIPAL_ID.value) {
    throw 'The Azure bootstrap deployment did not return identity outputs.'
}
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