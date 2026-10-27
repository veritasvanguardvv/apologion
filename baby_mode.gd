extends Node
# Baby Mode (Settings > Baby Mode, GameSettings.baby_mode) - autoload "BabyMode".
#
# For little children who can't type or say verses yet:
#   - no turn-based battles (turn_manager.gd skips them) and no verse box,
#     Verses / Type / Mic buttons or push-to-talk
#   - you defeat an enemy by running into it (walking, the joystick or the
#     Ram dash all count): every enemy (SinDeath too) goes down in ENEMY_HITS
#     rams, the boss idol takes IDOL_HITS. A ram that doesn't finish it: it
#     flashes, its HP bar drops, "1 more!", you bounce back - and it nips you
#     (HIT_DAMAGE, never below 1 HP)
#   - every ram reads a random matching verse out loud (the system's
#     text-to-speech voice in the game's language) and shows it in the
#     player's speech bubble
#   - when you're at half health or less, the party member (Pastor...) reads a
#     kid-safe healing verse out loud and heals you (PARTY_HEAL_PCT, then a
#     HEAL_COOLDOWN pause). Pots (pot.gd) drop healing items: a chime and the
#     "+N" heal number, no verse.
#   - ONE VOICE AT A TIME (say_line): nothing is read over something that's
#     still being read. A line that comes while one is being read waits in a
#     single slot (a newer ram verse replaces a waiting ram verse; a healing
#     verse beats a waiting ram verse) and is dropped if it waited too long -
#     so there's never a backlog. The speech bubble only shows a verse when it
#     starts being read. Only the idol's last ram cuts in.
#   - only SHORT verses: at most MAX_WORDS words in the game's language
#     (short_only; a kind with none left uses its shortest ones)
#   - you can't lose: other damage doesn't hurt you (character_body_2d.gd),
#     enemies can't take your last HP and falling puts you back
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
const ENEMY_HITS = 2        # every other enemy (SinDeath too) takes this many
const HIT_DAMAGE = 20.0     # HP an enemy takes off you when a ram doesn't finish it
const PARTY_HEAL_BELOW = 0.5   # the party member heals you at this much HP or less
const PARTY_HEAL_PCT = 40.0    # ... this % of your max HP
const HEAL_COOLDOWN = 8.0      # seconds before the party member heals again
const HEAL_DELAY = 1.2         # seconds after the hit (the ram's verse starts first)
const MAX_WORDS = 15           # longest verse (words, in the game's language) read in Baby Mode
const SHORTEST_FALLBACK = 3    # no verse short enough: the 3 shortest
const WORDS_PER_SEC = 2.4      # speaking speed estimate (rate 0.95) for "still speaking"
const RAM_LINE_WAIT = 2.5      # seconds a waiting ram verse may wait before it's dropped
const HEAL_LINE_WAIT = 12.0    # ... a waiting healing verse
const HIT_SOUND = "res://Greed/SUCCESS PICKUP Collect Chime 01.wav"
const HEAL_SOUND = "res://Greed/SUCCESS PICKUP Collect Chime 05.wav"

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
var party_heals = 0         # healing verses read by the party member (Baby Mode)
var last_heal_verse = {}
var last_heal_by = ""
var last_heal_spoken = ""   # the text sent to text-to-speech for the last healing verse
var _heal_ready_at = 0      # msec: the party member may heal again
var _heal_pending = false
var _busy_until = 0         # msec: the line being read should be done by then (estimate)
var _waiting = {}           # the one line waiting to be read ({} = none)
var lines_started = []      # tests: [{text, start, end (msec)}] (last 20)
var lines_dropped = 0       # tests: lines never read (something else was being read)


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
	if player != null and not TurnManager.in_battle:
		_check_party_heal(player)
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
	# the idol's last ram cuts in (the big moment); others wait their turn
	var final_idol_hit = is_boss_idol(enemy) and (enemy.hp if enemy.max_hp == IDOL_HITS else IDOL_HITS) <= 1
	if not verse.is_empty():
		say_verse(verse, player, 2 if final_idol_hit else 0)
	var defeated = false
	if is_boss_idol(enemy):
		if enemy.max_hp != IDOL_HITS:
			enemy.max_hp = IDOL_HITS   # (sindeath_scene.gd sets this too)
			enemy.hp = IDOL_HITS
		enemy.hp = max(0, enemy.hp - 1)
		_flash(enemy)
		_shake_camera(player)
		_bounce(player, enemy)
		if enemy.hp <= 0:
			defeated = true
			enemy.knock_out()   # survives_defeat: it cracks (sindeath_scene.gd smashes it)
		else:
			enemy.play_anim("hurt")
			enemy.show_popup(tr("%d more!") % int(enemy.hp), Color(1, 0.85, 0.3))
	else:
		var rams = int(enemy.get_meta("baby_rams", 0)) + 1
		enemy.set_meta("baby_rams", rams)
		if rams >= ENEMY_HITS:
			defeated = true
			enemy.instant_defeat("Rammed!")
		else:
			# hit, not out yet: its HP bar drops, it flashes, you bounce back
			var left = ENEMY_HITS - rams
			enemy.hp = max(1.0, ceil(float(enemy.max_hp) * left / ENEMY_HITS))
			if enemy.get("hp_bar") != null:
				enemy.hp_bar.max_value = enemy.max_hp
				enemy.hp_bar.value = enemy.hp
			_flash(enemy)
			_shake_camera(player, 4.0)
			_bounce(player, enemy)
			if enemy.has_method("play_anim"):
				enemy.play_anim("hurt")
			enemy.show_popup(tr("%d more!") % left, Color(1, 0.85, 0.3))
	if not defeated:
		hurt_player(player)
	enemy_rammed.emit(enemy, verse, defeated)
	return defeated


func _bounce(player, enemy):
	if is_instance_valid(player) and player.has_method("baby_bounce"):
		var c = enemy.get_center() if enemy.has_method("get_center") else enemy.global_position
		var dir = sign(player.global_position.x - c.x)
		player.baby_bounce(dir if dir != 0 else -1.0)


# The enemy nips back (a ram that didn't finish it): a little damage, never
# your last HP point - you can't lose in Baby Mode.
func hurt_player(player, amount := HIT_DAMAGE) -> float:
	if not is_instance_valid(player) or not player.has_method("baby_hurt"):
		return 0.0
	return player.baby_hurt(amount)


# ---------------- The party member heals you ----------------
# Pastor (or Baana...: the first computer-controlled party member who isn't
# knocked out) reads a healing verse out loud when you're at PARTY_HEAL_BELOW
# or less. A HEAL_DELAY after the hit, so the ram's verse is heard first; the
# healing verse is queued after it, and rams during it queue after it too.

func player_needs_heal(player) -> bool:
	return is_instance_valid(player) and player.max_hp > 0 and player.hp > 0 and player.hp <= player.max_hp * PARTY_HEAL_BELOW


func healer():
	for m in Targeting.party_members():
		if m.get("player_controlled") == true or m.get("knocked_out") == true or not m.has_method("pick_player_heal_verse"):
			continue
		return m
	return null


func _check_party_heal(player):
	if _heal_pending or Time.get_ticks_msec() < _heal_ready_at or not player_needs_heal(player):
		return
	if healer() == null:
		return
	_heal_pending = true
	await get_tree().create_timer(HEAL_DELAY).timeout
	_heal_pending = false
	if is_on() and player_needs_heal(player) and not TurnManager.in_battle:
		party_heal(player)


# The healing itself (also called by the tests). Returns the verse ({} = none).
func party_heal(player, m = null) -> Dictionary:
	if m == null:
		m = healer()
	if m == null or not is_instance_valid(player):
		return {}
	var heals = m.player_heal_verses(func(x): return kid_safe(x)) if m.has_method("player_heal_verses") else []
	heals = short_only(heals, SaveManager.language)
	var v = null if heals.is_empty() else heals.pick_random()
	if v == null:
		return {}
	player.heal(player.max_hp * PARTY_HEAL_PCT / 100.0)
	var text = player.verse_body(v)
	text = text.substr(0, 1).to_upper() + text.substr(1)
	var title = VerseManager.ref_text(v.ref)
	say_line(VerseManager.ref_text(spoken_ref(str(v.ref))) + ". " + text, SaveManager.language, v,
		func(_secs):
			if is_instance_valid(m) and m.has_method("_say"):
				m._say(title, text)
			last_heal_spoken = last_spoken, 1)
	_heal_ready_at = Time.get_ticks_msec() + int(HEAL_COOLDOWN * 1000)
	party_heals += 1
	last_heal_verse = v
	last_heal_by = str(m.get("display_name"))
	_play_heal_sound()
	print("Baby Mode: ", last_heal_by, " heals you with ", v.ref)
	return v


var _heal_sfx: AudioStreamPlayer
func _play_heal_sound():
	if _heal_sfx == null:
		_heal_sfx = AudioStreamPlayer.new()
		_heal_sfx.bus = "SFX"
		if ResourceLoader.exists(HEAL_SOUND):
			_heal_sfx.stream = load(HEAL_SOUND)
		add_child(_heal_sfx)
	if _heal_sfx.stream:
		_heal_sfx.play()


func _flash(enemy):
	var t = enemy.create_tween()
	t.tween_property(enemy, "modulate", Color(2.5, 2.5, 2.5), 0.06)
	t.tween_property(enemy, "modulate", Color.WHITE, 0.25)


func _shake_camera(player, amount := 7.0):
	var cam = get_viewport().get_camera_2d()
	if cam == null:
		return
	var t = cam.create_tween()
	for i in 5:
		t.tween_property(cam, "offset", Vector2(randf_range(-amount, amount), randf_range(-amount, amount) * 0.7), 0.04)
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
	var fell_at = player.get_body_center() if player.has_method("get_body_center") else player.global_position
	var pos = _safe[pick][1]
	_safe.resize(pick)   # (that spot again only if it's still the best one)
	player.global_position = pos + Vector2(0, -6)
	player.velocity = Vector2.ZERO
	_fall_hint(player, fell_at)
	return true


# Falling into the same water / pit again and again: the level can say
# which way to go instead (baby_fall_hint(fell_at, respawned_at) -> {"id",
# "dir", "done_x"}, e.g. Greed's water -> left to the portal), and after
# FALLS_FOR_HINT falls there within FALL_HINT_WINDOW seconds a big arrow by
# the sheep points that way (fall_hint_arrow.gd).
const FALLS_FOR_HINT = 2
const FALL_HINT_WINDOW = 90.0
const FallHintArrow = preload("res://fall_hint_arrow.gd")
var _falls = []          # [msec, hint id]
var hint_arrow: Node2D = null

func _fall_hint(player, fell_at: Vector2):
	var level = get_tree().current_scene
	if level == null or not level.has_method("baby_fall_hint"):
		return
	var at = player.get_body_center() if player.has_method("get_body_center") else player.global_position
	var hint: Dictionary = level.baby_fall_hint(fell_at, at)
	if hint.is_empty():
		return
	var now = Time.get_ticks_msec()
	_falls = _falls.filter(func(f): return now - f[0] < FALL_HINT_WINDOW * 1000.0)
	_falls.append([now, hint.id])
	if _falls.filter(func(f): return f[1] == hint.id).size() < FALLS_FOR_HINT:
		return
	if is_instance_valid(hint_arrow):
		hint_arrow.queue_free()
	var arrow = FallHintArrow.new()
	arrow.name = "FallHintArrow"
	arrow.dir = float(hint.dir)
	arrow.done_x = float(hint.done_x)
	arrow.player = player
	arrow.home = at + Vector2(float(hint.dir) * 70.0, -140.0)   # (the camera keeps the sheep near the left edge)
	arrow.position = arrow.home
	level.add_child(arrow)
	hint_arrow = arrow


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


# Words in a verse's text in this language (the English text if it has none)
func word_count(v: Dictionary, lang: String) -> int:
	return count_words(verse_text(v, lang))

static func count_words(text: String) -> int:
	var n = 0
	for w in text.split(" ", false):
		for ch in w:
			if ch.to_lower() != ch.to_upper() or ch.is_valid_int():
				n += 1
				break
	return n

# Only the verses of at most MAX_WORDS words (in lang); none -> the shortest ones
func short_only(pool: Array, lang: String) -> Array:
	var out = pool.filter(func(v): return word_count(v, lang) <= MAX_WORDS)
	if out.is_empty() and not pool.is_empty():
		var sorted = pool.duplicate()
		sorted.sort_custom(func(a, b): return word_count(a, lang) < word_count(b, lang))
		out = sorted.slice(0, SHORTEST_FALLBACK)
	return out

# The verses a ram on this kind reads (short ones, in the game's language)
func verse_pool(kind: String) -> Array:
	var lang = SaveManager.language
	var key = kind + "|" + lang
	if _pools.has(key):
		return _pools[key]
	var pool = short_only(_full_pool(kind), lang)
	_pools[key] = pool
	return pool

func _full_pool(kind: String) -> Array:
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
		pool = _full_pool("")
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


# Reads the verse out loud and shows it in the player's speech bubble (when it
# really starts being read). prio: 0 = a ram, 2 = cut in (the idol's last ram)
func say_verse(v: Dictionary, player = null, prio := 0):
	var lang = SaveManager.language
	var text = verse_text(v, lang)
	var ref = VerseManager.ref_text(str(v.ref))
	say_line(VerseManager.ref_text(spoken_ref(str(v.ref))) + ". " + text, lang, v,
		func(secs):
			if is_instance_valid(player) and player.get("bubble") != null:
				player.bubble.say(ref, text, false, clamp(secs + 0.5, 3.0, 9.0)), prio)


# ---------------- One voice at a time ----------------
# say_line(text, ...): read it now if nothing is being read; else it waits in
# the one waiting slot (prio 0 = ram verse, 1 = healing verse, 2 = cut in now).
# A waiting line is replaced by a newer one of the same or higher prio, and
# dropped after RAM_LINE_WAIT / HEAL_LINE_WAIT. show(secs) is called when the
# line starts (the speech bubble), secs = how long it should take to read.
# "Being read" = the estimate from the word count hasn't run out, or the
# device's TTS still says it's speaking (DisplayServer.tts_is_speaking - on
# iOS AVSpeechSynthesizer.isSpeaking), but never more than 6 s past the estimate.

func speech_busy() -> bool:
	var now = Time.get_ticks_msec()
	if now < _busy_until:
		return true
	return spoke and tts_available() and DisplayServer.tts_is_speaking() and now < _busy_until + 6000

func speech_seconds(text: String) -> float:
	return 0.6 + count_words(text) / WORDS_PER_SEC

func say_line(text: String, lang: String, v := {}, show := Callable(), prio := 0) -> bool:
	var line = {"text": text, "lang": lang, "v": v, "show": show, "prio": prio, "at": Time.get_ticks_msec()}
	if prio >= 2 or (not speech_busy() and _waiting.is_empty()):
		if not _waiting.is_empty() and prio >= 2:
			lines_dropped += 1
		_waiting = {}
		_start_line(line)
		return true
	if _waiting.is_empty() or prio >= int(_waiting.prio):
		if not _waiting.is_empty():
			lines_dropped += 1
		_waiting = line
	else:
		lines_dropped += 1
	return false

func _process(_delta):
	if _waiting.is_empty() or speech_busy():
		return
	var line = _waiting
	_waiting = {}
	var max_wait = HEAL_LINE_WAIT if int(line.prio) >= 1 else RAM_LINE_WAIT
	if Time.get_ticks_msec() - int(line.at) > max_wait * 1000.0 or not is_on():
		lines_dropped += 1
		return
	_start_line(line)

func _start_line(line: Dictionary):
	speak(line.text, line.lang, line.v, true)   # (nothing should be playing: cut off any leftover)
	var secs = speech_seconds(last_spoken)
	var now = Time.get_ticks_msec()
	_busy_until = now + int(secs * 1000.0)
	lines_started.append({"text": last_spoken, "start": now, "end": _busy_until})
	if lines_started.size() > 20:
		lines_started.pop_front()
	var show: Callable = line.show
	if show.is_valid():
		show.call(secs)


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


func speak(text: String, lang: String, v := {}, interrupt := true) -> bool:
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
	DisplayServer.tts_speak(text, voice, volume, 1.0, 0.95, 0, interrupt)
	spoke = true
	return true


func stop_speaking():
	_waiting = {}
	_busy_until = 0
	if tts_available():
		DisplayServer.tts_stop()
