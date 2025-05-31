#version 450

layout(binding = 0) uniform UniformBufferObject {
    dvec2 translate;
    mat4 transformation;
} ubo;

layout(location = 0) in dvec2 inPosition;
layout(location = 1) in uint inSpriteIndex;
layout(location = 2) in uint inSize;
layout(location = 3) in float inRotate;
layout(location = 4) in float inCutY;

layout(location = 0) out vec2 scale;
layout(location = 1) out uint spriteIndex;
layout(location = 2) out uint size;
layout(location = 3) out float rotate;
layout(location = 4) out float cutY;

void main() {
    gl_Position = ubo.transformation * vec4(inPosition + ubo.translate, 1, 1);
    gl_Position[2] = 0.9 - (gl_Position[1] / gl_Position[3] + 1) / 3.0;
    spriteIndex = inSpriteIndex;
    scale[0] = ubo.transformation[0][0];
    scale[1] = ubo.transformation[1][1];
    size = inSize;
    rotate = inRotate;
    cutY = inCutY;
}
