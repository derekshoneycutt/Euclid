#version 330

layout(location = 0) in vec2 vertexPosition;
layout(location = 1) in vec2 vertexTexCoord;
layout(location = 2) in vec3 instanceCenterDiameter;
layout(location = 3) in vec4 vertexColor;

out vec2 fragUV;
out vec4 fragColor;

uniform vec2 uViewport;

void main() {
    vec2 pixel = instanceCenterDiameter.xy + vertexPosition * instanceCenterDiameter.z;
    vec2 normalized = vec2(
        pixel.x * 2.0 / uViewport.x - 1.0,
        1.0 - pixel.y * 2.0 / uViewport.y);

    fragUV = vertexTexCoord;
    fragColor = vertexColor;
    gl_Position = vec4(normalized, 0.0, 1.0);
}