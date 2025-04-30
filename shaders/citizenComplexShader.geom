#version 450

layout(points) in;
layout(triangle_strip, max_vertices = 60) out;

layout(location = 0) in vec2 scale[];
layout(location = 1) in uint inSpriteIndex[];
layout(location = 2) in uint animationTimer[];
layout(location = 3) in float moveSpeed[];
layout(location = 4) in uint booleans[];

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out uint spriteIndex;

struct citizenPart {
    float width;
    float height;
    uint spriteIndex;
    vec2 offset;
    float angle;
    vec2 rotatePivot;
    bool spriteMirror;
} citizenParts[15];

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
    bool isStarving = (booleans[0] & (1u << 0)) != 0u;
    bool useAxe = (booleans[0] & (1u << 1)) != 0u; 
    bool hasWood = (booleans[0] & (1u << 2)) != 0u; 
    bool useHammer = (booleans[0] & (1u << 3)) != 0u; 
    bool isPlanting = (booleans[0] & (1u << 4)) != 0u; 
    bool isEating = (booleans[0] & (1u << 5)) != 0u; 
    vec4 center = gl_in[0].gl_Position;
    const float zoom = center[3];
    center[0] = center[0] / zoom;
    center[1] = center[1] / zoom;
    center[3] = 1;
    const uint IMAGE_CITIZEN_FRONT = 10;
    const uint IMAGE_CITIZEN_LEFT = 11;
    const uint IMAGE_CITIZEN_RIGHT = 12;
    const uint IMAGE_CITIZEN_BACK = 13;
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
    const uint IMAGE_CITIZEN_TAIL = 25;
    const uint IMAGE_CITIZEN_HEAD_BACK = 26;
    const uint IMAGE_CITIZEN_FOOT_SIDE = 27;
    const uint IMAGE_CITIZEN_HEAD_SIDE = 28;
    const uint IMAGE_AXE = 29;
    const uint IMAGE_WOOD_PLANK_STACK = 30;
    const uint IMAGE_HAMMER = 31;
    const uint IMAGE_POTATO = 32;

    const uint TILE_SIZE = 20;
    const uint COMPLETE_CITIZEN_IMAGE_SIZE = 200;
    const float sizeFactor = 20.0 / 200.0;
    const float sizeFactorHalve = 20.0 / 200.0 / 2;
    const float bodyWidthFactor = isStarving ? 0.5 : 1;
    uint partsCount = 0;
    if(isPlanting){
        const float baseRotate = sin(animationTimer[0] / 100.0) * 0.5;
        citizenParts[partsCount++] = citizenPart(51 * sizeFactorHalve, 11 * sizeFactorHalve, IMAGE_CITIZEN_TAIL, vec2(-25 * sizeFactor, 46 * sizeFactor), baseRotate, vec2(25 * sizeFactor, 0), false);
        citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 37 * sizeFactorHalve, IMAGE_CITIZEN_FOOT, vec2(-15 * sizeFactor, 45 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 37 * sizeFactorHalve, IMAGE_CITIZEN_FOOT, vec2( 15 * sizeFactor, 45 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(53 * sizeFactorHalve * bodyWidthFactor, 75 * sizeFactorHalve, IMAGE_CITIZEN_BODY, vec2( 0.0, 20 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 61 * sizeFactorHalve, IMAGE_CITIZEN_EAR_FRONT, vec2( -35 * sizeFactor, -30 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 61 * sizeFactorHalve, IMAGE_CITIZEN_EAR_FRONT, vec2(  35 * sizeFactor, -30 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(68 * sizeFactorHalve, 84 * sizeFactorHalve, IMAGE_CITIZEN_HEAD, vec2( 0.0,-24 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart( 6 * sizeFactorHalve,  8 * sizeFactorHalve, IMAGE_CITIZEN_PUPIL1, vec2( -13.0 * sizeFactor,-48 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(25 * sizeFactorHalve, 16 * sizeFactorHalve, IMAGE_CITIZEN_EYE_LEFT, vec2( -14.0 * sizeFactor,-50 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart( 8 * sizeFactorHalve,  8 * sizeFactorHalve, IMAGE_CITIZEN_PUPIL2, vec2( 13.0 * sizeFactor,-47 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 16 * sizeFactorHalve, IMAGE_CITIZEN_EYE_RIGHT, vec2( 14.0 * sizeFactor,-50 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(30 * sizeFactorHalve, 2 * sizeFactorHalve, IMAGE_BLACK_PIXEL, vec2( 0.0 * sizeFactor,0 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2(-25 * sizeFactor, 30  * sizeFactor), baseRotate, vec2(0,-20 * sizeFactor), false);
        citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 25 * sizeFactor, 30 * sizeFactor), -baseRotate, vec2(0,-20 * sizeFactor), false);
    }else if(isEating){
        const float baseRotate = sin(animationTimer[0] / 100.0) * 0.5;
        citizenParts[partsCount++] = citizenPart(51 * sizeFactorHalve, 11 * sizeFactorHalve, IMAGE_CITIZEN_TAIL, vec2(-25 * sizeFactor, 56 * sizeFactor), baseRotate, vec2(25 * sizeFactor, 0), false);
        citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 37 * sizeFactorHalve, IMAGE_CITIZEN_FOOT, vec2(-15 * sizeFactor, 75 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 37 * sizeFactorHalve, IMAGE_CITIZEN_FOOT, vec2( 15 * sizeFactor, 75 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(53 * sizeFactorHalve * bodyWidthFactor, 75 * sizeFactorHalve, IMAGE_CITIZEN_BODY, vec2( 0.0, 30 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 61 * sizeFactorHalve, IMAGE_CITIZEN_EAR_FRONT, vec2( -35 * sizeFactor, -50 * sizeFactor),0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 61 * sizeFactorHalve, IMAGE_CITIZEN_EAR_FRONT, vec2(  35 * sizeFactor, -50 * sizeFactor),0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(68 * sizeFactorHalve, 84 * sizeFactorHalve, IMAGE_CITIZEN_HEAD, vec2( 0.0,-44 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart( 6 * sizeFactorHalve,  8 * sizeFactorHalve, IMAGE_CITIZEN_PUPIL1, vec2( -10.0 * sizeFactor,-67 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(25 * sizeFactorHalve, 16 * sizeFactorHalve, IMAGE_CITIZEN_EYE_LEFT, vec2( -14.0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart( 8 * sizeFactorHalve,  8 * sizeFactorHalve, IMAGE_CITIZEN_PUPIL2, vec2( 10.0 * sizeFactor,-66 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 16 * sizeFactorHalve, IMAGE_CITIZEN_EYE_RIGHT, vec2( 14.0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(30 * sizeFactorHalve, 2 * sizeFactorHalve, IMAGE_BLACK_PIXEL, vec2( 0.0 * sizeFactor,-20 * sizeFactor), 0, vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(45 * sizeFactorHalve, 33 * sizeFactorHalve, IMAGE_POTATO, vec2( 0 * sizeFactor, -10 * sizeFactor), 0,  vec2(0,0), false);
        citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 42 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2(-25 * sizeFactor, 40 * sizeFactor), 2.84,  vec2(0,-20 * sizeFactor), false);
        citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 42 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 25 * sizeFactor, 40 * sizeFactor), 3.44,  vec2(0,-20 * sizeFactor), false);
    }else{
        switch(inSpriteIndex[0]){
            case IMAGE_CITIZEN_FRONT:{
                const float footAnimationOffset = sin(animationTimer[0] / 100.0 * moveSpeed[0]);
                const float handAnimationOffset = ( -sin(animationTimer[0] / 100.0 * moveSpeed[0]) + 1) * 10;
                const float handAnimationOffset2 = (sin(animationTimer[0] / 100.0 * moveSpeed[0]) + 1) * 10;
                const float earRotate = sin(animationTimer[0] / 100.0 * moveSpeed[0]) * 0.25 - 0.31;
                const float tailRotate = sin(animationTimer[0] / 100.0 * moveSpeed[0]) * 1.57 + 1.57;
                citizenParts[partsCount++] = citizenPart(51 * sizeFactorHalve, 11 * sizeFactorHalve, IMAGE_CITIZEN_TAIL, vec2(-25 * sizeFactor, 56 * sizeFactor), tailRotate, vec2(25 * sizeFactor, 0), false);
                citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 37 * sizeFactorHalve, IMAGE_CITIZEN_FOOT, vec2(-15 * sizeFactor, 75 * sizeFactor - footAnimationOffset), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 37 * sizeFactorHalve, IMAGE_CITIZEN_FOOT, vec2( 15 * sizeFactor, 75 * sizeFactor + footAnimationOffset), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(53 * sizeFactorHalve * bodyWidthFactor, 75 * sizeFactorHalve, IMAGE_CITIZEN_BODY, vec2( 0.0, 30 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 61 * sizeFactorHalve, IMAGE_CITIZEN_EAR_FRONT, vec2( -35 * sizeFactor, -50 * sizeFactor), earRotate, vec2(0,-20 * sizeFactor), false);
                citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 61 * sizeFactorHalve, IMAGE_CITIZEN_EAR_FRONT, vec2(  35 * sizeFactor, -50 * sizeFactor),-earRotate, vec2(0,-20 * sizeFactor), false);
                citizenParts[partsCount++] = citizenPart(68 * sizeFactorHalve, 84 * sizeFactorHalve, IMAGE_CITIZEN_HEAD, vec2( 0.0,-44 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart( 6 * sizeFactorHalve,  8 * sizeFactorHalve, IMAGE_CITIZEN_PUPIL1, vec2( -14.0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(25 * sizeFactorHalve, 16 * sizeFactorHalve, IMAGE_CITIZEN_EYE_LEFT, vec2( -14.0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart( 8 * sizeFactorHalve,  8 * sizeFactorHalve, IMAGE_CITIZEN_PUPIL2, vec2( 14.0 * sizeFactor,-69 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 16 * sizeFactorHalve, IMAGE_CITIZEN_EYE_RIGHT, vec2( 14.0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(30 * sizeFactorHalve, 2 * sizeFactorHalve, IMAGE_BLACK_PIXEL, vec2( 0.0 * sizeFactor,-20 * sizeFactor), 0, vec2(0,0), false);
                if(hasWood){
                    citizenParts[partsCount++] = citizenPart(179 * sizeFactorHalve, 111 * sizeFactorHalve, IMAGE_WOOD_PLANK_STACK, vec2( 0 * sizeFactor, -60 * sizeFactor), 0, vec2(0, 0), false);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2(-25 * sizeFactor, 30 * sizeFactor), 3.14,  vec2(0,-20 * sizeFactor), false);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 25 * sizeFactor, 30 * sizeFactor), 3.14,  vec2(0,-20 * sizeFactor), false);
                }else{
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, (52 - handAnimationOffset) * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2(-25 * sizeFactor, (30 - handAnimationOffset + 5) * sizeFactor), 0, vec2(0,0), false);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, (52 - handAnimationOffset2) * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 25 * sizeFactor, (30 - handAnimationOffset2 + 5) * sizeFactor), 0, vec2(0,0), false);
                }
                break;
            }
            case IMAGE_CITIZEN_LEFT:{
                const float baseRotate = sin(animationTimer[0] / 100.0 * moveSpeed[0]) * 0.5;
                if(!hasWood) citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2(0 * sizeFactor, 30 * sizeFactor), baseRotate, vec2(0,-20 * sizeFactor), false);
                citizenParts[partsCount++] = citizenPart(42 * sizeFactorHalve, 21 * sizeFactorHalve, IMAGE_CITIZEN_FOOT_SIDE, vec2(-7.0 * sizeFactor, 71 * sizeFactor), baseRotate, vec2(0 * sizeFactor,-40 * sizeFactor), false);
                citizenParts[partsCount++] = citizenPart(42 * sizeFactorHalve, 21 * sizeFactorHalve, IMAGE_CITIZEN_FOOT_SIDE, vec2(-7.0 * sizeFactor, 71 * sizeFactor), -baseRotate, vec2(0 * sizeFactor,-40 * sizeFactor), false);
                citizenParts[partsCount++] = citizenPart(51 * sizeFactorHalve, 11 * sizeFactorHalve, IMAGE_CITIZEN_TAIL, vec2(-8 * sizeFactor, 56 * sizeFactor), baseRotate + 3.14, vec2(25 * sizeFactor, 0), false);
                citizenParts[partsCount++] = citizenPart(53 * sizeFactorHalve * bodyWidthFactor, 75 * sizeFactorHalve, IMAGE_CITIZEN_BODY, vec2( 0.0, 30 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(120 * sizeFactorHalve,82 * sizeFactorHalve, IMAGE_CITIZEN_HEAD_SIDE, vec2( -20.0 * sizeFactor,-44 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart( 6 * sizeFactorHalve,  8 * sizeFactorHalve, IMAGE_CITIZEN_PUPIL1, vec2( -4 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(25 * sizeFactorHalve, 16 * sizeFactorHalve, IMAGE_CITIZEN_EYE_LEFT, vec2( 0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(30 * sizeFactorHalve,  2 * sizeFactorHalve, IMAGE_BLACK_PIXEL, vec2( -55.0 * sizeFactor,-20 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(29 * sizeFactorHalve, 73 * sizeFactorHalve, IMAGE_CITIZEN_EAR_SIDE, vec2( 22 * sizeFactor, -40 * sizeFactor), baseRotate, vec2(0,-20 * sizeFactor), false);
                if(useAxe){
                    const float cutRotate = sin(animationTimer[0] / 100.0) * 0.75;
                    citizenParts[partsCount++] = citizenPart(100 * sizeFactorHalve, 100 * sizeFactorHalve, IMAGE_AXE, vec2( -35 * sizeFactor, -20 * sizeFactor), -cutRotate, vec2(35 * sizeFactor, 30 * sizeFactor), true);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 0 * sizeFactor, 30 * sizeFactor), -cutRotate - 1.57, vec2(0,-20 * sizeFactor), false);
                }else if(useHammer){
                    const float cutRotate = sin(animationTimer[0] / 100.0);
                    citizenParts[partsCount++] = citizenPart(38 * sizeFactorHalve, 93 * sizeFactorHalve, IMAGE_HAMMER, vec2( -35 * sizeFactor, -20 * sizeFactor), -cutRotate, vec2(35 * sizeFactor, 30 * sizeFactor), true);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 0 * sizeFactor, 30 * sizeFactor), -cutRotate - 1.57, vec2(0,-20 * sizeFactor), false);
                }else if(hasWood){
                    citizenParts[partsCount++] = citizenPart(179 * sizeFactorHalve, 111 * sizeFactorHalve, IMAGE_WOOD_PLANK_STACK, vec2( 0 * sizeFactor, -60 * sizeFactor), 0, vec2(0, 0), false);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 0 * sizeFactor, 30 * sizeFactor), 3.14, vec2(0,-20 * sizeFactor), false);
                }else{
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 0 * sizeFactor, 30 * sizeFactor), -baseRotate, vec2(0,-20 * sizeFactor), false);
                }
                break;
            }
            case IMAGE_CITIZEN_RIGHT:{
                const float baseRotate = sin(animationTimer[0] / 100.0 * moveSpeed[0]) * 0.5;
                citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2(0 * sizeFactor, 30 * sizeFactor), baseRotate, vec2(0,-20 * sizeFactor), false);
                citizenParts[partsCount++] = citizenPart(42 * sizeFactorHalve, 21 * sizeFactorHalve, IMAGE_CITIZEN_FOOT_SIDE, vec2(10.0 * sizeFactor, 71 * sizeFactor), baseRotate, vec2(0 * sizeFactor,-40 * sizeFactor), true);
                citizenParts[partsCount++] = citizenPart(42 * sizeFactorHalve, 21 * sizeFactorHalve, IMAGE_CITIZEN_FOOT_SIDE, vec2(10.0 * sizeFactor, 71 * sizeFactor), -baseRotate, vec2(0 * sizeFactor,-40 * sizeFactor), true);
                citizenParts[partsCount++] = citizenPart(51 * sizeFactorHalve, 11 * sizeFactorHalve, IMAGE_CITIZEN_TAIL, vec2(-35 * sizeFactor, 56 * sizeFactor), baseRotate, vec2(25 * sizeFactor, 0), false);
                citizenParts[partsCount++] = citizenPart(53 * sizeFactorHalve * bodyWidthFactor, 75 * sizeFactorHalve, IMAGE_CITIZEN_BODY, vec2( 0.0, 30 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(120 * sizeFactorHalve,82 * sizeFactorHalve, IMAGE_CITIZEN_HEAD_SIDE, vec2( 22.0 * sizeFactor,-44 * sizeFactor), 0, vec2(0,0), true);
                citizenParts[partsCount++] = citizenPart( 6 * sizeFactorHalve,  8 * sizeFactorHalve, IMAGE_CITIZEN_PUPIL1, vec2( 4 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(25 * sizeFactorHalve, 16 * sizeFactorHalve, IMAGE_CITIZEN_EYE_LEFT, vec2( 0 * sizeFactor,-70 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(30 * sizeFactorHalve,  2 * sizeFactorHalve, IMAGE_BLACK_PIXEL, vec2( 55.0 * sizeFactor,-20 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(29 * sizeFactorHalve, 73 * sizeFactorHalve, IMAGE_CITIZEN_EAR_SIDE, vec2( -22 * sizeFactor, -40 * sizeFactor), baseRotate, vec2(0,-20 * sizeFactor), false);
                if(useAxe){
                    const float cutRotate = sin(animationTimer[0] / 100.0) * 0.75;
                    citizenParts[partsCount++] = citizenPart(100 * sizeFactorHalve, 100 * sizeFactorHalve, IMAGE_AXE, vec2( 35 * sizeFactor, -20 * sizeFactor), -cutRotate, vec2(-35 * sizeFactor, 30 * sizeFactor), false);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 0 * sizeFactor, 30 * sizeFactor), -cutRotate + 1.57, vec2(0,-20 * sizeFactor), false);
                }else if(useHammer){
                    const float cutRotate = sin(animationTimer[0] / 100.0);
                    citizenParts[partsCount++] = citizenPart(38 * sizeFactorHalve, 93 * sizeFactorHalve, IMAGE_HAMMER, vec2(  35 * sizeFactor, -20 * sizeFactor), -cutRotate, vec2(-35 * sizeFactor, 30 * sizeFactor), false);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 0 * sizeFactor, 30 * sizeFactor), -cutRotate + 1.57, vec2(0,-20 * sizeFactor), false);
                }else if(hasWood){
                    citizenParts[partsCount++] = citizenPart(179 * sizeFactorHalve, 111 * sizeFactorHalve, IMAGE_WOOD_PLANK_STACK, vec2( 0 * sizeFactor, -60 * sizeFactor), 0, vec2(0, 0), false);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 0 * sizeFactor, 30 * sizeFactor), 3.14, vec2(0,-20 * sizeFactor), false);
                }else{
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 0 * sizeFactor, 30 * sizeFactor), -baseRotate, vec2(0,-20 * sizeFactor), false);
                }
                break;
            }
            case IMAGE_CITIZEN_BACK:{
                const float footAnimationOffset = sin(animationTimer[0] / 100.0 * moveSpeed[0]);
                const float handAnimationOffset = ( -sin(animationTimer[0] / 100.0 * moveSpeed[0]) + 1) * 10;
                const float handAnimationOffset2 = (sin(animationTimer[0] / 100.0 * moveSpeed[0]) + 1) * 10;
                const float earRotate = sin(animationTimer[0] / 100.0 * moveSpeed[0]) * 0.25 - 0.31;
                const float tailRotate = sin(animationTimer[0] / 100.0 * moveSpeed[0]) * 1.57 + 1.57;
                if(hasWood){
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2(-25 * sizeFactor, 30 * sizeFactor), 3.14, vec2(0,-20 * sizeFactor), false);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 52 * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 25 * sizeFactor, 30 * sizeFactor), 3.14, vec2(0,-20 * sizeFactor), false);
                    citizenParts[partsCount++] = citizenPart(179 * sizeFactorHalve, 111 * sizeFactorHalve, IMAGE_WOOD_PLANK_STACK, vec2( 0 * sizeFactor, -60 * sizeFactor), 0, vec2(0, 0), false);
                }else{
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, (52 - handAnimationOffset) * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2(-25 * sizeFactor, (30 - handAnimationOffset + 5) * sizeFactor), 0, vec2(0,0), false);
                    citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, (52 - handAnimationOffset2) * sizeFactorHalve, IMAGE_CITIZEN_PAW, vec2( 25 * sizeFactor, (30 - handAnimationOffset2 + 5) * sizeFactor), 0, vec2(0,0), false);
                }
                citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 37 * sizeFactorHalve, IMAGE_CITIZEN_FOOT, vec2(-15 * sizeFactor, 75 * sizeFactor - footAnimationOffset), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(20 * sizeFactorHalve, 37 * sizeFactorHalve, IMAGE_CITIZEN_FOOT, vec2( 15 * sizeFactor, 75 * sizeFactor + footAnimationOffset), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(68 * sizeFactorHalve, 84 * sizeFactorHalve, IMAGE_CITIZEN_HEAD_BACK, vec2( 0.0,-44 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(53 * sizeFactorHalve * bodyWidthFactor, 75 * sizeFactorHalve, IMAGE_CITIZEN_BODY, vec2( 0.0, 30 * sizeFactor), 0, vec2(0,0), false);
                citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 61 * sizeFactorHalve, IMAGE_CITIZEN_EAR_FRONT, vec2( -35 * sizeFactor, -50 * sizeFactor), earRotate, vec2(0,-20 * sizeFactor), false);
                citizenParts[partsCount++] = citizenPart(23 * sizeFactorHalve, 61 * sizeFactorHalve, IMAGE_CITIZEN_EAR_FRONT, vec2(  35 * sizeFactor, -50 * sizeFactor),-earRotate, vec2(0,-20 * sizeFactor), false);
                citizenParts[partsCount++] = citizenPart(51 * sizeFactorHalve, 11 * sizeFactorHalve, IMAGE_CITIZEN_TAIL, vec2(-25 * sizeFactor, 56 * sizeFactor), tailRotate, vec2(25 * sizeFactor, 0), false);
                break;
            }
        }
    }
    
    vec2 rotatedOffset;
    for(int i = 0; i < partsCount; i++ ){
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
        gl_Position = partCenter + vec4(rotatedOffset, -0.00001 * i, 0.0);
        if(currentCitizenPart.spriteMirror) fragTexCoord = vec2(1.0, 0.0); else fragTexCoord = vec2(0.0, 0.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        // top-right vertex
        rotatedOffset = rotateAroundPoint(offsets[1], currentCitizenPart.rotatePivot, currentCitizenPart.angle) * scale[0] / zoom;
        gl_Position = partCenter + vec4(rotatedOffset, -0.00001 * i, 0.0);
        if(currentCitizenPart.spriteMirror) fragTexCoord = vec2(0.0, 0.0); else fragTexCoord = vec2(1.0, 0.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        // bottom-left vertex
        rotatedOffset = rotateAroundPoint(offsets[2], currentCitizenPart.rotatePivot, currentCitizenPart.angle) * scale[0] / zoom;
        gl_Position = partCenter + vec4(rotatedOffset, -0.00001 * i, 0.0);
        if(currentCitizenPart.spriteMirror) fragTexCoord = vec2(1.0, 1.0); else fragTexCoord = vec2(0.0, 1.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        // bottom-right vertex
        rotatedOffset = rotateAroundPoint(offsets[3], currentCitizenPart.rotatePivot, currentCitizenPart.angle) * scale[0] / zoom;
        gl_Position = partCenter + vec4(rotatedOffset, -0.00001 * i, 0.0);
        if(currentCitizenPart.spriteMirror) fragTexCoord = vec2(0.0, 1.0); else fragTexCoord = vec2(1.0, 1.0);
        spriteIndex = currentCitizenPart.spriteIndex;
        EmitVertex();

        EndPrimitive();
    }
}
