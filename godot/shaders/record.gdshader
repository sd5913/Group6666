shader_type canvas_item;
// The nested records (scripts/view/record_view.gd), drawn in whole cells of the screen's pixels like the rest of the game:
// five rings, the first level's innermost, each in its level's colour with darker grooves and a highlight turning with
// it, a dark hole in the middle and the hero standing in it.

#include "res://shaders/hero2d.gdshaderinc"

uniform vec2 screen = vec2(1152.0, 648.0);
uniform vec2 center = vec2(576.0, 324.0);
uniform float cell = 2.0;
uniform float u = 1.0;
uniform float radii[6];
uniform vec4 colors[5];
uniform float angles[5];
uniform float pulse = 0.0;
uniform vec3 hole = vec3(0.1, 0.09, 0.22);
uniform vec2 hero_center = vec2(576.0, 324.0);
uniform vec2 hero_half = vec2(22.0, 35.0);
uniform float hero_corner = 15.0;
uniform vec3 body = vec3(1.0, 0.68, 0.43);
uniform vec3 line = vec3(0.32, 0.12, 0.02);

const float TAU_ = 6.28318530718;

vec3 ring(int i, float r, float a, float b, float th) {
	vec3 c = colors[i].rgb * (1.0 + 0.1 * pulse);
	if (b - r < 1.5 * cell) {  // its edge
		return colors[i].rgb * 0.3;
	}
	if (r - a < 3.0 * cell) {  // the shadow of the record inside it
		c *= 0.8;
	}
	float t = (r - a) / (b - a);
	float turn = th - angles[i];
	bool broken = fract(turn / TAU_ * 7.0) < 0.14;
	if (!broken && (abs(t - 0.36) * (b - a) < 0.5 * cell || abs(t - 0.66) * (b - a) < 0.5 * cell)) {
		c *= 0.68;  // a groove
	}
	float h = cos(2.0 * (turn - 0.6));
	if (h > 0.94) {  // the highlight, across the record
		c = mix(c, vec3(1.0), 0.32);
	}
	else if (h > 0.76) {
		c = mix(c, vec3(1.0), 0.14);
	}
	return c;
}

void fragment() {
	vec2 q = (floor(UV * screen / cell) + 0.5) * cell;
	vec2 p = q - center;
	float r = length(p);
	float th = atan(p.y, p.x);
	vec4 o = vec4(0.0);
	if (r >= radii[5] && length(p - vec2(0.0, 6.0 * u)) < radii[5]) {
		o = vec4(0.0, 0.0, 0.0, 0.2);  // its shadow on the sky
	}
	if (r < radii[0]) {
		o = vec4(hole, 1.0);  // the hole: the sky behind, so the hero stands out as on the run
	}
	else {
		for (int i = 0; i < 5; i++) {
			if (r >= radii[i] && r < radii[i + 1]) {
				o = vec4(ring(i, r, radii[i], radii[i + 1], th), 1.0);
				break;
			}
		}
	}
	vec4 h = hero_pixel(q - hero_center, hero_half, hero_corner, body, line, u);
	if (h.a > 0.0) {
		o = h;
	}
	COLOR = o;
}
