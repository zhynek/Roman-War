shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
varying vec3 position;
void vertex(){position=VERTEX;}
void fragment(){float fade=1.0/(1.0+length(VERTEX)*.04); float ripple=sin(position.x*1.8+position.z*.7+TIME*.8)+sin(position.z*2.1-TIME*.5); ALBEDO=vec3(.18,.29,.29)+vec3(ripple*.005*fade); ROUGHNESS=.29; METALLIC=.25; NORMAL_MAP=vec3(.5+ripple*.035*fade,.5+sin(position.x*2.0+TIME)*.06*fade,1.0);}
