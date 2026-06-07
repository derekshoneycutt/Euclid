#version 330

in vec2 fragUV;
in vec4 fragColor;
out vec4 finalColor;

uniform vec3 uLightDirView;
uniform float uAmbient;
uniform float uDiffuse;
uniform float uSpecularStrength;
uniform float uSpecularPower;
uniform vec2 uP0;
uniform vec2 uP1;
uniform float uRadius;
uniform float uViewportHeight;

void main() {
    vec2 p0 = vec2(uP0.x, uViewportHeight - uP0.y);
    vec2 p1 = vec2(uP1.x, uViewportHeight - uP1.y);
    vec2 frag = gl_FragCoord.xy;

    vec2 d = p1 - p0;
    float dLen = max(length(d), 0.0001);
    vec2 dir = d / dLen;
    vec2 perp = vec2(-dir.y, dir.x);

    vec2 v = frag - p0;
    float t = clamp(dot(v, dir), 0.0, dLen);
    vec2 closest = p0 + dir * t;

    float radius = max(uRadius, 0.0001);
    float signedDist = dot(frag - closest, perp);
    float x = clamp(signedDist / radius, -1.0, 1.0);
    float yz = max(1.0 - x * x, 0.0);
    vec3 N = normalize(vec3(0.0, x, sqrt(yz)));

    vec3 L = normalize(uLightDirView);
    vec3 V = vec3(0.0, 0.0, 1.0);
    vec3 H = normalize(L + V);

    float lambert = max(dot(N, L), 0.0);
    float spec = pow(max(dot(N, H), 0.0), uSpecularPower) * uSpecularStrength;

    float edgeDark = smoothstep(0.35, 1.0, abs(x));
    float centerBoost = pow(max(yz, 0.0), 0.28);

    // Directional glint band for visible 3D sheen.
    float glintCoord = abs(x + 0.35 * sign(L.y + 0.0001));
    float glint = pow(clamp(1.0 - glintCoord, 0.0, 1.0), 20.0);

    vec3 base = fragColor.rgb;
    float diffuseBand = uAmbient + uDiffuse * lambert;
    float tubeShape = (1.0 + 0.55 * centerBoost) * (1.0 - 0.40 * edgeDark);
    vec3 lit = base * diffuseBand * tubeShape;

    float sheen = 0.55 * spec + 0.30 * glint;
    lit += base * sheen;

    lit = max(lit, base * 0.20);
    lit = clamp(lit, 0.0, 1.0);

    finalColor = vec4(lit, fragColor.a);
}
