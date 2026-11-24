shader_type canvas_item;
// Text filled with a vertical gradient (scripts/view/key_label.gd: a key's name in its own colours): from `top` at y0
// down to `bottom` at y1 (the item's own coordinates), the glyphs' coverage and the item's alpha kept.

uniform vec4 top : source_color = vec4(1.0);
uniform vec4 bottom : source_color = vec4(1.0);
uniform float y0 = 0.0;
uniform float y1 = 1.0;

varying float ly;

void vertex() {
	ly = VERTEX.y;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float k = clamp((ly - y0) / max(y1 - y0, 0.001), 0.0, 1.0);
	COLOR = vec4(mix(top.rgb, bottom.rgb, k), c.a);
}
