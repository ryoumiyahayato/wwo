shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(0.7,0.72,0.73,0.8);
uniform float opacity = 1.0;
uniform float age = 0.0;
void vertex(){
 MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}
void fragment(){
 vec2 p = UV * 2.0 - 1.0;
 float edge = 1.0 - smoothstep(0.35, 1.0, length(p));
 float billow = 0.78 + 0.12*sin(p.x*11.0+p.y*6.0+age*0.23)*sin(p.y*13.0-p.x*4.0-age*0.17);
 ALBEDO = tint.rgb * (0.86 + 0.14*(1.0-UV.y));
 ALPHA = edge * billow * tint.a * opacity;
}
