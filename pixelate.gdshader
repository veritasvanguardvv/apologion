shader_type canvas_item;
// PIXELATE: makes any picture look like low-resolution pixel art by reading
// the texture in big square blocks ("pixels") instead of every tiny dot.
// pixel_size = how many texture pixels make one big pixel (bigger = chunkier).
uniform float pixel_size : hint_range(1.0, 128.0) = 24.0;

varying vec4 modulate_color;

void vertex() {
	modulate_color = COLOR;   // keeps the node's modulate working
}

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 blocks = tex_size / pixel_size;
	vec2 uv = (floor(UV * blocks) + 0.5) / blocks;   // the centre of each block
	COLOR = texture(TEXTURE, uv) * modulate_color;
}
