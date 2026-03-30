from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    environment: str = Field(default="dev")

    # Foundry project
    azure_ai_project_endpoint: str
    azure_ai_model_deployment_name: str = Field(default="gpt-4.1")

    # Azure App Configuration (agent IDs are read from here at startup)
    azure_app_configuration_endpoint: str = Field(default="")

    # Specialist agent IDs — optional when using App Configuration
    kb_lookup_agent_id: str = Field(default="")
    ticket_agent_id: str = Field(default="")
    triage_agent_id: str = Field(default="")

    # Managed identity (optional — auto-detected in Container Apps)
    azure_client_id: str = Field(default="")

    # Halo API (for direct proxy endpoints)
    halo_base_url: str = Field(default="")

    # APIM
    apim_subscription_key: str = Field(default="")
