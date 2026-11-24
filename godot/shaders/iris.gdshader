shader_type canvas_item;
// The iris (scripts/view/iris.gd): black, in whole cells of the screen's pixels, but for a hole in the hero's shape. With
// hero_on, the hero is drawn in the hole, that opaque (at 1 there is only black and the hero, whatever scene is behind).

#include "res://shaders/hero2d.gdshaderinc"

uniform vec2 screen = vec2(1152.0, 648.0);
uniform float cell = 2.0;
uniform float u = 1.0;
uniform vec2 center = vec2(576.0, 324.0);
uniform vec2 half_size = vec2(22.0, 35.0);
uniform float corner = 15.0;
uniform float size = 1.0;
uniform float hero_on = 0.0;
uniform vec3 body = vec3(1.0, 0.68, 0.43);
uniform vec3 line = vec3(0.32, 0.12, 0.02);

void fragment() {
	vec2 p = (floor(UV * screen / cell) + 0.5) * cell - center;
	if (hero_sd(p, half_size * size, corner * size) > 0.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	}
	else if (hero_on > 0.0) {
		vec4 h = hero_pixel(p, half_size, corner, body, line, u);
		COLOR = h.a > 0.0 ? vec4(h.rgb, hero_on) : vec4(0.0, 0.0, 0.0, hero_on);
	}
	else {
		COLOR = vec4(0.0);
	}
}
