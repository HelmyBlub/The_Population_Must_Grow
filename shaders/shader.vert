#version 450

layout(binding = 0) uniform UniformBufferObject {
    mat4 transformation;
    vec2 translate;
} ubo;

layout(location = 0) in vec2 inPosition;
layout(location = 1) in uint inSpriteIndex;

layout(location = 0) out uint spriteIndex;

void main() {
    gl_Position = ubo.transformation * vec4(inPosition + ubo.translate, 1.0, 1);
    spriteIndex = inSpriteIndex;
}
