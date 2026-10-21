#version 440
// Объём края жидкого стекла для элементов управления (кнопки, переключатели, поля) — LiquidRim.qml.
// Без чтения фона, поэтому дёшево и на телефоне: тот же блик по краю, «мениск» и затенение глубины,
// что у liquidglass.frag (основа — MacShell, iOSDesign, MIT License, Copyright (c) 2026 Rickky).
// Сборка: qsb --qt6 -o liquidrim.frag.qsb liquidrim.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // размер элемента, px
    float radius;       // радиус углов, px
    float bezel;        // ширина выпуклого края, px
    float rim;          // сила блика
    float dark;         // 0 — светлая тема, 1 — тёмная
    float pressed;      // 0..1 — нажатие: блик тусклее, глубина сильнее
    vec2 lightDir;      // направление света (общее на окно)
};

float roundBox(vec2 q, vec2 hs, float r)
{
    vec2 d = abs(q) - (hs - r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void main()
{
    vec2 p  = qt_TexCoord0 * size;
    vec2 hs = size * 0.5;
    vec2 q  = p - hs;
    float r = min(radius, min(hs.x, hs.y));
    float sd  = roundBox(q, hs, r);
    float cov = clamp(0.5 - sd, 0.0, 1.0);
    if (cov <= 0.0) { fragColor = vec4(0.0); return; }

    float t = max(-sd, 0.0);
    float bz = max(bezel, 1.0);
    // середина элемента: все слагаемые края там меньше 1/255 — пиксель пропускается без расчётов
    float ty0 = clamp((q.y + hs.y) / size.y, 0.0, 1.0);
    if (t > bz * 2.0 + 24.0 && (1.0 - ty0) * 0.05 * (1.0 - pressed) < 0.004) { fragColor = vec4(0.0); return; }
    vec2 d2 = abs(q) - (hs - r);
    vec2 sg = vec2(q.x >= 0.0 ? 1.0 : -1.0, q.y >= 0.0 ? 1.0 : -1.0);
    vec2 m  = max(d2, 0.0);
    vec2 g  = (length(m) > 1e-4) ? normalize(m) * sg
                                 : ((d2.x > d2.y) ? vec2(sg.x, 0.0) : vec2(0.0, sg.y));

    // блик по краю (свет сверху слева) и «мениск» внутри края
    vec2  L      = normalize(lightDir);
    float facing = dot(g, L);
    float spec   = pow(max(facing, 0.0), 1.6) + 0.55 * pow(max(-facing, 0.0), 2.2);
    float k      = rim * mix(1.0, 0.55, pressed) * mix(0.85, 1.0, dark);
    float hi     = exp(-t / 1.1) * (0.20 + 0.80 * spec) + exp(-t / 4.0) * 0.10 * (0.30 + spec);
    float mx     = (t - bz * 0.5) / (bz * 0.2 + 1.0);
    hi += exp(-mx * mx) * 0.08 * (0.35 + spec);
    hi *= k;

    // глубина: темнее к нижнему внутреннему краю и по всему краю — стекло «толстое»; сверху мягкий свет
    float ty    = clamp((q.y + hs.y) / size.y, 0.0, 1.0);
    float shade = 0.14 * exp(-t / 5.0) * clamp(g.y, 0.0, 1.0) + 0.06 * exp(-t / (bz * 0.5));
    shade *= mix(1.0, 1.6, pressed);
    float top   = (1.0 - ty) * 0.05 * (1.0 - pressed);

    // белый блик поверх (сложение) и тень (затемнение) — одним цветом с умноженной альфой
    float light = hi + top;
    vec3  rgb   = vec3(0.96, 0.98, 1.0) * light;
    float a     = clamp(light + shade, 0.0, 1.0);
    fragColor = vec4(rgb, a) * cov * qt_Opacity;
}
