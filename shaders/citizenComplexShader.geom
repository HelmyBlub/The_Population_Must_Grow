#version 450

layout(points) in;
layout(triangle_strip, max_vertices = 52) out;

layout(location = 0) in vec2 scale[];
layout(location = 1) in uint inSpriteIndex[];
layout(location = 2) in uint animationTimer[];
layout(location = 3) in float moveSpeed[];

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out uint spriteIndex;

struct citizenPart {
    float width;
    float height;
    uint spriteIndex;
    vec2 offset;
    float angle;
    vec2 rotatePivot;

} citizenParts[13];

vec2 rotateAroundPoint(vec2 point, vec2 pivot, float angle){
    vec2 translated = point - pivot;

    float s = sin(angle);
    float c = cos(angle);
    mat2 rot = mat2(c, -s, s, c);
    vec2 rotated = rot * translated;

    return rotated + pivot;
}

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
    const uint IMAGE_CITIZEN_EAR_FRONT = 18;
    const uint IMAGE_CITIZEN_EAR_SIDE = 19;
    const uint IMAGE_CITIZEN_EYE_LEFT = 20;
    const uint IMAGE_CITIZEN_EYE_RIGHT = 21;
    const uint IMAGE_CITIZEN_PUPIL1 = 22;
    const uint IMAGE_CITIZEN_PUPIL2 = 23;
    const uint IMAGE_BLACK_PIXEL = 24;

    const uint TILE_SIZE = 20;
    const uint COMPLETE_CITIZEN_IMAGE_SIZE = 200;
    const float sizeFactor = 20.0 / 200.0;
    const float sizeFactorHalve = 20.0 / 200.0 / 2;
    const float footAnimationOffset = sin(animationTimer[0] / 100.0 * moveSpeed[0]);
    const float handAnimationOffset = ( -sin(animationTimer[0] / 100.0 * moveSpeed[0]) + 1) * 10;
    const float handAnimationOffset2 = (sin(animationTimer[0] / 100.0 * moveSpeed[0]) + 1) * 10;
    const float earRotate = sin(animationTimer[0] / 100.0 * moveSpeed[0]) * 0.25;
    citizenParts = citizenPart[](
        citizenPart(20 * sizeFactorHalve, 37 * sizeFactorHalve, IMAGE_CITIZEN_FOOT, vec2(-15 * sizeFactor, 75 * sizeFactor - footAnimationOffset), 0, vec2(0,0)),
        citizenPart(20 * sizeFactorHalve, 37 * sizeFactorHalve, IMAGE_CITIZEN_FOOT, vec2( 15 * sizeFactor, 75 * sizeFactor + footAnimationOffset), 0, vec2(0,0)),
        citizenPart(53 * sizeFactorHalve, 75 * sizeFactorHalve, IMAGE_CITIZEN_BODY, vec2( 0.0, 30 * sizeFactor), 0, vec2(0,0)),
        citizenPart(23 * sizeFactorHalve, 61 * sizeFactorHalve, IMAGE_CITIZEN_EAR_FRONT, vec2( -35 * sizeFactor, -50 * sizeFactor), earRotate, vec2(0,-20 * sizeFactor)),
        citizenPart(23 * sizeFactorHalve, 61 * sizeFactorHalve, IMAGE_CITIZEN_EAR_FRONT, vec2(  35 * sizeFactor, -50 * sizeFactor),-earRotate, vec2(0,-20 * sizeFactor)),
        citizenPart(68 * sizeFactorHalve, 84 * sizeFactorHalve, IMAGE_CITIZEN_HEAD, vec2( 0.0,-44 * sizeFactor), 0, vec2(0,0)),
        citizenPart( 6 * sizeFactorHalve,  8 * sizeFactorHalve, IMAGE_CITIZEN_PUPIL1, vec2( -14.0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0)),
        citizenPart(25 * sizeFactorHalve, 16 * sizeFactorHalve, IMAGE_CITIZEN_EYE_LEFT, vec2( -14.0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0)),
        citizenPart( 8 * sizeFactorHalve,  8 * sizeFactorHalve, IMAGE_CITIZEN_PUPIL2, vec2( 14.0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0)),
        citizenPart(23 * sizeFactorHalve, 16 * sizeFactorHalve, IMAGE_CITIZEN_EYE_RIGHT, vec2( 14.0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0)),
        citizenPart(30 * sizeFactorHalve, 2 * sizeFactorHalve, IMAGE_BLACK_PIXEL, vec2( 0.0 * sizeFactor,-20 * sizeFactor), 0, vec2(0,0)),
        citizenPart(20 * sizeFactorHalve, (52 - handAnimationOffset) * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2(-25 * sizeFactor, (30 - handAnimationOffset + 5) * sizeFactor), 0, vec2(0,0)),
        citizenPart(20 * sizeFactorHalve, (52 - handAnimationOffset2) * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 25 * sizeFactor, (30 - handAnimationOffset2 + 5) * sizeFactor), 0, vec2(0,0))
    );
    
    vec2 rotatedOffset;
    for(int i = 0; i < citizenParts.length(); i++ ){
        const citizenPart currentCitizenPart = citizenParts[i];
        const vec4 partCenter = center + vec4(currentCitizenPart.offset * scale[0] / zoom, 0, 0);
        const float width = currentCitizenPart.width;
        const float height = currentCitizenPart.height;
        vec2 offsets[4] = vec2[](
            vec2(-width, -height),
            vec2( width, -height),
            vec2(-width,  height),
            vec2( width,  height)
        );

        // top-left vertex
        rotatedOffset = rotateAroundPoint(offsets[0], currentCitizenPart.rotatePivot, currentCitizenPart.angle) * scale[0] / zoom;
        gl_Position = partCenter + vec4(rotatedOffset, -0.0001 * i, 0.0);
        fragTexCoord = vec2(0.0, 0.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        // top-right vertex
        rotatedOffset = rotateAroundPoint(offsets[1], currentCitizenPart.rotatePivot, currentCitizenPart.angle) * scale[0] / zoom;
        gl_Position = partCenter + vec4(rotatedOffset, -0.0001 * i, 0.0);
        fragTexCoord = vec2(1.0, 0.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        // bottom-left vertex
        rotatedOffset = rotateAroundPoint(offsets[2], currentCitizenPart.rotatePivot, currentCitizenPart.angle) * scale[0] / zoom;
        gl_Position = partCenter + vec4(rotatedOffset, -0.0001 * i, 0.0);
        fragTexCoord = vec2(0.0, 1.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        // bottom-right vertex
        rotatedOffset = rotateAroundPoint(offsets[3], currentCitizenPart.rotatePivot, currentCitizenPart.angle) * scale[0] / zoom;
        gl_Position = partCenter + vec4(rotatedOffset, -0.0001 * i, 0.0);
        fragTexCoord = vec2(1.0, 1.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        EndPrimitive();
    }
}
