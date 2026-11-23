extends SceneTree
# Run:
#   godot --headless --path . --script tests/baby_mode_default.gd
#   godot --headless --path . --script tests/baby_mode_default.gd -- edition=web_greed
# Baby Mode defaults ON, except the itch Web (web_greed) edition, which defaults OFF.
# An explicit Settings toggle is remembered; leftover implicit web_greed saves are not.

func _initialize():
	call_deferred("verify")


func verify():
	var GS = root.get_node("GameSettings")
	var SM = root.get_node("SaveManager")
	assert(GS.default_baby_mode_for("main") == true)
	assert(GS.default_baby_mode_for("es") == true)
	assert(GS.default_baby_mode_for("web_greed") == false)
	assert(GS.resolve_baby_mode(null, false, false) == true)
	assert(GS.resolve_baby_mode(null, false, true) == false)
	assert(GS.resolve_baby_mode(true, false, true) == false)
	assert(GS.resolve_baby_mode(false, false, true) == false)
	assert(GS.resolve_baby_mode(true, true, true) == true)
	assert(GS.resolve_baby_mode(false, true, true) == false)
	assert(GS.resolve_baby_mode(true, false, false) == true)
	assert(GS.resolve_baby_mode(false, false, false) == false)
	print("PASS resolve_baby_mode: web_greed defaults off; other editions on; explicit wins; unmigrated web_greed resets to off")

	var web = SM.is_web_greed_edition()
	assert(GS.default_baby_mode() == (not web))
	var path = ProjectSettings.globalize_path(GS.PATH)
	var backup = null
	if FileAccess.file_exists(GS.PATH):
		backup = FileAccess.get_file_as_string(GS.PATH)
	DirAccess.remove_absolute(path)
	GS.baby_mode_chosen = false
	GS._load()
	assert(GS.baby_mode == (not web))
	assert(GS.baby_mode_chosen == false)
	print("PASS unset settings: baby_mode default is %s for edition %s" % ["off" if web else "on", SM.edition()])

	var c = ConfigFile.new()
	c.set_value("gameplay", "baby_mode", true)
	c.save(GS.PATH)
	GS._load()
	if web:
		assert(GS.baby_mode == false)
		assert(GS.baby_mode_chosen == false)
		print("PASS web_greed migration: implicit saved true becomes off")
	else:
		assert(GS.baby_mode == true)
		print("PASS normal edition: saved true is kept")

	c.set_value("gameplay", "baby_mode", true)
	c.set_value("gameplay", "baby_mode_chosen", true)
	c.save(GS.PATH)
	GS._load()
	assert(GS.baby_mode == true)
	assert(GS.baby_mode_chosen == true)
	print("PASS explicit baby_mode=true is kept")

	c.set_value("gameplay", "baby_mode", false)
	c.set_value("gameplay", "baby_mode_chosen", true)
	c.save(GS.PATH)
	GS._load()
	assert(GS.baby_mode == false)
	assert(GS.baby_mode_chosen == true)
	print("PASS explicit baby_mode=false is kept")

	DirAccess.remove_absolute(path)
	if backup != null:
		var f = FileAccess.open(GS.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	quit()
