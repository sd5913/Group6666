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
uniform bool slime = false;
uniform vec3 body = vec3(1.0, 0.68, 0.43);
uniform vec3 line = vec3(0.32, 0.12, 0.02);

// Broad dome with a softened, flat foot, matching the runner's visible profile.
float slime_sd(vec2 p, vec2 h) {
	float y = clamp(0.5 + p.y / (2.0 * h.y), 0.0, 1.0);
	float crown = max(0.0, 0.73 - y) / 0.78;
	float heel = max(0.0, y - 0.86);
	float width = sqrt(1.0 - crown * crown) - 0.095 * smoothstep(0.0, 0.14, heel);
	return max(abs(p.y) - h.y, abs(p.x) - h.x * width);
}

vec3 slime_pixel(vec2 p) {
	float d = slime_sd(p, half_size);
	if (d > -1.5 * u) {
		return line;
	}
	vec2 q = p / half_size;
	vec3 c = body * mix(1.06, 0.76, smoothstep(-0.8, 0.85, q.y + q.x * 0.35));
	if (q.y > -0.04 && q.y < 0.30
			&& (abs(q.x - 0.08) < 0.073 || abs(q.x - 0.40) < 0.073)) {
		c = vec3(0.12, 0.06, 0.11);
	}
	if ((q.y > -0.76 && q.y < -0.59 && q.x > -0.44 && q.x < -0.21)
			|| (q.y >= -0.59 && q.y < -0.47 && q.x > -0.52 && q.x < -0.36)) {
		c = vec3(1.0);
	}
	return c;
}

void fragment() {
	vec2 p = (floor(UV * screen / cell) + 0.5) * cell - center;
	vec2 h = half_size * size;
	float d = slime ? slime_sd(p, h) : hero_sd(p, h, corner * size);
	if (d > 0.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	}
	else if (hero_on > 0.0) {
		vec4 hero = slime ? vec4(slime_pixel(p), 1.0) : hero_pixel(p, half_size, corner, body, line, u);
		COLOR = hero.a > 0.0 ? vec4(hero.rgb, hero_on) : vec4(0.0, 0.0, 0.0, hero_on);
	}
	else {
		COLOR = vec4(0.0);
	}
}
