#version 450

layout(points) in;
layout(triangle_strip, max_vertices = 24) out;

layout(location = 0) in vec2 scale[];
layout(location = 1) in uint inSpriteIndex[];
layout(location = 2) in uint animationTimer[];

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out uint spriteIndex;

struct citizenPart {
    float width;
    float height;
    uint spriteIndex;
    vec2 offset;
} citizenParts[6];

void main(void)
{	
    vec4 center = gl_in[0].gl_Position;
    const float zoom = center[3];
    center[0] = center[0] / zoom;
    center[1] = center[1] / zoom;
    center[3] = 1;

    const uint IMAGE_CITIZEN_BODY = 14;
    const uint IMAGE_CITIZEN_HEAD = 15;
    const uint IMAGE_CITIZEN_PAW = 16;
    const uint IMAGE_CITIZEN_FOOT = 17;
    const uint TILE_SIZE = 20;
    const uint COMPLETE_CITIZEN_IMAGE_SIZE = 200;
    const float sizeFactor = 20.0 / 200.0 / 2;
    citizenParts = citizenPart[](
        citizenPart(20 * sizeFactor, 52 * sizeFactor, IMAGE_CITIZEN_PAW, vec2( -2.5 * scale[0].x / zoom, 0.0)),
        citizenPart(20 * sizeFactor, 52 * sizeFactor, IMAGE_CITIZEN_PAW, vec2( 2.5 * scale[0].x / zoom, 0.0)),
        citizenPart(68 * sizeFactor, 84 * sizeFactor, IMAGE_CITIZEN_HEAD, vec2(0.0, -5 * scale[0].y / zoom)),
        citizenPart(53 * sizeFactor, 75 * sizeFactor, IMAGE_CITIZEN_BODY, vec2(0.0, 0.0)),
        citizenPart(20 * sizeFactor, 37 * sizeFactor, IMAGE_CITIZEN_FOOT, vec2( -1.5 * scale[0].x / zoom,  5 * scale[0].y / zoom)),
        citizenPart(20 * sizeFactor, 37 * sizeFactor, IMAGE_CITIZEN_FOOT, vec2( 1.5 * scale[0].x / zoom,  5 * scale[0].y / zoom))
    );

    for(int i = 0; i < citizenParts.length(); i++ ){
        const citizenPart currentCitizenPart = citizenParts[i];
        const vec4 partCenter = center + vec4(currentCitizenPart.offset, 0, 0);
        const float width = (currentCitizenPart.width * scale[0].x) / zoom;
        const float height = (currentCitizenPart.height * scale[0].y) / zoom;
        // top-left vertex
        gl_Position = partCenter + vec4(-width, -height, 0.0, 0.0);
        fragTexCoord = vec2(0.0, 0.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        // top-right vertex
        gl_Position = partCenter + vec4(width, -height, 0.0, 0.0);
        fragTexCoord = vec2(1.0, 0.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        // bottom-left vertex
        gl_Position = partCenter + vec4(-width, height, 0.0, 0.0);
        fragTexCoord = vec2(0.0, 1.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        // bottom-right vertex
        gl_Position = partCenter + vec4(width, height, 0.0, 0.0);
        fragTexCoord = vec2(1.0, 1.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        EndPrimitive();
    }
}
