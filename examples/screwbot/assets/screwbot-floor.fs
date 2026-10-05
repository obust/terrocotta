#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform float time;
uniform vec2 targetUv;
uniform float reachable;
uniform float errorAmount;

out vec4 finalColor;

float gridLine(vec2 coordinate)
{
    vec2 width = max(fwidth(coordinate), vec2(0.0001));
    vec2 distanceToLine = abs(fract(coordinate - 0.5) - 0.5) / width;
    return 1.0 - min(min(distanceToLine.x, distanceToLine.y), 1.0);
}

void main()
{
    vec2 uv = fragTexCoord;
    vec4 source = texture(texture0, uv) * fragColor;

    // The floor covers 520 x 480 world units: thirteen by twelve 40-unit cells.
    float minorGrid = gridLine(uv * vec2(13.0, 12.0));
    float majorGrid = gridLine(uv * vec2(3.25, 3.0));
    vec3 gridColor = vec3(0.10, 0.34, 0.50);

    vec2 worldDelta = (uv - targetUv) * vec2(520.0, 480.0);
    float targetDistance = length(worldDelta);
    float ringPhase = fract(targetDistance / 34.0 - time * 0.42);
    float ringWidth = max(fwidth(ringPhase), 0.012);
    float rings = 1.0 - smoothstep(0.0, ringWidth * 2.2, min(ringPhase, 1.0 - ringPhase));
    rings *= smoothstep(185.0, 25.0, targetDistance);

    float reticle = 1.0 - smoothstep(1.2, 3.2, abs(targetDistance - 18.0));
    vec3 statusColor = mix(vec3(1.0, 0.25, 0.38), vec3(0.25, 0.95, 0.58), reachable);
    float warningPulse = mix(0.76 + 0.24 * sin(time * 7.0), 1.0, reachable);

    float materialNoise = fract(sin(dot(floor(uv * vec2(1024.0)), vec2(127.1, 311.7))) * 43758.5453);
    vec3 color = source.rgb * (0.86 + materialNoise * 0.035);
    color += gridColor * (minorGrid * 0.055 + majorGrid * 0.11);
    color += statusColor * rings * (0.050 + errorAmount * 0.045) * warningPulse;
    color += statusColor * reticle * 0.15 * warningPulse;

    // A broad cool pool ties the floor to the overhead fluorescent fixtures.
    float workcell = 1.0 - smoothstep(0.10, 0.62, length((uv - vec2(0.48, 0.48)) * vec2(1.0, 1.08)));
    color += vec3(0.02, 0.075, 0.105) * workcell;

    finalColor = vec4(clamp(color, 0.0, 1.0), source.a);
}
