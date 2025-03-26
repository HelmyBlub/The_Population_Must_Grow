#version 450

layout(points) in;
layout(triangle_strip, max_vertices = 4) out;

layout(location = 0) in vec2 scale[];
layout(location = 1) in uint inSpriteIndex[];
layout(location = 2) in uint inSize[];

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out uint spriteIndex;

void main(void)
{	
    vec4 center = gl_in[0].gl_Position;
    float size = inSize[0] / 2;
    float width = (size * scale[0].x) / center[3];
    float height = (size * scale[0].y) / center[3];
    center[0] = center[0] / center[3];
    center[1] = center[1] / center[3];
    center[3] = 1;

    // top-left vertex
    gl_Position = center + vec4(-width, -height, 0.0, 0.0);
    fragTexCoord = vec2(0.0, 0.0);
    spriteIndex = inSpriteIndex[0];
    EmitVertex();

    // top-right vertex
    gl_Position = center + vec4(width, -height, 0.0, 0.0);
    fragTexCoord = vec2(1.0, 0.0);
    spriteIndex = inSpriteIndex[0];
    EmitVertex();

    // bottom-left vertex
    gl_Position = center + vec4(-width, height, 0.0, 0.0);
    fragTexCoord = vec2(0.0, 1.0);
    spriteIndex = inSpriteIndex[0];
    EmitVertex();

    // bottom-right vertex
    gl_Position = center + vec4(width, height, 0.0, 0.0);
    fragTexCoord = vec2(1.0, 1.0);
    spriteIndex = inSpriteIndex[0];
    EmitVertex();

    EndPrimitive();
}