shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;
// Inverted-hull ink outline: a dark shell pushed out along the normal,
// scaled by view distance so the line stays about the same width on screen.
uniform vec4 ink : source_color = vec4(0.16, 0.13, 0.15, 1.0);
uniform float width = 0.0022;
void vertex(){
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += NORMAL * width * d;
}
void fragment(){
	ALBEDO = ink.rgb;
}
