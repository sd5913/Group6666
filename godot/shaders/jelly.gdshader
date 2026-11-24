shader_type spatial;
render_mode unshaded, shadows_disabled;
#include "res://shaders/jelly.gdshaderinc"
#include "res://shaders/slime-shape.gdshaderinc"
// Neutral white keeps the glint out of pixel_post's warm sky color mask.
const vec3 SLIME_GLINT = vec3(1.0);
const vec3 SLIME_EYE = vec3(0.19608, 0.10196, 0.17255);
uniform vec4 body : source_color = vec4(1.0);
uniform float rim = 0.65;
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
	// Match the stool guest's soft volume and upper-left reflection. Body is
	// supplied by the current level; only the shape and light treatment are shared.
	float u = clamp(x / 0.55, -1.0, 1.0);
	float v = 1.0 - h;
	float ny = clamp((v - 0.35) * 1.2, -1.0, 1.0);
	float nz = sqrt(max(0.04, 1.0 - 0.73 * u * u - 0.32 * ny * ny));
	float lambert = max(0.0, -0.48 * u - 0.50 * ny + 0.72 * nz);
	float volume = 0.64 + 0.52 * lambert - 0.23 * clamp((v - 0.64) / 0.36, 0.0, 1.0);
	float highlight = exp(-pow((u + 0.38) / 0.27, 2.0) - pow((v - 0.23) / 0.16, 2.0));
	float broad = exp(-pow((u + 0.31) / 0.56, 2.0) - pow((v - 0.37) / 0.55, 2.0));
	float cool = clamp((u - 0.56) / 0.36, 0.0, 1.0) * (1.0 - v * 0.55);
	float shade = 1.0 - 0.17 * clamp((v - 0.79) / 0.11, 0.0, 1.0);
	vec3 base = pow(body.rgb, vec3(1.0 / 1.52));
	vec3 color = (base * volume + highlight * vec3(67.0, 51.0, 47.0) / 255.0
		+ broad * vec3(16.0, 9.0, 5.0) / 255.0
		+ cool * vec3(8.0, 24.0, 34.0) / 255.0) * shade;
	color *= mix(0.70, 1.0, smoothstep(0.35, 0.85, abs(n.z)));

	// Keep the same left-hand highlight as the tavern guest. Eyes shift
	// right because the runner is facing into the course.
	vec2 pixel = floor(vec2(24.0 + x * 62.0, 4.0 + (1.0 - h) * 36.0));
	if ((pixel.x >= 9.0 && pixel.x <= 20.0 && pixel.y >= 5.0 && pixel.y <= 13.0)
			&& pixel.y > 18.0 - pixel.x && pixel.y < 24.0 - pixel.x * 0.5
			&& n.x < 0.15) {
		color = SLIME_GLINT;
	}
	// Place the eyes toward the forward side as in the guest reference,
	// mirroring its side-facing placement for the right-moving runner.
	float eye_x = pixel.x - 8.0;
	if (abs(n.z) > 0.5 && pixel.y >= 19.0 && pixel.y <= 25.0
			&& ((eye_x >= 23.0 && eye_x <= 26.0) || (eye_x >= 31.0 && eye_x <= 34.0))) {
		color = SLIME_EYE;
	}
	// Match the shared sRGB palette through the level's pixel postprocess.
	ALBEDO = pow(color, vec3(1.52));
}
