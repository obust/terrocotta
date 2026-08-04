#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform float time;

out vec4 finalColor;

void main()
{
    vec4 source = texture(texture0, fragTexCoord) * fragColor;
    float luma = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 graded = mix(vec3(luma), source.rgb, 1.03);
    graded = (graded - 0.5) * 1.025 + 0.5;

    // A restrained cool industrial grade and sub-pixel scan pattern keep the
    // canvas crisp while making emissive PGA colors read like instrument light.
    float scan = 0.995 + 0.005 * sin((gl_FragCoord.y + time * 9.0) * 3.14159265);
    graded *= vec3(0.995, 1.0, 1.018) * scan;
    float emissive = max(0.0, max(graded.b, graded.g) - graded.r - 0.18);
    float instrumentPulse = 0.96 + 0.04 * sin(time * 1.7);
    graded += vec3(0.015, 0.055, 0.09) * emissive * instrumentPulse;

    finalColor = vec4(clamp(graded, 0.0, 1.0), source.a);
}
