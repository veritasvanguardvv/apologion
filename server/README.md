# Apologion leaderboard server (not deployed yet)

A tiny REST API for **churches** and **"enemies defeated" leaderboards**.
Stack: **Python + Flask + SQLite** (one file database, no separate database server).

The game works without it: `online/enabled` is `false` in Project Settings, so
the game uses its offline `LocalBackend`. This folder has a `.gdignore`, so Godot
ignores it (it's not part of the game export).

## Why Flask + SQLite?
- One small Python file (`app.py`) + one SQL file (`schema.sql`), easy to read.
- SQLite = just a file, so it runs on **PythonAnywhere's free plan**, which keeps
  files on disk between restarts (many free hosts wipe the disk, e.g. Render's
  free web services, so SQLite would lose the leaderboard there).
- When it outgrows that, switch to Postgres (same SQL, almost no changes).

## Run it on your computer
```bash
cd server
python -m venv venv
venv\Scripts\activate          # Windows   (Mac/Linux: source venv/bin/activate)
pip install -r requirements.txt
python app.py                  # -> http://127.0.0.1:5000
```
Then in Godot: Project Settings > Online > **Enabled** = on,
**Base Url** = `http://127.0.0.1:5000`, and play. (Turn it off again for normal play.)

Run the tests: `pip install pytest` then `pytest test_app.py`.

Try it by hand:
```bash
curl "http://127.0.0.1:5000/churches?search=haines"
curl "http://127.0.0.1:5000/leaderboard?scope=state&region=Florida&country=USA&type=church"
```

## Endpoints
| Method | Path | What it does |
|---|---|---|
| GET | `/churches?search=text` | approved churches whose name/city words start with the typed words |
| POST | `/churches` | `{name, city, region, country}` -> new church, **waits for moderation** (`approved: false`) |
| POST | `/players` | `{name, church_id}` -> `{id, token}` (send `id` + `token` again to change name/church) |
| POST | `/scores` | `{player_id, token, delta}` adds enemies defeated |
| GET | `/leaderboard?scope=state\|country\|world&region=&country=&type=church\|player` | top 50 |
| GET | `/admin/churches/pending` | header `X-Admin-Token` |
| POST | `/admin/churches/<id>/approve` | header `X-Admin-Token` |

Churches are ranked by the **total enemies defeated by all their members**;
the Players tab ranks individual players. State/Country use the player's church's
state and country (compared without caring about upper/lower case, so spell
them the same way - e.g. always "USA").

### Basic anti-cheat (in `app.py`, change to taste)
- `delta` must be a whole number from 1 to 50 per request (the game sends chunks of 50 max)
- at most 1000 defeats per player per day, 120 score posts per hour
- scores need the secret player token; 5 church submissions per IP per day
- names are trimmed and `<`, `>` and control characters removed

This stops casual cheating, not a determined hacker (anything the game can send,
a person can send too). Good enough for a church leaderboard.

## Deploy later for free (PythonAnywhere)
1. Make a free "Beginner" account at pythonanywhere.com.
2. Upload this `server` folder (Files tab, or `git clone` your repo in a Bash console).
3. Bash console: `pip install --user flask`
4. Web tab > Add a new web app > Manual configuration (Python 3.x).
   In the WSGI file put:
   ```python
   import sys, os
   sys.path.insert(0, "/home/YOURNAME/apologion/server")
   os.environ["APOLOGION_ADMIN_TOKEN"] = "pick-a-long-secret"
   from app import app as application
   ```
5. Reload. Your API is at `https://YOURNAME.pythonanywhere.com`.
6. In Godot: Online > Enabled = on, Base Url = that address. Export the game.

Free plan notes: one web app at `yourname.pythonanywhere.com`, limited CPU,
512 MB disk, and the free web app must be renewed by logging in about once a
month or it's switched off. The paid "Developer" plan is about $10/month.

Approve submitted churches:
```bash
curl -H "X-Admin-Token: pick-a-long-secret" https://YOURNAME.pythonanywhere.com/admin/churches/pending
curl -X POST -H "X-Admin-Token: pick-a-long-secret" https://YOURNAME.pythonanywhere.com/admin/churches/ID/approve
```
