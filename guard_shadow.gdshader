// The shadow the Guard wings cast on whoever is under them (guard_shadow.gd).
// There is one light, so a shaded pixel takes the sprite's OWN shadow
// colour: a palette swap (lit wool -> the grey already drawn on the sheep's
// underside, the face -> its own darker tone...), never an in-between shade.
// Colours already in shadow and the outline stay as they are. The shadow
// sweeps down from the top as the dome lands (a hard edge, in whole pixels).
shader_type canvas_item;
const int MAX_SWAPS = 8;
uniform float reach = 0.0;               // how far down it has come (0 top .. 1 bottom; <= 0 none)
uniform vec2 span = vec2(-1.0, 1.0);     // the sprite's top / bottom (local y)
uniform int swaps = 0;
uniform vec3 lit[MAX_SWAPS];             // a colour in the light ...
uniform vec3 shade[MAX_SWAPS];           // ... and the same colour in shadow
uniform float tolerance = 0.035;         // (anti-aliased neighbours of a palette colour)
varying float ly;
varying vec4 tint;     // the modulate alone (COLOR in fragment() already has the texture in it)
void vertex() {
	ly = VERTEX.y;
	tint = COLOR;
}
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float y = (ly - span.x) / max(span.y - span.x, 0.001);
	if (y < reach) {
		for (int i = 0; i < MAX_SWAPS; i++) {
			if (i >= swaps) {
				break;
			}
			if (distance(t.rgb, lit[i]) < tolerance) {
				t.rgb = shade[i];
				break;
			}
		}
	}
	COLOR = t * tint;
}
