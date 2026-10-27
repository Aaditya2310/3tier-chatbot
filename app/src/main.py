"""TriTier ChatOps — FastAPI app tier.

Endpoints:
  GET  /                    -> chat UI (presentation tier, served as static files)
  POST /api/chat            -> answer a message and store it in Postgres
  GET  /api/history/{sid}   -> conversation history for a session
  GET  /health              -> liveness: process is up (no DB check, so a DB blip
                               doesn't make the ALB kill every instance at once)
  GET  /ready               -> readiness: process is up AND the DB answers
  GET  /metrics             -> Prometheus scrape endpoint (blocked at the ALB)
"""
import os
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from pydantic import BaseModel, Field
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from .db import Message, SessionLocal, init_db
from .llm import get_provider

STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")
INSTANCE_ID = os.getenv("INSTANCE_ID", "local")

# --- Prometheus metrics -------------------------------------------------------
REQUESTS = Counter(
    "http_requests_total", "HTTP requests", ["method", "path", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds", "Request latency", ["method", "path"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)
IN_FLIGHT = Gauge("http_requests_in_flight", "Requests currently being served")
CHAT_MESSAGES = Counter("chat_messages_total", "Chat messages answered", ["provider"])
DB_ERRORS = Counter("db_errors_total", "Database errors")


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Retry so the container survives RDS still booting on first deploy.
    for attempt in range(10):
        try:
            init_db()
            break
        except Exception as exc:  # noqa: BLE001
            print(f"DB not ready (attempt {attempt + 1}/10): {exc}", flush=True)
            time.sleep(3)
    yield


app = FastAPI(title="TriTier ChatOps", lifespan=lifespan)
provider = get_provider()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _route_label(request: Request) -> str:
    # Use the route template (/api/history/{session_id}) not the raw path,
    # otherwise every session id becomes a new time series (cardinality blowup).
    route = request.scope.get("route")
    return getattr(route, "path", "unmatched")


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    if request.url.path == "/metrics":
        return await call_next(request)
    IN_FLIGHT.inc()
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        path = _route_label(request)
        LATENCY.labels(request.method, path).observe(time.perf_counter() - start)
        REQUESTS.labels(request.method, path, str(status)).inc()
        IN_FLIGHT.dec()


# --- API ----------------------------------------------------------------------
class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    session_id: str | None = None


class ChatOut(BaseModel):
    session_id: str
    reply: str
    provider: str
    served_by: str


@app.post("/api/chat", response_model=ChatOut)
def chat(body: ChatIn, db: Session = Depends(get_db)):
    sid = body.session_id or str(uuid.uuid4())
    reply = provider.reply(body.message)
    try:
        db.add_all([
            Message(session_id=sid, role="user", content=body.message),
            Message(session_id=sid, role="assistant", content=reply),
        ])
        db.commit()
    except Exception:
        db.rollback()
        DB_ERRORS.inc()
        raise HTTPException(status_code=503, detail="database unavailable")
    CHAT_MESSAGES.labels(provider.name).inc()
    return ChatOut(session_id=sid, reply=reply, provider=provider.name, served_by=INSTANCE_ID)


@app.get("/api/history/{session_id}")
def history(session_id: str, db: Session = Depends(get_db)):
    rows = db.scalars(
        select(Message).where(Message.session_id == session_id).order_by(Message.id)
    ).all()
    return [{"role": m.role, "content": m.content, "at": m.created_at.isoformat()} for m in rows]


@app.get("/health")
def health():
    return {"status": "ok", "instance": INSTANCE_ID}


@app.get("/ready")
def ready(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
    except Exception:
        DB_ERRORS.inc()
        raise HTTPException(status_code=503, detail="database unreachable")
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


# --- Presentation tier ----------------------------------------------------------
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/", include_in_schema=False)
def index():
    return FileResponse(os.path.join(STATIC_DIR, "index.html"))
