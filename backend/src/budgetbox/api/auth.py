import time
from typing import Annotated

import structlog
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from budgetbox.core.errors import Unauthorized
from budgetbox.db.session import get_session
from budgetbox.modules.tokens import service as tokens
from budgetbox.modules.tokens.models import DeviceToken

log = structlog.get_logger()

_bearer = HTTPBearer(auto_error=False)


def require_device(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    session: Annotated[Session, Depends(get_session)],
) -> DeviceToken:
    """Single-user auth: a valid, unrevoked device token. Failures get a small
    tarpit sleep and a log line with the source address."""
    if credentials is not None:
        token = tokens.authenticate(session, credentials.credentials)
        if token is not None:
            return token
    client = request.client.host if request.client else "unknown"
    log.warning("auth_failed", client=client, path=request.url.path)
    time.sleep(0.15)
    raise Unauthorized("Missing or invalid device token.")
