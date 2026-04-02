import json
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
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

cors_allowed_origins = [origin.strip() for origin in settings.cors_allowed_origins.split(",") if origin.strip()]
if not cors_allowed_origins:
    cors_allowed_origins = ["*"]

# CORS — allow the embeddable widget to call from any origin
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_allowed_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def stream_workflow(message: str):
    yield json.dumps({"event": "progress", "agent": "classifier", "status": "running"}) + "\n"
    try:
        wf = build_itsm_workflow()
        async for event in wf.run(message, stream=True):
            # "output" events come from finalize/general_handler via yield_output — the final answer
            if getattr(event, "type", None) == "output" and isinstance(event.data, str):
                yield json.dumps({
                    "event": "progress",
                    "agent": event.executor_id or "",
                    "text": event.data,
                }) + "\n"
            # "data" events are intermediate agent streaming updates
            elif hasattr(event, "data") and hasattr(event.data, "author_name"):
                # Skip internal agents (e.g. classifier) whose output is not user-facing
                if event.data.author_name in _internal_agents:
                    continue
                # Skip intermediate streaming fragments — only forward if this is
                # the specialist agent's text (non-empty, non-tool-call content)
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
