# Foundry prompt agent CI/CD sample

This repository provisions one Microsoft Foundry account with multiple projects, deploys a shared model, creates a versioned prompt agent with live web search in every project, and connects each project to Application Insights. Authentication uses Microsoft Entra ID: `DefaultAzureCredential` locally, workload identity federation in GitHub Actions, and system-assigned managed identities on Foundry resources. No model API keys are used.

## Architecture

```mermaid
flowchart LR
    Developer[Developer / azd] -->|Entra ID| ARM[Azure Resource Manager]
    GitHub[GitHub Actions OIDC] -->|Federated identity| ARM
    ARM --> Account[Foundry account]
    Account --> Model[gpt-4.1-mini deployment]
    Account --> Dev[dev project]
    Account --> Test[test project]
    Account --> Prod[prod project]
    Dev & Test & Prod --> Agent[Versioned prompt agent + web search]
    Dev & Test & Prod --> AppInsights[Application Insights]
    AppInsights --> Logs[Log Analytics]
```

The same immutable source configuration in [agent/agent.json](agent/agent.json) is promoted by creating a new agent version in each selected Foundry project. Bicep owns Azure resources and RBAC; the Python SDK owns the prompt-agent definition.

## Local deployment with azd

Prerequisites: Azure CLI, Azure Developer CLI, Python 3.11+, and an Azure subscription where you can create resources and role assignments. Model and web-search availability vary by region and subscription.

```powershell
az login
azd auth login
azd env new foundry-demo

$principalId = az ad signed-in-user show --query id -o tsv
azd env set AZURE_PRINCIPAL_ID $principalId
azd env set AZURE_PRINCIPAL_TYPE User
azd env set AZURE_LOCATION eastus2
azd env set AZURE_AI_PROJECT_NAMES_JSON '["dev","test","prod"]'
azd up
```

`azd up` provisions the infrastructure and runs the promotion script. Re-running it creates a new agent version in each project. To reduce cost, use only `["dev"]` for a demo. To remove the resources, run `azd down --purge`.

## Try the agent

Load the current azd outputs, then invoke any project:

```powershell
azd env get-values | ForEach-Object {
  if ($_ -match '^([^=]+)="(.*)"$') { Set-Item "env:$($Matches[1])" $Matches[2] }
}
.\.venv\Scripts\python.exe scripts\deploy_agent.py invoke --prompt "What changed in Microsoft Foundry this week?"
```

You can also press `F5` in VS Code after creating a workspace-root `.env` from `azd env get-values`. Responses print URL citations, and OpenTelemetry sends invocation traces to the linked Application Insights resource.

## GitHub Actions setup

Create a GitHub Environment such as `demo`, then add these environment variables:

| Variable | Purpose |
| --- | --- |
| `AZURE_CLIENT_ID` | Client ID of the Entra application or user-assigned identity used for OIDC |
| `AZURE_PRINCIPAL_ID` | Object ID of its service principal, used for Foundry RBAC |
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |
| `AZURE_LOCATION` | Region such as `eastus2` |

Configure a federated credential on that identity for the GitHub repository/environment and grant it permission to deploy resources and assign the Foundry User role. The workflow validates tests and Bicep, provisions with `azd`, and promotes the agent to the requested JSON list of projects.

For customer handoff, fork the repository, replace the GitHub Environment variables, review the Bing Grounding terms/data-boundary notice for web search, and choose a model/region with available quota.

## Security notes

- Local authentication is disabled on Foundry and Application Insights.
- The App Insights project connection stores its connection string because that is the platform's supported association mechanism; telemetry export itself supplies an Entra credential.
- Web results are untrusted and can leave the Azure compliance/geographic boundary. Do not put secrets or sensitive personal data in web-search prompts.