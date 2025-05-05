#version 450

layout(points) in;
layout(triangle_strip, max_vertices = 4) out;

layout(location = 0) in uint inSpriteIndex[];
layout(location = 1) in float width[];
layout(location = 2) in float height[];

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out uint spriteIndex;

void main(void)
{	
    // top-left vertex
    gl_Position = gl_in[0].gl_Position;
    fragTexCoord = vec2(0, 0);
    spriteIndex = inSpriteIndex[0];
    EmitVertex();

    // top-right vertex
    gl_Position = vec4(gl_in[0].gl_Position.x + width[0], gl_in[0].gl_Position.y, 1.0, 1.0);
    fragTexCoord = vec2(1.0, 0);
    spriteIndex = inSpriteIndex[0];
    EmitVertex();

    // bottom-left vertex
    gl_Position = vec4(gl_in[0].gl_Position.x, gl_in[0].gl_Position.y  + height[0], 1.0, 1.0);
    fragTexCoord = vec2(0.0, 1.0);
    spriteIndex = inSpriteIndex[0];
    EmitVertex();

    // bottom-right vertex
    gl_Position = vec4(gl_in[0].gl_Position.x + width[0], gl_in[0].gl_Position.y  + height[0], 1.0, 1.0);
    fragTexCoord = vec2(1.0, 1.0);
    spriteIndex = inSpriteIndex[0];
    EmitVertex();

    EndPrimitive();
}