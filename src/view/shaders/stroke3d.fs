#version 330

in vec2 fragAuxiliary;
in vec4 fragColor;
out vec4 finalColor;

uniform vec3 uLightDirView;
uniform float uAmbient;
uniform float uDiffuse;
uniform float uMaterialRoughness;
uniform float uMaterialFresnel0;
uniform float uMaterialSpecularTint;
uniform float uMaterialShadowLimit;
uniform vec2 uP0;
uniform vec2 uP1;
uniform float uRadius;
uniform float uViewportHeight;
uniform float uStrokeMode;
uniform float uStripAlpha;
uniform vec3 uStripColor;
uniform float uStripSideExtent;
uniform float uArcIntersectionsEnabled;
uniform float uIntersectionDepthWidth;
uniform float uAttachmentExtent;
uniform float uOccluderCount;
uniform vec2 uOccluderP0[2];
uniform vec2 uOccluderP1[2];
uniform float uOccluderRadius[2];
uniform float uOccluderDepth0[2];
uniform float uOccluderDepth1[2];
uniform vec3 uOccluderTangent[2];

float segmentDistance(vec2 point, vec2 start, vec2 finish) {
    vec2 segment = finish - start;
    float segmentSquared = max(dot(segment, segment), 0.0001);
    float h = clamp(dot(point - start, segment) / segmentSquared, 0.0, 1.0);
    return length(point - start - segment * h);
}

vec3 srgbToLinear(vec3 value) {
    vec3 low = value / 12.92;
    vec3 high = pow((value + 0.055) / 1.055, vec3(2.4));
    return mix(low, high, greaterThan(value, vec3(0.04045)));
}

vec3 linearToSrgb(vec3 value) {
    vec3 low = value * 12.92;
    vec3 high = 1.055 * pow(value, vec3(1.0 / 2.4)) - 0.055;
    return mix(low, high, greaterThan(value, vec3(0.0031308)));
}

float stableSpecularLobe(float halfDot, float power) {
    float rawLobe = pow(halfDot, power);
    return rawLobe / (1.0 + fwidth(rawLobe));
}

void main() {
    vec2 frag = gl_FragCoord.xy;
    float coverage;
    float silhouetteDistance;
    float sourceAlpha;
    vec3 sourceColor;
    vec3 N;
    vec3 V = vec3(0.0, 0.0, 1.0);
    float intersectionContact = 0.0;
    float intersectionVisibility = 1.0;
    float weldSuppression = 0.0;

    if (uStrokeMode > 0.5) {
        vec3 tangent = normalize(fragColor.rgb * 2.0 - 1.0);
        vec3 side = cross(tangent, V);
        float sideLength = max(length(side), 0.0001);
        side /= sideLength;
        vec3 front = normalize(cross(side, tangent));
        float x = (fragColor.a * 2.0 - 1.0) * uStripSideExtent;
        float stripDistance = abs(x) - 1.0;
        float coverageWidth = max(fwidth(stripDistance), 0.0001);
        coverage = clamp(0.5 - stripDistance / coverageWidth, 0.0, 1.0);
        x = clamp(x, -1.0, 1.0);
        float yz = max(1.0 - x * x, 0.0);
        N = normalize(side * x + front * sqrt(yz));
        silhouetteDistance = abs(x);
        sourceAlpha = uStripAlpha;
        sourceColor = uStripColor;
    } else {
        vec2 p0 = vec2(uP0.x, uViewportHeight - uP0.y);
        vec2 p1 = vec2(uP1.x, uViewportHeight - uP1.y);
        vec2 d = p1 - p0;
        float dLen = max(length(d), 0.0001);
        vec2 dir = d / dLen;
        vec2 perp = vec2(-dir.y, dir.x);
        vec2 v = frag - p0;
        float axisCoord = dot(v, dir);
        float t = clamp(axisCoord, 0.0, dLen);
        vec2 closest = p0 + dir * t;
        float radius = max(uRadius, 0.0001);
        vec2 radial = (frag - closest) / radius;
        float radialSquared = dot(radial, radial);
        float capsuleDistance = sqrt(radialSquared) - 1.0;
        float coverageWidth = max(fwidth(capsuleDistance), 0.0001);
        coverage = clamp(0.5 - capsuleDistance / coverageWidth, 0.0, 1.0);

        float signedDist = dot(frag - closest, perp);
        float x = clamp(signedDist / radius, -1.0, 1.0);
        float yz = max(1.0 - x * x, 0.0);
        silhouetteDistance = abs(x);
        if (axisCoord < 0.0 || axisCoord > dLen) {
            N = normalize(vec3(radial, sqrt(max(1.0 - radialSquared, 0.0))));
            silhouetteDistance = sqrt(radialSquared);
        } else {
            N = normalize(vec3(perp * x, sqrt(yz)));
        }
        sourceAlpha = fragColor.a;
        sourceColor = fragColor.rgb;
    }

    if (coverage <= 0.0) {
        discard;
    }

    if (uArcIntersectionsEnabled > 0.5) {
        float depthRadius = max(uIntersectionDepthWidth * 0.5, 0.0001);
        float arcDepth = fragAuxiliary.x + N.z * depthRadius;
        float arcParameter = clamp(fragAuxiliary.y, 0.0, 1.0);
        for (int index = 0; index < 2; ++index) {
            if (float(index) >= uOccluderCount) {
                break;
            }

            vec2 legP0 = vec2(
                uOccluderP0[index].x, uViewportHeight - uOccluderP0[index].y);
            vec2 legP1 = vec2(
                uOccluderP1[index].x, uViewportHeight - uOccluderP1[index].y);
            vec2 legSegment = legP1 - legP0;
            float legLengthSquared = max(dot(legSegment, legSegment), 0.0001);
            float legParameter = clamp(
                dot(frag - legP0, legSegment) / legLengthSquared, 0.0, 1.0);
            vec2 legClosest = legP0 + legSegment * legParameter;
            float legRadius = max(uOccluderRadius[index], 0.0001);
            float legDistance = length(frag - legClosest) - legRadius;
            float overlapWidth = max(fwidth(legDistance), 0.75);
            float overlap = 1.0 - smoothstep(
                -overlapWidth, overlapWidth, legDistance);

            vec3 legTangent = normalize(uOccluderTangent[index]);
            vec3 legSide = normalize(cross(legTangent, V));
            vec3 legFront = normalize(cross(legSide, legTangent));
            vec2 legDirection = legSegment / sqrt(legLengthSquared);
            vec2 legPerpendicular = vec2(-legDirection.y, legDirection.x);
            float legX = clamp(
                dot(frag - legClosest, legPerpendicular) / legRadius, -1.0, 1.0);
            vec3 legNormal = normalize(
                legSide * legX + legFront * sqrt(max(1.0 - legX * legX, 0.0)));

            float legCenterDepth = mix(
                uOccluderDepth0[index], uOccluderDepth1[index], legParameter);
            float legDepth = legCenterDepth + legNormal.z * depthRadius;
            float depthDelta = arcDepth - legDepth;
            float depthWidth = max(uIntersectionDepthWidth, 0.0001);
            float arcInFront = smoothstep(-depthWidth, depthWidth, depthDelta);
            float depthProximity = 1.0 - smoothstep(
                depthWidth, depthWidth * 2.0, abs(depthDelta));

            float attachmentDistance = index == 0 ? arcParameter : 1.0 - arcParameter;
            float attachment = 1.0 - smoothstep(
                uAttachmentExtent, uAttachmentExtent * 1.5, attachmentDistance);
            float weld = attachment * overlap;
            float visibleAtLeg = mix(arcInFront, 1.0, weld);
            intersectionVisibility *= mix(1.0, visibleAtLeg, overlap);

            float softUnion = overlap * depthProximity * (1.0 - weld) * 0.24;
            vec3 unionNormal = normalize(N + legNormal);
            N = normalize(mix(N, unionNormal, max(softUnion, weld * 0.72)));
            intersectionContact += 0.06 * overlap * depthProximity * (1.0 - weld);
            weldSuppression = max(weldSuppression, weld);
        }
        sourceAlpha *= intersectionVisibility;
    }

    vec3 L = normalize(uLightDirView);
    vec3 H = normalize(L + V);

    float lambert = max(dot(N, L), 0.0);
    float halfDot = max(dot(N, H), 0.0);
    float viewDot = max(dot(N, V), 0.0);
    float roughness = clamp(uMaterialRoughness, 0.0, 1.0);
    float narrowPower = mix(120.0, 24.0, roughness);
    float broadPower = max(narrowPower * 0.16, 6.0);
    float narrowSpecular = stableSpecularLobe(halfDot, narrowPower);
    float broadSpecular = stableSpecularLobe(halfDot, broadPower);

    float edgeDark = smoothstep(0.35, 1.0, silhouetteDistance);
    float centerBoost = pow(max(1.0 - silhouetteDistance * silhouetteDistance, 0.0), 0.28);

    vec3 base = srgbToLinear(sourceColor);
    float diffuseBand = uAmbient + uDiffuse * lambert;
    float tubeShape = (1.0 + 0.22 * centerBoost) * (1.0 - 0.25 * edgeDark);
    vec3 lit = base * diffuseBand * tubeShape;

    float contextualDarkening = intersectionContact;
    for (int index = 0; index < 2; ++index) {
        if (float(index) >= uOccluderCount) {
            break;
        }

        vec2 occluderP0 = vec2(
            uOccluderP0[index].x, uViewportHeight - uOccluderP0[index].y);
        vec2 occluderP1 = vec2(
            uOccluderP1[index].x, uViewportHeight - uOccluderP1[index].y);
        float projectedLightLength = max(length(L.xy), 0.0001);
        vec2 projectedLight = L.xy / projectedLightLength;
        vec2 shadowOffset = -projectedLight * uOccluderRadius[index] * 1.25;

        float shadowDistance = segmentDistance(
            frag, occluderP0 + shadowOffset, occluderP1 + shadowOffset) -
            uOccluderRadius[index];
        float shadowWidth = max(fwidth(shadowDistance), 0.75);
        float shadowMask = 1.0 - smoothstep(-shadowWidth, shadowWidth, shadowDistance);

        float contactDistance = max(segmentDistance(frag, occluderP0, occluderP1) -
            uOccluderRadius[index], 0.0);
        float contactScale = max(uOccluderRadius[index] * 1.5, 1.0);
        float contactRatio = contactDistance / contactScale;
        float contactMask = exp(-0.5 * contactRatio * contactRatio);
        contextualDarkening += (0.24 * shadowMask + 0.10 * contactMask) *
            (1.0 - weldSuppression);
    }
    lit *= 1.0 - min(contextualDarkening, uMaterialShadowLimit);

    vec3 materialFresnel0 = mix(
        vec3(uMaterialFresnel0), base, uMaterialSpecularTint);
    vec3 fresnel = materialFresnel0 + (vec3(1.0) - materialFresnel0) *
        pow(1.0 - viewDot, 5.0);
    lit += fresnel * (0.42 * narrowSpecular + 0.10 * broadSpecular);

    lit = max(lit, base * 0.20);
    lit = clamp(lit, 0.0, 1.0);
    lit = linearToSrgb(lit);

    finalColor = vec4(lit, sourceAlpha * coverage);
}
