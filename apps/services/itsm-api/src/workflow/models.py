from typing import Literal

from pydantic import BaseModel


class ClassificationResult(BaseModel):
    """Structured output from the classifier agent."""

    intent: Literal["kb_lookup", "ticket", "kb_and_ticket", "triage", "general"]
    reason: str
    user_message: str  # Pass through for downstream agents


class AgentResult(BaseModel):
    """Structured output from specialist agents."""

    response: str
