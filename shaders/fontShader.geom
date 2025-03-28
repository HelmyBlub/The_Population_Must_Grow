#version 450

layout(points) in;
layout(triangle_strip, max_vertices = 4) out;

layout(location = 0) in vec2 inTexCords[];
layout(location = 1) in vec2 inSize[];
layout(location = 2) in vec3 inColor[];

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out vec3 outColor;

void main(void)
{	
    vec4 topLeft = gl_in[0].gl_Position;
    float width = inSize[0][0];
    float height = inSize[0][1];

    // top-left vertex
    gl_Position = topLeft;
    fragTexCoord = vec2(inTexCords[0].x, 0.0);
    outColor = inColor[0];
    EmitVertex();

    // top-right vertex
    gl_Position = topLeft + vec4(width,0.0, 0.0, 0.0);
    fragTexCoord = vec2(inTexCords[0].x + 0.1, 0.0);
    outColor = inColor[0];
    EmitVertex();

    // bottom-left vertex
    gl_Position = topLeft + vec4(0.0, height, 0.0, 0.0);
    fragTexCoord = vec2(inTexCords[0].x, 1.0);
    outColor = inColor[0];
    EmitVertex();

    // bottom-right vertex
    gl_Position = topLeft + vec4(width, height, 0.0, 0.0);
    fragTexCoord = vec2(inTexCords[0].x+ 0.1, 1.0);
    outColor = inColor[0];
    EmitVertex();

    EndPrimitive();
}