shader_type spatial;
render_mode cull_back;
uniform vec4 tint : source_color = vec4(0.7,0.65,0.52,1.0);
uniform int family = 0;
uniform float metal_amount = 0.65;
uniform float surface_roughness = 0.47;
varying vec3 position_world;
varying vec3 normal_world;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
  vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
  return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() {
  position_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
  normal_world=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
  vec3 n=abs(normal_world);
  vec2 p=n.y>0.7?position_world.xz:(n.x>n.z?position_world.zy:position_world.xy);
  float grain=noise(p*16.0)*0.055+noise(p*3.7)*0.08+noise(p*0.18)*0.12;
  vec3 color=tint.rgb*COLOR.rgb*(0.85+grain);
  ROUGHNESS=0.91;
  if (family==0 || family==1) {
    float row_height=family==1?0.115:0.32;
    float unit_width=family==1?0.36:0.72;
    float row=floor(p.y/row_height);
    vec2 cell=vec2(p.x/unit_width+mod(row,2.0)*0.5,p.y/row_height);
    vec2 edge=min(fract(cell),1.0-fract(cell));
    float antialias=max(fwidth(cell.x),fwidth(cell.y));
    float mortar=1.0-smoothstep(0.025,0.04+antialias,min(edge.x,edge.y));
    color*=0.91+0.16*hash(floor(cell));
    color=mix(color,color*0.70,mortar*0.42);
    NORMAL_MAP=vec3(0.5+(noise(p*7.0)-0.5)*0.025,0.5+(noise(p.yx*7.0)-0.5)*0.025,1.0);
    NORMAL_MAP_DEPTH=0.25;
  } else if (family==2) {
    vec2 tile=p/vec2(0.25,0.38);
    float ridge=sin(tile.x*6.28318)*0.5+0.5;
    float seam=1.0-smoothstep(0.02,0.07+fwidth(tile.y),fract(tile.y));
    color*=0.83+0.12*ridge+0.14*noise(floor(tile));
    color=mix(color,color*0.65,seam*0.6);
    NORMAL_MAP=vec3(0.5+sin(tile.x*6.28318)*0.11,0.5,1.0);
    NORMAL_MAP_DEPTH=0.5;
  } else if (family==3) {
    color*=0.90+noise(vec2(p.x*25.0,p.y*0.4))*0.18;
    ROUGHNESS=0.83;
  } else if (family==4) {
    METALLIC=metal_amount; ROUGHNESS=surface_roughness;
  } else if (family==5) {
    float paving=sin(p.x*5.0)*sin(p.y*5.0);
    color*=0.98+paving*0.025;
  } else if (family==6) {
    color=mix(color,vec3(0.28,0.32,0.20),noise(p*0.014)*0.30);
    color*=0.87+noise(p*0.63)*0.18;
  }
  ALBEDO=color;
}
