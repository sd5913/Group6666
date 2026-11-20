varying vec2 slime_plane;
varying vec3 slime_normal;

void vertex() {
	slime_plane = vec2(VERTEX.x, slime_height(VERTEX));
	slime_normal = NORMAL;
	slime_shape(VERTEX);
}

void fragment() {
	vec3 n = normalize(slime_normal);
	float h = slime_plane.y;
	float x = slime_plane.x;
	vec3 color = SLIME_BODY;
	if (h < 0.21 || n.x > 0.72) {
		color = SLIME_SHADOW;
	} else if (h < 0.33 || n.x > 0.51) {
		color = SLIME_SHADE;
	} else if (h > 0.73 || n.y > 0.48 || n.x < -0.40) {
		color = SLIME_RIM;
	}

	// Keep the same left-hand highlight as the tavern guest. Eyes shift
	// right because the runner is facing into the course.
	vec2 pixel = floor(vec2(24.0 + x * 62.0, 4.0 + (1.0 - h) * 36.0));
	if ((pixel.x >= 9.0 && pixel.x <= 20.0 && pixel.y >= 5.0 && pixel.y <= 13.0)
			&& pixel.y > 18.0 - pixel.x && pixel.y < 24.0 - pixel.x * 0.5
			&& n.x < 0.15) {
		color = SLIME_CREAM;
	}
	if (abs(n.z) > 0.5 && pixel.y >= 19.0 && pixel.y <= 25.0
			&& ((pixel.x >= 23.0 && pixel.x <= 26.0) || (pixel.x >= 31.0 && pixel.x <= 34.0))) {
		color = SLIME_EYE;
	}
	// Match the shared sRGB palette through the level's pixel postprocess.
	ALBEDO = pow(color, vec3(1.52));
}
