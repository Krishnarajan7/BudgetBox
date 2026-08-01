"""Job harness: every job is a catch-up (safe to rerun, self-heals after downtime).
Each run is recorded in job_runs; /healthz surfaces the latest daily run."""

from collections.abc import Callable

import structlog
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from budgetbox.core.ids import new_id
from budgetbox.core.time import now_utc
from budgetbox.modules.recurring.models import JobRun

log = structlog.get_logger()

Job = Callable[[Session], str]


def run_jobs(factory: sessionmaker[Session], name: str, jobs: list[Job]) -> bool:
    """Run jobs sequentially in one recorded run. Returns True when all succeeded."""
    with factory() as session:
        run = JobRun(id=new_id(), name=name, started_at=now_utc())
        session.add(run)
        session.commit()

        details: list[str] = []
        ok = True
        for job in jobs:
            try:
                details.append(job(session))
            except Exception:
                log.exception("job_failed", job=job.__name__)
                details.append(f"{job.__name__}: FAILED")
                ok = False
                session.rollback()
        run.finished_at = now_utc()
        run.ok = ok
        run.detail = "; ".join(details)[:500]
        session.commit()
        log.info("jobs_done", name=name, ok=ok, detail=run.detail)
        return ok


def last_run(session: Session, name: str) -> JobRun | None:
    stmt = select(JobRun).where(JobRun.name == name).order_by(JobRun.started_at.desc()).limit(1)
    return session.scalar(stmt)
