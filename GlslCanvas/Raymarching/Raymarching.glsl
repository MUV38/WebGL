#extension GL_OES_standard_derivatives : enable

#if GL_ES
precision mediump float;
#endif

#define EPSILON 0.0001
#define saturate(x) clamp(x, 0.0, 1.0)

uniform vec2 u_resolution;
uniform vec2 u_mouse;
uniform float u_time;

vec3 lightDir = normalize(vec3(0.5, 1.0, 1.0));
vec3 lightColor = vec3(1.0, 0.8, 0.65);

struct Material
{
    vec3 albedo;
};

struct RayResult
{
    float dist;
    Material mat;
};

//-------------------------------------------------------------------------------------
//  http://iquilezles.org/www/articles/distfunctions/distfunctions.htm
//-------------------------------------------------------------------------------------

RayResult sdSphere( vec3 p, float s, Material mat)
{
    RayResult result;
    {
        result.dist = length(p) - s;
        result.mat = mat;
    }
    return result;
}

RayResult sdBox( vec3 p, vec3 b, Material mat )
{
    RayResult result;
    {
        vec3 d = abs(p) - b;
        result.dist = min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
        result.mat = mat;
    }
    return result;
}

RayResult sdTorus( vec3 p, vec2 t, Material mat )
{
    RayResult result;
    {
        vec2 q = vec2(length(p.xz)-t.x,p.y);
        result.dist = length(q)-t.y;
        result.mat = mat;
    }
    return result;
}

RayResult sdPlane( vec3 p, vec4 n, Material mat )
{
    RayResult result;
    {
        // n must be normalized
        result.dist = dot(p,n.xyz) + n.w;
        result.mat = mat;
    }
    return result;
}

RayResult sdTwistTorus(vec3 p, vec2 t, Material mat)
{
    float c = cos(20.0*p.y);
    float s = sin(20.0*p.y);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xz,p.y);
    return sdTorus(q, t, mat);
}

RayResult opU( RayResult r1, RayResult r2 )
{
    if (r1.dist < r2.dist) {
        return r1;
    } else {
        return r2;
    }
}

//-------------------------------------------------------------------------------------

//-------------------------------------------------------------------------------------

// http://iquilezles.org/www/articles/checkerfiltering/checkerfiltering.htm
// http://iquilezles.org/www/articles/distfunctions/distfunctions.htm
float Checkers(in vec2 p)
{
    // filter kernel
    vec2 w = fwidth(p) + 0.001;
    // analytical integral (box filter)
    vec2 i = 2.0*(abs(fract((p-0.5*w)*0.5)-0.5)-abs(fract((p+0.5*w)*0.5)-0.5))/w;
    // xor pattern
    return 0.5 - 0.5*i.x*i.y;                  
}

RayResult Raymarch(vec3 pos)
{
    RayResult result;
    result.dist = 1.0;
    result.mat.albedo = vec3(0.0, 0.0, 0.0);

    // scene define
    result = opU(result, sdPlane(pos, vec4(0.0, 1.0, 0.0, 0.1), Material(vec3(0.5))));
    result = opU(result, sdSphere(pos - vec3(0.0, 0, 0), 0.1, Material(vec3(1.0, 0.0, 0.0))));
    result = opU(result, sdTwistTorus(pos - vec3(-0.3, 0.05, 0), vec2(0.1, 0.05), Material(vec3(0.0, 1.0, 0.0))));
    result = opU(result, sdBox(pos - vec3(0.3, 0, 0), vec3(.1, .1, .1), Material(vec3(0.0, 0.0, 1.0))));

    return result;
}

vec3 GetNormal(vec3 pos)
{
    return normalize(vec3(
        Raymarch(pos).dist - Raymarch(vec3(pos.x - EPSILON, pos.y, pos.z)).dist,
        Raymarch(pos).dist - Raymarch(vec3(pos.x, pos.y - EPSILON, pos.z)).dist,
        Raymarch(pos).dist - Raymarch(vec3(pos.x, pos.y, pos.z - EPSILON)).dist
    ));
}

float CalcSoftshadow(vec3 ro, vec3 rd, float mint, float tmax)
{
	float res = 1.0;
    float t = mint;
    for (int i=0 ; i<16 ; i++) {
		float h = Raymarch(ro + rd*t).dist;
        res = min(res, 8.0*h/t);
        t += clamp(h, 0.02, 0.10);
        if (h<0.001 || t>tmax) { break; }
    }
    return saturate(res);
}

//-------------------------------------------------------------------------------------

void main()
{
    vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / min(u_resolution.x, u_resolution.y);

    // light
    vec3 L = normalize(lightDir + vec3(sin(u_time), 0.0, cos(u_time)));

    // camera
    vec3 cam_pos = vec3(-5, 2, 10);
    vec3 cam_target = vec3(0, 0, 0);

    vec3 front = cam_target - cam_pos;
    float target_len = length(front);
    front = normalize(front);
    vec3 right = cross(vec3(0.0, 1.0, 0.0), front);
    vec3 up = cross(front, right);

    // ray
    vec3 screen_pos = right * uv.x + up * uv.y + front * target_len;
    vec3 ray = normalize(screen_pos - cam_pos);

    // color
    vec3 bg_color = vec3(0.7, 0.9, 1.0);
    vec3 amb_color = vec3(0.3);    
    vec3 color = bg_color;

    // ray marching
    const int DEPTH = 256;
    vec3 cur_pos = cam_pos;
    for (int i=0 ; i<DEPTH ; i++) {
        RayResult r = Raymarch(cur_pos);
        if (r.dist < EPSILON)
        {
            // lighting
            {
                vec3 normal = GetNormal(cur_pos);
                
                // diffuse
                vec3 diff = r.mat.albedo * vec3(saturate(dot(normal, L))) * lightColor;
                // shadow
                diff *= CalcSoftshadow( cur_pos, L, 0.02, 2.5 );
                // ambient
                vec3 amb  = r.mat.albedo * amb_color;
                // final color
                color = saturate(diff + amb);
            }
            break;
        }
        cur_pos += ray * r.dist;
    }

    // gamma
    color.rgb = pow(color.rgb, vec3(1.0/2.2));

    gl_FragColor = vec4(color, 1);
}