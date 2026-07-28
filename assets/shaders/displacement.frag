#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_breath;
uniform float u_blink;
uniform vec2 u_drift;
uniform vec2 u_anchorLeftEye;
uniform vec2 u_anchorRightEye;
uniform vec2 u_anchorMouth;
uniform vec2 u_anchorNose;
uniform float u_headTurn;
uniform vec2 u_lookDir;
uniform float u_mouthOpen;
uniform float u_mouthAngle;
uniform float u_eyeTiltAngle;
uniform float u_mouthOffsetY;
uniform vec2 u_anchorLeftBrow;
uniform vec2 u_anchorRightBrow;
uniform vec2 u_anchorLeftMouthCorner;
uniform vec2 u_anchorRightMouthCorner;
uniform float u_mouthWidth;
uniform float u_mouthRound;
uniform float u_blinkBob;

uniform sampler2D u_texture;

out vec4 fragColor;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / u_resolution;

    vec2 disp = vec2(0.0);

    // Breathing: vertical wave on chest/shoulders
    float breathMask = smoothstep(0.35, 0.75, uv.y);
    float breathWave = sin(u_time * 0.8 + uv.x * 3.14159) * 0.006;
    disp.y += breathWave * breathMask * u_breath;

    // Head drift: gentle global wander
    disp += u_drift * 0.004;

    // Anchor tracking: offset anchors so masks follow drifted image
    vec2 driftOffset = u_drift * 0.004;
    vec2 aLeftEye = u_anchorLeftEye - driftOffset;
    vec2 aRightEye = u_anchorRightEye - driftOffset;
    vec2 aMouth = u_anchorMouth - driftOffset;
    vec2 aNose = u_anchorNose - driftOffset;
    vec2 aLeftBrow = u_anchorLeftBrow - driftOffset;
    vec2 aRightBrow = u_anchorRightBrow - driftOffset;
    vec2 aLeftMouthCorner = u_anchorLeftMouthCorner - driftOffset;
    vec2 aRightMouthCorner = u_anchorRightMouthCorner - driftOffset;

    // --- EYE BLINK (rotated by eye tilt) ---
    float blinkCos = cos(u_eyeTiltAngle);
    float blinkSin = sin(u_eyeTiltAngle);

    float leftLocalX = uv.x - aLeftEye.x;
    float leftLocalY = uv.y - aLeftEye.y;
    float leftEyeRX = leftLocalX * blinkCos + leftLocalY * blinkSin;
    float leftEyeRY = -leftLocalX * blinkSin + leftLocalY * blinkCos;
    float leftMask = smoothstep(0.05, 0.01, abs(leftEyeRX)) * smoothstep(0.04, 0.005, abs(leftEyeRY));
    float leftUpper = max(0.0, leftEyeRY) * u_blink * 2.25;
    float leftLower = max(0.0, -leftEyeRY) * u_blink * 1.125;
    float leftBlinkVert = leftUpper - leftLower;
    disp.x += leftBlinkVert * blinkSin * leftMask;
    disp.y += leftBlinkVert * blinkCos * leftMask;

    float rightLocalX = uv.x - aRightEye.x;
    float rightLocalY = uv.y - aRightEye.y;
    float rightEyeRX = rightLocalX * blinkCos + rightLocalY * blinkSin;
    float rightEyeRY = -rightLocalX * blinkSin + rightLocalY * blinkCos;
    float rightMask = smoothstep(0.05, 0.01, abs(rightEyeRX)) * smoothstep(0.04, 0.005, abs(rightEyeRY));
    float rightUpper = max(0.0, rightEyeRY) * u_blink * 2.25;
    float rightLower = max(0.0, -rightEyeRY) * u_blink * 1.125;
    float rightBlinkVert = rightUpper - rightLower;
    disp.x += rightBlinkVert * blinkSin * rightMask;
    disp.y += rightBlinkVert * blinkCos * rightMask;

    // --- HEAD TURN: depth-based horizontal shift for 3D rotation ---
    float faceCenterX = (aLeftEye.x + aRightEye.x) * 0.5;
    float faceCenterY = (aLeftEye.y + aRightEye.y) * 0.5;
    float faceWidth = abs(aRightEye.x - aLeftEye.x) * 2.5;
    float faceHeight = faceWidth * 1.2;
    float faceMask = smoothstep(faceWidth, faceWidth * 0.15, abs(uv.x - faceCenterX))
                   * smoothstep(faceHeight, faceHeight * 0.15, abs(uv.y - faceCenterY));

    float turnDisp = faceMask * u_headTurn * 0.03;
    disp.x += turnDisp;
    disp.y += abs(uv.x - faceCenterX) * u_headTurn * 0.002 * faceMask;

    // --- BLINK HEAD BOB ---
    disp.y += u_blinkBob * faceMask;

    // --- NOSE FLARE ---
    float noseFlareMask = smoothstep(0.06, 0.01, length(uv - aNose));
    float noseFlareAmount = u_breath * 0.003;
    disp.x += (uv.x - aNose.x) * noseFlareAmount * 8.0 * noseFlareMask;

    // --- EYE BALL MOVEMENT ---
    float lShiftX = u_lookDir.x * 0.008;
    float lShiftY = u_lookDir.y * 0.004;
    float lEyeMask = smoothstep(0.04, 0.008, abs(uv.x - aLeftEye.x))
                   * smoothstep(0.03, 0.005, abs(uv.y - aLeftEye.y));
    disp.x += lShiftX * lEyeMask;
    disp.y += lShiftY * lEyeMask;

    float rShiftX = u_lookDir.x * 0.008;
    float rShiftY = u_lookDir.y * 0.004;
    float rEyeMask = smoothstep(0.04, 0.008, abs(uv.x - aRightEye.x))
                   * smoothstep(0.03, 0.005, abs(uv.y - aRightEye.y));
    disp.x += rShiftX * rEyeMask;
    disp.y += rShiftY * rEyeMask;

    // --- MOUTH OPEN/CLOSE: lip-sync ---
    float mouthDX = uv.x - aMouth.x;
    float mouthDY = uv.y - (aMouth.y + u_mouthOffsetY);
    float mouthXDist = abs(mouthDX);
    float mouthXMask = smoothstep(0.12, 0.015, mouthXDist);
    float mouthYMask = smoothstep(0.10, 0.01, abs(mouthDY));
    float mouthMask = mouthXMask * mouthYMask;

    float upperLip = max(0.0, -mouthDY) * u_mouthOpen * 0.28;
    float lowerLip = max(0.0, mouthDY) * u_mouthOpen * 0.14;
    disp.y += (lowerLip - upperLip) * mouthMask;

    float mouthWidthPush = u_mouthWidth * mouthDX * 0.12;
    disp.x += (mouthDX * u_mouthOpen * 0.15 + mouthWidthPush) * mouthMask;

    disp.x += mouthDX * u_mouthRound * 0.12 * mouthMask;
    disp.y += mouthDY * u_mouthRound * 0.06 * mouthMask;

    // Organic noise layer
    float organic = fbm(uv * 4.0 + u_time * 0.15) - 0.5;
    disp += organic * 0.004;

    vec2 sampleUV = uv + disp;
    sampleUV = clamp(sampleUV, vec2(0.0), vec2(1.0));

    vec4 color = texture(u_texture, sampleUV);

    // --- MOUTH CAVITY SHADOW (post-displacement, elliptical) ---
    {
        float cosA = cos(u_mouthAngle);
        float sinA = sin(u_mouthAngle);
        vec2 cavityD = sampleUV - vec2(u_anchorMouth.x, u_anchorMouth.y + u_mouthOffsetY);
        vec2 cavityLocal = vec2(
          cavityD.x * cosA + cavityD.y * sinA,
          -cavityD.x * sinA + cavityD.y * cosA
        );
        float cornerDist = length(aRightMouthCorner - aLeftMouthCorner);
        float halfWidth = cornerDist * 0.45;
        float halfHeight = 0.005 + u_mouthOpen * 0.025;
        float xNorm = cavityLocal.x / max(halfWidth, 0.001);
        float yNorm = cavityLocal.y / max(halfHeight, 0.001);
        float ellipseDist = xNorm * xNorm + yNorm * yNorm;
        float cavityMask = smoothstep(1.0, 0.3, ellipseDist);
        float depthGrad = smoothstep(1.0, 0.0, ellipseDist);
        color.rgb *= (1.0 - cavityMask * depthGrad * u_mouthOpen * 0.7);
        float teethY = smoothstep(-halfHeight * 0.1, -halfHeight * 0.6, cavityLocal.y);
        float teethMask = cavityMask * teethY * smoothstep(0.2, 0.6, u_mouthOpen);
        color.rgb += vec3(0.06, 0.055, 0.05) * teethMask * u_mouthOpen;
    }

    fragColor = color;
}
