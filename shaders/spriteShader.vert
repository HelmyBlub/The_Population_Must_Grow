#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in uint inSpriteIndex;
layout(location = 2) in float inWidth;
layout(location = 3) in float inHeight;

layout(location = 0) out uint spriteIndex;
layout(location = 1) out float width;
layout(location = 2) out float height;

void main() {
    gl_Position = vec4(inPosition, 1, 1);
    spriteIndex = inSpriteIndex;
    width = inWidth;
    height = inHeight;
}
