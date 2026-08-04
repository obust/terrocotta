#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec2 resolution;
uniform vec2 direction;

out vec4 finalColor;

void main()
{
    vec2 stepUv = direction / resolution;
    vec4 color = texture(texture0, fragTexCoord) * 0.227027;
    color += texture(texture0, fragTexCoord + stepUv * 1.384615) * 0.316216;
    color += texture(texture0, fragTexCoord - stepUv * 1.384615) * 0.316216;
    color += texture(texture0, fragTexCoord + stepUv * 3.230769) * 0.070270;
    color += texture(texture0, fragTexCoord - stepUv * 3.230769) * 0.070270;
    finalColor = color * fragColor;
}
