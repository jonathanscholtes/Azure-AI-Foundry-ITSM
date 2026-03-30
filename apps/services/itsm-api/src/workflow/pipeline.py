import logging
import os

from agent_framework import Agent, Case, Default, WorkflowBuilder
from agent_framework.azure import AzureAIAgentClient
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential

from .classifier import create_classifier
from .handlers import (
    finalize,
    general_handler,
    get_intent_case,
    to_specialist_request,
)

logger = logging.getLogger(__name__)

# Agent ID keys stored in Azure App Configuration
_AGENT_ID_KEYS = ["KB_LOOKUP_AGENT_ID", "TICKET_AGENT_ID", "TRIAGE_AGENT_ID"]


def _get_credential():
    """Use ManagedIdentityCredential in Azure, DefaultAzureCredential locally."""
    client_id = os.environ.get("AZURE_CLIENT_ID")
    if client_id:
        return ManagedIdentityCredential(client_id=client_id)
    return DefaultAzureCredential()


def _resolve_agent_ids(credential) -> dict[str, str]:
    """Resolve agent IDs from App Configuration, falling back to env vars.

    Reads the App Configuration endpoint from AZURE_APP_CONFIGURATION_ENDPOINT.
    If the endpoint is not set or a key is missing, falls back to the
    corresponding environment variable (for local development).
    """
    ids: dict[str, str] = {}
    app_config_endpoint = os.environ.get("AZURE_APP_CONFIGURATION_ENDPOINT")

    if app_config_endpoint:
        try:
            from azure.appconfiguration import AzureAppConfigurationClient

            client = AzureAppConfigurationClient(
                base_url=app_config_endpoint, credential=credential
            )
            for key in _AGENT_ID_KEYS:
                setting = client.get_configuration_setting(key=key)
                if setting and setting.value:
                    ids[key] = setting.value
                    logger.info("App Config  %-25s = %s", key, setting.value)
        except Exception as exc:
            logger.warning("Failed to read from App Configuration: %s", exc)

    # Fall back to env vars for any keys not resolved from App Config
    for key in _AGENT_ID_KEYS:
        if key not in ids:
            val = os.environ.get(key, "")
            if val:
                ids[key] = val
                logger.info("Env var     %-25s = %s", key, val)
            else:
                raise RuntimeError(
                    f"Agent ID '{key}' not found in App Configuration or environment variables."
                )
    return ids


def build_itsm_workflow():
    """Assemble the ITSM orchestration workflow.

    - Classifier runs locally via AzureAIAgentClient.as_agent()
    - Specialist agents are existing Foundry agents, referenced by agent ID
    """
    credential = _get_credential()

    # Client for the local classifier (creates agent with instructions inline)
    client = AzureAIAgentClient(
        project_endpoint=os.environ["AZURE_AI_PROJECT_ENDPOINT"],
        model_deployment_name=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=credential,
    )

    classifier = create_classifier(client)

    # Resolve agent IDs from App Configuration (or env vars for local dev)
    agent_ids = _resolve_agent_ids(credential)

    # Foundry-deployed specialist agents — referenced by agent ID
    kb_lookup = Agent(
        chat_client=AzureAIAgentClient(
            credential=credential,
            agent_id=agent_ids["KB_LOOKUP_AGENT_ID"],
        ),
        name="KB Lookup",
    )
    ticket_agent = Agent(
        chat_client=AzureAIAgentClient(
            credential=credential,
            agent_id=agent_ids["TICKET_AGENT_ID"],
        ),
        name="Ticket Agent",
    )
    triage_agent = Agent(
        chat_client=AzureAIAgentClient(
            credential=credential,
            agent_id=agent_ids["TRIAGE_AGENT_ID"],
        ),
        name="Triage Agent",
    )

    # Build the workflow graph with switch-case routing
    workflow = (
        WorkflowBuilder(start_executor=classifier)
        .add_switch_case_edge_group(
            classifier,
            [
                Case(
                    condition=get_intent_case("kb_lookup"),
                    target=to_specialist_request,
                ),
                Case(
                    condition=get_intent_case("ticket"),
                    target=to_specialist_request,
                ),
                Case(
                    condition=get_intent_case("triage"),
                    target=to_specialist_request,
                ),
                Default(target=general_handler),
            ],
        )
        # Each transform executor → its specialist agent → finalize
        .add_edge(to_specialist_request, kb_lookup)
        .add_edge(kb_lookup, finalize)
        .add_edge(to_specialist_request, ticket_agent)
        .add_edge(ticket_agent, finalize)
        .add_edge(to_specialist_request, triage_agent)
        .add_edge(triage_agent, finalize)
        .build()
    )
    return workflow
