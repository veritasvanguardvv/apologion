"""Basic tests for the leaderboard server.  Run:  pytest server/test_app.py"""
import pytest

from app import create_app


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("APOLOGION_ADMIN_TOKEN", "secret")
    app = create_app(str(tmp_path / "test.db"))
    return app.test_client()


def test_seeded_churches_and_search(client):
    names = [c["name"] for c in client.get("/churches").get_json()["churches"]]
    assert "Christ's Church on the Move" in names and "FPC Haines City" in names
    found = client.get("/churches?search=christ church").get_json()["churches"]
    assert [c["id"] for c in found] == ["christs-church-on-the-move"]
    assert client.get("/churches?search=haines").get_json()["churches"][0]["city"] == "Haines City"


def test_submission_needs_approval(client):
    r = client.post("/churches", json={"name": "Grace Chapel", "city": "Austin", "region": "Texas", "country": "USA"})
    assert r.status_code == 201 and r.get_json()["church"]["approved"] is False
    assert client.get("/churches?search=grace").get_json()["churches"] == []
    assert client.post("/admin/churches/grace-chapel-austin/approve").status_code == 403
    client.post("/admin/churches/grace-chapel-austin/approve", headers={"X-Admin-Token": "secret"})
    assert len(client.get("/churches?search=grace").get_json()["churches"]) == 1
    assert client.post("/churches", json={"name": "x"}).status_code == 400


def test_scores_limits_and_leaderboards(client):
    a = client.post("/players", json={"name": "Ana", "church_id": "fpc-haines-city"}).get_json()["player"]
    b = client.post("/players", json={"name": "Ben", "church_id": "christs-church-on-the-move"}).get_json()["player"]
    assert client.post("/scores", json={"player_id": a["id"], "token": a["token"], "delta": 30}).get_json()["total"] == 30
    client.post("/scores", json={"player_id": b["id"], "token": b["token"], "delta": 12})
    # sanity limits
    assert client.post("/scores", json={"player_id": a["id"], "token": a["token"], "delta": 51}).status_code == 400
    assert client.post("/scores", json={"player_id": a["id"], "token": a["token"], "delta": 0}).status_code == 400
    assert client.post("/scores", json={"player_id": a["id"], "token": "wrong", "delta": 5}).status_code == 403
    for scope, extra in [("state", "&region=florida&country=usa"), ("country", "&country=USA"), ("world", "")]:
        churches = client.get(f"/leaderboard?scope={scope}&type=church{extra}").get_json()["entries"]
        assert [(e["name"], e["score"]) for e in churches] == [("FPC Haines City", 30), ("Christ's Church on the Move", 12)]
        players = client.get(f"/leaderboard?scope={scope}&type=player{extra}").get_json()["entries"]
        assert [p["name"] for p in players] == ["Ana", "Ben"]
    assert client.get("/leaderboard?scope=state&type=church&region=texas&country=usa").get_json()["entries"] == []
    # updating the player's church needs the token
    assert client.post("/players", json={"id": a["id"], "token": "nope", "name": "Ana"}).status_code == 403


def test_daily_cap(client):
    p = client.post("/players", json={"name": "Speedy"}).get_json()["player"]
    for _ in range(20):
        client.post("/scores", json={"player_id": p["id"], "token": p["token"], "delta": 50})
    r = client.post("/scores", json={"player_id": p["id"], "token": p["token"], "delta": 1})
    assert r.status_code == 429
