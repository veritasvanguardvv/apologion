// The shadow the Guard wings cast on whoever is under them (guard_shadow.gd):
// it darkens the character from the top down. Bright wool goes grey, the
// face only a little, the black outline stays (as in the reference art).
shader_type canvas_item;
uniform float shadow : hint_range(0.0, 1.0) = 0.0;  // 1 = fully under the wings
uniform float reach = 2.0;                          // how far down it has come (0 top .. 1 bottom)
uniform vec2 span = vec2(-1.0, 1.0);                // the sprite's top / bottom (local y)
varying float ly;
void vertex() {
	ly = VERTEX.y;
}
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float t = (ly - span.x) / max(span.y - span.x, 0.001);
	float a = shadow * (1.0 - smoothstep(reach - 0.08, reach, t));
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb *= 1.0 - a * 0.275 * l * l * l;
	COLOR = c;
}
