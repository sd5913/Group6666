shader_type canvas_item;
render_mode unshaded;
// Pixel-art look for the whole 3D view (drawn by scripts/view/pixel_post.gd over the world, under the HUD).
// 1. The picture is cut into big square art pixels, each taking the colour at its centre. The grid is pinned to the
//    run (`grid` follows a fixed point of the track plane), so pillars and the player keep their pixels while the camera
//    scrolls instead of shimmering.
// 2. The darker side of every strong edge gets a one-pixel outline (and the lighter side an optional highlight). Faint
//    edges (the pale background shapes against the sky) get none, so the backdrop stays behind the run.
// 3. Colours are pushed a little more vivid, then reduced to a few brightness steps (YCoCg, so hues don't drift; the
//    colour itself gets finer steps). Where the picture has a gradient the brightness steps are mixed with an ordered
//    4x4 Bayer dither, sitting on the same grid; flat areas (the sky, flat faces) stay one colour.
// References: depth/normal outline post-processing (godotshaders.com "3D Pixel art outline & highlight", CC0) and the
// pixel-snapping advice that goes with it; Bayer ordered dithering as in godotshaders.com "Arbitrary Color Reduction
// and Palette Ordered Dithering" and the Codrops "Building a Real-Time Dithering Shader" write-up. Written from scratch.

// This variant samples the tavern SubViewport texture.
uniform sampler2D source_texture : source_color, filter_nearest;
uniform float art_h = 270.0;     // art pixels from the bottom of the screen to the top
uniform vec2 grid = vec2(0.0);   // a corner of the art-pixel grid, in screen UV (it moves with the run)
uniform float levels = 16.0;     // brightness steps
uniform float chroma_levels = 64.0;  // steps of each colour axis
uniform float dither = 0.8;      // how strongly gradients are dithered (1: a full step)
uniform float outline = 0.4;     // how much darker the dark side of an edge gets
uniform float edge = 0.14;       // brightness difference (0..1) between neighbouring art pixels that counts as an edge
uniform float highlight = 0.0;   // how much lighter the light side of an edge gets
uniform float saturation = 1.15;
uniform float contrast = 1.05;
uniform float compat_gamma = 0.6;
uniform float compat_gain = 0.5;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// The colour of one art pixel: the screen at its centre.
vec3 cell_rgb(vec2 cell, vec2 corner, float px, vec2 res) {
	vec2 uv = (corner + (cell + 0.5) * px) / res;
	vec3 rgb = textureLod(source_texture, clamp(uv, vec2(0.0), vec2(1.0)), 0.0).rgb;

	return rgb;
}

void fragment() {
	vec2 res = vec2(textureSize(source_texture, 0));     // the art surface in pixels
	float px = max(1.0, floor(res.y / art_h + 0.5));     // screen pixels per art pixel (whole, so every one is square)
	vec2 corner = grid * res;
	vec2 cell = floor((UV * res - corner) / px);
	vec3 c = cell_rgb(cell, corner, px, res);
	// edges: compare with the four neighbouring art pixels
	float y = luma(c);
	float yr = luma(cell_rgb(cell + vec2(1.0, 0.0), corner, px, res));
	float yl = luma(cell_rgb(cell - vec2(1.0, 0.0), corner, px, res));
	float yd = luma(cell_rgb(cell + vec2(0.0, 1.0), corner, px, res));
	float yu = luma(cell_rgb(cell - vec2(0.0, 1.0), corner, px, res));
	float brighter = max(max(yr, yl), max(yd, yu)) - y;  // how much brighter the brightest neighbour is
	float darker = y - min(min(yr, yl), min(yd, yu));    // how much darker the darkest neighbour is
	// a gradient keeps going the same way on both sides; an edge is a step with flat on one side
	float ramp_x = (yr - y) * (y - yl) > 0.0 ? min(abs(yr - y), abs(y - yl)) : 0.0;
	float ramp_y = (yd - y) * (y - yu) > 0.0 ? min(abs(yd - y), abs(y - yu)) : 0.0;
	// a hard threshold: an edge either gets its outline or not, so soft edges don't turn into dotted lines
	float dark_side = smoothstep(edge, edge + 0.02, brighter);
	c *= 1.0 - outline * dark_side;
	c = mix(c, vec3(1.0), highlight * smoothstep(edge, edge + 0.02, darker) * (1.0 - dark_side));
	// a little more vivid
	c = mix(vec3(luma(c)), c, saturation);
	c = clamp((c - 0.5) * contrast + 0.5, 0.0, 1.0);
	// brightness in a few steps (dithered in gradients), colour in finer ones: YCoCg keeps the hues where they were
	float Y = dot(c, vec3(0.25, 0.5, 0.25));
	float co = 0.5 * c.r - 0.5 * c.b;
	float cg = -0.25 * c.r + 0.5 * c.g - 0.25 * c.b;
	ivec2 b = ivec2(mod(cell, 4.0));
	float th = (BAYER[b.y * 4 + b.x] + 0.5) / 16.0 - 0.5;
	float grad = smoothstep(0.001, 0.006, max(ramp_x, ramp_y)) * (1.0 - dark_side);
	Y = floor(Y * (levels - 1.0) + 0.5 + th * dither * grad) / (levels - 1.0);
	co = floor(co * chroma_levels + 0.5) / chroma_levels;
	cg = floor(cg * chroma_levels + 0.5) / chroma_levels;
	c = vec3(Y + co - cg, Y + cg, Y - co - cg);
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
