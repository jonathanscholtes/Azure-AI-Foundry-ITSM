from agent_framework import Agent
from agent_framework.azure import AzureAIClient


def create_classifier(
    project_endpoint: str,
    credential,
    agent_name: str,
) -> Agent:
    """Create the intent classifier referencing a Foundry-deployed agent.

    The agent instructions live server-side and already request JSON output.
    Handlers parse the response via ``ClassificationResult.model_validate_json``.
    """
    return Agent(
        client=AzureAIClient(
            project_endpoint=project_endpoint,
            credential=credential,
            agent_name=agent_name,
            use_latest_version=True,
        ),
        name=agent_name,
    )
