shader_type spatial;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define INST uniform
#else
#define INST instance uniform
#endif
// A jaw column made of voxels (built by scripts/view/voxel_column.gd, driven by scripts/mechanics/jaws.gd).
// Whole: like a pillar — the jaw's colour, bright at the working end (the face towards the gap) and darker away from
// it, each voxel a touch lighter or darker than its neighbours so the blocks read; it glows as it closes in.
// Broken (age >= 0): the voxels near the break fly off on their own, ballistically — popped up and out from where the
// column broke (sideways more than along the column), harder the nearer they were, spinning, bouncing on the ground
// under the jaw if there is one — and shrink away after a second or so; the farther ones let go a little later, so it
// crumbles outwards from the break. The rest of the column (beyond `keep`) is pulled back the way it came, out of the
// picture. Voxels sunk in the ground stay hidden there.
// Per voxel (MultiMesh): COLOR.r = brightness jitter, INSTANCE_CUSTOM = (centre x, y, z in the column, random 0..1).

INST vec4 tint : source_color = vec4(1.0, 0.5, 0.12, 1.0);
INST float glow = 0.0;          // 0..1
INST float shine = 1.0;         // how much it whitens and glows (small blocks on a pale sky keep their colour with less)
INST float fade_len = 0.0;      // metres from the working end to the far colour (0: fade_depth), as on the pillars
INST float solid_len = 0.0;     // metres from the working end that keep the full colour before the fade starts
INST float far_sky = 0.0;       // 1: the far end turns into the sky instead of the dark (hanging rows)
INST float grain = 1.0;         // how much each voxel differs from its neighbours (0: smooth; it melts away into the sky)
INST float age = -1.0;          // seconds since the column broke (< 0: whole)
INST vec3 blast = vec3(0.0);    // where it broke, in the column's own space (working end = origin)
INST float power = 5.0;         // how fast the voxels right at the break fly off (m/s)
INST float hole = 0.0;          // voxels this close to the break go at once (a dent) ...
INST float hold = 0.0;          // ... and the rest this much later
INST vec3 push = vec3(0.0);     // velocity the break hands on (the player's), strongest next to it
INST float floor_y = -1000.0;   // the ground under the jaw, in the column's space (-1000: none)
INST vec2 floor_x = vec2(0.0);  // how far that ground reaches along the run (column space)

uniform float gravity = 22.0;
uniform float voxel = 0.15;        // voxel edge (metres)
uniform float fade_depth = 5.0;    // metres from the working end down to full darkness, as on the pillars
uniform vec4 sky : source_color = vec4(0.98, 0.87, 0.74, 1.0);  // set every frame (5-5 warm / cool) when far_sky is used
uniform float glow_energy = 2.2;
uniform float crumble = 0.03;      // seconds per metre from the break before a voxel lets go
uniform float keep = 2.0;          // voxels farther than this from the break don't fly: that part of the column is pulled back
uniform float pull = 30.0;         // how fast it is pulled back (m/s²)
uniform float pop = 2.0;           // extra upward speed for the voxels right at the break (m/s)
uniform float bounce = 0.35;       // how much of its fall speed a voxel keeps when it bounces
uniform float life = 1.2;          // about how long a voxel flies before it shrinks away (seconds)

varying float from_end;
varying float jitter;
varying float flash;

float hash(float n) {
	return fract(sin(n * 127.1 + 0.13) * 43758.5453);
}

vec3 turn(vec3 v, vec3 axis, float a) {
	float c = cos(a);
	return v * c + cross(axis, v) * sin(a) + axis * dot(axis, v) * (1.0 - c);
}

void vertex() {
	vec3 c = INSTANCE_CUSTOM.xyz;
	float seed = INSTANCE_CUSTOM.w * 97.0;
	from_end = abs(c.y);
	jitter = COLOR.r;
	flash = 0.0;
	if (age >= 0.0) {
		bool has_floor = floor_y > -999.0;
		bool over_floor = c.x > floor_x.x && c.x < floor_x.y;
		if (has_floor && over_floor && c.y < floor_y - 0.05) {
			VERTEX = vec3(0.0);  // sunk in the pillar it stands on: never seen, stays there
		} else if (length(c - blast) > keep) {
			float t = max(age - hold, 0.0);
			VERTEX.y += sign(c.y) * 0.5 * pull * t * t;  // the far part of the column goes back where it came from
		} else {
			float d = length(c - blast);
			float t = age - (d < hole ? 0.0 : hold + d * crumble);
			if (t > 0.0) {
				vec3 r = vec3(hash(seed), hash(seed + 1.7), hash(seed + 3.1)) * 2.0 - 1.0;
				// sprayed out sideways from the break more than back along the column; gravity does the rest
				vec3 away = normalize((c - blast) * vec3(1.0, 0.4, 1.0) + r * 0.45 + vec3(0.0, 0.0, 0.01));
				float near = 1.0 / (1.0 + 0.6 * d);
				vec3 v = away * power * (0.55 + 0.6 * hash(seed + 5.3)) * near + push * near + r * 0.6;
				v.y += pop * near;
				vec3 p = c + v * t;
				p.y = c.y + v.y * t - 0.5 * gravity * t * t;
				float spun = t;
				float half_v = voxel * 0.5;
				if (has_floor && c.y > floor_y) {
					// lands on the ground under the jaw (if it is still over it then): one bounce, then it slides to a stop
					float h = c.y - floor_y - half_v;
					float t1 = (v.y + sqrt(max(v.y * v.y + 2.0 * gravity * h, 0.0))) / gravity;
					float x1 = c.x + v.x * t1;
					if (t > t1 && x1 > floor_x.x && x1 < floor_x.y) {
						float vy1 = bounce * (gravity * t1 - v.y);
						float t2 = 2.0 * vy1 / gravity;
						vec2 slow = v.xz * 0.5;
						float a = min(t - t1, t2);
						p.xz = c.xz + v.xz * t1 + slow * a;
						p.y = floor_y + half_v + vy1 * a - 0.5 * gravity * a * a;
						spun = t1 + a;
						if (t - t1 > t2) {
							float s = min(t - t1 - t2, 0.25);
							p.xz += slow * (s - s * s / 0.5);  // slowing to a stop over a quarter second
							p.y = floor_y + half_v;
							spun += s;
						}
					}
				}
				vec3 axis = normalize(r + vec3(0.001, 0.002, 0.003));
				float ang = (5.0 + 9.0 * hash(seed + 7.7)) * spun * (r.x < 0.0 ? -1.0 : 1.0);
				float end = life * (0.8 + 0.5 * hash(seed + 9.1));
				float size = 1.0 - smoothstep(end - 0.3, end, t);
				VERTEX = turn(VERTEX, axis, ang) * size + (p - c);
				NORMAL = turn(NORMAL, axis, ang);
				flash = 1.0 - smoothstep(0.0, 0.12, t);
			}
		}
	}
}

void fragment() {
	float len = fade_len > 0.0 ? fade_len : fade_depth;
	float f = clamp(1.0 - max(from_end - solid_len, 0.0) / max(len - solid_len, 0.01), 0.0, 1.0);
	f *= f;
	float cap = from_end < voxel ? 2.0 : 1.0;  // the working end glows harder, like a pillar's cap
	float j = 1.0 + (jitter - 1.0) * grain * mix(1.0, f, far_sky);  // no speckles in the sky a hanging row fades into
	vec3 lit = mix(tint.rgb, vec3(1.0), (0.15 + 0.35 * glow) * shine);
	ALBEDO = mix(mix(tint.rgb * 0.12, sky.rgb, far_sky), lit, f) * j;
	EMISSION = tint.rgb * (glow_energy * cap * (0.15 + glow) * f * f * shine + 0.6 * flash) * j + sky.rgb * 0.2 * far_sky * (1.0 - f);
	ROUGHNESS = 0.55;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO *= mix(0.6, 1.0, max(shine, far_sky * (1.0 - f)));
	EMISSION *= mix(0.4, 1.0, max(shine, far_sky * (1.0 - f)));  // (it lights in two passes that add up after their tone curve: pale colours went white)
#endif
}
