import os

os.environ["DATABASE_URL"] = "sqlite:///./test.db"

from fastapi.testclient import TestClient  # noqa: E402

from src.main import app  # noqa: E402


def client():
    return TestClient(app)


def test_health_and_ready():
    with client() as c:
        assert c.get("/health").json()["status"] == "ok"
        assert c.get("/ready").status_code == 200


def test_chat_persists_history():
    with client() as c:
        r = c.post("/api/chat", json={"message": "what is a NAT?"})
        assert r.status_code == 200
        body = r.json()
        assert "NAT" in body["reply"]
        hist = c.get(f"/api/history/{body['session_id']}").json()
        assert [m["role"] for m in hist] == ["user", "assistant"]


def test_validation_rejects_empty_message():
    with client() as c:
        assert c.post("/api/chat", json={"message": ""}).status_code == 422


def test_metrics_use_route_template_not_raw_path():
    with client() as c:
        c.get("/api/history/abc-123")
        text = c.get("/metrics").text
        assert 'path="/api/history/{session_id}"' in text
        assert "abc-123" not in text


def test_index_served():
    with client() as c:
        assert "TriTier ChatOps" in c.get("/").text
