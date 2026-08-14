#version 330

in vec2 fragUV;
in vec4 fragColor;
in float fragSpriteIndex;
out vec4 finalColor;

uniform sampler2D texture0;

const float atlasColumns = 3.0;
const float atlasRows = 3.0;

void main() {
    float spriteIndex = clamp(fragSpriteIndex, 0.0, 8.0);
    float tileX = mod(spriteIndex, atlasColumns);
    float tileY = floor(spriteIndex / atlasColumns);
    vec2 tileUV = (fragUV + vec2(tileX, tileY)) / vec2(atlasColumns, atlasRows);
    finalColor = texture(texture0, tileUV) * fragColor;
}