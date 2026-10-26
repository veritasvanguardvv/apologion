extends Node
# Baby Mode (Settings > Baby Mode, GameSettings.baby_mode) - autoload "BabyMode".
#
# For little children who can't type or say verses yet:
#   - no turn-based battles (turn_manager.gd skips them) and no verse box,
#     Verses / Type / Mic buttons or push-to-talk
#   - you defeat an enemy by running into it (walking, the joystick or the
#     Ram dash all count): every enemy goes down in one ram, the boss idol
#     takes IDOL_HITS rams (it flashes, you bounce back, the HP panel counts down)
#   - every ram reads a random matching verse out loud (the system's
#     text-to-speech voice in the game's language) and shows it in the
#     player's speech bubble
#   - you can't lose: the player takes no damage (character_body_2d.gd)
#
# Which verses (verse_pool): an enemy's kind is its only_vs ("idol",
# "sindeath"), else its base_type (a sin like "greed", or "atheist"...), else
# the first sin in its line_sets (Umbrid -> sloth), else the level's sin.
#   - a sin: verses whose strongest sin is that sin (like the Pastor's
#     on-theme rule, party_member.gd verse_main_sins)
#   - idol / sindeath / atheist / demon / false_teacher: the verses that hurt
#     that kind (the sheet's "Dmg to ..." columns, verses.json "vs")
#   - nothing found: the Universal verses (all_damage, no sin)
# Verses that aren't for small children (KID_UNSAFE words) are never used.

const SINS = ["sloth", "lust", "greed", "wrath", "gluttony", "envy", "pride"]
const VS_KINDS = ["idol", "sindeath", "atheist", "demon", "false_teacher"]
const KID_UNSAFE = "(?i)prostitut|harlot|whore|adulter|fornicat|\\blust|sexual|seduc|naked|immoral|\\brape|sodom|breast"

const RAM_REACH = 10.0      # px between the bodies that still counts as touching
const RAM_HEIGHT = 24.0     # px of up/down gap that still counts
const HIT_COOLDOWN = 0.6    # seconds between two rams
const IDOL_HITS = 3         # the boss idol takes this many rams
const HIT_SOUND = "res://Greed/SUCCESS PICKUP Collect Chime 01.wav"

signal enemy_rammed(enemy, verse: Dictionary, defeated: bool)

var verses: Array = []
var _pools = {}             # kind -> Array of verses
var _last_ref = {}          # kind -> last verse used (no repeats in a row)
var _unsafe: RegEx
var _touching = {}          # enemy -> true: hit, still touching (needs to back off first)
var _cooldown = 0.0
var _voices = {}            # language -> voice id ("" = none)
var _sfx: AudioStreamPlayer

# Also read by the tests
var speak_aloud = true      # false = text only
var last_kind = ""
var last_verse = {}
var last_spoken = ""        # the text sent (or that would be sent) to text-to-speech
var last_spoken_language = ""
var spoke = false           # did the last ram really reach a TTS voice?


func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_unsafe = RegEx.create_from_string(KID_UNSAFE)
	_load_verses()
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "BabyRamSfx"
	if ResourceLoader.exists(HIT_SOUND):
		_sfx.stream = load(HIT_SOUND)
	add_child(_sfx)
	GameSettings.baby_mode_changed.connect(_on_baby_mode_changed)


func is_on() -> bool:
	return GameSettings.baby_mode


func _on_baby_mode_changed(on: bool):
	_touching.clear()
	if on and TurnManager.in_battle:
		TurnManager._end_battle()   # no battles in Baby Mode (enemies stay; ram them)
	if not on:
		stop_speaking()


# ---------------- Ramming ----------------

func _physics_process(delta):
	_cooldown = max(0.0, _cooldown - delta)
	if not is_on():
		return
	var player = get_tree().get_first_node_in_group("player")
	_track_safe_spot(player)
	if player == null or TurnManager.in_battle or TurnManager.encounters_paused or player.get("cutscene_lock") == true:
		return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not TurnManager._is_alive(enemy) or enemy.get("dormant") == true or enemy.hp <= 0:
			continue
		if touching(player, enemy):
			if not _touching.has(enemy) and _cooldown <= 0.0:
				ram(enemy, player)
		else:
			_touching.erase(enemy)
	# things that break when rammed (the Golden Calf after SinDeath: greed_barrier.gd)
	for thing in get_tree().get_nodes_in_group("baby_rammables"):
		if is_instance_valid(thing) and thing.has_method("on_rammed") and touching(player, thing) and _cooldown <= 0.0:
			_cooldown = HIT_COOLDOWN
			thing.on_rammed(player)
	for e in _touching.keys():
		if not is_instance_valid(e):
			_touching.erase(e)


func touching(player: Node2D, other: Node2D) -> bool:
	var gap = TurnManager.body_gap(player, other)
	if gap.x <= RAM_REACH and gap.y <= RAM_HEIGHT:
		return true
	# an enemy inside a solid body (the boss idol in the Golden Calf): touching
	# that body - from the side or standing on it - counts too
	var shell = other.get_meta("baby_ram_body", null) if other.has_meta("baby_ram_body") else null
	if shell is Node2D and is_instance_valid(shell) and shell != other:
		gap = TurnManager.body_gap(player, shell)
		return gap.x <= RAM_REACH and gap.y <= RAM_HEIGHT
	return false


func is_boss_idol(enemy) -> bool:
	return str(enemy.get("only_vs")) == "idol" or str(enemy.get("base_type")) == "idol"


# One ram: a verse is read out, the enemy is hit. Returns true if it was defeated.
func ram(enemy, player = null) -> bool:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	_touching[enemy] = true
	_cooldown = HIT_COOLDOWN
	var verse = pick_verse(enemy)
	_play_hit_sound()
	if not verse.is_empty():
		say_verse(verse, player)
	var defeated = false
	if is_boss_idol(enemy):
		if enemy.max_hp != IDOL_HITS:
			enemy.max_hp = IDOL_HITS   # (sindeath_scene.gd sets this too)
			enemy.hp = IDOL_HITS
		enemy.hp = max(0, enemy.hp - 1)
		_flash(enemy)
		_shake_camera(player)
		if is_instance_valid(player) and player.has_method("baby_bounce"):
			var dir = sign(player.global_position.x - enemy.get_center().x)
			player.baby_bounce(dir if dir != 0 else -1.0)
		if enemy.hp <= 0:
			defeated = true
			enemy.knock_out()   # survives_defeat: it cracks (sindeath_scene.gd smashes it)
		else:
			enemy.play_anim("hurt")
			enemy.show_popup(tr("%d more!") % int(enemy.hp), Color(1, 0.85, 0.3))
	else:
		defeated = true
		enemy.instant_defeat("Rammed!")
	enemy_rammed.emit(enemy, verse, defeated)
	return defeated


func _flash(enemy):
	var t = enemy.create_tween()
	t.tween_property(enemy, "modulate", Color(2.5, 2.5, 2.5), 0.06)
	t.tween_property(enemy, "modulate", Color.WHITE, 0.25)


func _shake_camera(player):
	var cam = get_viewport().get_camera_2d()
	if cam == null:
		return
	var t = cam.create_tween()
	for i in 5:
		t.tween_property(cam, "offset", Vector2(randf_range(-7, 7), randf_range(-5, 5)), 0.04)
	t.tween_property(cam, "offset", Vector2.ZERO, 0.05)


func _play_hit_sound():
	if _sfx and _sfx.stream:
		_sfx.play()


# ---------------- Falling (you can't lose) ----------------
# Falling into a pit puts you back where you last stood (a moment before),
# instead of restarting the level / ending the Endless run.
# (greed_level.gd / endless_level.gd player_fell call fall_back)
var _safe = []          # [msec, position] while standing on the ground, newest last
var _safe_scene = 0

func _track_safe_spot(player):
	var scene = get_tree().current_scene
	var id = scene.get_instance_id() if scene else 0
	if id != _safe_scene:
		_safe.clear()
		_safe_scene = id
	if player == null or not player.is_on_floor() or player.get("cutscene_lock") == true:
		return
	var now = Time.get_ticks_msec()
	if _safe.is_empty() or now - _safe[-1][0] >= 200:
		_safe.append([now, player.global_position])
		if _safe.size() > 40:
			_safe.pop_front()


func fall_back(player) -> bool:
	if not is_on() or player == null or _safe.is_empty():
		return false
	var now = Time.get_ticks_msec()
	var pick = 0
	for i in range(_safe.size() - 1, -1, -1):
		if now - _safe[i][0] >= 1000:
			pick = i
			break
	var pos = _safe[pick][1]
	_safe.resize(pick)   # (that spot again only if it's still the best one)
	player.global_position = pos + Vector2(0, -6)
	player.velocity = Vector2.ZERO
	return true


# ---------------- Verses ----------------

func _load_verses():
	var f = FileAccess.open("res://data/verses.json", FileAccess.READ)
	if f == null:
		push_warning("BabyMode: can't read data/verses.json")
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		verses = data.get("verses", [])


# The sin(s) a verse hits hardest (ties count, like party_member.gd verse_main_sins)
static func main_sins(v: Dictionary) -> Array:
	var sins = v.get("sins", {})
	var best = 0.0
	var out = []
	if not sins is Dictionary:
		return out
	for s in sins:
		var pct = float(sins[s])
		if pct <= 0.0:
			continue
		if pct > best:
			best = pct
			out = [s]
		elif pct == best:
			out.append(s)
	return out


func kid_safe(v: Dictionary) -> bool:
	var en = str(v.get("en", ""))
	return en != "" and _unsafe.search(en) == null


# Which verses fit this enemy: "idol", "sindeath", a sin, "atheist"... ("" = universal)
func enemy_kind(enemy) -> String:
	var only = str(enemy.get("only_vs")) if enemy.get("only_vs") != null else ""
	if only != "":
		return only
	var base = str(enemy.get("base_type")) if enemy.get("base_type") != null else ""
	if base in SINS or base in VS_KINDS:
		return base
	var sets = enemy.get("line_sets")
	if sets != null:
		for s in sets:
			if str(s) in SINS:
				return str(s)
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("level_sin"):
		var ls = str(player.level_sin())
		if ls in SINS:
			return ls
	return ""


func verse_pool(kind: String) -> Array:
	if _pools.has(kind):
		return _pools[kind]
	var pool = []
	for v in verses:
		if not v is Dictionary or not kid_safe(v):
			continue
		if kind in VS_KINDS:
			var vs = v.get("vs", {})
			if vs is Dictionary and float(vs.get(kind, 0)) > 0.0:
				pool.append(v)
		elif kind in SINS:
			if kind in main_sins(v):
				pool.append(v)
		elif float(v.get("all_damage", 0)) > 0.0 and main_sins(v).is_empty():
			pool.append(v)   # universal
	if pool.is_empty() and kind != "":
		pool = verse_pool("")
	_pools[kind] = pool
	return pool


func pick_verse(enemy) -> Dictionary:
	var kind = enemy_kind(enemy)
	last_kind = kind
	var pool = verse_pool(kind)
	if pool.is_empty():
		return {}
	var v = pool[randi() % pool.size()]
	if pool.size() > 1 and _last_ref.get(kind, "") == v.ref:
		v = pool[(pool.find(v) + 1 + randi() % (pool.size() - 1)) % pool.size()]
	_last_ref[kind] = v.ref
	last_verse = v
	return v


func verse_text(v: Dictionary, lang: String) -> String:
	var t = str(v.get(lang, ""))
	return t if t != "" else str(v.get("en", ""))


# "Romans 7:8b" -> "Romans 7:8", "John 19:30 (2)" -> "John 19:30" (for reading out)
static func spoken_ref(ref: String) -> String:
	var r = ref
	var paren = r.find(" (")
	if paren != -1:
		r = r.substr(0, paren)
	while r.length() > 0 and r[r.length() - 1] in ["a", "b", "c", "d"] and r.length() > 1 and r[r.length() - 2].is_valid_int():
		r = r.substr(0, r.length() - 1)
	return r


# Shows the verse in the player's speech bubble and reads it out loud
func say_verse(v: Dictionary, player = null):
	var lang = SaveManager.language
	var text = verse_text(v, lang)
	var ref = VerseManager.ref_text(str(v.ref))
	if is_instance_valid(player) and player.get("bubble") != null:
		var time = clamp(2.5 + text.length() * 0.06, 3.0, 7.0)
		player.bubble.say(ref, text, false, time)
	speak(VerseManager.ref_text(spoken_ref(str(v.ref))) + ". " + text, lang, v)


# ---------------- Text-to-speech ----------------
# The device's own voices (DisplayServer TTS: AVSpeechSynthesizer on iOS and
# macOS, SAPI on Windows, Android's TTS, the browser's speechSynthesis,
# speech-dispatcher on Linux). Needs audio/general/text_to_speech=true in
# project.godot. No voice (or no TTS at all, e.g. headless): text only.

func tts_available() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


func _voice_for(lang: String) -> String:
	if _voices.has(lang):
		return _voices[lang]
	var id = ""
	var list = DisplayServer.tts_get_voices_for_language(lang)
	if not list.is_empty():
		id = list[0]
	_voices[lang] = id
	return id


func speak(text: String, lang: String, v := {}) -> bool:
	last_spoken = text
	last_spoken_language = lang
	spoke = false
	if not speak_aloud or not tts_available():
		return false
	var voice = _voice_for(lang)
	if voice == "" and lang != "en" and not v.is_empty():
		# no voice for this language: read the English verse instead
		lang = "en"
		voice = _voice_for("en")
		text = VerseManager.ref_text(spoken_ref(str(v.ref))) + ". " + verse_text(v, "en")
		last_spoken = text
		last_spoken_language = lang
	if voice == "":
		var all = DisplayServer.tts_get_voices()
		if all.is_empty():
			return false
		voice = str(all[0].get("id", ""))
	var volume = int(round(clamp(GameSettings.sfx_volume, 0.0, 1.0) * 100.0))
	DisplayServer.tts_speak(text, voice, volume, 1.0, 0.95, 0, true)   # (interrupts the last verse)
	spoke = true
	return true


func stop_speaking():
	if tts_available():
		DisplayServer.tts_stop()
