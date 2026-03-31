import json
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import StreamingResponse

from .config import Settings
from .models import ChatRequest, HealthResponse
from .workflow.pipeline import build_itsm_workflow, init_workflow

logger = logging.getLogger(__name__)

settings = Settings()
_internal_agents: set[str] = set()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _internal_agents
    logger.info("Initialising ITSM workflow...")
    _internal_agents = init_workflow()
    logger.info("Workflow ready  (internal agents hidden from UI: %s)", _internal_agents)
    yield
    logger.info("Shutting down")


app = FastAPI(
    title="ITSM Service Desk API",
    version="0.1.0",
    lifespan=lifespan,
)


async def stream_workflow(message: str):
    yield json.dumps({"event": "progress", "agent": "classifier", "status": "running"}) + "\n"
    try:
        wf = build_itsm_workflow()
        async for event in wf.run(message, stream=True):
            if hasattr(event, "data") and hasattr(event.data, "author_name"):
                # Skip internal agents (e.g. classifier) whose output is not user-facing
                if event.data.author_name in _internal_agents:
                    continue
                yield json.dumps({
                    "event": "progress",
                    "agent": event.data.author_name or "",
                    "text": event.data.text or "",
                }) + "\n"
        yield json.dumps({"event": "complete"}) + "\n"
    except Exception:
        logger.exception("Workflow error")
        yield json.dumps({"event": "error", "text": "An error occurred processing your request."}) + "\n"


@app.post("/chat")
async def chat(request: ChatRequest):
    return StreamingResponse(
        stream_workflow(message=request.message),
        media_type="application/x-ndjson",
        headers={"X-Accel-Buffering": "no"},
    )


@app.get("/health")
async def health() -> HealthResponse:
    return HealthResponse(status="ok", environment=settings.environment)
