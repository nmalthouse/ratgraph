#version 420 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec2 texcoord;
layout (location = 2) in vec3 normal;
layout (location = 3) in uint color;

layout (location = 0) out vec4 out_color;
layout (location = 1) out vec2 out_texcoord;

uniform mat4 model = mat4(1.0f);
uniform mat4 view = mat4(1.0f);
void main() {
   //gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
   //gl_Position = model * view * vec4(aPos,  1.0);
   gl_Position =   view * model * vec4(aPos,  1.0);
   out_color = unpackUnorm4x8(color).abgr;
   out_texcoord = texcoord;
};
