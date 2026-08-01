"""Notes: idempotent upsert, pinned-first listing, archive-as-delete."""

from typing import Any

import time_machine
from fastapi.testclient import TestClient

from budgetbox.core.ids import new_id


def make_note(client: TestClient, note_id: str | None = None, **overrides: Any) -> str:
    note_id = note_id or new_id()
    body: dict[str, Any] = {"title": "Groceries", "body": "milk, eggs", **overrides}
    resp = client.put(f"/v1/notes/{note_id}", json=body)
    assert resp.status_code == 200, resp.text
    return note_id


def titles(client: TestClient, **params: Any) -> list[str]:
    resp = client.get("/v1/notes", params=params)
    assert resp.status_code == 200, resp.text
    return [n["title"] for n in resp.json()]


def test_upsert_creates_then_replaces_in_place(client: TestClient) -> None:
    note_id = new_id()
    created = client.put(f"/v1/notes/{note_id}", json={"title": "Draft"}).json()
    assert (created["id"], created["title"]) == (note_id, "Draft")
    assert (created["body"], created["pinned"], created["archived"]) == ("", False, False)

    replaced = client.put(
        f"/v1/notes/{note_id}", json={"title": "Packing list", "body": "socks", "pinned": True}
    )
    assert replaced.status_code == 200
    assert replaced.json()["body"] == "socks"
    assert replaced.json()["created_at"] == created["created_at"]
    assert len(client.get("/v1/notes").json()) == 1  # replaced, not duplicated


def test_upsert_is_idempotent(client: TestClient) -> None:
    note_id = new_id()
    body = {"title": "Wifi", "body": "router in the hall", "pinned": True}
    first = client.put(f"/v1/notes/{note_id}", json=body).json()
    second = client.put(f"/v1/notes/{note_id}", json=body).json()
    assert first == second
    assert len(client.get("/v1/notes").json()) == 1


def test_list_orders_pinned_first_then_most_recently_updated(client: TestClient) -> None:
    with time_machine.travel("2026-07-10T10:00:00+05:30", tick=False):
        oldest = make_note(client, title="Oldest")
    with time_machine.travel("2026-07-10T10:01:00+05:30", tick=False):
        make_note(client, title="Middle")
    with time_machine.travel("2026-07-10T10:02:00+05:30", tick=False):
        make_note(client, title="Pinned", pinned=True)
    with time_machine.travel("2026-07-10T10:03:00+05:30", tick=False):
        assert client.patch(f"/v1/notes/{oldest}", json={"body": "touched"}).status_code == 200

    # Pinned wins outright; the touched note then outranks the one it used to trail.
    assert titles(client) == ["Pinned", "Oldest", "Middle"]


def test_archived_notes_are_hidden_unless_asked_for(client: TestClient) -> None:
    kept = make_note(client, title="Keep")
    gone = make_note(client, title="Done with this")
    assert client.patch(f"/v1/notes/{gone}", json={"archived": True}).json()["archived"] is True

    assert titles(client) == ["Keep"]
    assert sorted(titles(client, include_archived=True)) == ["Done with this", "Keep"]

    # Un-archiving brings it back, and a plain save never resurrects it on its own.
    client.patch(f"/v1/notes/{gone}", json={"archived": False})
    assert sorted(titles(client)) == ["Done with this", "Keep"]
    assert kept in [n["id"] for n in client.get("/v1/notes").json()]


def test_upsert_leaves_archived_alone(client: TestClient) -> None:
    note_id = make_note(client, title="Shelved")
    client.patch(f"/v1/notes/{note_id}", json={"archived": True})
    resaved = client.put(f"/v1/notes/{note_id}", json={"title": "Shelved", "body": "edited"})
    assert resaved.json()["archived"] is True
    assert titles(client) == []


def test_patch_touches_only_the_fields_sent(client: TestClient) -> None:
    note_id = make_note(client, title="Recipe", body="dal, rice", pinned=True)
    patched = client.patch(f"/v1/notes/{note_id}", json={"body": "dal, rice, ghee"})
    assert patched.status_code == 200, patched.text
    note = patched.json()
    assert (note["title"], note["body"]) == ("Recipe", "dal, rice, ghee")
    assert (note["pinned"], note["archived"]) == (True, False)
    assert note["updated_at"] >= note["created_at"]


def test_patch_unknown_note_is_a_not_found_problem(client: TestClient) -> None:
    resp = client.patch(f"/v1/notes/{new_id()}", json={"title": "ghost"})
    assert resp.status_code == 404
    assert resp.headers["content-type"].startswith("application/problem+json")
    assert resp.json()["type"] == "urn:budgetbox:problem:not-found"


def test_title_over_the_limit_is_rejected(client: TestClient) -> None:
    resp = client.put(f"/v1/notes/{new_id()}", json={"title": "x" * 201})
    assert resp.status_code == 422
    assert resp.json()["type"] == "urn:budgetbox:problem:validation-error"


def test_notes_show_up_in_the_changes_feed(client: TestClient) -> None:
    note_id = make_note(client, title="Tracked")
    changed = client.get("/v1/changes", params={"since": "2026-01-01T00:00:00+00:00"}).json()
    assert changed["changed"]["notes"] == [note_id]
