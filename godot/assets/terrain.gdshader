shader_type spatial;
// Photo ground (Poly Haven CC0 textures) blended by height, slope and the map's painted colours.
// mode 0 = jungle island: sand at the shore, grass, forest dirt on slopes, rock up the volcano.
// mode 1 = quarry: gravel on the pit floor, soil walls on the benches, dirt roads, grass outside.

uniform int mode = 0;
uniform sampler2D tex_a : source_color, filter_linear_mipmap, repeat_enable; // sand / gravel
uniform sampler2D tex_b : source_color, filter_linear_mipmap, repeat_enable; // grass
uniform sampler2D tex_c : source_color, filter_linear_mipmap, repeat_enable; // rock / soil wall
uniform sampler2D tex_d : source_color, filter_linear_mipmap, repeat_enable; // dirt
uniform float tile = 14.0;
uniform float tint = 0.45;      // how much the painted map colour still shows through
uniform vec3 hot_spot = vec3(150.0, 60.0, -140.0);  // volcano crater (jungle)

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy / s).rgb * w.x + texture(t, p.xz / s).rgb * w.y + texture(t, p.xy / s).rgb * w.z;
}

void fragment() {
	vec3 col = COLOR.rgb;
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	vec2 uv = wpos.xz / tile;
	// One lookup per texture (cheap on tablets); the rotated UV for grass/dirt hides tiling.
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.61;
	vec3 a = texture(tex_a, uv).rgb;
	vec3 b = texture(tex_b, uv2).rgb;
	vec3 d = texture(tex_d, uv2).rgb;
	vec3 c = slope > 0.2 || wpos.y > 28.0 ? tri(tex_c, wpos, wnrm, tile * 0.8) : texture(tex_c, uv).rgb;
	vec3 g;
	float road_m = 0.0;
	if (mode == 0) {
		float sand = 1.0 - smoothstep(0.8, 2.6, wpos.y);
		float rock = max(smoothstep(0.35, 0.6, slope), smoothstep(30.0, 48.0, wpos.y));
		float dirt = smoothstep(0.18, 0.35, slope) * (1.0 - rock);
		g = mix(b, d, dirt);
		g = mix(g, c, rock);
		g = mix(g, a, sand);
	} else {
		float green = smoothstep(0.02, 0.12, col.g - col.r);
		float wall = smoothstep(0.25, 0.5, slope);
		float floor_g = 1.0 - smoothstep(-6.0, -2.0, wpos.y);
		// Road mask: the map paints haul roads a strong orange-brown.
		float road = smoothstep(0.12, 0.2, col.r - col.b) * (1.0 - smoothstep(0.42, 0.5, col.g));
		road_m = road * (1.0 - wall);
		g = mix(d, a, floor_g);
		g = mix(g, b, green);
		g = mix(g, c, wall);
		g = mix(g, d * vec3(1.05, 0.95, 0.85), road * (1.0 - wall));
	}
	// Keep the painted variation (greens, lava) without losing the photo detail.
	vec3 lum = vec3(dot(col, vec3(0.3, 0.59, 0.11)));
	ALBEDO = g * mix(vec3(1.0), col / max(lum, vec3(0.05)) * 0.55 + 0.45, tint * (1.0 - road_m * 0.85));
	ROUGHNESS = 0.95;
	if (mode == 0) {
		float hot = 1.0 - smoothstep(4.0, 16.0, distance(wpos.xz, hot_spot.xz));
		hot *= smoothstep(40.0, 50.0, wpos.y);
		EMISSION = vec3(1.0, 0.35, 0.05) * hot * 1.5;
	}
}
