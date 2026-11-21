// Dogworks Racing story 006 (gameplay programmer). Racer pennant cloth.
// Target: Forward+ (the project default), 1 texture sample per fragment, ~40 vertices per flag.
// Flat pattern texture, unlit (the identity colour must read the same everywhere), and a gentle
// sideways wave that grows towards the tail. All values are uniforms set from PennantStyle.
shader_type spatial;
render_mode cull_disabled, unshaded;

group_uniforms look;
uniform sampler2D pattern : source_color, filter_nearest;
group_uniforms wave;
uniform float wave_amp = 0.05;   // meters of sideways displacement at the tail
uniform float wave_rate = 6.0;   // rad/s
uniform float wave_cycles = 1.2; // waves along the cloth
uniform float phase = 0.0;       // per-slot offset so neighbouring flags do not wave in step

const float TWO_PI = 6.2831853;

void vertex() {
	// UV.x is 0 at the pole and 1 at the tail: the pole end stays still.
	VERTEX.x += sin(UV.x * wave_cycles * TWO_PI - TIME * wave_rate + phase) * wave_amp * UV.x;
}

void fragment() {
	ALBEDO = texture(pattern, UV).rgb;
}
