import logging
import os

from agent_framework import Agent, Case, Default, WorkflowBuilder
from agent_framework.azure import AzureAIClient
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential

from .classifier import create_classifier
from .handlers import (
    finalize,
    general_handler,
    get_intent_case,
    to_kb_lookup,
    to_ticket_agent,
    to_triage_agent,
)

logger = logging.getLogger(__name__)

# Agent name keys stored in Azure App Configuration
_AGENT_NAME_KEYS = ["CLASSIFIER_AGENT_NAME", "KB_LOOKUP_AGENT_NAME", "TICKET_AGENT_NAME", "TRIAGE_AGENT_NAME"]

# Cached at startup by init_workflow()
_credential = None
_project_endpoint: str = ""
_agent_names: dict[str, str] = {}
_internal_agents: set[str] = set()


def _get_credential():
    """Use ManagedIdentityCredential in Azure, DefaultAzureCredential locally."""
    client_id = os.environ.get("AZURE_CLIENT_ID")
    if client_id:
        return ManagedIdentityCredential(client_id=client_id)
    return DefaultAzureCredential()


def _resolve_agent_names(credential) -> dict[str, str]:
    """Resolve agent names from App Configuration, falling back to env vars.

    Reads the App Configuration endpoint from AZURE_APP_CONFIGURATION_ENDPOINT.
    If the endpoint is not set or a key is missing, falls back to the
    corresponding environment variable (for local development).
    """
    names: dict[str, str] = {}
    app_config_endpoint = os.environ.get("AZURE_APP_CONFIGURATION_ENDPOINT")

    if app_config_endpoint:
        try:
            from azure.appconfiguration import AzureAppConfigurationClient

            client = AzureAppConfigurationClient(
                base_url=app_config_endpoint, credential=credential
            )
            for key in _AGENT_NAME_KEYS:
                setting = client.get_configuration_setting(key=key)
                if setting and setting.value:
                    names[key] = setting.value
                    logger.info("App Config  %-25s = %s", key, setting.value)
        except Exception as exc:
            logger.warning("Failed to read from App Configuration: %s", exc)

    # Fall back to env vars for any keys not resolved from App Config
    for key in _AGENT_NAME_KEYS:
        if key not in names:
            val = os.environ.get(key, "")
            if val:
                names[key] = val
                logger.info("Env var     %-25s = %s", key, val)
            else:
                raise RuntimeError(
                    f"Agent name '{key}' not found in App Configuration or environment variables."
                )
    return names


def init_workflow() -> set[str]:
    """One-time startup: resolve credentials and agent names.

    Returns the set of internal agent names whose streaming output should be
    hidden from the UI (e.g. the classifier).
    """
    global _credential, _project_endpoint, _agent_names, _internal_agents
    _credential = _get_credential()
    _project_endpoint = os.environ["AZURE_AI_PROJECT_ENDPOINT"]
    _agent_names = _resolve_agent_names(_credential)
    _internal_agents = {_agent_names["CLASSIFIER_AGENT_NAME"]}
    return _internal_agents


def build_itsm_workflow():
    """Build a fresh workflow instance (call per request).

    All agents (classifier + specialists) are Foundry-deployed agents,
    referenced by agent name via the V2 API.

    The SDK Workflow object is stateful and does not support concurrent
    executions, so each request needs its own instance.  The expensive
    credential/name resolution is cached by ``init_workflow()``.
    """

    # Resolve agent names from App Configuration (or env vars for local dev)
    agent_names = _agent_names

    # Foundry-deployed classifier agent
    classifier = create_classifier(
        project_endpoint=_project_endpoint,
        credential=_credential,
        agent_name=agent_names["CLASSIFIER_AGENT_NAME"],
    )

    # Foundry-deployed specialist agents — referenced by agent name (V2 API)
    kb_lookup = Agent(
        client=AzureAIClient(
            project_endpoint=_project_endpoint,
            credential=_credential,
            agent_name=agent_names["KB_LOOKUP_AGENT_NAME"],
            use_latest_version=True,
        ),
        name=agent_names["KB_LOOKUP_AGENT_NAME"],
    )
    ticket_agent = Agent(
        client=AzureAIClient(
            project_endpoint=_project_endpoint,
            credential=_credential,
            agent_name=agent_names["TICKET_AGENT_NAME"],
            use_latest_version=True,
        ),
        name=agent_names["TICKET_AGENT_NAME"],
    )
    triage_agent = Agent(
        client=AzureAIClient(
            project_endpoint=_project_endpoint,
            credential=_credential,
            agent_name=agent_names["TRIAGE_AGENT_NAME"],
            use_latest_version=True,
        ),
        name=agent_names["TRIAGE_AGENT_NAME"],
    )

    # Build the workflow graph with switch-case routing
    workflow = (
        WorkflowBuilder(start_executor=classifier)
        .add_switch_case_edge_group(
            classifier,
            [
                Case(
                    condition=get_intent_case("kb_lookup"),
                    target=to_kb_lookup,
                ),
                Case(
                    condition=get_intent_case("ticket"),
                    target=to_ticket_agent,
                ),
                Case(
                    condition=get_intent_case("triage"),
                    target=to_triage_agent,
                ),
                Default(target=general_handler),
            ],
        )
        # Each transform executor → its specialist agent → finalize
        .add_edge(to_kb_lookup, kb_lookup)
        .add_edge(kb_lookup, finalize)
        .add_edge(to_ticket_agent, ticket_agent)
        .add_edge(ticket_agent, finalize)
        .add_edge(to_triage_agent, triage_agent)
        .add_edge(triage_agent, finalize)
        .build()
    )
    return workflow
