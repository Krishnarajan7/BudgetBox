from collections.abc import Iterator

from fastapi import Request
from sqlalchemy import Engine
from sqlalchemy.orm import Session, sessionmaker


def make_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(engine, expire_on_commit=False)


def get_session(request: Request) -> Iterator[Session]:
    """Session-per-request. Services call session.begin() to own their transactions."""
    factory: sessionmaker[Session] = request.app.state.session_factory
    with factory() as session:
        yield session
