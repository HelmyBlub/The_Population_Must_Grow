#version 450

layout(binding = 0) uniform UniformBufferObject {
    mat4 transformation;
} ubo;

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 inTexCoord;

layout(location = 0) out vec2 fragTexCoord;

void main() {
    gl_Position = ubo.transformation * vec4(inPosition, 1.0, 1);
    fragTexCoord = inTexCoord;
}
