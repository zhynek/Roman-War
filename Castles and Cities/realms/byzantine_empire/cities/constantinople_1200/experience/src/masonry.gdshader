shader_type spatial;
render_mode cull_back;
uniform vec4 tint : source_color = vec4(0.7,0.65,0.52,1.0);
uniform int family = 0;
uniform float metal_amount = 0.65;
uniform float surface_roughness = 0.47;
uniform vec2 ward_origin = vec2(0.0);
uniform vec2 ward_polygon[16];
uniform int ward_vertex_count = 5;
uniform vec4 ground_tint : source_color = vec4(0.48,0.50,0.38,1.0);
varying vec3 position_world;
varying vec3 normal_world;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
  vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
  return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
// Procedural frequencies must fade to their average when smaller than a pixel.
// MSAA alone cannot filter aliasing generated inside the fragment shader.
float resolution_weight(vec2 p) {
  return 1.0-smoothstep(0.25,1.1,max(length(dFdx(p)),length(dFdy(p))));
}
float filtered_noise(vec2 p) { return mix(0.5,noise(p),resolution_weight(p)); }
void vertex() {
  position_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
  normal_world=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
  vec3 n=abs(normal_world);
  vec2 p=n.y>0.7?position_world.xz:(n.x>n.z?position_world.zy:position_world.xy);
  float grain=filtered_noise(p*16.0)*0.055+filtered_noise(p*3.7)*0.08+filtered_noise(p*0.18)*0.12;
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
    float resolved=resolution_weight(cell);
    color*=0.91+0.16*mix(0.5,hash(floor(cell)),resolved);
    color=mix(color,color*0.70,mix(0.08,mortar,resolved)*0.42);
    // Architecture meshes do not supply tangent frames. Keep their geometric
    // normals instead of writing an undefined tangent-space NORMAL_MAP.
  } else if (family==2) {
    vec2 tile=p/vec2(0.25,0.38);
    float ridge=sin(tile.x*6.28318)*0.5+0.5;
    float seam=1.0-smoothstep(0.02,0.07+fwidth(tile.y),fract(tile.y));
    float resolved=resolution_weight(tile);
    color*=0.83+0.12*mix(0.5,ridge,resolved)+0.14*mix(0.5,noise(floor(tile)),resolved);
    color=mix(color,color*0.65,mix(0.045,seam,resolved)*0.6);
  } else if (family==3) {
    color*=0.90+filtered_noise(vec2(p.x*25.0,p.y*0.4))*0.18;
    ROUGHNESS=0.83;
  } else if (family==4) {
    METALLIC=metal_amount; ROUGHNESS=surface_roughness;
  } else if (family==5) {
    float paving=sin(p.x*5.0)*sin(p.y*5.0);
    color*=0.98+paving*0.025*resolution_weight(p*5.0);
  } else if (family==6) {
    color=mix(color,vec3(0.28,0.32,0.20),filtered_noise(p*0.014)*0.30);
    color*=0.87+filtered_noise(p*0.63)*0.18;
  }
  if (family==9) {
    vec2 local=vec2(position_world.x,-position_world.z)-ward_origin;
    float distance_edge=10000.0;
    for(int i=0;i<ward_vertex_count;i++) {
      vec2 a=ward_polygon[i], b=ward_polygon[(i+1)%ward_vertex_count], ab=b-a;
      distance_edge=min(distance_edge,length(local-a-ab*clamp(dot(local-a,ab)/dot(ab,ab),0.0,1.0)));
    }
    vec3 grass=ground_tint.rgb*(0.85+grain);
    grass=mix(grass,vec3(0.28,0.32,0.20),filtered_noise(p*0.014)*0.30);
    grass*=0.87+filtered_noise(p*0.63)*0.18;
    color=mix(grass,color,smoothstep(0.0,9.0,distance_edge));
  }
  if (family==8) {
    float mottling=filtered_noise(p*0.75);
    float wear=smoothstep(0.38,0.7,filtered_noise(p*2.1));
    color*=0.87+0.19*mottling;
    color=mix(color,color*vec3(0.77,0.73,0.65),wear*0.23);
    ROUGHNESS=0.98;
  }
  ALBEDO=color;
}
