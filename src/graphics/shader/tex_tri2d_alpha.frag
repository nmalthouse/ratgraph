#version 420 core
layout (location = 0) in vec4 color;
layout (location = 1) in vec2 texcoord;
layout (location = 0) out vec4 FragColor;


uniform sampler2D text;
uniform vec3 textColor;

void main() {
    FragColor = color;
    FragColor.a *= texture(text, texcoord).r * 1.0;
}
