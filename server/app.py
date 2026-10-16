"""Apologion leaderboard server (Flask + SQLite).

A tiny REST API for churches and "enemies defeated" leaderboards.
Run locally:   pip install -r requirements.txt   then   python app.py
(see README.md for deploying it for free on PythonAnywhere)

Endpoints
  GET  /health
  GET  /churches?search=text            approved churches matching the text
  POST /churches                        submit a church (waits for moderation)
  POST /players                         create (or update) a player -> id + token
  POST /scores                          add enemies defeated (delta) for a player
  GET  /leaderboard?scope=state|country|world&region=&country=&type=church|player
  GET  /admin/churches/pending          (needs header X-Admin-Token)
  POST /admin/churches/<id>/approve     (needs header X-Admin-Token)
"""
import os
import re
import secrets
import sqlite3
from pathlib import Path

from flask import Flask, g, jsonify, request

HERE = Path(__file__).resolve().parent

# ---- Anti-cheat sanity limits (change to taste) ----
MAX_DELTA_PER_POST = 50        # the game sends at most 50 defeats per request
MAX_DEFEATS_PER_DAY = 1000     # per player, per UTC day (a long play day is ~100-300)
MAX_POSTS_PER_HOUR = 120       # per player
MAX_CHURCH_SUBMISSIONS_PER_DAY = 5   # per IP address
NAME_MAX = 20


def create_app(db_path=None):
    app = Flask(__name__)
    app.config["DB_PATH"] = db_path or os.environ.get("APOLOGION_DB", str(HERE / "apologion.db"))
    app.config["ADMIN_TOKEN"] = os.environ.get("APOLOGION_ADMIN_TOKEN", "")

    def db():
        if "db" not in g:
            g.db = sqlite3.connect(app.config["DB_PATH"])
            g.db.row_factory = sqlite3.Row
            g.db.execute("PRAGMA foreign_keys = ON")
        return g.db

    @app.teardown_appcontext
    def close_db(_exc):
        conn = g.pop("db", None)
        if conn is not None:
            conn.close()

    with app.app_context():
        db().executescript((HERE / "schema.sql").read_text(encoding="utf-8"))
        db().commit()

    def error(message, code=400):
        return jsonify({"error": message}), code

    def body():
        data = request.get_json(silent=True)
        return data if isinstance(data, dict) else {}

    def clean(text, limit):
        text = re.sub(r"[\x00-\x1f<>]", "", str(text or "")).strip()
        return text[:limit]

    def church_json(row):
        return {"id": row["id"], "name": row["name"], "city": row["city"], "region": row["region"],
                "country": row["country"], "approved": bool(row["approved"])}

    def words(text):
        return re.findall(r"\w+", str(text).lower().replace("'", "").replace("\u2019", ""))

    @app.after_request
    def allow_cors(resp):
        resp.headers["Access-Control-Allow-Origin"] = "*"
        resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
        return resp

    @app.get("/health")
    def health():
        return jsonify({"ok": True})

    # ---------------- Churches ----------------

    @app.get("/churches")
    def list_churches():
        typed = words(request.args.get("search", ""))
        rows = db().execute("SELECT * FROM churches WHERE approved = 1 ORDER BY name").fetchall()
        result = []
        for row in rows:
            church_words = words(row["name"] + " " + row["city"])
            # every typed word must start a word of the name/city ("christ church" finds "Christ's Church...")
            if all(any(w.startswith(t) for w in church_words) for t in typed):
                result.append(church_json(row))
        return jsonify({"churches": result[:50]})

    @app.post("/churches")
    def submit_church():
        data = body()
        name = clean(data.get("name"), 80)
        city = clean(data.get("city"), 60)
        region = clean(data.get("region"), 60)
        country = clean(data.get("country"), 60)
        if len(name) < 3 or not city or not country:
            return error("name (3+ letters), city and country are required")
        ip = request.headers.get("X-Forwarded-For", request.remote_addr or "").split(",")[0].strip()
        recent = db().execute(
            "SELECT COUNT(*) FROM churches WHERE submitter_ip = ? AND created_at > datetime('now', '-1 day')", (ip,)
        ).fetchone()[0]
        if recent >= MAX_CHURCH_SUBMISSIONS_PER_DAY:
            return error("too many submissions today", 429)
        # Already there (same name + city)? Return that one instead of a duplicate.
        same = db().execute("SELECT * FROM churches WHERE lower(name) = lower(?) AND lower(city) = lower(?)", (name, city)).fetchone()
        if same:
            return jsonify({"church": church_json(same)}), 200
        base = "-".join(words(name + " " + city))[:60] or "church"
        church_id, n = base, 2
        while db().execute("SELECT 1 FROM churches WHERE id = ?", (church_id,)).fetchone():
            church_id, n = f"{base}-{n}", n + 1
        db().execute("INSERT INTO churches (id, name, city, region, country, approved, submitter_ip) VALUES (?,?,?,?,?,0,?)",
                     (church_id, name, city, region, country, ip))
        db().commit()
        row = db().execute("SELECT * FROM churches WHERE id = ?", (church_id,)).fetchone()
        return jsonify({"church": church_json(row)}), 201

    # ---------------- Players ----------------

    @app.post("/players")
    def upsert_player():
        data = body()
        name = clean(data.get("name"), NAME_MAX) or "Player"
        church_id = clean(data.get("church_id"), 80) or None
        if church_id and not db().execute("SELECT 1 FROM churches WHERE id = ?", (church_id,)).fetchone():
            return error("unknown church", 404)
        if data.get("id"):
            row = db().execute("SELECT * FROM players WHERE id = ?", (data.get("id"),)).fetchone()
            if not row or not secrets.compare_digest(row["token"], str(data.get("token", ""))):
                return error("wrong player id or token", 403)
            db().execute("UPDATE players SET name = ?, church_id = ? WHERE id = ?", (name, church_id, row["id"]))
            db().commit()
            return jsonify({"player": {"id": row["id"], "name": name, "church_id": church_id, "total": row["total"]}})
        token = secrets.token_hex(16)
        cur = db().execute("INSERT INTO players (token, name, church_id) VALUES (?,?,?)", (token, name, church_id))
        db().commit()
        return jsonify({"player": {"id": cur.lastrowid, "token": token, "name": name, "church_id": church_id, "total": 0}}), 201

    # ---------------- Scores ----------------

    @app.post("/scores")
    def add_score():
        data = body()
        row = db().execute("SELECT * FROM players WHERE id = ?", (data.get("player_id"),)).fetchone()
        if not row or not secrets.compare_digest(row["token"], str(data.get("token", ""))):
            return error("wrong player id or token", 403)
        delta = data.get("delta")
        if not isinstance(delta, int) or isinstance(delta, bool) or delta < 1 or delta > MAX_DELTA_PER_POST:
            return error(f"delta must be a whole number from 1 to {MAX_DELTA_PER_POST}")
        today = db().execute(
            "SELECT COALESCE(SUM(delta), 0) FROM scores WHERE player_id = ? AND date(created_at) = date('now')", (row["id"],)
        ).fetchone()[0]
        if today + delta > MAX_DEFEATS_PER_DAY:
            return error("daily limit reached", 429)
        posts = db().execute(
            "SELECT COUNT(*) FROM scores WHERE player_id = ? AND created_at > datetime('now', '-1 hour')", (row["id"],)
        ).fetchone()[0]
        if posts >= MAX_POSTS_PER_HOUR:
            return error("too many requests", 429)
        db().execute("INSERT INTO scores (player_id, delta) VALUES (?, ?)", (row["id"], delta))
        db().execute("UPDATE players SET total = total + ? WHERE id = ?", (delta, row["id"]))
        db().commit()
        return jsonify({"ok": True, "total": row["total"] + delta})

    # ---------------- Leaderboards ----------------

    @app.get("/leaderboard")
    def leaderboard():
        scope = request.args.get("scope", "world")
        kind = request.args.get("type", "church")
        region = request.args.get("region", "").strip().lower()
        country = request.args.get("country", "").strip().lower()
        limit = min(max(int(request.args.get("limit", 50) or 50), 1), 100)
        if scope not in ("state", "country", "world") or kind not in ("church", "player"):
            return error("scope must be state|country|world and type church|player")
        where, args = [], []
        if scope == "state":
            if not region or not country:
                return error("region and country are needed for scope=state")
            where.append("lower(trim(c.region)) = ? AND lower(trim(c.country)) = ?")
            args += [region, country]
        elif scope == "country":
            if not country:
                return error("country is needed for scope=country")
            where.append("lower(trim(c.country)) = ?")
            args.append(country)
        filters = (" AND " + " AND ".join(where)) if where else ""
        if kind == "church":
            sql = ("SELECT c.name AS name, c.city AS detail, SUM(p.total) AS score FROM churches c "
                   "JOIN players p ON p.church_id = c.id WHERE c.approved = 1" + filters +
                   " GROUP BY c.id HAVING score > 0 ORDER BY score DESC, c.name LIMIT ?")
        else:
            sql = ("SELECT p.name AS name, COALESCE(c.name, '') AS detail, p.total AS score FROM players p "
                   "LEFT JOIN churches c ON c.id = p.church_id WHERE p.total > 0" + filters +
                   " ORDER BY score DESC, p.id LIMIT ?")
        rows = db().execute(sql, args + [limit]).fetchall()
        entries = [{"rank": i + 1, "name": r["name"], "detail": r["detail"], "score": r["score"]} for i, r in enumerate(rows)]
        return jsonify({"scope": scope, "type": kind, "entries": entries})

    # ---------------- Moderation ----------------

    def is_admin():
        token = app.config["ADMIN_TOKEN"]
        return bool(token) and secrets.compare_digest(request.headers.get("X-Admin-Token", ""), token)

    @app.get("/admin/churches/pending")
    def pending_churches():
        if not is_admin():
            return error("admin only", 403)
        rows = db().execute("SELECT * FROM churches WHERE approved = 0 ORDER BY created_at").fetchall()
        return jsonify({"churches": [church_json(r) for r in rows]})

    @app.post("/admin/churches/<church_id>/approve")
    def approve_church(church_id):
        if not is_admin():
            return error("admin only", 403)
        db().execute("UPDATE churches SET approved = 1 WHERE id = ?", (church_id,))
        db().commit()
        return jsonify({"ok": True})

    return app


app = create_app()   # PythonAnywhere / gunicorn look for "app"

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.environ.get("PORT", 5000)))
