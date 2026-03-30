from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    message: str
    session_id: str = Field(default="")


class ChatEvent(BaseModel):
    event: str
    agent: str = Field(default="")
    text: str = Field(default="")
    status: str = Field(default="")


class HealthResponse(BaseModel):
    status: str = "ok"
    environment: str = ""
