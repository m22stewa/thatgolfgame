shader_type canvas_item;

uniform float s11 : hint_range(0.01, 1.0, 0.001) = 0.8;
uniform float s33 : hint_range(0.0, 1.0, 0.001) = .13;
uniform float s55 : hint_range(0.0, 1.0, 0.001) = .16;
uniform float s77 : hint_range(0.0, 10.0, 0.001) = .9;
uniform float s99 : hint_range(0.0, 100.0, 0.001) = 6.5;

uniform int Praticle_num : hint_range(0, 100, 1) = 30;

uniform float Range : hint_range(0.1, 1.0, 0.01) = .75;
uniform float speed : hint_range(0.1, 100.0, 0.01) = 2.;
uniform float gravity : hint_range(0.1, 5.0, 0.001) = .5;
uniform int TimeStep : hint_range(1, 10, 1) = 2;

uniform float ShneyMagnitude: hint_range(0.01, 10.0, 0.01) = 1.;

float randomseed (in float _st) {
	return fract(cos(_st*12.9898)*43758.5453123);
}

vec4 boom(int c, vec2 suv, float t) {

	vec4 COL = vec4(0.);

	for (int i = 0; i < Praticle_num; i++) {

		//float ox1 = mod(randomseed(float(i)*7.),1.);
		//float ox2 = mod(randomseed(float(i)*67.),1.);

		float ofx1 = (0.5 - randomseed(float(i + c*Praticle_num + 1)*7.325))*0.5;
		float ofx2 = (0.5 - randomseed(float(i + c/Praticle_num + 3)*17.688))*0.5;
		float theta = atan(ofx1, ofx2);
		float mt = pow(t*7.,s11);

		float x1 = sin(theta)*(pow(mt,1.) + randomseed(float(i/3)*7.)*0.5);
		float x2 = cos(theta)*(pow(mt,1.) + randomseed(float(i/3)*12.)*0.5);
		x2 += distance(vec2(x1 + ofx1, x2 + ofx2), vec2(ofx1, ofx2))*gravity;

		float v2 = (1./(TAU))*exp(-((pow(x1 - ofx1,2.)+pow(x2 + ofx2,2.))/(2.*ShneyMagnitude)))*s77;
		float v = max(1. - pow(distance(vec2(x1 + ofx1, x2 + ofx2), vec2(suv.x + ofx1, suv.y + ofx2)*s99)*s77, s55),0.) + v2*s33;
		float o = v;
		float f = 0.;

		if (c == 0) {
			COL += vec4(o,f,f,v);
		} else if (c - 1 == 0) {
			COL += vec4(f,o,f,v);
		} else if (c - 2 == 0) {
			COL += vec4(f,f,o,v);
		} else if (c - 3 == 0) {
			COL += vec4(o,o,f,v);
		} else if (c - 4 == 0) {
			COL += vec4(f,o,o,v);
		} else if (c - 5 == 0) {
			COL += vec4(o,f,o,v);
		} else {
			COL += vec4(o,o,o,v);
		}

		//COL.a += (0.5 - randomseed(float(i*7 + 3)+TIME*0.0002))*0.00007;
	}

	return COL;
}

bool inrange (in vec2 v1, in vec2 v2, in float r) {

	return ((v1.y <= v2.y + r && v1.y >= v2.y - r) && (v1.x <= v2.x + r && v1.x >= v2.x - r));
}

void fragment() {

	vec2 suv = (UV - 0.5)*2.;

	COLOR = vec4(0.);

	for (int j = 0; j < 6; j++) {

		float timestep = float(TimeStep)*speed;
		float td = 6.*float(j)/timestep + TIME*speed;
		float tf = td/timestep;

		float mt = mod(td, timestep);
		vec2 duv = suv + Range*(1. - vec2(randomseed(float(j)*37. + floor(tf)), randomseed(float(j)*17. + floor(tf)))*2.);
		COLOR += boom(j, duv, mt);
	}
}
