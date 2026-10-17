extends Node
# SpeechRecognizer (autoload / singleton)
# ---------------------------------------
# Push-to-talk voice input: HOLD Shift and say a verse, RELEASE Shift and the
# words you said are recited exactly as if you had typed them and pressed
# Enter (same verse matching and battle-turn rules).
#
# Shift works any time EXCEPT while you're typing in the verse box, because
# there Shift is needed for capital letters.
#
# HOW IT WORKS
#   1. Microphone: an AudioStreamMicrophone plays into a bus called "Mic".
#      That bus has an AudioEffectCapture (it collects the sound) followed by
#      an AudioEffectAmplify at -80 dB (so you don't hear yourself).
#      Needs Project Settings > Audio > Driver > Enable Input (already on).
#   2. Speech-to-text "backend": Godot Whisper (addons/godot_whisper), which
#      runs OpenAI's Whisper model offline on your computer (whisper.cpp).
#      It needs a model file in res://models/ (see VOICE_SETUP.md). The best
#      one found in model_paths is used.
#   3. The result is sent with the "transcribed" signal; the player
#      (character_body_2d.gd) puts it in the verse box and recites it.
#
# To use a different speech-to-text system, replace _backend_transcribe() and
# is_available() - everything else stays the same.

signal listening_changed(on)       # mic on/off (the player shows the speaker icon)
signal transcribed(text)           # what was heard ("" = nothing understood)
signal status(message)             # short messages like "Recognizing..."

const MIC_BUS = "Mic"
const EXTENSION_PATH = "res://addons/godot_whisper/godot_whisper.gdextension"

# Model files to try, best first. Bigger = more accurate but slower.
# ggml-tiny-q5_1.bin (32 MB) comes with the game; download base-q5_1 for
# better accuracy, especially in Spanish (see VOICE_SETUP.md).
var model_paths = [
	"res://models/ggml-small-q5_1.bin",
	"res://models/ggml-base-q5_1.bin",
	"res://models/ggml-base.bin",
	"res://models/ggml-tiny-q5_1.bin",
	"res://models/ggml-tiny.bin",
]
var max_record_seconds = 12.0      # stops listening by itself after this long
var min_record_seconds = 0.3       # shorter than this = probably an accidental tap
# Words that help Whisper spell Bible names correctly
var prompts = {
	"en": "Bible verses: Psalm, Proverbs, Isaiah, Genesis, Galatians, Corinthians, Yahweh, the LORD.",
	"es": "Versículos de la Biblia: Salmos, Proverbios, Isaías, Génesis, Gálatas, Corintios, Jehová.",
	"pl": "Wersety biblijne: Psalm, Przysłów, Izajasza, Mateusza, Łukasza, Rzymian, Koryntian, Galacjan, Pan.",
}

var listening = false
var busy = false                   # true while a recording is being turned into text
var mic_player: AudioStreamPlayer
var capture: AudioEffectCapture
var frames = PackedVector2Array()  # the recording (stereo frames at the mix rate)
var listen_time = 0.0

var stt: Node = null               # the Whisper "SpeechToText" node (if the addon is installed)
var model_path = ""
var thread: Thread


func _ready():
	_setup_mic_bus()
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = MIC_BUS
	add_child(mic_player)
	model_path = _find_model()
	print_report()
	if is_available():
		stt = ClassDB.instantiate("SpeechToText")
		add_child(stt)


# True if speech-to-text can run (addon + model found)
func is_available() -> bool:
	return ClassDB.class_exists("SpeechToText") and model_path != ""


# ---------------- Diagnostics ----------------
# If voice doesn't work, the game says WHY (in the verse box) and the Output
# panel / console shows a full "[Voice]" report. Tell whoever helps you what
# it says.

# The specific reason voice can't work, or "" if everything looks fine.
# (English text with %s - translated with tr() where it's shown.)
func problem() -> Array:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return ["Voice: audio input is turned off (Project Settings > Audio > Driver > Enable Input)"]
	if not FileAccess.file_exists(EXTENSION_PATH):
		return ["Voice: the Godot Whisper addon is missing (%s)", EXTENSION_PATH]
	var library = _library_path()
	if library == "":
		# Not a fault the player can fix - say it kindly and point to typing
		return ["Voice input isn't available on this computer yet (%s). Type the verse and press Enter instead.", OS.get_name() + " " + Engine.get_architecture_name()]
	if not _library_exists(library):
		return ["Voice: the addon's library file is missing: %s", library]
	if not GDExtensionManager.is_extension_loaded(EXTENSION_PATH):
		return ["Voice: the addon's library didn't load (%s). Restart Godot; if it still fails, look for 'Can't open dynamic library' in the Output panel", library.get_file()]
	if not ClassDB.class_exists("SpeechToText"):
		return ["Voice: the addon loaded but has no SpeechToText class (wrong addon version?)"]
	if model_path == "":
		return ["Voice: no model file found. Put ggml-tiny-q5_1.bin in %s", "res://models/"]
	if AudioServer.get_input_device_list().is_empty():
		return ["Voice: no microphone found"]
	return []

# Same as problem(), translated and ready to show ("" = no problem)
func problem_text() -> String:
	var p = problem()
	if p.is_empty():
		return ""
	return tr(p[0]) % p[1] if p.size() > 1 else tr(p[0])

# macOS libraries are .framework folders, the others single files
func _library_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

# Which library file the .gdextension wants on this computer, e.g.
# res://addons/godot_whisper/bin/libgodot_whisper.windows.template_release.x86_64.dll
func _library_path() -> String:
	var config = ConfigFile.new()
	if config.load(EXTENSION_PATH) != OK:
		return ""
	var os_name = OS.get_name().to_lower()   # "windows", "linux", "macos"...
	if os_name in ["linux", "freebsd"]:
		os_name = "linux"
	var arch = Engine.get_architecture_name()   # "x86_64", "arm64"...
	var build = "debug" if OS.is_debug_build() else "release"
	for key in [os_name + "." + build + "." + arch, os_name + "." + arch, os_name + "." + build, os_name]:
		if config.has_section_key("libraries", key):
			var file = str(config.get_value("libraries", key))
			return file if file.begins_with("res://") else EXTENSION_PATH.get_base_dir().path_join(file)
	return ""

# Prints everything we know about the voice setup (shown in Godot's Output panel)
func print_report():
	var library = _library_path()
	print("[Voice] ---- voice recognition check ----")
	print("[Voice] OS: ", OS.get_name(), " ", Engine.get_architecture_name(), (" (debug)" if OS.is_debug_build() else ""))
	print("[Voice] audio/driver/enable_input: ", ProjectSettings.get_setting("audio/driver/enable_input", false))
	print("[Voice] addon file: ", EXTENSION_PATH, " exists=", FileAccess.file_exists(EXTENSION_PATH))
	print("[Voice] library: ", library, " exists=", library != "" and _library_exists(library))
	print("[Voice] library loaded: ", GDExtensionManager.is_extension_loaded(EXTENSION_PATH), "  SpeechToText class: ", ClassDB.class_exists("SpeechToText"))
	print("[Voice] model: ", model_path if model_path != "" else "NONE (tried " + ", ".join(model_paths) + ")")
	print("[Voice] microphones: ", AudioServer.get_input_device_list(), "  using: ", AudioServer.input_device)
	var p = problem()
	if p.is_empty():
		print("[Voice] READY - hold Shift and speak")
	else:
		print("[Voice] NOT READY: ", (p[0] % p[1]) if p.size() > 1 else p[0])

func _find_model() -> String:
	for path in model_paths:
		if FileAccess.file_exists(path):
			return path
	return ""


# Creates the "Mic" bus: capture first, then silence it so it isn't played back
func _setup_mic_bus():
	var index = AudioServer.get_bus_index(MIC_BUS)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, MIC_BUS)
		capture = AudioEffectCapture.new()
		capture.buffer_length = 1.0
		AudioServer.add_bus_effect(index, capture, 0)
		var silence = AudioEffectAmplify.new()
		silence.volume_db = -80.0
		AudioServer.add_bus_effect(index, silence, 1)
	else:
		capture = AudioServer.get_bus_effect(index, 0)


# ---------------- Push-to-talk (Shift) ----------------

func _input(event):
	if event.is_action_pressed("push_to_talk") and not event.is_echo():
		var focus = get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return   # typing: Shift is for capital letters
		start_listening()
	elif event.is_action_released("push_to_talk") and listening:
		stop_listening()


func start_listening():
	if listening or get_tree().get_first_node_in_group("player") == null:
		return
	if busy:
		status.emit(tr("Still recognizing - wait a moment"))
		return
	if not problem().is_empty():
		status.emit(problem_text())   # say exactly what's wrong
		print("[Voice] ", problem_text())
		return
	listening = true
	listen_time = 0.0
	frames = PackedVector2Array()
	if capture:
		capture.clear_buffer()
	mic_player.play()
	listening_changed.emit(true)


func stop_listening():
	if not listening:
		return
	_collect_frames()
	listening = false
	mic_player.stop()
	listening_changed.emit(false)
	var seconds = frames.size() / AudioServer.get_mix_rate()
	if listen_time >= min_record_seconds and frames.is_empty():
		_mic_problem(tr("Voice: no sound came from the microphone (%s). Check Windows Settings > Privacy > Microphone") % AudioServer.input_device)
		return
	if seconds < min_record_seconds:
		status.emit(tr("Hold Shift while you speak"))
		return
	if _loudest(frames) < silence_level:
		_mic_problem(tr("Voice: the microphone only recorded silence (%s). Check it isn't muted and that apps may use it") % AudioServer.input_device)
		return
	transcribe_frames(frames)

var silence_level = 0.002   # a recording quieter than this everywhere = the mic gives nothing

func _mic_problem(message: String):
	status.emit(message)
	print("[Voice] ", message, "  microphones: ", AudioServer.get_input_device_list())

# The loudest sample in a recording (0 = silence, 1 = maximum)
static func _loudest(recording: PackedVector2Array) -> float:
	var loudest = 0.0
	for f in recording:
		loudest = max(loudest, abs(f.x), abs(f.y))
	return loudest


func _process(delta):
	if listening:
		listen_time += delta
		_collect_frames()
		if listen_time >= max_record_seconds:
			stop_listening()

func _collect_frames():
	if capture and capture.can_get_buffer(1):
		frames.append_array(capture.get_buffer(capture.get_frames_available()))


# ---------------- Speech to text ----------------

# Turns a recording (stereo frames at AudioServer's mix rate) into text in a
# background thread, then emits "transcribed".
func transcribe_frames(recording: PackedVector2Array):
	if not is_available():
		status.emit(problem_text())
		return
	if busy:
		return
	busy = true
	status.emit(tr("Recognizing..."))
	thread = Thread.new()
	thread.start(_thread_work.bind(recording, SaveManager.language))

func _thread_work(recording: PackedVector2Array, lang: String):
	var text = _backend_transcribe(recording, lang)
	_finish.call_deferred(text)

func _finish(text: String):
	thread.wait_to_finish()
	busy = false
	print("Heard: \"", text, "\"")
	transcribed.emit(text)


# The actual speech-to-text (Godot Whisper). Runs in the background thread.
func _backend_transcribe(recording: PackedVector2Array, lang: String) -> String:
	if stt.get("language_model") == null:
		stt.set("language_model", load(model_path))   # loaded the first time it's needed
	# Whisper's language: English / Spanish / Polish (Auto if this build has no Polish)
	var language_name = {"es": "Spanish", "pl": "Polish"}.get(lang, "English")
	if not ClassDB.class_has_integer_constant("SpeechToText", language_name):
		language_name = "Auto"
	stt.set("language", ClassDB.class_get_integer_constant("SpeechToText", language_name))
	var samples = to_16k_mono(recording, AudioServer.get_mix_rate())
	if samples.is_empty():
		return ""
	var tokens = stt.call("transcribe", samples, prompts.get(lang, ""), 0)
	if tokens.is_empty():
		return ""
	return _clean(str(tokens[0]))

# Whisper wants 16000 samples per second, mono. The mic gives stereo at the
# game's mix rate (usually 44100 or 48000), so average the two channels and
# pick in-between values (linear interpolation).
static func to_16k_mono(recording: PackedVector2Array, mix_rate: float) -> PackedFloat32Array:
	var out = PackedFloat32Array()
	if recording.size() < 2:
		return out
	var step = mix_rate / 16000.0
	var count = int((recording.size() - 1) / step)
	out.resize(count)
	for i in count:
		var pos = i * step
		var j = int(pos)
		var t = pos - j
		var a = (recording[j].x + recording[j].y) * 0.5
		var b = (recording[j + 1].x + recording[j + 1].y) * 0.5
		out[i] = lerp(a, b, t)
	return out

# Removes things like "[BLANK_AUDIO]" or "(music)" that Whisper sometimes adds
func _clean(text: String) -> String:
	for pair in [["[", "]"], ["(", ")"], ["<", ">"], ["*", "*"]]:
		while text.find(pair[0]) != -1:
			var a = text.find(pair[0])
			var b = text.find(pair[1], a + 1)
			if b == -1:
				break
			text = text.substr(0, a) + text.substr(b + 1)
	return text.strip_edges()


# For testing without a microphone: pretend this was heard
func inject_transcript(text: String):
	transcribed.emit(text)


func _exit_tree():
	if thread and thread.is_started():
		thread.wait_to_finish()
