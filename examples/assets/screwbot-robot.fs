#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform float time;
uniform float reachable;
uniform float errorAmount;

out vec4 finalColor;

void main()
{
    vec2 uv = fragTexCoord;
    vec4 source = texture(texture0, uv) * fragColor;
    vec3 tint = source.rgb;

    float maximum = max(tint.r, max(tint.g, tint.b));
    float minimum = min(tint.r, min(tint.g, tint.b));
    float saturation = maximum - minimum;
    float coloredPanel = smoothstep(0.09, 0.32, saturation);

    float across = abs(uv.y - 0.5) * 2.0;
    float edge = smoothstep(0.70, 0.98, across);
    float centerChannel = 1.0 - smoothstep(0.035, 0.11, abs(uv.y - 0.5));
    float panelSeam = 1.0 - smoothstep(0.0, max(fwidth(uv.x) * 1.6, 0.006), abs(fract(uv.x * 4.0) - 0.5));

    float phase = fract(uv.x * 2.2 - time * 0.58);
    float travellingPulse = exp(-58.0 * (phase - 0.5) * (phase - 0.5));
    vec3 statusColor = mix(vec3(1.0, 0.20, 0.34), vec3(0.18, 0.92, 1.0), reachable);

    vec3 color = tint;
    color *= 0.86 + 0.14 * (1.0 - across);
    color += mix(vec3(0.05, 0.09, 0.14), tint * 0.24, coloredPanel) * edge;
    color -= panelSeam * 0.035 * (1.0 - coloredPanel);
    color += centerChannel * coloredPanel * tint * 0.13;
    color += centerChannel * travellingPulse * statusColor * (0.22 + errorAmount * 0.22);

    // A narrow moving specular highlight makes the links read as machined parts.
    float brushedHighlight = pow(max(0.0, 1.0 - abs(fract(uv.x * 1.7 + time * 0.055) - 0.5) * 2.0), 18.0);
    color += brushedHighlight * vec3(0.09, 0.13, 0.18) * (0.35 + coloredPanel);

    finalColor = vec4(clamp(color, 0.0, 1.0), source.a);
}
