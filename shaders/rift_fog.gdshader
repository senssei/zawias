// SPDX-FileCopyrightText: 2026 Rafal Warzycha
// SPDX-License-Identifier: MIT
// Mgła ze Szczeliny nad kadrem półcutscenki (ADR 0012): płynący fioletowy opar i winieta.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.38, 0.22, 0.55, 1.0);
uniform float density = 0.45;      // 0 = brak mgły, 1 = sam opar (przejście)
uniform float vignette = 0.85;
uniform float speed = 0.035;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * vec2(1.78, 1.0) * 2.4;
	float t = TIME * speed;
	float n = fbm(uv + vec2(t, -t * 0.6) + fbm(uv * 0.7 - vec2(t * 0.8, t)) * 1.3);
	float mist = smoothstep(0.35, 0.85, n);
	float a = clamp(density * (0.55 + mist * 0.9) + (density > 0.95 ? 1.0 : 0.0), 0.0, 1.0);
	vec2 c = UV - 0.5;
	float vig = smoothstep(0.25, 0.8, length(c * vec2(1.2, 1.0))) * vignette;
	vec3 col = mix(tint.rgb * (0.6 + mist * 0.7), vec3(0.03, 0.01, 0.05), vig * 0.8);
	COLOR = vec4(col, max(a, vig * 0.9));
}
