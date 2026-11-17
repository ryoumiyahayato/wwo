shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float opacity=1.0;
uniform vec4 tint:source_color=vec4(.16,.14,.12,.8);
uniform bool confirmed_penetration=false;
void fragment(){
 vec2 p=UV*2.0-1.0;float r=length(p);
 float rim=1.0-smoothstep(.45,.98,r);
 float mark=confirmed_penetration ? mix(.95,.45,smoothstep(.15,.65,r)) : .58;
 ALBEDO=tint.rgb;ALPHA=tint.a*opacity*rim*mark;
}
