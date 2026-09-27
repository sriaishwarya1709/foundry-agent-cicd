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
& .\.venv\Scripts\python.exe scripts\deploy_agent.py deploy