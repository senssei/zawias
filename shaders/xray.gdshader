shader_type spatial;
// Sylwetka postaci za przeszkodą (ściana, malunek): rysowana tylko tam, gdzie test głębi NIE przechodzi.
// Siatka przesunięta ku kamerze o `push`, żeby postać nie „prześwitywała” przez samą siebie (ręka za tułowiem).
render_mode unshaded, cull_back, depth_draw_never, depth_test_inverted, blend_mix, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.55, 0.78, 1.0, 0.5);
uniform float push = 1.0;   // 0.6 nie wystarczało: noga pod płaszczem prześwitywała (kąt kamery wydłuża odległość w osi widoku)

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.z += push;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = color.rgb;
	ALPHA = color.a * (0.55 + 0.45 * rim);
}
