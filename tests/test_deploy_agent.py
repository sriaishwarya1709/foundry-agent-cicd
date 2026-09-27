import json
from pathlib import Path
from unittest.mock import Mock

from scripts.deploy_agent import (
    create_agent_version,
    deployment_endpoints,
    load_config,
    project_endpoints,
)


def test_load_config_reads_instructions(tmp_path: Path) -> None:
    (tmp_path / "instructions.md").write_text("Use web search.", encoding="utf-8")
    (tmp_path / "agent.json").write_text(
        json.dumps(
            {
                "name": "demo",
                "description": "demo agent",
                "instructions_file": "instructions.md",
                "web_search": {
                    "country": "US",
                    "city": "Seattle",
                    "region": "Washington",
                    "search_context_size": "medium",
                    "external_web_access": True,
                },
            }
        ),
        encoding="utf-8",
    )

    config = load_config(tmp_path / "agent.json")

    assert config.name == "demo"
    assert config.instructions == "Use web search."


def test_project_endpoints_prefers_explicit_json() -> None:
    expected = ["https://example.ai.azure.com/api/projects/dev"]

    assert project_endpoints({"AZURE_AI_PROJECT_ENDPOINTS_JSON": json.dumps(expected)}) == expected


def test_project_endpoints_builds_each_project() -> None:
    environment = {
        "AZURE_AI_ACCOUNT_NAME": "contoso-foundry",
        "AZURE_AI_PROJECT_NAMES": "dev,test,prod",
    }

    assert project_endpoints(environment) == [
        "https://contoso-foundry.services.ai.azure.com/api/projects/dev",
        "https://contoso-foundry.services.ai.azure.com/api/projects/test",
        "https://contoso-foundry.services.ai.azure.com/api/projects/prod",
    ]


def test_deployment_endpoints_selects_only_requested_stage() -> None:
    endpoints = ["dev-endpoint", "test-endpoint", "prod-endpoint"]

    assert deployment_endpoints(endpoints, "test-endpoint") == ["test-endpoint"]
    assert deployment_endpoints(endpoints, None) == endpoints


def test_create_agent_version_enables_web_search() -> None:
    config = load_config()
    client = Mock()
    client.agents.create_version.return_value = Mock(name=config.name, version="1")

    create_agent_version(client, config, "gpt-4.1-mini")

    call = client.agents.create_version.call_args
    assert call.kwargs["agent_name"] == config.name
    assert call.kwargs["definition"].model == "gpt-4.1-mini"
    assert call.kwargs["definition"].tools[0].type == "web_search"