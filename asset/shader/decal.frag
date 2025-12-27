#version 420 core
layout (location = 0) in vec4 pos_cs;
layout (location = 1) in vec4 pos_world;
layout (location = 2) in vec3 decal_pos;

layout (location = 2) out vec4 FragColor;

layout(binding = 0) uniform sampler2D g_pos;
layout(binding = 1) uniform sampler2D g_norm;
layout(binding = 2) uniform sampler2D g_depth;
uniform mat4 view;
uniform mat4 viewInv;
uniform mat4 cam_view_inv;
uniform vec3 view_pos;
uniform vec2 screenSize;
uniform vec2 the_fucking_window_offset = vec2(0.0);
uniform float exposure;
uniform float gamma = 2.2;
uniform bool draw_debug = false;
uniform float far_clip;


void main(){
    vec2 uv = (gl_FragCoord.xy - the_fucking_window_offset) / screenSize;

    vec3 world_pos = texture(g_pos, uv).rgb;
    vec3 normal = texture(g_norm, uv).rgb;

    vec4 crap = vec4(world_pos - decal_pos, 1.0);
    crap.xyz /= 32.0;
    if(crap.x > 1.0 || crap.x < -1.0 || crap.y > 1.0 || crap.y < -1.0 || crap.z < -1.0 || crap.z > 1.0)
        discard;

    vec3 nn = (normal * 0.5) + 0.5;

    FragColor = vec4(nn, 0.5);
}

