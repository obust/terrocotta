#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform sampler2D bloomTexture;
uniform float time;
uniform vec2 resolution;

out vec4 finalColor;

void main()
{
    vec2 uv = fragTexCoord;
    vec4 source = texture(texture0, uv) * fragColor;
    vec3 bloom = texture(bloomTexture, uv).rgb;

    // Keep the warehouse photographic while letting deliberately emissive
    // geometry feel like light. The pulse is intentionally almost subliminal.
    float instrumentPulse = 0.97 + 0.03 * sin(time * 1.7);
    vec3 color = source.rgb + bloom * 0.82 * instrumentPulse;

    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, 1.035);
    color *= vec3(0.992, 1.0, 1.018);

    // A filmic shoulder preserves the hue of additive cyan and violet light.
    color = color * (1.0 + color * 0.12) / (1.0 + color * 0.32);

    vec2 centered = uv * 2.0 - 1.0;
    float vignette = 1.0 - 0.085 * dot(centered, centered);
    color *= vignette;

    float logicalY = uv.y * resolution.y;
    float scan = 0.996 + 0.004 * sin((logicalY + time * 8.0) * 3.14159265);
    color *= scan;

    // Stable, very fine sensor grain prevents flat gradients from banding.
    float noise = fract(sin(dot(gl_FragCoord.xy + time * 17.0, vec2(12.9898, 78.233))) * 43758.5453);
    color += (noise - 0.5) * 0.006;

    finalColor = vec4(clamp(color, 0.0, 1.0), source.a);
}
