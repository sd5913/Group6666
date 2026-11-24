shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled, cull_disabled, depth_draw_never;

uniform sampler2D cave_atlas : source_color, filter_linear, repeat_disable;
uniform int cave_index = 0;
uniform float camera_scroll = 0.0;
uniform float song_time = 0.0;
uniform float resonance = 0.0;

void vertex() {
	// Fill the camera at the depth of a distant wall. Use the camera projection
	// so the same depth test works in either renderer and with any aspect ratio.
	POSITION = PROJECTION_MATRIX * vec4(0.0, 0.0, -120.0, 1.0);
	POSITION.xy = VERTEX.xy * POSITION.w;
}

void fragment() {
	vec2 size = vec2(textureSize(cave_atlas, 0));
	vec2 plate = floor(size * 0.5);
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float plate_aspect = plate.x / plate.y;
	vec2 crop = vec2(min(1.0, aspect / plate_aspect), min(1.0, plate_aspect / aspect));
	vec2 uv = (SCREEN_UV - 0.5) * crop * 0.94 + vec2(0.5);
	uv.x += camera_scroll;
	if (cave_index == 0) {
		float water = smoothstep(0.41, 0.61, uv.y);
		uv.x += sin(floor(uv.y * 76.0) * 0.56 + song_time * 1.4) * 0.0028 * water;
	}
	// Mirror the next stretch of wall so running past the edge has no seam.
	uv.x = 1.0 - abs(mod(uv.x, 2.0) - 1.0);
	uv.y = clamp(uv.y, 0.0, 1.0);
	vec2 quadrant = vec2(float(cave_index % 2), float(cave_index / 2));
	// Leave a few source texels at the borders of each atlas quadrant.
	vec2 texel = uv * (plate - 6.0) + 3.0;
	vec3 color = texture(cave_atlas, (quadrant * plate + texel) / size).rgb;
	if (cave_index == 3) {
		float warm_rock = smoothstep(0.045, 0.22, color.r - color.b);
		color *= 1.0 + 0.04 * warm_rock * resonance;
	}
	ALBEDO = color;
}
