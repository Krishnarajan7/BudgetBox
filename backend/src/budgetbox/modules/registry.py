"""The one place that knows every module. Imports each module's models (so
Base.metadata and Alembic see the full schema) and collects every router.
Owned by the orchestrator: parallel feature work never edits this file."""

import importlib

from fastapi import APIRouter

_MODEL_MODULES = [
    "budgetbox.modules.tokens.models",
    "budgetbox.modules.categories.models",
    "budgetbox.modules.accounts.models",
    "budgetbox.modules.transactions.models",
    "budgetbox.modules.settings.models",
    "budgetbox.modules.recurring.models",
    "budgetbox.modules.goals.models",
    "budgetbox.modules.budgets.models",
    "budgetbox.modules.networth.models",
    "budgetbox.modules.notes.models",
    "budgetbox.modules.focus.models",
    "budgetbox.modules.journal.models",
    "budgetbox.modules.events.models",
    "budgetbox.modules.vault.models",
]

_ROUTER_MODULES: list[str] = [
    "budgetbox.modules.categories.router",
    "budgetbox.modules.accounts.router",
    "budgetbox.modules.transactions.router",
    "budgetbox.modules.settings.router",
    "budgetbox.modules.summary.router",
    "budgetbox.modules.recurring.router",
    "budgetbox.modules.budgets.router",
    "budgetbox.modules.goals.router",
    "budgetbox.modules.networth.router",
    "budgetbox.modules.insights.router",
    "budgetbox.modules.changes.router",
    "budgetbox.modules.export.router",
    "budgetbox.modules.notes.router",
    "budgetbox.modules.focus.router",
    "budgetbox.modules.journal.router",
    "budgetbox.modules.events.router",
    "budgetbox.modules.vault.router",
]


def import_all_models() -> None:
    """Populate Base.metadata with the full schema (Alembic and app startup)."""
    for module in _MODEL_MODULES:
        importlib.import_module(module)


def all_routers() -> list[APIRouter]:
    """Routers mounted under /v1 (auth applied by the app factory)."""
    routers: list[APIRouter] = []
    for module in _ROUTER_MODULES:
        routers.append(importlib.import_module(module).router)
    return routers
