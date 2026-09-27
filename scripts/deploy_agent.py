from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    PromptAgentDefinition,
    WebSearchApproximateLocation,
    WebSearchTool,
)
from azure.identity import DefaultAzureCredential

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "agent" / "agent.json"


@dataclass(frozen=True)
class AgentConfig:
    name: str
    description: str
    instructions: str
    country: str
    city: str
    region: str
    search_context_size: str
    external_web_access: bool


def load_config(path: Path = DEFAULT_CONFIG) -> AgentConfig:
    raw = json.loads(path.read_text(encoding="utf-8"))
    instructions_path = path.parent / raw["instructions_file"]
    web_search = raw["web_search"]
    return AgentConfig(
        name=raw["name"],
        description=raw["description"],
        instructions=instructions_path.read_text(encoding="utf-8").strip(),
        country=web_search["country"],
        city=web_search["city"],
        region=web_search["region"],
        search_context_size=web_search["search_context_size"],
        external_web_access=web_search["external_web_access"],
    )


def project_endpoints(environment: dict[str, str] | None = None) -> list[str]:
    values = environment or os.environ
    explicit = values.get("AZURE_AI_PROJECT_ENDPOINTS_JSON")
    if explicit:
        endpoints = json.loads(explicit)
        if not isinstance(endpoints, list) or not all(isinstance(item, str) for item in endpoints):
            raise ValueError("AZURE_AI_PROJECT_ENDPOINTS_JSON must be a JSON array of strings")
        return endpoints

    account = values.get("AZURE_AI_ACCOUNT_NAME")
    names = values.get("AZURE_AI_PROJECT_NAMES")
    if not account or not names:
        raise ValueError(
            "Set AZURE_AI_PROJECT_ENDPOINTS_JSON, or both AZURE_AI_ACCOUNT_NAME and AZURE_AI_PROJECT_NAMES"
        )
    return [
        f"https://{account}.services.ai.azure.com/api/projects/{name.strip()}"
        for name in names.split(",")
        if name.strip()
    ]


def create_agent_version(client: AIProjectClient, config: AgentConfig, model: str) -> Any:
    return client.agents.create_version(
        agent_name=config.name,
        definition=PromptAgentDefinition(
            model=model,
            instructions=config.instructions,
            tools=[
                WebSearchTool(
                    user_location=WebSearchApproximateLocation(
                        country=config.country,
                        city=config.city,
                        region=config.region,
                    ),
                    search_context_size=config.search_context_size,
                    external_web_access=config.external_web_access,
                )
            ],
        ),
        description=config.description,
    )


def deploy(endpoints: Iterable[str], model: str, config: AgentConfig) -> None:
    credential = DefaultAzureCredential()
    for endpoint in endpoints:
        client = AIProjectClient(endpoint=endpoint, credential=credential)
        agent = create_agent_version(client, config, model)
        print(f"Promoted {agent.name} version {agent.version} to {endpoint}")


def invoke(endpoint: str, prompt: str, config: AgentConfig) -> None:
    credential = DefaultAzureCredential()
    project = AIProjectClient(endpoint=endpoint, credential=credential)
    connection_string = project.telemetry.get_application_insights_connection_string()
    if connection_string:
        from azure.monitor.opentelemetry import configure_azure_monitor
        from opentelemetry.instrumentation.openai_v2 import OpenAIInstrumentor

        configure_azure_monitor(connection_string=connection_string, credential=credential)
        OpenAIInstrumentor().instrument()

    response = project.get_openai_client().responses.create(
        input=prompt,
        tool_choice="required",
        extra_body={"agent_reference": {"name": config.name, "type": "agent_reference"}},
    )
    print(response.output_text)
    for item in response.output:
        if getattr(item, "type", None) != "message":
            continue
        for content in getattr(item, "content", []):
            for annotation in getattr(content, "annotations", []):
                if getattr(annotation, "type", None) == "url_citation":
                    print(f"Citation: {annotation.url}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Promote or invoke the Foundry prompt agent.")
    parser.add_argument("command", choices=("deploy", "invoke"))
    parser.add_argument("--project", help="Project endpoint for invoke; defaults to the first configured project.")
    parser.add_argument("--prompt", default="What are the latest Microsoft Foundry agent updates?")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = load_config()
    endpoints = project_endpoints()
    model = os.environ.get("AZURE_AI_MODEL_DEPLOYMENT_NAME", "gpt-4.1-mini")
    if args.command == "deploy":
        deploy(endpoints, model, config)
    else:
        invoke(args.project or endpoints[0], args.prompt, config)


if __name__ == "__main__":
    main()