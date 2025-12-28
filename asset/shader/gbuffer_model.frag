#version 420 core
layout (location = 0) out vec4 g_pos;
layout (location = 1) out vec4 g_norm;
layout (location = 2) out vec4 g_albedo;


layout (location = 0) in vec4 in_color;
layout (location = 1) in vec2 in_texcoord;
layout (location = 2) in vec3 in_normal;
layout (location = 3) in vec3 in_frag_pos;
layout (location = 6) in mat3 in_tbn;
layout (location = 5) in float blend;

layout (binding = 0) uniform sampler2D diffuse_texture;
layout (binding = 1) uniform sampler2D blend_texture;
layout (binding = 2) uniform sampler2D normal_texture;

uniform bool do_normal = false;

vec3 bumpNorm(){
    if(do_normal == false)
        return in_normal;
    vec3 norm = texture(normal_texture, in_texcoord).xyz * 2.0 - 1.0;
    return  normalize(in_tbn * norm);
}


void main(){
    g_pos = vec4(in_frag_pos,1);
    //g_norm = vec4(texture(normal_texture, in_texcoord).rgb, 1);
    //g_norm = vec4(normalize(in_normal),1);
    g_norm = vec4(bumpNorm(),1);
    //g_norm = texture(normal_texture, in_texcoord);
   
    g_albedo = mix(texture(diffuse_texture, in_texcoord), texture(blend_texture, in_texcoord), blend) * in_color;
   
    //g_albedo = vec4(0.2,0.2,0.2,1.0);
    if(g_albedo.a < 0.1)
        discard;
}
