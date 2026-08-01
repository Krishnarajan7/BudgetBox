import logging

import structlog


def configure_logging(*, env: str, level: str) -> None:
    """JSON lines in prod (journalctl | jq), pretty console in dev. Never log bodies."""
    logging.basicConfig(level=level.upper(), format="%(message)s")

    renderer: structlog.typing.Processor
    if env == "prod":
        renderer = structlog.processors.JSONRenderer()
    else:
        renderer = structlog.dev.ConsoleRenderer()

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            logging.getLevelNamesMapping()[level.upper()]
        ),
        cache_logger_on_first_use=True,
    )
