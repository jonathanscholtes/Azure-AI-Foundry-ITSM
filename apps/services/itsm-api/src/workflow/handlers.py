import asyncio
from typing import Any

from agent_framework import (
    Agent,
    AgentExecutorRequest,
    AgentExecutorResponse,
    Message,
    WorkflowContext,
    executor,
)
from agent_framework.azure import AzureAIClient

from .models import ClassificationResult


# Set by pipeline.py at init time so the kb_and_ticket handler can call both agents
_kb_and_ticket_config: dict = {}


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


@executor(id="to_kb_and_ticket")
async def to_kb_and_ticket(
    response: AgentExecutorResponse, ctx: WorkflowContext[None, str]
) -> None:
    """Fan-out: call both KB lookup and ticket agents, combine results."""
    result = ClassificationResult.model_validate_json(response.agent_response.text)
    user_msg = result.user_message

    cfg = _kb_and_ticket_config
    credential = cfg["credential"]
    endpoint = cfg["project_endpoint"]
    kb_name = cfg["kb_agent_name"]
    ticket_name = cfg["ticket_agent_name"]

    kb_agent = Agent(
        client=AzureAIClient(
            project_endpoint=endpoint,
            credential=credential,
            agent_name=kb_name,
            use_latest_version=True,
        ),
        name=kb_name,
    )
    ticket_agent = Agent(
        client=AzureAIClient(
            project_endpoint=endpoint,
            credential=credential,
            agent_name=ticket_name,
            use_latest_version=True,
        ),
        name=ticket_name,
    )

    # Run both agents concurrently
    kb_result, ticket_result = await asyncio.gather(
        kb_agent.run(messages=[Message(role="user", contents=[user_msg])]),
        ticket_agent.run(messages=[Message(role="user", contents=[user_msg])]),
        return_exceptions=True,
    )

    parts: list[str] = []
    if not isinstance(kb_result, Exception):
        kb_text = (kb_result.text or "").strip() if kb_result else ""
        if kb_text and "unable to find" not in kb_text.lower():
            parts.append(f"**Knowledge Base Results:**\n\n{kb_text}")
    if not isinstance(ticket_result, Exception):
        ticket_text = (ticket_result.text or "").strip() if ticket_result else ""
        if ticket_text:
            parts.append(f"**Ticket System Results:**\n\n{ticket_text}")

    if parts:
        await ctx.yield_output("\n\n---\n\n".join(parts))
    else:
        await ctx.yield_output("No results found in the knowledge base or ticket system.")


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
