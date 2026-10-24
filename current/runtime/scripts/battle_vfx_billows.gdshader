shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(.5,.46,.39,.7);
uniform float opacity = 1.0;
uniform float age = 0.0;
uniform float heat = 0.0;
uniform float seed = 0.0;
uniform float cloud_softness = 0.0;
uniform float soft_intersection = 0.0;
uniform sampler2D scene_depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0]*length(MODEL_MATRIX[0].xyz),INV_VIEW_MATRIX[1]*length(MODEL_MATRIX[1].xyz),INV_VIEW_MATRIX[2]*length(MODEL_MATRIX[2].xyz),MODEL_MATRIX[3]);
}
void fragment(){
 vec2 p=UV*2.0-1.0;
 vec2 q=p*3.0+vec2(seed,age*.19);
 float n=noise(q)*.58+noise(q*2.03+5.2)*.28+noise(q*4.01)*.14;
 n=mix(n,noise(q*.48)*.72+noise(q*.97+3.1)*.28,cloud_softness);
 float edge=1.0-smoothstep(.28+n*.23,.76+n*.23,length(p));
 float density=mix(smoothstep(.15,.8,n),.42+.58*n,cloud_softness)*edge;
 float light=.65+.42*(1.0-UV.y)+n*.17;
 ALBEDO=mix(tint.rgb*light,vec3(1.0,.34,.055),heat*(.35+.65*n));
 EMISSION=vec3(1.0,.43,.06)*heat*(.5+1.5*n);
 float soft_edge=1.0;
 if(soft_intersection>0.0){
  float scene_depth=texture(scene_depth_texture,SCREEN_UV).r;
  #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
  vec3 ndc=vec3(SCREEN_UV,scene_depth)*2.0-1.0;
  #else
  vec3 ndc=vec3(SCREEN_UV*2.0-1.0,scene_depth);
  #endif
  vec4 view_pos=INV_PROJECTION_MATRIX*vec4(ndc,1.0);
  float behind_distance=-view_pos.z/view_pos.w+VERTEX.z;
  soft_edge=smoothstep(0.0,soft_intersection,behind_distance);
 }
 float safe_rim=1.0-smoothstep(.65,.98,length(p));
 ALPHA=tint.a*opacity*density*safe_rim*soft_edge;
}
