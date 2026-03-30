from agent_framework import Agent
from agent_framework.azure import AzureAIAgentClient

from .models import ClassificationResult

CLASSIFIER_INSTRUCTIONS = """\
You are an intent classifier for an IT Service Desk. Classify the user's \
request into exactly one of the following intents:

- kb_lookup: Questions about how to do something, troubleshooting steps, \
documentation lookups, "how do I" questions
- ticket: Requests to search, view, create, or update support tickets
- triage: Requests to classify, prioritize, assign, escalate, or route an \
issue or ticket to a team
- general: Greetings, meta-questions about your capabilities, or anything \
that does not fit the above categories

Return JSON with fields: intent, reason, user_message (echo the original \
message exactly).
"""


def create_classifier(client: AzureAIAgentClient) -> Agent:
    """Create the intent classifier — runs locally, not deployed to Foundry."""
    return client.as_agent(
        name="Classifier",
        instructions=CLASSIFIER_INSTRUCTIONS,
        response_format=ClassificationResult,
    )
