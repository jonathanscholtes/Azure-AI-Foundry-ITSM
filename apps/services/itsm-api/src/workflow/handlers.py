from typing import Any

from agent_framework import (
    AgentExecutorRequest,
    AgentExecutorResponse,
    Message,
    WorkflowContext,
    executor,
)

from .models import ClassificationResult


def get_intent_case(expected_intent: str):
    """Factory for switch-case condition predicates."""

    def condition(message: Any) -> bool:
        if not isinstance(message, AgentExecutorResponse):
            return False
        try:
            result = ClassificationResult.model_validate_json(
                message.agent_response.text
            )
            return result.intent == expected_intent
        except Exception:
            return False

    return condition


async def _forward_to_specialist(
    response: AgentExecutorResponse, ctx: WorkflowContext[AgentExecutorRequest]
) -> None:
    """Shared logic: extract user message and forward to the specialist agent."""
    result = ClassificationResult.model_validate_json(response.agent_response.text)
    await ctx.send_message(
        AgentExecutorRequest(
            messages=[Message(role="user", contents=[result.user_message])],
            should_respond=True,
        )
    )


@executor(id="to_kb_lookup")
async def to_kb_lookup(
    response: AgentExecutorResponse, ctx: WorkflowContext[AgentExecutorRequest]
) -> None:
    """Transform classifier output into a request for the KB Lookup agent."""
    await _forward_to_specialist(response, ctx)


@executor(id="to_ticket_agent")
async def to_ticket_agent(
    response: AgentExecutorResponse, ctx: WorkflowContext[AgentExecutorRequest]
) -> None:
    """Transform classifier output into a request for the Ticket agent."""
    await _forward_to_specialist(response, ctx)


@executor(id="to_triage_agent")
async def to_triage_agent(
    response: AgentExecutorResponse, ctx: WorkflowContext[AgentExecutorRequest]
) -> None:
    """Transform classifier output into a request for the Triage agent."""
    await _forward_to_specialist(response, ctx)


@executor(id="finalize")
async def finalize(
    response: AgentExecutorResponse, ctx: WorkflowContext[None, str]
) -> None:
    """Yield the specialist agent's response as workflow output."""
    await ctx.yield_output(response.agent_response.text)


@executor(id="general_handler")
async def general_handler(
    response: AgentExecutorResponse, ctx: WorkflowContext[None, str]
) -> None:
    """Default case — provide a helpful message for unclassified intents."""
    result = ClassificationResult.model_validate_json(response.agent_response.text)
    await ctx.yield_output(
        "I can help with knowledge base lookups, ticket operations, and issue "
        f"triage. You said: {result.user_message}"
    )
