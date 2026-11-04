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
#   icon_region     = (optional) only this part of the icon picture
#   flies_away      = money: when you open the inventory it flies off the
#                     screen and is gone ("Riches certainly make themselves
#                     wings; they fly away as an eagle" - Proverbs 23:5)
#   heavy           = gold: while you carry any, you can't jump quite as high
#                     (greed_level.gd). Drop it to be light again.
#   drop_pickup     = what is left on the ground when you drop it:
#                     "item" = an item_pickup.tscn you can pick up again,
#                     "greed:<kind>" = a Greed pickup (greed_pickup.gd),
#                     "" = it's just thrown away
# Every item can be dropped (inventory: click it, then Drop).

const ITEMS = {
	"healing_scroll": {
		"name": "Healing Scroll",
		"icon": "res://General/Items/fc112.png",   # green scroll
		"verse": "1 Peter 2:24b",          # heals 50% of max HP
		"outside_battle": true,
		"drop_pickup": "item",
	},
	"battle_scroll": {
		"name": "Battle Scroll",
		"icon": "res://General/Items/fc110.png",   # red scroll
		"verse": "Galatians 3:13",         # Universal attack (hurts any enemy type)
		"outside_battle": false,
		"drop_pickup": "item",
	},
	"guard_scroll": {
		"name": "Guard Scroll",
		"icon": "res://General/Items/fc111.png",   # blue scroll
		"verse": "Psalm 17:8",             # Guard: enemies do half damage for 3 rounds
		"outside_battle": true,
		"drop_pickup": "item",
	},
	"zeal_scroll": {
		"name": "Zeal Scroll",
		"icon": "res://General/Items/fc110.png",   # (tinted gold in the level)
		"verse": "Romans 12:11",           # Zeal: run faster + jump much higher for 7 s
		"outside_battle": true,
		"drop_pickup": "item",
	},
	# Greed level (greed_pickup.gd)
	"money": {
		"name": "Money",
		"icon": "res://Greed/money.png",
		"flies_away": true,
		"drop_pickup": "",                 # dropped money is just gone
	},
	"gold_bar": {
		"name": "Gold Bar",
		"icon": "res://Greed/treasure_icons_16x16.png",
		"icon_region": Rect2(49, 32, 15, 16),
		"heavy": true,
		"drop_pickup": "greed:gold",
	},
}

# KEY ITEMS: permanent story items (letters...). They live in the inventory's
# "Key Items" tab, not in the regular slots: no Use, no Drop, no weight, and
# the flying money never touches them. Clicking one shows its text again.
#   name    = shown in the tab (translated with strings.csv)
#   icon    = picture (icon_region optional, like ITEMS)
#   text    = what it says (translated). A %s in it is replaced by the key
#             currently bound to text_key_action (Settings > key remapping).
const KEY_ITEMS = {
	"letter_v_ram": {
		"name": "Letter from V.",
		"icon": "res://Greed/Letter1.png",
		"text": "Press %s to ram.",
		"text_key_action": "ram",
		"text_touch": "Tap Ram to ram.",   # (phones / tablets: the Ram button)
	},
}
