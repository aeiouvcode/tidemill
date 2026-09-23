shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.075, 0.36, 0.42, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.23, 0.57, 0.57, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.94, 0.88, 1.0);
uniform float foam_width = 0.85;
uniform float wave_scale = 0.35;
uniform float wave_speed = 0.6;
uniform float sparkle_strength = 0.12;
uniform vec4 island_rect = vec4(-3.5, -3.5, 3.5, 3.5); // xz bounds of the platform

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), u.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), u.x), u.y);
}

varying vec2 world_xz;

void vertex(){
	// gentle swell so the shoreline laps
	VERTEX.y += 0.05 * sin(VERTEX.x * 0.28 + TIME * 0.9) + 0.04 * sin(VERTEX.z * 0.24 + TIME * 1.15);
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float sd_box(vec2 p, vec2 c, vec2 b){
	vec2 d = abs(p - c) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

void fragment(){
	vec2 p = UV * 90.0 * wave_scale;
	float n1 = vnoise(p + vec2(TIME * wave_speed, TIME * wave_speed * 0.7));
	float n2 = vnoise(p * 1.7 - vec2(TIME * wave_speed * 0.8, TIME * wave_speed * 0.5));
	float n = n1 * 0.65 + n2 * 0.35;
	// fake normal ripple
	float dx = vnoise(p + vec2(0.08, 0.0) + vec2(TIME * wave_speed, 0.0)) - n1;
	float dz = vnoise(p + vec2(0.0, 0.08) + vec2(0.0, TIME * wave_speed)) - n1;
	NORMAL = normalize(vec3(-dx * 6.0, 1.0, -dz * 6.0));

	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, n * 0.55);
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;

	// shore-SDF foam: distance from the platform edge, lapping with the swell
	vec2 shore_c = (island_rect.xy + island_rect.zw) * 0.5;
	vec2 shore_b = (island_rect.zw - island_rect.xy) * 0.5;
	float d_shore = sd_box(world_xz, shore_c, shore_b);
	d_shore += (vnoise(world_xz * 2.1 + vec2(TIME * 0.4, TIME * 0.3)) - 0.5) * 0.55;
	d_shore += 0.18 * sin(TIME * 1.1 + world_xz.x * 1.7 + world_xz.y * 1.3);
	float foam_line = 1.0 - smoothstep(0.0, foam_width, d_shore);
	float foam_n = vnoise(world_xz * 3.4 + vec2(TIME * 0.9, -TIME * 0.6));
	foam_line *= smoothstep(0.18, 0.62, foam_n + foam_line * 0.55);
	// second thin wash line just outside the main one
	float wash = (1.0 - smoothstep(0.0, foam_width * 2.2, d_shore)) * 0.35;
	wash *= smoothstep(0.35, 0.7, vnoise(world_xz * 2.2 - vec2(TIME * 0.5, TIME * 0.4)));
	ALBEDO = mix(ALBEDO, foam_color.rgb, clamp(foam_line + wash, 0.0, 1.0));

	// sun sparkle
	float sp = pow(max(0.0, vnoise(p * 6.4 + vec2(-TIME * 1.3, TIME)) - 0.86) * 7.0, 3.0);
	ALBEDO += vec3(1.0, 0.95, 0.8) * sp * sparkle_strength;
}
