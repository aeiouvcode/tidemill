shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;
// Port of the v4 sea: flat teal, shallows and lapping foam rings driven by a
// blurred land mask, plus soft broken foam at the shoreline.
uniform sampler2D mask : filter_linear, repeat_disable;
uniform float mb = 17.0;
uniform float u_time = 0.0;
uniform vec3 base_col : source_color = vec3(0.17, 0.40, 0.43);
uniform vec3 shallow : source_color = vec3(0.40, 0.62, 0.58);
varying vec3 w;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), u.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), u.x), u.y);
}
void vertex(){ w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec2 muv = (w.xz + mb) / (2.0 * mb);
	float m = (muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0) ? 0.0 : texture(mask, muv).r;
	float n = sin(w.x*0.35 + u_time*0.25) * sin(w.z*0.3 - u_time*0.2);
	vec3 col = base_col * (0.97 + 0.05*n);
	col = mix(col, shallow, smoothstep(0.0, 0.55, m) * 0.7);
	float ring = 0.5 + 0.5*sin(m*26.0 - u_time*1.1 + n*0.6);
	float brk = smoothstep(0.25, 0.65, vnoise(w.xz*2.6 + vec2(u_time*0.3, -u_time*0.2)));
	float foam = smoothstep(0.72, 0.95, ring) * smoothstep(0.03, 0.2, m) * (1.0 - smoothstep(0.3, 0.45, m)) * 0.45 * (0.5 + 0.5*brk);
	foam += smoothstep(0.45, 0.52, m) * 0.6;
	col = mix(col, vec3(0.93, 0.97, 0.94), clamp(foam, 0.0, 1.0) * 0.9);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
