#version 450

layout(binding = 0) uniform UniformBufferObject {
    dvec2 translate;
    mat4 transformation;
} ubo;

layout(points) in;
layout(triangle_strip, max_vertices = 4) out;

layout(location = 0) in float inTexX[];
layout(location = 1) in float inTexWidth[];
layout(location = 2) in float inSize[];
layout(location = 3) in vec3 inColor[];

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out vec3 outColor;

void main(void)
{	
    vec4 topLeft = gl_in[0].gl_Position;
    float height = inSize[0] * ubo.transformation[1][1];
    float width = inSize[0] * ubo.transformation[0][0] * (inTexWidth[0] * (1600 / 40));

    // top-left vertex
    gl_Position = topLeft;
    fragTexCoord = vec2(inTexX[0], 0.0);
    outColor = inColor[0];
    EmitVertex();

    // top-right vertex
    gl_Position = topLeft + vec4(width,0.0, 0.0, 0.0);
    fragTexCoord = vec2(inTexX[0] + inTexWidth[0], 0.0);
    outColor = inColor[0];
    EmitVertex();

    // bottom-left vertex
    gl_Position = topLeft + vec4(0.0, height, 0.0, 0.0);
    fragTexCoord = vec2(inTexX[0], 1.0);
    outColor = inColor[0];
    EmitVertex();

    // bottom-right vertex
    gl_Position = topLeft + vec4(width, height, 0.0, 0.0);
    fragTexCoord = vec2(inTexX[0] + inTexWidth[0], 1.0);
    outColor = inColor[0];
    EmitVertex();

    EndPrimitive();
}