// The hero drawn flat (the start screen, the end screen, the iris): the jelly block as it looks on screen, a rounded box
// with a dark outline, a darker rim and its little highlight. p: from its middle; h: half its size with the outline;
// r: its corners' radius; u: screen pixels per pixel at 648 high.

float hero_sd(vec2 p, vec2 h, float r) {
	vec2 q = abs(p) - h + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

vec4 hero_pixel(vec2 p, vec2 h, float r, vec3 body, vec3 line, float u) {
	float d = hero_sd(p, h, r);
	if (d > 0.0) {
		return vec4(0.0);
	}
	if (d > -2.0 * u) {
		return vec4(line, 1.0);
	}
	vec3 c = body;
	if (d > -5.0 * u) {
		c *= 0.86;
	}
	else if (p.y < -h.y * 0.3) {
		c = mix(c, vec3(1.0), 0.1);
	}
	vec2 e = p - vec2(h.x * 0.35, -h.y * 0.72);
	if (max(abs(e.x), abs(e.y)) < 2.0 * u) {
		c = mix(c, vec3(1.0), 0.65);
	}
	return vec4(c, 1.0);
}
