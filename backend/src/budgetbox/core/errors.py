"""Domain error hierarchy. Every error carries a stable slug the client can switch on;
the API layer maps these to RFC 9457 problem+json responses."""


class DomainError(Exception):
    slug: str = "domain-error"
    status: int = 422
    title: str = "Domain rule violated"

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


class NotFound(DomainError):
    slug = "not-found"
    status = 404
    title = "Not found"


class Conflict(DomainError):
    slug = "conflict"
    status = 409
    title = "Conflict"


class Invalid(DomainError):
    slug = "invalid"
    status = 422
    title = "Invalid request"


class Unauthorized(DomainError):
    slug = "unauthorized"
    status = 401
    title = "Unauthorized"
