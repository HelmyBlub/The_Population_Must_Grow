#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in float inTexX;
layout(location = 2) in float inTexWidth;
layout(location = 3) in float inSize;
layout(location = 4) in vec3 inColor;

layout(location = 0) out float outTexX;
layout(location = 1) out float outTexWidth;
layout(location = 2) out float outSize;
layout(location = 3) out vec3 outColor;

void main() {
    gl_Position = vec4(inPosition, 1.0, 1);
    outTexX = inTexX;
    outTexWidth = inTexWidth;
    outSize = inSize;
    outColor = inColor;
}
