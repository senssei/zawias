shader_type spatial;
// Zrzut głębi makiety: odległość wzdłuż osi kamery zakodowana w R (starszy bajt) i G (młodszy), B=1 to geometria.
render_mode unshaded, fog_disabled;

uniform vec3 proj_origin;
uniform vec3 proj_forward;
uniform float t0 = 10.0;
uniform float t1 = 90.0;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float v = clamp((dot(w - proj_origin, proj_forward) - t0) / (t1 - t0), 0.0, 1.0);
	float q = floor(v * 65535.0 + 0.5);
	float hi = floor(q / 256.0);
	float lo = q - hi * 256.0;
	vec3 enc = vec3(hi / 255.0, lo / 255.0, 1.0);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = enc;  // Compatibility: wynik trafia do zrzutu bez konwersji do sRGB
#else
	ALBEDO = srgb_to_linear(enc);
#endif
}
