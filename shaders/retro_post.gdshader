// Full-screen post pass: virtual low resolution + ordered dither + colour banding.
// All of it scales with the global `retro` dial; at 0.0 this is an exact pass-through.
shader_type canvas_item;

global uniform float retro;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 virtual_res = vec2(426.0, 240.0);
uniform float min_levels = 40.0;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0);
	return m[i] / 16.0;
}

void fragment() {
	vec2 res = vec2(textureSize(screen_tex, 0));
	float pix_amt = smoothstep(0.2, 0.95, retro);
	vec2 vr = mix(res, virtual_res, pix_amt);
	vec2 cell = floor(SCREEN_UV * vr);
	vec2 uv = (cell + 0.5) / vr;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;

	float d_amt = smoothstep(0.3, 1.0, retro);
	float levels = mix(255.0, min_levels, d_amt);
	float b = (bayer4(cell) - 0.5) * d_amt;
	c = floor(c * levels + b + 0.5) / levels;

	COLOR = vec4(c, 1.0);
}
