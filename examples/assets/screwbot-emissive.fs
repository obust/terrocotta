#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;

out vec4 finalColor;

void main()
{
    vec4 source = texture(texture0, fragTexCoord) * fragColor;
    float maximum = max(source.r, max(source.g, source.b));
    float minimum = min(source.r, min(source.g, source.b));
    float saturation = maximum - minimum;

    float coloredInstrument = smoothstep(0.10, 0.38, saturation) * smoothstep(0.18, 0.70, maximum);
    float whiteInstrument = smoothstep(0.72, 0.98, maximum) * 0.16;
    float emission = max(coloredInstrument, whiteInstrument);

    finalColor = vec4(source.rgb * emission * 1.25, source.a * emission);
}
