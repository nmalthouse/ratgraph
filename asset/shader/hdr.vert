#version 460 core

layout (location = 0) in vec3 pos;
layout (location = 1) in vec2 tex_coord;

out vec2 TexCoords;

void main(){
    TexCoords = tex_coord;
    gl_Position = vec4(pos, 1.0);
}

