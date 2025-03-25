#version 450
#extension GL_EXT_nonuniform_qualifier : enable
layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) flat in uint spriteIndex;

layout(location = 0) out vec4 outColor;

layout(binding = 1) uniform sampler2D texSampler[];

void main() {
    outColor = texture(texSampler[nonuniformEXT(spriteIndex)], fragTexCoord);
}
