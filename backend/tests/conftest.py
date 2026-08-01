from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from budgetbox.api.app import create_app
from budgetbox.core.config import Settings
from budgetbox.db.migrate import upgrade_to_head
from budgetbox.modules.tokens import service as token_service


@pytest.fixture
def app(tmp_path: Path) -> FastAPI:
    """Fresh database per test, schema built via the real migration chain —
    every test run validates migrations from empty."""
    cfg = Settings(env="dev", db_path=tmp_path / "test.db", log_level="WARNING")
    upgrade_to_head(cfg.db_url)
    return create_app(cfg)


@pytest.fixture
def session(app: FastAPI) -> Iterator[Session]:
    with app.state.session_factory() as s:
        yield s


@pytest.fixture
def token(app: FastAPI) -> str:
    with app.state.session_factory() as s:
        _, raw = token_service.issue(s, "test-device")
    return raw


@pytest.fixture
def client(app: FastAPI, token: str) -> TestClient:
    """Authenticated client — the common case."""
    c = TestClient(app)
    c.headers["Authorization"] = f"Bearer {token}"
    return c


@pytest.fixture
def anon_client(app: FastAPI) -> TestClient:
    return TestClient(app, raise_server_exceptions=False)
