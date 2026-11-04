extends Node
# VerseManager (autoload / singleton)
# ------------------------------------
# Remembers which verses the player has discovered and which ones they have
# already used in the current "cycle". Because it is an autoload (see
# Project > Project Settings > Globals), it survives scene changes, so your
# discovered verses carry over from level to level.
#
# The cycle rule:
#   - Every verse you use goes into used_this_cycle.
#   - A verse in used_this_cycle can't be used again ("on cooldown")...
#   - ...until every discovered verse has been used. Then the list is cleared
#     and the cycle starts over.
#   - A verse you just discovered isn't in used_this_cycle yet, so it can be
#     used right away.
#
# Verses are identified by their "ref" string, e.g. "Matthew 5:28"
# (the same "ref" as in all_verses in character_body_2d.gd).

# Emitted whenever discovered/used changes, so the verse box can redraw itself.
signal verses_changed

var discovered: Array = []        # refs the player has found
var used_this_cycle: Array = []   # refs used since the last cycle reset


# Adds a verse to the discovered list. Returns true if it was new.
func discover(ref: String) -> bool:
	if ref in discovered:
		return false
	discovered.append(ref)
	verses_changed.emit()
	return true


func is_discovered(ref: String) -> bool:
	return ref in discovered


# True if the verse is discovered and not used yet this cycle.
# Reusable verses (shown with an infinity sign in the verse list) are never
# used up: they don't take part in the cycle at all.
const REUSABLE = ["Isaiah 40:31a"]

func is_reusable(ref: String) -> bool:
	return ref in REUSABLE

func can_use(ref: String) -> bool:
	return is_discovered(ref) and (is_reusable(ref) or not (ref in used_this_cycle))


func is_used(ref: String) -> bool:
	return ref in used_this_cycle


# Call this after a verse is successfully used.
func mark_used(ref: String) -> void:
	if is_reusable(ref):
		verses_changed.emit()
		return
	if not (ref in used_this_cycle):
		used_this_cycle.append(ref)
	# Have we used every discovered verse? Then start a new cycle.
	if remaining_count() == 0:
		used_this_cycle.clear()
		print("Verse cycle complete - all verses are available again")
	verses_changed.emit()


# How many discovered verses are still available this cycle.
func remaining_count() -> int:
	var count = 0
	for ref in discovered:
		if not (ref in used_this_cycle) and not is_reusable(ref):
			count += 1
	return count


# --- Save / load helpers (used by SaveManager) ---

func get_save_data() -> Dictionary:
	return {"discovered": discovered.duplicate(), "used_this_cycle": used_this_cycle.duplicate()}


func load_save_data(data: Dictionary) -> void:
	discovered = Array(data.get("discovered", []))
	used_this_cycle = Array(data.get("used_this_cycle", []))
	verses_changed.emit()


# A verse reference in the current language, e.g. "Psalm 17:8" -> "Salmos 17:8".
# The book names are translated in General/translations/strings.csv.
func ref_text(ref: String) -> String:
	var space = ref.rfind(" ")   # the book is everything before the last space
	if space == -1:
		return tr(ref)
	return tr(ref.substr(0, space)) + ref.substr(space)
