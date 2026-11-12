shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 deep_color : source_color = vec3(0.07,0.20,0.24);
uniform vec3 shallow_color : source_color = vec3(0.21,0.39,0.40);
uniform float opacity : hint_range(0.0,1.0)=0.83;
uniform float speed=0.12;
varying vec3 river_position;
void vertex(){river_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
  vec2 xz=river_position.xz;
  float wave=sin(xz.x*0.24+TIME*speed*3.2)*cos(xz.y*0.13-TIME*speed*2.4);
  float glint=sin(xz.x*.74+xz.y*.28+TIME*.36)*sin(xz.y*.63-TIME*.26);
  float shore=clamp(COLOR.r,0.0,1.0);
  ALBEDO=mix(deep_color,shallow_color,shore*0.50)+vec3(0.012)*wave+0.018*max(glint,0.0);
  ROUGHNESS=0.28;
  METALLIC=0.0;
  SPECULAR=0.36;
  ALPHA=opacity;
}
