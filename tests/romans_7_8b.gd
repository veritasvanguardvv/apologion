extends SceneTree
# Run: godot --headless --path . --script tests/romans_7_8b.gd
func _initialize():
	call_deferred("verify")

func verify():
	var p = load("res://character_body_2d.gd").new()
	p._load_sheet_verses()
	var v = p.get_verse("Romans 7:8b")
	assert(v != null)
	assert(v.en == "But apart from the law, sin is dead.")
	assert(not p._hits_sin(v, "greed"))
	p.filter_group = "Attacks"
	p.filter_type = "greed"
	assert(not p._passes_filter(v))
	assert(not p._has_regular_attack(v))
	# SinDeath's only_vs eligibility reads the actual sheet boss column.
	var boss = load("res://enemy.gd").new()
	boss.only_vs = "sindeath"
	assert(p._hits_only_vs(v, boss))
	assert(v.vs.sindeath == 100)
	var bm = root.get_node("BabyMode")
	assert(not "greed" in bm.main_sins(v))
	var greed_pool = bm._full_pool("greed")
	var boss_pool = bm._full_pool("sindeath")
	assert(not greed_pool.any(func(row): return row.ref == "Romans 7:8b"))
	assert(boss_pool.any(func(row): return row.ref == "Romans 7:8b"))
	print("PASS Romans 7:8b: not Greed/regular damage; SinDeath 100%; Baby Mode pools correct")
	boss.free()
	p.free()
	quit()
