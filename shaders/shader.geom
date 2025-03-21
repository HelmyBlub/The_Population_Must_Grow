#version 450

layout (points) in;
layout (triangle_strip, max_vertices = 4) out;

layout (location = 0) out vec2 fragTexCoord;

void main(void)
{	
    vec4 center = gl_in[0].gl_Position;
    float size = 0.05;

    // top-left vertex
    gl_Position = center + vec4(-size, -size, 0.0, 0.0);
    fragTexCoord = vec2(0.0, 0.0);
    EmitVertex();

    // top-right vertex
    gl_Position = center + vec4(size, -size, 0.0, 0.0);
    fragTexCoord = vec2(1.0, 0.0);
    EmitVertex();

    // bottom-left vertex
    gl_Position = center + vec4(-size, size, 0.0, 0.0);
    fragTexCoord = vec2(0.0, 1.0);
    EmitVertex();

    // bottom-right vertex
    gl_Position = center + vec4(size, size, 0.0, 0.0);
    fragTexCoord = vec2(1.0, 1.0);
    EmitVertex();

    EndPrimitive();
}