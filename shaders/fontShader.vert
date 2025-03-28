#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 inTexCords;
layout(location = 2) in vec2 inSize;
layout(location = 3) in vec3 inColor;

layout(location = 0) out vec2 outTexCords;
layout(location = 1) out vec2 outSize;
layout(location = 2) out vec3 outColor;

void main() {
    gl_Position = vec4(inPosition, 1.0, 1);
    outTexCords = inTexCords;
    outSize = inSize;
    outColor = inColor;
}
