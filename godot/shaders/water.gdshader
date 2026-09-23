shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.075, 0.36, 0.42, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.23, 0.57, 0.57, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.94, 0.88, 1.0);
uniform float foam_width = 0.9;
uniform float wave_scale = 0.35;
uniform float wave_speed = 0.6;
uniform float sparkle_strength = 0.35;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), u.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), u.x), u.y);
}

void vertex(){
	// gentle swell so the shoreline laps
	VERTEX.y += 0.05 * sin(VERTEX.x * 0.28 + TIME * 0.9) + 0.04 * sin(VERTEX.z * 0.24 + TIME * 1.15);
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

	// depth-based shoreline foam
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float scene_depth = -view_pos.z;
	float frag_depth = -VERTEX.z;
	float diff = scene_depth - frag_depth;
	float foam_line = 1.0 - smoothstep(0.0, foam_width, diff);
	// break the foam up with noise + time
	float foam_n = vnoise(p * 2.3 + vec2(TIME * 0.9, -TIME * 0.6));
	foam_line *= smoothstep(0.25, 0.75, foam_n + foam_line * 0.5);
	ALBEDO = mix(ALBEDO, foam_color.rgb, clamp(foam_line, 0.0, 1.0));

	// sun sparkle
	float sp = pow(max(0.0, vnoise(p * 3.1 + vec2(-TIME * 1.3, TIME)) - 0.72) * 3.5, 2.0);
	ALBEDO += vec3(1.0, 0.95, 0.8) * sp * sparkle_strength;
}
