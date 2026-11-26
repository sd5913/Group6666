shader_type spatial;
render_mode unshaded, shadows_disabled, blend_mix;

#include "res://shaders/jelly.gdshaderinc"
#include "res://shaders/slime-shape.gdshaderinc"

uniform vec4 trail_color : source_color = vec4(1.0);
uniform float opacity = 0.5;

void vertex() {
	slime_shape(VERTEX);
}

void fragment() {
	ALBEDO = trail_color.rgb;
	ALPHA = opacity;
}
