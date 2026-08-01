from fastapi import APIRouter, Response

from budgetbox.api.deps import SessionDep
from budgetbox.modules.export.csv_export import txns_csv

router = APIRouter(prefix="/export", tags=["export"])


@router.get("/txns.csv")
def export_txns(session: SessionDep) -> Response:
    return Response(
        content=txns_csv(session),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="budgetbox-txns.csv"'},
    )
