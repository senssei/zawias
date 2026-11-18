shader_type spatial;
// Malowany kadr z głębią: płaszczyzna rysuje malunek i wpisuje do bufora głębi głębię wyliczoną z malunku,
// więc postacie i rekwizyty 3D chowają się za namalowanymi dachami i ścianami.
// Malunek ma już światło; jedyne, co dokładamy, to cienie rzucane przez postacie i rekwizyty 3D (słońce).
render_mode cull_disabled, fog_disabled, depth_draw_always, ambient_light_disabled, specular_disabled;

uniform sampler2D paint : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D pdepth : filter_nearest, repeat_disable;   // R=starszy bajt, G=młodszy, B>0.5 = scena
uniform mat4 proj_view;
uniform vec3 proj_origin;
uniform vec3 proj_forward;
uniform float t0 = 10.0;
uniform float t1 = 90.0;
uniform float shadow_strength = 0.5;
uniform vec3 void_color : source_color = vec3(0.07, 0.05, 0.09);

float painted_t(vec2 uv) {
	vec4 d = textureLod(pdepth, clamp(uv, 0.0, 1.0), 0.0);
	bool inside = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
	if (!inside || d.b < 0.5) {
		return t1;
	}
	float q = floor(d.r * 255.0 + 0.5) * 256.0 + floor(d.g * 255.0 + 0.5);
	return mix(t0, t1, q / 65535.0);
}

vec2 proj_uv(vec3 w) {
	vec4 c = proj_view * vec4(w, 1.0);
	vec2 uv = c.xy / c.w * 0.5 + 0.5;
	return vec2(uv.x, 1.0 - uv.y);
}

// Siatka (płaszczyzna prostopadła do projektora) przesunięta wzdłuż promieni na głębię z malunku:
// dzięki temu cienie postaci padają na odtworzoną powierzchnię. Dokładną krawędź daje DEPTH we fragmencie.
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = painted_t(proj_uv(w));
	float tw = dot(w - proj_origin, proj_forward);
	VERTEX.z -= t - tw;
}

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 c = proj_view * vec4(w, 1.0);
	vec2 uv = c.xy / c.w * 0.5 + 0.5;
	uv.y = 1.0 - uv.y;
	bool inside = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
	vec3 col = inside ? texture(paint, uv).rgb : void_color;
	vec4 d = texture(pdepth, clamp(uv, 0.0, 1.0));
	float t = t1;
	if (inside && d.b > 0.5) {
		float q = floor(d.r * 255.0 + 0.5) * 256.0 + floor(d.g * 255.0 + 0.5);
		t = mix(t0, t1, q / 65535.0);
	}
	float tw = dot(w - proj_origin, proj_forward);
	vec3 p = w + proj_forward * (t - tw);
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	float z = clip.z / clip.w;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	DEPTH = z * 0.5 + 0.5;
#else
	DEPTH = z;
#endif
	ALBEDO = col;
	EMISSION = col * (1.0 - shadow_strength);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += vec3(shadow_strength * ATTENUATION);   // wynik: kolor * (1 - s + s * cień)
	}
}
