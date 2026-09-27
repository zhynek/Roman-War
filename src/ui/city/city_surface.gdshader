shader_type spatial;
render_mode diffuse_burley;
// Original analytical materials. Alpha is a family tag; no image textures and
// no alpha blending. World-space derivatives fade grain before it can shimmer.
varying highp vec3 surface_position;
varying vec4 surface_tint;
varying vec3 world_normal;
float grain(vec3 p) {
	p = mod(p, 128.0);
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}
float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(grain(cell), grain(cell + vec3(1,0,0)), f.x),
		mix(grain(cell + vec3(0,1,0)), grain(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(grain(cell + vec3(0,0,1)), grain(cell + vec3(1,0,1)), f.x),
		mix(grain(cell + vec3(0,1,1)), grain(cell + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	surface_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_tint = COLOR;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	float footprint = max(length(dFdx(surface_position)), length(dFdy(surface_position)));
	float broad = noise3(surface_position * 0.65);
	float detail_weight = 1.0 - smoothstep(0.018, 0.10, footprint);
	float mineral = mix(0.5, noise3(surface_position * 9.0), detail_weight);
	float age = 0.94 + (broad-0.5)*0.10 + (mineral-0.5)*0.06;
	float family = surface_tint.a;
	float roughness = 0.94;
	float relief = (mineral-0.5)*0.018*detail_weight;
	vec3 pigment = surface_tint.rgb;
	// Metre-scale masonry, laid in staggered courses. Mortar has physical
	// shallow relief; screen derivatives soften joints at a distance.
	vec2 face = abs(world_normal.x)>abs(world_normal.z) ? surface_position.zy : surface_position.xy;
	float course = floor(face.y/0.46);
	vec2 block = vec2((face.x+mod(course,2.0)*0.54)/1.08,face.y/0.46);
	vec2 edge = min(fract(block),1.0-fract(block))*vec2(1.08,0.46);
	float joint = 1.0-smoothstep(0.008,0.021+footprint*0.35,min(edge.x,edge.y));
	float block_age = grain(vec3(floor(block),3.0));
	if(family>0.90 && abs(world_normal.y)<0.4){
		pigment *= 0.91+block_age*0.15;
		pigment = mix(pigment,vec3(0.43,0.405,0.34),joint*0.65);
		relief += (1.0-joint)*0.027;
		roughness = 0.86+block_age*0.12;
	}
	if (family > 0.22 && family < 0.28) {
		// Slow lengthwise fibres distinguish timbers from mottled masonry.
		vec3 fibre_scale = abs(world_normal.y) > 0.6 ? vec3(1.4, 12.0, 27.0) : vec3(27.0, 1.4, 12.0);
		float fibres = noise3(surface_position * fibre_scale);
		age = 0.93 + (broad-0.5)*0.11 + (fibres-0.5)*0.16*detail_weight;
		roughness = 0.86;
		relief = (fibres-0.5)*0.021*detail_weight;
	} else if (family > 0.47 && family < 0.53) {
		age = 0.98 + (broad-0.5)*0.15 + (mineral-0.5)*0.06;
		roughness = 0.88;
		relief *= 0.6;
	} else if (family > 0.72 && family < 0.78) {
		float lime = noise3(surface_position * 2.8);
		float wear = noise3(surface_position*1.3)*0.65+noise3(surface_position*5.1)*0.35;
		float exposed = (1.0-smoothstep(0.32,0.39,wear))*(1.0-smoothstep(0.9,4.0,surface_position.y));
		pigment=mix(pigment,mix(vec3(0.58,0.40,0.29),vec3(0.55,0.50,0.40),joint),exposed);
		float damp=(1.0-smoothstep(0.05,0.7,surface_position.y))*(0.04+lime*0.09);
		pigment*=1.0-damp;
		age = 0.98 + (lime-0.5)*0.10 + (mineral-0.5)*0.09;
		relief+=(lime-0.5)*0.033-exposed*0.016;
	} else if (family < 0.075) {
		// Compacted earth has broad dry patches, without a tiled checkerboard.
		age = 0.94 + (broad-0.5)*0.17 + (mineral-0.5)*0.10;
	} else if (family < 0.13) {
		age = 0.96 + (mineral-0.5)*0.18;
	}
	// Derivative bump adds shallow mineral/lime and timber relief without a
	// texture or high-frequency unfiltered normal map. View-space gradients
	// remain attached to the actual surface as the camera rotates.
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 rx = cross(dy, NORMAL);
	vec3 ry = cross(NORMAL, dx);
	float determinant = dot(dx, rx);
	vec3 gradient = sign(determinant) * (dFdx(relief)*rx + dFdy(relief)*ry) / max(abs(determinant), 0.00001);
	NORMAL = normalize(NORMAL - clamp(gradient, vec3(-0.32), vec3(0.32)));
	ALBEDO = pow(pigment, vec3(2.2)) * age;
	ROUGHNESS = roughness;
	AO = 0.96 + mineral * 0.04;
}
