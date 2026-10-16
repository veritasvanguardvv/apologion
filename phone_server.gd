extends Node
# PhoneServer (autoload / singleton) - LOCAL MULTIPLAYER WITH PHONES
# ------------------------------------------------------------------
# Like Jackbox: the game (on the Windows PC) runs a tiny web server on your
# home Wi-Fi. Friends open the address on their phone's browser (or scan the
# QR code), type their name + the room code, and play as an extra party
# member. Nothing to install, nothing paid, no internet needed.
#
# How it works:
#   - An HTTP server (Godot's TCPServer) on port 8080 sends the controller
#     web page (phone_controller_page.gd) to the phone.
#   - A WebSocket server on the NEXT port (8081) carries the live messages
#     (join, verse, skip, and the game state the phone shows).
#   - Up to 3 phone players. Each one gets a party member (phone_player.tscn)
#     with its own color and name above the head.
#   - If a phone disconnects (screen off, Wi-Fi hiccup), its character stays
#     and skips its turns; joining again with the SAME NAME takes the same slot.
#
# Change the port in Project Settings > Phone > Http Port (the WebSocket uses
# that port + 1). Windows asks the first time whether to allow the game on
# networks: tick "Private networks" and click Allow. Phones must be on the
# same Wi-Fi as the PC. See MULTIPLAYER.md.

const QRCode = preload("res://qr_code.gd")
const ControllerPage = preload("res://phone_controller_page.gd")
const PHONE_PLAYER_SCENE = "res://phone_player.tscn"

# Tint + name color for phone players 1, 2 and 3 (blue, pink, green)
const SLOT_COLORS = [Color(0.45, 0.8, 1.0), Color(1.0, 0.55, 0.85), Color(0.55, 1.0, 0.5)]
# Room codes use letters that are hard to mix up (no I/O/0/1)
const CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ"

var http_port = 8080            # Project Settings: phone/http_port
var turn_timeout = 30.0         # seconds a phone player has for their turn (phone/turn_timeout)
var max_phone_players = 3       # + the computer companion = party of 4 (+ you)
var state_interval = 0.5        # how often phones get a fresh state (seconds)
var max_messages = 8            # battle messages kept for the phones

signal players_changed          # someone joined / left / reconnected
signal hosting_changed(is_hosting)

var hosting = false
var room_code = ""
var lan_ip = ""
var ws_port = 0
var http_server: TCPServer
var ws_server: TCPServer
var http_clients = []           # web page requests in progress
var sockets = []                # open WebSockets: {ws, slot, born}
# slot (1..3) -> {name, socket (or null), used: [verse refs], node}
var players = {}
var messages = []               # last battle messages (shown on the phones)
var state_timer = 0.0
var clock = 0.0

# Lobby window (built in code)
var lobby_layer: CanvasLayer
var lobby_panel: Panel
var qr_rect: TextureRect
var url_label: Label
var code_label: Label
var players_label: RichTextLabel
var status_label: Label
var other_label: Label
var host_button: Button


func _ready():
	http_port = int(ProjectSettings.get_setting("phone/http_port", 8080))
	turn_timeout = float(ProjectSettings.get_setting("phone/turn_timeout", 30.0))
	TurnManager.message_shown.connect(_on_battle_message)
	_build_lobby()


# ---------------- Start / stop ----------------

# Starts both servers. Returns "" if it worked, or an error message.
func start_hosting() -> String:
	if hosting:
		return ""
	# Try a few port pairs in case the first is busy (8080/8081, 8082/8083...)
	for attempt in 5:
		var port = http_port + attempt * 2
		var h = TCPServer.new()
		var w = TCPServer.new()
		if h.listen(port, "*") == OK and w.listen(port + 1, "*") == OK:
			http_server = h
			ws_server = w
			ws_port = port + 1
			http_port = port
			break
		h.stop()
		w.stop()
	if http_server == null:
		return tr("Couldn't start the server (port %d busy?)") % http_port
	lan_ip = detect_lan_ip()
	room_code = ""
	for i in 4:
		room_code += CODE_LETTERS[randi() % CODE_LETTERS.length()]
	hosting = true
	print("Phone server: ", get_join_url(), "  room ", room_code, "  (WebSocket port ", ws_port, ")")
	hosting_changed.emit(true)
	_update_lobby()
	return ""


# Stops the servers and removes the phone players from the party.
func stop_hosting():
	if not hosting:
		return
	for s in sockets:
		s.ws.close(1000, "Host stopped")
	for c in http_clients:
		c.peer.disconnect_from_host()
	sockets.clear()
	http_clients.clear()
	http_server.stop()
	ws_server.stop()
	http_server = null
	ws_server = null
	for slot in players:
		var node = players[slot].node
		if node != null and is_instance_valid(node):
			node.remove_from_group("party")
			node.queue_free()
	players.clear()
	hosting = false
	hosting_changed.emit(false)
	players_changed.emit()
	_update_lobby()


# The address phones open, e.g. http://192.168.1.23:8080/?r=ABCD
func get_join_url(with_code := true) -> String:
	var url = "http://%s:%d/" % [lan_ip, http_port]
	return url + ("?r=" + room_code if with_code else "")


# The computer's address on the home network. Prefers the usual home/office
# ranges 192.168.x.x, then 10.x.x.x and 172.16-31.x.x.
static func detect_lan_ip() -> String:
	var best = ""
	var best_score = -1
	for address in lan_candidates():
		var score = lan_score(address)
		if score > best_score:
			best = address
			best_score = score
	return best if best != "" else "127.0.0.1"

static func lan_score(address: String) -> int:
	if address.begins_with("192.168."):
		return 3
	if address.begins_with("10."):
		return 2
	if address.begins_with("172."):
		var second = int(address.split(".")[1])
		if second >= 16 and second <= 31:
			return 2
	return 0

# All IPv4 addresses that phones could reach (no 127.x / 169.254.x)
static func lan_candidates() -> Array:
	var list = []
	for address in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		list.append(address)
	return list


# ---------------- Every frame: answer requests ----------------

func _process(delta):
	clock += delta
	if not hosting:
		return
	_poll_http()
	_poll_websockets()
	state_timer -= delta
	if state_timer <= 0.0:
		state_timer = state_interval
		broadcast_state()


# A phone asks for the web page
func _poll_http():
	while http_server.is_connection_available():
		http_clients.append({"peer": http_server.take_connection(), "data": PackedByteArray(), "born": clock})
	for c in http_clients.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			http_clients.erase(c)
			continue
		var available = peer.get_available_bytes()
		if available > 0:
			var result = peer.get_partial_data(available)
			if result[0] == OK:
				c.data.append_array(result[1])
		var text = c.data.get_string_from_ascii()
		if text.contains("\r\n\r\n") or c.data.size() > 8192:
			_answer_http(peer, text)
			peer.disconnect_from_host()
			http_clients.erase(c)
		elif clock - c.born > 5.0:
			peer.disconnect_from_host()   # too slow, give up
			http_clients.erase(c)


func _answer_http(peer: StreamPeerTCP, request: String):
	var first_line = request.get_slice("\r\n", 0)   # e.g. "GET /?r=ABCD HTTP/1.1"
	var path = first_line.get_slice(" ", 1).get_slice("?", 0)
	var status = "200 OK"
	var type = "text/html; charset=utf-8"
	var body = PackedByteArray()
	if not first_line.begins_with("GET "):
		status = "405 Method Not Allowed"
	elif path == "/" or path == "/index.html":
		body = ControllerPage.build(ws_port, TranslationServer.get_locale().substr(0, 2), _ui_texts()).to_utf8_buffer()
	elif path == "/favicon.ico":
		status = "204 No Content"
	else:
		status = "404 Not Found"
		type = "text/plain; charset=utf-8"
		body = "Not found".to_utf8_buffer()
	var header = "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [status, type, body.size()]
	peer.put_data(header.to_utf8_buffer())
	if body.size() > 0:
		peer.put_data(body)


# Live connections from the phones
func _poll_websockets():
	while ws_server.is_connection_available():
		var ws = WebSocketPeer.new()
		ws.accept_stream(ws_server.take_connection())
		sockets.append({"ws": ws, "slot": 0, "born": clock})
	for s in sockets.duplicate():
		var ws: WebSocketPeer = s.ws
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var packet = ws.get_packet()
					if packet.size() <= 4000:   # ignore anything huge
						_on_message(s, packet.get_string_from_utf8())
			WebSocketPeer.STATE_CONNECTING:
				if clock - s.born > 10.0:
					ws.close()
					sockets.erase(s)
			WebSocketPeer.STATE_CLOSED:
				sockets.erase(s)
				_on_socket_closed(s)


func _send(s, data: Dictionary):
	if s != null and s.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		s.ws.send_text(JSON.stringify(data))


# ---------------- Messages from phones ----------------

func _on_message(s, text: String):
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match str(msg.get("t", "")):
		"join":
			_join(s, str(msg.get("name", "")), str(msg.get("room", "")))
		"verse":
			if s.slot != 0:
				var note = phone_verse(s.slot, str(msg.get("text", "")))
				_send(s, {"t": "note", "text": note})
				broadcast_state()
		"skip":
			if s.slot != 0:
				var node = get_player_node(s.slot)
				if node == null or not node.phone_skip():
					_send(s, {"t": "note", "text": tr("Wait for your turn!")})
				broadcast_state()


func _join(s, player_name: String, room: String):
	player_name = clean_name(player_name)
	if room.strip_edges().to_upper() != room_code:
		_send(s, {"t": "error", "text": tr("Wrong room code")})
		return
	if player_name == "":
		_send(s, {"t": "error", "text": tr("Please type your name")})
		return
	# Same name as someone who joined before? Take their slot back.
	var slot = slot_for_name(player_name)
	if slot != 0:
		var old = players[slot].socket
		if old != null and old != s:
			old.slot = 0
			old.ws.close(1000, "Joined from another tab")
	else:
		slot = _free_slot()
		if slot == 0:
			_send(s, {"t": "error", "text": tr("The room is full (%d phone players)") % max_phone_players})
			return
		players[slot] = {"name": player_name, "socket": null, "used": [], "node": null}
		print("Phone player ", slot, " joined: ", player_name)
	players[slot].socket = s
	s.slot = slot
	_send(s, {"t": "joined", "slot": slot, "name": players[slot].name, "color": "#" + SLOT_COLORS[slot - 1].to_html(false)})
	ensure_phone_members()
	var node = get_player_node(slot)
	if node:
		node.update_name_label()
	players_changed.emit()
	_update_lobby()
	broadcast_state()


func _on_socket_closed(s):
	if s.slot == 0 or not players.has(s.slot) or players[s.slot].socket != s:
		return
	players[s.slot].socket = null
	print("Phone player ", s.slot, " disconnected: ", players[s.slot].name)
	var node = get_player_node(s.slot)
	if node:
		node.update_name_label()
	players_changed.emit()
	_update_lobby()


# Removes odd characters and keeps names short (they go above the head)
static func clean_name(text: String) -> String:
	var result = ""
	for c in text.strip_edges():
		if c.unicode_at(0) >= 32 and not c in "<>\"\\":
			result += c
	return result.substr(0, 16).strip_edges()


func slot_for_name(player_name: String) -> int:
	for slot in players:
		if players[slot].name.to_lower() == player_name.to_lower():
			return slot
	return 0

func _free_slot() -> int:
	for slot in range(1, max_phone_players + 1):
		if not players.has(slot):
			return slot
	return 0

func is_slot_connected(slot: int) -> bool:
	return players.has(slot) and players[slot].socket != null

func get_player_node(slot: int):
	if not players.has(slot):
		return null
	var node = players[slot].node
	return node if node != null and is_instance_valid(node) else null


# ---------------- Verses (each phone player has their own cycle) ----------------
# They share the host's DISCOVERED verses (VerseManager.discovered), so the
# team's list grows together, but "used this cycle" is per person.

func phone_verse(slot: int, text: String) -> String:
	var node = get_player_node(slot)
	if node == null:
		return tr("Wait for your turn!")
	if not TurnManager.in_battle:
		return tr("Verses work in battles, on your turn")
	return node.phone_verse(text)

func can_use_verse(slot: int, ref: String) -> bool:
	return players.has(slot) and VerseManager.is_discovered(ref) and not (ref in players[slot].used)

func mark_verse_used(slot: int, ref: String):
	var used = players[slot].used
	if not (ref in used):
		used.append(ref)
	if remaining_count(slot) == 0:
		used.clear()   # everything used: a new cycle starts (just for this player)

func remaining_count(slot: int) -> int:
	var count = 0
	for ref in VerseManager.discovered:
		if not (ref in players[slot].used):
			count += 1
	return count


# ---------------- Phone players in the level ----------------

# Makes sure every phone player has a character next to you. Called when
# someone joins and when a level starts (party_manager.gd).
func ensure_phone_members():
	var player = get_tree().get_first_node_in_group("player")
	var level = get_tree().current_scene
	if player == null or level == null:
		return
	for slot in players:
		if get_player_node(slot) != null and not players[slot].node.is_queued_for_deletion():
			continue
		var member = load(PHONE_PLAYER_SCENE).instantiate()
		member.member_id = "phone_%d" % slot
		member.phone_slot = slot
		member.display_name = players[slot].name
		member.follow_distance = 90.0 + 65.0 * slot   # one behind the other
		member.add_to_group("phone_players")
		member.global_position = PartyManager._spot_next_to(player) - Vector2(65.0 * slot, 0)
		level.add_child(member)
		member.get_node("Visual").modulate = SLOT_COLORS[slot - 1]
		member.update_name_label()
		players[slot].node = member


# ---------------- What the phones show ----------------

func _on_battle_message(text: String):
	messages.append(text)
	while messages.size() > max_messages:
		messages.pop_front()
	if hosting:
		broadcast_state()

func broadcast_state():
	for s in sockets:
		if s.slot != 0 and players.has(s.slot):
			_send(s, state_for(s.slot))


func state_for(slot: int) -> Dictionary:
	var node = get_player_node(slot)
	var player = get_tree().get_first_node_in_group("player")
	var current = TurnManager.current
	var turn_name = ""
	if TurnManager.in_battle and current != null and is_instance_valid(current):
		turn_name = host_name() if current.is_in_group("player") else str(current.display_name)
	# Everyone in the party with their HP
	var party = []
	if player:
		party.append({"name": host_name(), "hp": player.hp, "max_hp": player.max_hp, "ko": false, "color": ""})
	for member in get_tree().get_nodes_in_group("party"):
		var color = ""
		if member.player_controlled:
			color = "#" + SLOT_COLORS[member.phone_slot - 1].to_html(false)
		party.append({"name": member.display_name, "hp": snapped(member.hp, 0.1), "max_hp": member.max_hp, "ko": member.knocked_out, "color": color})
	# The team's discovered verses (with this player's own "used" marks)
	var verses = []
	if player:
		for ref in VerseManager.discovered:
			var v = player.get_verse(ref)
			if v != null:
				var body = player.verse_body(v)
				verses.append({"ref": VerseManager.ref_text(ref), "text": body.substr(0, 1).to_upper() + body.substr(1), "power": player.verse_power_text(v), "used": ref in players[slot].used})
	return {
		"t": "state",
		"lang": TranslationServer.get_locale().substr(0, 2),
		"ui": _ui_texts(),
		"name": players[slot].name,
		"hp": node.hp if node else 0,
		"max_hp": node.max_hp if node else 100,
		"in_battle": TurnManager.in_battle,
		"your_turn": node != null and node.waiting_for_phone,
		"time_left": int(ceil(node.phone_time_left)) if node else 0,
		"turn_name": turn_name,
		"party": party,
		"verses": verses,
		"messages": messages,
	}

# The host's name on phones (the profile name if there is one)
func host_name() -> String:
	var profile_name = str(SaveManager.get("profile_name")) if SaveManager.get("profile_name") != null else ""
	return profile_name if profile_name != "" else tr("Host")

func _ui_texts() -> Dictionary:
	var ui = {}
	for key in ControllerPage.UI_KEYS:
		ui[key] = tr(key)
	return ui


# ---------------- Lobby window (Multiplayer button) ----------------

func open_lobby():
	if not hosting:
		var error = start_hosting()
		status_label.text = error
	lobby_layer.visible = true
	_update_lobby()

func close_lobby():
	lobby_layer.visible = false

func is_lobby_open() -> bool:
	return lobby_layer != null and lobby_layer.visible


func _build_lobby():
	lobby_layer = CanvasLayer.new()
	lobby_layer.layer = 20   # above the menus
	lobby_layer.visible = false
	add_child(lobby_layer)
	lobby_panel = Panel.new()
	lobby_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.09, 1.0)
	lobby_panel.add_theme_stylebox_override("panel", style)
	lobby_layer.add_child(lobby_panel)

	var title = Label.new()
	title.text = "Multiplayer"
	title.position = Vector2(40, 20)
	title.add_theme_font_size_override("font_size", 40)
	lobby_panel.add_child(title)

	qr_rect = TextureRect.new()
	qr_rect.position = Vector2(40, 90)
	qr_rect.size = Vector2(320, 320)
	qr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lobby_panel.add_child(qr_rect)

	var steps = Label.new()
	steps.text = "On your phone: scan the QR code, or open this address in the browser:"
	steps.position = Vector2(390, 90)
	steps.size = Vector2(720, 30)
	steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steps.add_theme_font_size_override("font_size", 20)
	lobby_panel.add_child(steps)

	url_label = Label.new()
	url_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	url_label.position = Vector2(390, 150)
	url_label.add_theme_font_size_override("font_size", 38)
	url_label.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
	lobby_panel.add_child(url_label)

	code_label = Label.new()
	code_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	code_label.position = Vector2(390, 205)
	code_label.add_theme_font_size_override("font_size", 38)
	lobby_panel.add_child(code_label)

	players_label = RichTextLabel.new()
	players_label.bbcode_enabled = true
	players_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	players_label.position = Vector2(390, 270)
	players_label.size = Vector2(720, 150)
	players_label.add_theme_font_size_override("normal_font_size", 22)
	lobby_panel.add_child(players_label)

	var notes = Label.new()
	notes.text = "Phones must be on the same Wi-Fi as this computer. The first time, Windows asks to allow the game on networks: tick Private networks and click Allow."
	notes.position = Vector2(40, 430)
	notes.size = Vector2(1070, 60)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_theme_font_size_override("font_size", 17)
	notes.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	lobby_panel.add_child(notes)

	other_label = Label.new()
	other_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	other_label.position = Vector2(40, 495)
	other_label.size = Vector2(1070, 30)
	other_label.add_theme_font_size_override("font_size", 15)
	other_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	lobby_panel.add_child(other_label)

	status_label = Label.new()
	status_label.position = Vector2(40, 525)
	status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	lobby_panel.add_child(status_label)

	host_button = Button.new()
	host_button.position = Vector2(560, 560)
	host_button.size = Vector2(260, 64)
	host_button.focus_mode = Control.FOCUS_NONE
	host_button.pressed.connect(_on_host_button)
	lobby_panel.add_child(host_button)

	var back = Button.new()
	back.text = "Back"
	back.position = Vector2(840, 560)
	back.size = Vector2(260, 64)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(close_lobby)
	lobby_panel.add_child(back)
	SaveManager.language_changed.connect(func(_l): _update_lobby())


func _on_host_button():
	if hosting:
		stop_hosting()
	else:
		status_label.text = start_hosting()
	_update_lobby()


func _update_lobby():
	if lobby_panel == null:
		return
	host_button.text = tr("Stop hosting") if hosting else tr("Start hosting")
	if not hosting:
		qr_rect.texture = null
		url_label.text = ""
		code_label.text = ""
		players_label.text = tr("Not hosting")
		other_label.text = ""
		return
	qr_rect.texture = QRCode.make_texture(get_join_url(), 8)
	url_label.text = get_join_url(false)
	code_label.text = tr("Room code: %s") % room_code
	var others = []
	for address in lan_candidates():
		if address != lan_ip:
			others.append("http://%s:%d/" % [address, http_port])
	other_label.text = (tr("Not working? Try:") + " " + ", ".join(others)) if not others.is_empty() else ""
	var text = "[b]" + tr("Players (%d/%d):") % [players.size(), max_phone_players] + "[/b]\n"
	for slot in range(1, max_phone_players + 1):
		if players.has(slot):
			var color = SLOT_COLORS[slot - 1].to_html(false)
			var state = tr("connected") if is_slot_connected(slot) else tr("disconnected")
			text += "[color=#%s]●[/color] %s  [color=#999](%s)[/color]\n" % [color, players[slot].name.replace("[", "("), state]
		else:
			text += "[color=#555]○ " + tr("waiting for a phone...") + "[/color]\n"
	players_label.text = text
