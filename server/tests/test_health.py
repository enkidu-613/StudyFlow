from fastapi.testclient import TestClient

from server.app.main import app, create_app


def test_liveness_is_available_without_database() -> None:
    response = TestClient(app).get("/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readiness_reports_database_configuration_message(
    monkeypatch,
) -> None:
    monkeypatch.delenv("STUDYFLOW_DATABASE_URL", raising=False)

    response = TestClient(create_app()).get("/health/ready")

    assert response.status_code == 503
    assert response.json()["database"] == "not_configured"
    assert "STUDYFLOW_DATABASE_URL is not set" in response.json()["message"]
