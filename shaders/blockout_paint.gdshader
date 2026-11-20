// SPDX-FileCopyrightText: 2026 Rafal Warzycha
// SPDX-License-Identifier: MIT
shader_type spatial;
// Makieta „czytelna dla malarza” (tylko zrzuty do malowania): bruk, tynk z oknami, miedziany dach, kamienny mur.
// kind: 0 bruk, 1 dom, 2 mur, 3 bruk z rdzą
uniform int kind = 0;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 col = vec3(0.5);
	if (kind == 0 || kind == 3) {
		vec2 g = w.xz * 4.0;                       // kostki 25 cm, rzędy przesunięte
		g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
		vec2 f = fract(g);
		float mortar = step(0.08, f.x) * step(0.08, f.y);
		float v = 0.38 + 0.18 * h21(floor(g));
		col = mix(vec3(0.16), vec3(v, v, v * 1.05), mortar);
		if (kind == 3) col = mix(col, vec3(0.55, 0.25, 0.10), 0.55);
	} else if (kind == 1) {
		if (n.y > 0.5) {                           // dach: rzędy rdzawoczerwonej dachówki (kontrast z szarym brukiem)
			float stripe = step(0.15, fract(w.x * 3.0 + w.z * 3.0));
			col = mix(vec3(0.30, 0.10, 0.06), vec3(0.62, 0.24, 0.12), stripe * (0.7 + 0.3 * h21(floor(w.xz * 2.0))));
		} else {                                   // ściana: tynk + rząd okien co 1 m, ciemniejszy cokół
			float u = abs(n.x) > 0.5 ? w.z : w.x;
			float fu = fract(u);
			float win = step(0.32, fu) * step(fu, 0.68) * step(0.9, w.y) * step(w.y, 1.8);
			float win2 = step(0.32, fu) * step(fu, 0.68) * step(2.1, w.y) * step(w.y, 2.6);
			col = vec3(0.62, 0.50, 0.44);
			col = mix(col, vec3(0.30, 0.24, 0.22), step(w.y, 0.35));
			col = mix(col, vec3(0.95, 0.72, 0.35), max(win, win2));
			col = mix(col, vec3(0.25, 0.18, 0.14), step(2.75, w.y));   // gzyms pod dachem
		}
	} else if (kind == 2) {                        // mur z ciosów
		vec2 g = (abs(n.y) > 0.5) ? w.xz * 2.0 : vec2((abs(n.x) > 0.5 ? w.z : w.x) * 2.0, w.y * 4.0);
		g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
		vec2 f = fract(g);
		float mortar = step(0.06, f.x) * step(0.1, f.y);
		float v = 0.42 + 0.15 * h21(floor(g));
		col = mix(vec3(0.2), vec3(v, v * 0.98, v * 0.95), mortar);
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
