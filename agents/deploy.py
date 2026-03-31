"""
Deploy ITSM Foundry Agents.

Creates or updates the three ITSM agents in the Microsoft Foundry project
and stores their names in Azure App Configuration for container app consumption.

Agents are defined as individual modules under the ``agents`` package:
  - agents.kb_lookup     : searches Halo ITSM KB articles via MCP/APIM
  - agents.ticket_agent  : queries and manages Halo ITSM tickets via MCP/APIM
  - agents.triage_agent  : classifies and routes incoming issues via MCP/APIM

Usage:
    python agents/deploy.py \\
        --project-endpoint <FOUNDRY_PROJECT_ENDPOINT> \\
        --model-deployment gpt-4.1 \\
        [--mcp-server-url  <APIM_GATEWAY_URL>/halo-itsm-mcp] \\
        [--apim-subscription-key <KEY>]

    If --mcp-server-url and --apim-subscription-key are provided, agents that
    have USES_MCP=True will be deployed with the Halo ITSM MCP tool attached.
    Otherwise they are deployed without tools (you can add tools in the portal).
"""

import argparse
import json
import logging
import os
import sys
from typing import Optional

# When run as a script (python agents/deploy.py) the repo root is not
# automatically on sys.path, so the 'agents' package import below would fail.
# Insert the repo root explicitly.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import MCPTool, PromptAgentDefinition
from azure.appconfiguration import AzureAppConfigurationClient, ConfigurationSetting
from azure.identity import DefaultAzureCredential

from agents import classifier, kb_lookup, ticket_agent, triage_agent

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

# Map of short name -> module (used by --only filter)
AGENT_MODULE_MAP = {
    "classifier":    classifier,
    "kb_lookup":     kb_lookup,
    "ticket_agent":  ticket_agent,
    "triage_agent":  triage_agent,
}

# Ordered list of agent modules to deploy (all agents)
AGENT_MODULES = list(AGENT_MODULE_MAP.values())

# Default MCP server label
DEFAULT_MCP_SERVER_LABEL = "halo-itsm-mcp"


# ---------------------------------------------------------------------------
# Deployer
# ---------------------------------------------------------------------------

class AgentDeployer:
    """Create or update ITSM agents in Microsoft Foundry."""

    def __init__(
        self,
        project_endpoint: str,
        model_deployment: str,
        mcp_server_url: Optional[str],
        mcp_server_label: str,
        apim_subscription_key: Optional[str],
        app_config_endpoint: Optional[str] = None,
    ):
        self.project_endpoint      = project_endpoint
        self.model_deployment      = model_deployment
        self.mcp_server_url        = mcp_server_url
        self.mcp_server_label      = mcp_server_label
        self.apim_subscription_key = apim_subscription_key
        self.app_config_endpoint   = app_config_endpoint

        credential = DefaultAzureCredential()

        self.project_client = AIProjectClient(
            endpoint=project_endpoint,
            credential=credential,
        )

        self.app_config_client = None
        if app_config_endpoint:
            self.app_config_client = AzureAppConfigurationClient(
                base_url=app_config_endpoint,
                credential=credential,
            )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _mcp_tools(self) -> list:
        """Build MCP tool list if server URL and subscription key are configured."""
        if not self.mcp_server_url or not self.apim_subscription_key:
            return []
        return [
            MCPTool(
                server_label=self.mcp_server_label,
                server_url=self.mcp_server_url,
                headers={"Ocp-Apim-Subscription-Key": self.apim_subscription_key},
                require_approval="never",
            )
        ]

    def _create_or_update(self, agent_name: str, instructions: str, tools: list) -> str:
        """Create a new version of a named agent and return its ID.

        Always calls create_version() so each CI/CD run produces an immutable,
        versioned artifact (itsm-kb-lookup:1, :2, ...).  This enables rollback
        by pointing the API at a previous agent ID.
        Old versions are pruned to KEEP_VERSIONS after the new one is created.
        """
        KEEP_VERSIONS = 3

        definition = PromptAgentDefinition(
            model=self.model_deployment,
            instructions=instructions,
            tools=tools or None,
        )

        agent = self.project_client.agents.create_version(
            agent_name=agent_name,
            definition=definition,
        )
        logger.info("Created  %-35s id=%s", agent_name, agent.id)

        # Prune old versions - keep the most recent KEEP_VERSIONS
        try:
            versions = list(self.project_client.agents.list_versions(agent_name=agent_name))
            versions.sort(key=lambda a: getattr(a, "version", 0), reverse=True)
            for old in versions[KEEP_VERSIONS:]:
                self.project_client.agents.delete_version(
                    agent_name=agent_name,
                    version=old.version,
                )
                logger.info("Pruned   %-35s version=%s", agent_name, old.version)
        except Exception as exc:
            logger.warning("Could not prune old versions of %s: %s", agent_name, exc)

        return agent.id

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def deploy(self, only: Optional[list] = None) -> dict:
        """Deploy agents and print JSON lines to stdout for PS1 consumption.

        Args:
            only: If provided, a list of short agent names (e.g. ["kb_lookup"])
                  to deploy.  When *None* or empty, all agents are deployed.
        """
        if only:
            modules = [AGENT_MODULE_MAP[n] for n in only if n in AGENT_MODULE_MAP]
            if not modules:
                logger.error(
                    "None of the requested agents matched: %s  (valid: %s)",
                    only, list(AGENT_MODULE_MAP.keys()),
                )
                sys.exit(1)
        else:
            modules = AGENT_MODULES

        label = ", ".join(m.NAME for m in modules)
        logger.info("=" * 60)
        logger.info("ITSM - deploying Foundry agents")
        logger.info("  Project    : %s", self.project_endpoint)
        logger.info("  Model      : %s", self.model_deployment)
        logger.info("  MCP server : %s", self.mcp_server_url or "(not configured)")
        logger.info("  Agents     : %s", label)
        logger.info("=" * 60)

        mcp_tools = self._mcp_tools()
        if not mcp_tools:
            logger.warning(
                "MCP server URL or APIM subscription key not provided. "
                "Agents will be deployed WITHOUT the Halo ITSM MCP tool. "
                "Configure APIM then re-run."
            )
        results = {}

        try:
            for agent_mod in modules:
                tools = mcp_tools if agent_mod.USES_MCP else []
                agent_id = self._create_or_update(
                    agent_mod.NAME,
                    agent_mod.INSTRUCTIONS,
                    tools,
                )
                results[agent_mod.NAME] = agent_id

                # Output JSON line - consumed by Deploy-FoundryAgents.ps1
                print(json.dumps({
                    "agent_name": agent_mod.NAME,
                    "agent_id": agent_id,
                    "env_var": agent_mod.ENV_VAR,
                }))

            # Write agent names to App Configuration for container app consumption
            if self.app_config_client:
                logger.info("Writing agent names to App Configuration...")
                for agent_mod in modules:
                    name = agent_mod.NAME
                    self.app_config_client.set_configuration_setting(
                        ConfigurationSetting(key=agent_mod.ENV_VAR, value=name)
                    )
                    logger.info("  App Config  %-25s = %s", agent_mod.ENV_VAR, name)
            else:
                logger.info("App Configuration endpoint not provided - skipping config store write.")

            logger.info("=" * 60)
            logger.info("[OK] Agents deployed.")
            for name, aid in results.items():
                logger.info("  %-35s : %s", name, aid)
            logger.info("=" * 60)
            return results

        except Exception:
            logger.exception("Agent deployment failed.")
            sys.exit(1)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Deploy ITSM Foundry agents."
    )
    parser.add_argument("--project-endpoint", required=True)
    parser.add_argument("--model-deployment", default="gpt-4.1")
    parser.add_argument(
        "--mcp-server-url",
        default=os.environ.get("MCP_SERVER_URL", ""),
        help="Full URL to the Halo ITSM MCP server endpoint (via APIM).",
    )
    parser.add_argument(
        "--mcp-server-label",
        default=DEFAULT_MCP_SERVER_LABEL,
        help="Label for the MCP tool in Foundry (default: halo-itsm-mcp).",
    )
    parser.add_argument(
        "--apim-subscription-key",
        default=os.environ.get("APIM_SUBSCRIPTION_KEY", ""),
        help="APIM subscription key for the Halo ITSM API.",
    )
    parser.add_argument(
        "--app-config-endpoint",
        default=os.environ.get("AZURE_APP_CONFIGURATION_ENDPOINT", ""),
        help="Azure App Configuration endpoint for storing agent names.",
    )
    parser.add_argument(
        "--only",
        nargs="+",
        choices=list(AGENT_MODULE_MAP.keys()),
        default=None,
        help="Deploy only the specified agent(s). Omit to deploy all agents.",
    )
    args = parser.parse_args()

    deployer = AgentDeployer(
        project_endpoint=args.project_endpoint,
        model_deployment=args.model_deployment,
        mcp_server_url=args.mcp_server_url or None,
        mcp_server_label=args.mcp_server_label,
        apim_subscription_key=args.apim_subscription_key or None,
        app_config_endpoint=args.app_config_endpoint or None,
    )
    deployer.deploy(only=args.only)


if __name__ == "__main__":
    main()
