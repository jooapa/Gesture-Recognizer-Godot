shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable;
uniform float progress : hint_range(0.0, 1.0) = 0.3;
uniform float scroll_speed = 0.5;

// Helper: HSV to RGB
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	// Animate hue with TIME
	float hue = fract(TIME * 0.2);
	vec3 rgb = hsv2rgb(vec3(hue, 1.0, 1.0));
	vec4 animated_color = vec4(rgb, 1.0);

	// Offset the UV based on TIME
	vec2 moving_uv = UV;
	moving_uv.x -= TIME * scroll_speed;

	// Sample texture
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a == 0.0) { tex = vec4(1.0); }

	// Dissolve using the moving noise
	float dissolve = texture(noise_tex, moving_uv).x;
	dissolve = step(progress, dissolve);

	vec4 final_color = tex * COLOR * animated_color;
	final_color.a *= dissolve;

	COLOR = final_color;
}
