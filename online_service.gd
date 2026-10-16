extends Node
# OnlineService (autoload / singleton) - CHURCHES + LEADERBOARDS
# ----------------------------------------------------------------
# The game talks to a "backend" that stores churches and scores:
#
#   LocalBackend (used now, works offline): keeps everything on this computer
#     in user://online_local.json. It knows the 2 preset churches plus any
#     church you submit. Leaderboards only show YOU and your church - it never
#     makes up other players.
#   HttpBackend (for later, OFF by default): the same calls sent to the small
#     web server in the /server folder (Flask + SQLite) with HTTPRequest.
#
# Turn it on in Project Settings > Online:
#   online/enabled  = true
#   online/base_url = "https://your-name.pythonanywhere.com"  (or http://127.0.0.1:5000 to test)
#
# The stat is "enemies defeated" (SaveManager.lifetime_defeats). Every defeat
# is added to a QUEUE (pending_defeats). When online, the queue is sent to the
# server in small chunks; if the server can't be reached, it stays queued
# (and saved) and is sent later - nothing is lost.

# The churches every copy of the game knows. "id" is the same on the server.
const PRESET_CHURCHES = [
	{"id": "christs-church-on-the-move", "name": "Christ's Church on the Move", "city": "Lake Wales", "region": "Florida", "country": "USA"},
	{"id": "fpc-haines-city", "name": "FPC Haines City", "city": "Haines City", "region": "Florida", "country": "USA"},
]
const STATE_PATH = "user://online.json"
const MAX_SCORE_CHUNK = 50      # the server accepts at most 50 defeats per request
@export var sync_every = 60.0   # seconds between automatic sync attempts (when online)

signal synced(ok)

var enabled = false
var base_url = ""
var local: LocalBackend
var remote: HttpBackend
var pending_defeats = 0         # defeats not sent to the server yet
var player_id = ""              # given by the server the first time
var player_token = ""           # secret that proves scores come from this player
var registered_as = {}          # the name/church last sent to the server
var syncing = false
var sync_timer = 0.0
var menu                        # the Church / Leaderboards screens (online_menu.gd)


func _ready():
	enabled = bool(ProjectSettings.get_setting("online/enabled", false))
	base_url = str(ProjectSettings.get_setting("online/base_url", "http://127.0.0.1:5000"))
	local = LocalBackend.new()
	remote = HttpBackend.new(self, base_url)
	_load_state()
	menu = preload("res://online_menu.gd").new()
	add_child(menu)


func _process(delta):
	if not enabled:
		return
	sync_timer -= delta
	if sync_timer <= 0.0:
		sync_timer = sync_every
		sync()


# Switch online mode on/off from code (tests, or a future settings toggle)
func set_online(on: bool, url := ""):
	enabled = on
	if url != "":
		base_url = url
		remote.base_url = url
	sync_timer = 0.0


# ---------------- Churches ----------------

# Churches whose name/city matches the search text. Online: from the server
# (falls back to the local list if it can't be reached).
func search_churches(text: String) -> Dictionary:
	if enabled:
		var r = await remote.search_churches(text)
		if r.ok:
			return {"ok": true, "churches": r.churches, "note": ""}
		return {"ok": false, "churches": local.search_churches(text), "note": tr("Couldn't reach the server - showing saved churches")}
	return {"ok": true, "churches": local.search_churches(text), "note": ""}


# "Submit your church". Online: sent to the server, where it waits for a
# moderator (you can still pick it right away). Offline: saved locally and
# sent to the server later, when online mode is turned on.
func submit_church(church_name: String, city: String, region: String, country: String) -> Dictionary:
	var info = {"name": church_name.strip_edges(), "city": city.strip_edges(), "region": region.strip_edges(), "country": country.strip_edges()}
	if info.name.length() < 3 or info.city == "" or info.country == "":
		return {"ok": false, "error": tr("Please fill in the name, city and country")}
	if enabled:
		var r = await remote.submit_church(info)
		if r.ok:
			local.remember_church(r.church)
			return r
	return {"ok": true, "church": local.submit_church(info)}


# Saves the player's name + church (SaveManager) and tells the server.
func set_profile(new_name: String, new_church: Dictionary):
	SaveManager.set_profile(new_name.strip_edges().substr(0, 20), new_church)
	if enabled:
		await sync()


# ---------------- Scores ----------------

# Called by SaveManager after every defeat.
func record_defeats(amount: int):
	local.player_total = SaveManager.lifetime_defeats
	if enabled:
		pending_defeats += amount
		_save_state()
		sync_timer = min(sync_timer, 2.0)   # send it soon


# Sends the profile and the queued defeats to the server. Returns true if
# everything got through.
func sync() -> bool:
	if not enabled or syncing:
		return false
	syncing = true
	var ok = await _sync_profile()
	while ok and pending_defeats > 0:
		var chunk = min(pending_defeats, MAX_SCORE_CHUNK)
		var r = await remote.submit_score(player_id, player_token, chunk)
		if r.ok:
			pending_defeats -= chunk
			_save_state()
		else:
			ok = false   # keep the rest queued for next time
	syncing = false
	synced.emit(ok)
	return ok


func _sync_profile() -> bool:
	var church = SaveManager.church.duplicate()
	# A church submitted while offline? Send it to the server first.
	if church.get("id", "").begins_with("local-"):
		var r = await remote.submit_church(church)
		if not r.ok:
			return false
		local.replace_church(church.id, r.church)
		church = r.church
		SaveManager.set_profile(SaveManager.profile_name, church)
	var wanted = {"name": _leaderboard_name(), "church_id": church.get("id", "")}
	if player_id != "" and wanted == registered_as:
		return true
	if player_id == "":
		# First time: the server gets the lifetime total so far (in chunks)
		pending_defeats = SaveManager.lifetime_defeats
	var r = await remote.register_player(wanted.name, wanted.church_id, player_id, player_token)
	if not r.ok:
		return false
	player_id = str(r.player.id)
	player_token = str(r.player.get("token", player_token))
	registered_as = wanted
	_save_state()
	return true


func _leaderboard_name() -> String:
	return SaveManager.profile_name if SaveManager.profile_name != "" else "Player"


# ---------------- Leaderboards ----------------
# scope: "state", "country" or "world"   type: "church" or "player"
# State/Country use YOUR church's state and country.
func get_leaderboard(scope: String, type: String) -> Dictionary:
	var church = SaveManager.church
	if scope != "world" and church.is_empty():
		return {"ok": false, "entries": [], "note": tr("Choose your church first to see State and Country rankings")}
	var region = church.get("region", "")
	var country = church.get("country", "")
	if enabled:
		await sync()
		var r = await remote.get_leaderboard(scope, type, region, country)
		if r.ok:
			return {"ok": true, "entries": r.entries, "note": ""}
		var offline = local.get_leaderboard(scope, type)
		offline.note = tr("Couldn't reach the server - showing only your own score")
		return offline
	var result = local.get_leaderboard(scope, type)
	result.note = tr("Offline: only your own score is shown until online leaderboards are turned on")
	return result


# Which area a scope means, for the screen title ("Florida", "USA", "World")
func scope_area(scope: String) -> String:
	match scope:
		"state":
			return SaveManager.church.get("region", "")
		"country":
			return SaveManager.church.get("country", "")
	return tr("World")


# ---------------- Saving this service's own data ----------------

func _save_state():
	var file = FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"pending_defeats": pending_defeats, "player_id": player_id, "player_token": player_token, "registered_as": registered_as}))

func _load_state():
	if not FileAccess.file_exists(STATE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	if typeof(data) == TYPE_DICTIONARY:
		pending_defeats = int(data.get("pending_defeats", 0))
		player_id = str(data.get("player_id", ""))
		player_token = str(data.get("player_token", ""))
		registered_as = data.get("registered_as", {})


# Search helper shared by both backends: every word typed must be the start
# of a word in the church's name or city ("christ church" finds
# "Christ's Church on the Move", "haines" finds "FPC Haines City").
static func church_matches(church: Dictionary, text: String) -> bool:
	var words = _words(str(church.get("name", "")) + " " + str(church.get("city", "")))
	for typed in _words(text):
		var found = false
		for w in words:
			if w.begins_with(typed):
				found = true
				break
		if not found:
			return false
	return true

static func _words(text: String) -> Array:
	var clean = ""
	for c in text.to_lower():
		if c == "'" or c == "’":
			continue   # Christ's -> christs
		clean += c if (c.is_valid_identifier() or c.is_valid_int()) else " "
	return Array(clean.split(" ", false))

static func make_id(text: String) -> String:
	return "-".join(_words(text))


# ======================================================================
# LocalBackend - everything stored on this computer (no internet needed)
# ======================================================================
class LocalBackend:
	const PATH = "user://online_local.json"
	var submitted = []        # churches you submitted (waiting for moderation)
	var player_total = 0

	func _init():
		player_total = SaveManager.lifetime_defeats
		if FileAccess.file_exists(PATH):
			var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if typeof(data) == TYPE_DICTIONARY:
				submitted = data.get("submitted", [])

	func _save():
		var file = FileAccess.open(PATH, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"submitted": submitted}))

	func all_churches() -> Array:
		var list = []
		for c in PRESET_CHURCHES:
			list.append(c.duplicate())
		list.append_array(submitted)
		return list

	func search_churches(text: String) -> Array:
		var list = []
		for c in all_churches():
			if OnlineService.church_matches(c, text):
				list.append(c)
		return list

	func submit_church(info: Dictionary) -> Dictionary:
		var church = info.duplicate()
		church.id = "local-" + OnlineService.make_id(info.name + " " + info.city)
		church.pending = true
		for c in submitted:
			if c.id == church.id:
				return c
		submitted.append(church)
		_save()
		return church

	# A church the server told us about (so it shows up offline too)
	func remember_church(church: Dictionary):
		for c in all_churches():
			if c.id == church.id:
				return
		submitted.append(church)
		_save()

	func replace_church(old_id: String, church: Dictionary):
		for i in submitted.size():
			if submitted[i].id == old_id:
				submitted[i] = church
		_save()

	# Only the real local player (and their church) - nothing made up.
	func get_leaderboard(_scope: String, type: String) -> Dictionary:
		var entries = []
		var church = SaveManager.church
		var total = SaveManager.lifetime_defeats
		if type == "church":
			if not church.is_empty():
				entries.append({"rank": 1, "name": church.name, "score": total, "detail": church.get("city", "")})
		else:
			var player_name = SaveManager.profile_name if SaveManager.profile_name != "" else TranslationServer.translate("You")
			entries.append({"rank": 1, "name": player_name, "score": total, "detail": church.get("name", "")})
		return {"ok": true, "entries": entries}


# ======================================================================
# HttpBackend - the same calls sent to the web server (/server folder)
# ======================================================================
class HttpBackend:
	var node: Node            # HTTPRequest nodes must live in the scene tree
	var base_url = ""
	var timeout = 8.0

	func _init(owner_node: Node, url: String):
		node = owner_node
		base_url = url

	# Sends one request and waits for the answer: {ok, code, data}
	func _request(method: int, path: String, body = null) -> Dictionary:
		var http = HTTPRequest.new()
		http.timeout = timeout
		node.add_child(http)
		var headers = ["Content-Type: application/json", "Accept: application/json"]
		var err = http.request(base_url.trim_suffix("/") + path, headers, method, JSON.stringify(body) if body != null else "")
		if err != OK:
			http.queue_free()
			return {"ok": false, "code": 0, "data": {}}
		var result = await http.request_completed   # [result, code, headers, body]
		http.queue_free()
		var json = JSON.new()   # (JSON.new() = no error printed for an empty answer)
		var data = json.data if json.parse(result[3].get_string_from_utf8()) == OK else {}
		if typeof(data) != TYPE_DICTIONARY:
			data = {}
		var ok = result[0] == HTTPRequest.RESULT_SUCCESS and result[1] >= 200 and result[1] < 300
		if not ok:
			print("Online: ", path, " failed (result ", result[0], ", HTTP ", result[1], ") ", data.get("error", ""))
		return {"ok": ok, "code": result[1], "data": data}

	func search_churches(text: String) -> Dictionary:
		var r = await _request(HTTPClient.METHOD_GET, "/churches?search=" + text.uri_encode())
		return {"ok": r.ok, "churches": r.data.get("churches", [])}

	func submit_church(info: Dictionary) -> Dictionary:
		var body = {"name": info.get("name", ""), "city": info.get("city", ""), "region": info.get("region", ""), "country": info.get("country", "")}
		var r = await _request(HTTPClient.METHOD_POST, "/churches", body)
		return {"ok": r.ok, "church": r.data.get("church", {}), "error": r.data.get("error", "")}

	func register_player(player_name: String, church_id: String, player_id: String, token: String) -> Dictionary:
		var body = {"name": player_name, "church_id": church_id}
		if player_id != "":
			body.id = player_id
			body.token = token
		var r = await _request(HTTPClient.METHOD_POST, "/players", body)
		return {"ok": r.ok, "player": r.data.get("player", {})}

	func submit_score(player_id: String, token: String, delta: int) -> Dictionary:
		var r = await _request(HTTPClient.METHOD_POST, "/scores", {"player_id": player_id, "token": token, "delta": delta})
		return {"ok": r.ok, "total": r.data.get("total", 0)}

	func get_leaderboard(scope: String, type: String, region: String, country: String) -> Dictionary:
		var query = "?scope=%s&type=%s&region=%s&country=%s" % [scope, type, region.uri_encode(), country.uri_encode()]
		var r = await _request(HTTPClient.METHOD_GET, "/leaderboard" + query)
		return {"ok": r.ok, "entries": r.data.get("entries", [])}
