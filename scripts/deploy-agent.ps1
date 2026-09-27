$ErrorActionPreference = 'Stop'

$values = azd env get-values | Out-String
$values -split "`n" | ForEach-Object {
    if ($_ -match '^([^=]+)="(.*)"$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
    }
}

if (-not (Test-Path '.venv')) {
    python -m venv .venv
}

& .\.venv\Scripts\python.exe -m pip install --disable-pip-version-check -r requirements.txt
$deployArguments = @('scripts\deploy_agent.py', 'deploy')
if ($env:AZURE_AI_DEPLOY_PROJECT) {
    $projectEndpoint = "https://$($env:AZURE_AI_ACCOUNT_NAME).services.ai.azure.com/api/projects/$($env:AZURE_AI_DEPLOY_PROJECT)"
    $deployArguments += @('--project', $projectEndpoint)
}
& .\.venv\Scripts\python.exe @deployArguments