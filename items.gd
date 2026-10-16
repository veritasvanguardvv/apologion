extends RefCounted
# ITEM DEFINITIONS
# ----------------
# Every item the player can carry. To add a new item, add an entry here and
# place a pickup for it in a level (item_pickup.tscn, set "item_id").
#
#   name            = shown in the inventory (translated with strings.csv)
#   icon            = picture (64x64 png)
#   verse           = a scroll casts this verse (a "ref" from all_verses in
#                     character_body_2d.gd). Using a scroll does NOT use up the
#                     verse in your cycle and does NOT discover it.
#   outside_battle  = can it be used when you're not in a battle?
#                     (healing: yes, attacks: no - there's nobody to hit)

const ITEMS = {
	"healing_scroll": {
		"name": "Healing Scroll",
		"icon": "res://Items/fc112.png",   # green scroll
		"verse": "1 Peter 2:24b",          # heals 50% of max HP
		"outside_battle": true,
	},
	"battle_scroll": {
		"name": "Battle Scroll",
		"icon": "res://Items/fc110.png",   # red scroll
		"verse": "Galatians 3:13",         # Universal attack (hurts any enemy type)
		"outside_battle": false,
	},
	"guard_scroll": {
		"name": "Guard Scroll",
		"icon": "res://Items/fc111.png",   # blue scroll
		"verse": "Psalm 17:8",             # Guard: enemies do half damage for 3 rounds
		"outside_battle": true,
	},
}
