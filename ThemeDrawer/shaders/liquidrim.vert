#version 440
// Вершинный шейдер объёма края (LiquidRim.qml) — как встроенный в ShaderEffect, но собранный под те же
// версии GLSL, что и liquidrim.frag. Блок uniform обязан совпадать с фрагментным.
// Сборка: qsb --qt6 --glsl "300es,330" --hlsl 50 --msl 12 -o liquidrim.vert.qsb liquidrim.vert

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float radius;
    float bezel;
    float rim;
    float dark;
    float pressed;
    vec2 lightDir;
};

out gl_PerVertex { vec4 gl_Position; };

void main()
{
    qt_TexCoord0 = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
