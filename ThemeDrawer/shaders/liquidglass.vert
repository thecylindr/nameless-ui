#version 440
// Вершинный шейдер жидкого стекла (LiquidGlassLayer.qml) — как встроенный в ShaderEffect, но собранный
// под те же версии GLSL, что и liquidglass.frag. Блок uniform обязан совпадать с фрагментным.
// Сборка: qsb --qt6 --glsl "300es,330" --hlsl 50 --msl 12 -o liquidglass.vert.qsb liquidglass.vert

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 glassSize;
    vec2 winSize;
    float radius;
    float bezel;
    float thickness;
    float dispersion;
    float blurPx;
    float tintMix;
    float saturation;
    float dark;
    float rim;
    float grain;
    float magnify;
    float taps;
    float dpr;
    float fbHeight;
    float yUp;
    vec2 lightDir;
    float texScale;
};

out gl_PerVertex { vec4 gl_Position; };

void main()
{
    qt_TexCoord0 = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
