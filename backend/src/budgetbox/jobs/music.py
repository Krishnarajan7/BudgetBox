"""The half-hour heartbeat that outruns Spotify's 50-play window. A separate
recorded run (name='music'), so /healthz's daily line stays about the daily."""

from sqlalchemy.orm import Session, sessionmaker

from budgetbox.core.config import settings
from budgetbox.jobs.runner import run_jobs

MUSIC = "music"


def poll_spotify(session: Session) -> str:
    from budgetbox.modules.music import service

    return service.poll(session, settings())


def run_music(factory: sessionmaker[Session]) -> bool:
    return run_jobs(factory, MUSIC, [poll_spotify])
