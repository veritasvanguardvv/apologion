extends RefCounted
# ENEMY VERSES
# ------------
# Verses that ENEMIES recite on their turn. This list is separate from the
# player's verses (all_verses in character_body_2d.gd): the player can never
# discover or use these. Typing one just says "That's an enemy's verse".
#
# Give an enemy verses with its "verses" list in the Inspector (enemy.gd),
# e.g. ["Genesis 3:17"].
#
# Each entry:
#   title    = what the speech bubble shows as the reference
#   type     = the enemy becomes this type after reciting it. Then only player
#              attack verses of this type (or "all" = Universal) can hurt it.
#   damage   = damage to the player (Guard and Fear still reduce it)
#   en / es  = the text in English / Spanish (RVR1960)
#   counters = refs of PLAYER verses that counter it. Reciting one of them on
#              your very next turn does x3 damage (counter_multiplier in
#              character_body_2d.gd). Leave it empty [] = can't be countered.
#              To add more, just add refs here (they must exist in all_verses).

const VERSES = {
	"Genesis 3:17": {
		"title": "Genesis 3",
		"type": "sloth",
		"damage": 8,
		"en": "God cursed work to be painful.",
		"es": "Maldita será la tierra por tu causa; con dolor comerás de ella todos los días de tu vida.",
		"counters": ["Galatians 3:13"],
	},
}
