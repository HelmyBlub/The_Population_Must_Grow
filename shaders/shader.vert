#version 450

layout(binding = 0) uniform UniformBufferObject {
    mat4 transformation;
    vec2 translate;
} ubo;

layout(location = 0) in vec2 inPosition;
layout(location = 1) in uint inSpriteIndex;
layout(location = 2) in uint inSize;

layout(location = 0) out vec2 scale;
layout(location = 1) out uint spriteIndex;
layout(location = 2) out uint size;

void main() {
    gl_Position = ubo.transformation * vec4(inPosition + ubo.translate, 1, 1);
    gl_Position[2] = 1 - (gl_Position[1] + 1) / 2 / gl_Position[3];
    spriteIndex = inSpriteIndex;
    scale[0] = ubo.transformation[0][0];
    scale[1] = ubo.transformation[1][1];
    size = inSize;
}
