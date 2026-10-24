#version 440
// Объём края жидкого стекла для элементов управления (кнопки, переключатели, поля, панели) — Rim.qml.
// Без чтения фона, поэтому дёшево: блик по краю (френель), «мениск», тёмная линза за ним, лёгкая дисперсия цвета по кромке
// и блик в углу со стороны света (основа — MacShell, iOSDesign, MIT License, Copyright (c) 2026 Rickky).
// Внутренняя часть элемента — только мягкий верхний свет, без расчёта края: у больших панелей это почти все пиксели.
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

    float t  = max(-sd, 0.0);
    float bz = max(bezel, 1.0);
    float ty = clamp((q.y + hs.y) / size.y, 0.0, 1.0);
    float top = (1.0 - ty) * (1.0 - ty) * 0.06 * (1.0 - pressed);
    // середина элемента: только верхний свет
    if (t > bz * 2.5 + 16.0) { fragColor = vec4(vec3(0.97, 0.98, 1.0) * top, top) * cov * qt_Opacity; return; }

    vec2 d2 = abs(q) - (hs - r);
    vec2 sg = vec2(q.x >= 0.0 ? 1.0 : -1.0, q.y >= 0.0 ? 1.0 : -1.0);
    vec2 m  = max(d2, 0.0);
    vec2 g  = (length(m) > 1e-4) ? normalize(m) * sg
                                 : ((d2.x > d2.y) ? vec2(sg.x, 0.0) : vec2(0.0, sg.y));

    vec2  L      = normalize(lightDir);
    float facing = dot(g, L);
    // френель: кромка светится по всему контуру, сильнее со стороны света; противоположная сторона ловит отражённый свет
    float spec   = pow(max(facing, 0.0), 1.5) + 0.6 * pow(max(-facing, 0.0), 2.4);
    float k      = rim * mix(1.0, 0.55, pressed) * mix(0.85, 1.0, dark);
    float edge   = exp(-t / 0.9);
    float hi     = edge * (0.24 + 0.76 * spec) + exp(-t / 3.5) * 0.10 * (0.30 + spec);
    // мениск — светлая полоса внутри края, за ним тёмная линза (стекло преломляет и собирает свет к краю)
    float mx     = (t - bz * 0.5) / (bz * 0.22 + 1.0);
    hi += exp(-mx * mx) * 0.09 * (0.35 + spec);
    float lx     = (t - bz * 1.25) / (bz * 0.35 + 1.0);
    float lens   = exp(-lx * lx) * 0.07 * (0.5 + 0.5 * max(-facing, 0.0));
    // блик в углу со стороны света: короткое яркое пятно на изгибе
    float corner = length(m) > 1e-4 ? pow(max(facing, 0.0), 6.0) * exp(-t / 2.2) * 0.35 : 0.0;
    hi = (hi + corner) * k;

    // глубина: темнее к нижнему внутреннему краю — стекло «толстое»
    float shade = 0.14 * exp(-t / 5.0) * clamp(g.y, 0.0, 1.0) + 0.06 * exp(-t / (bz * 0.5)) + lens;
    shade *= mix(1.0, 1.6, pressed);

    // дисперсия: по кромке со стороны света — тёплый отсвет, с обратной — холодный (как радужный край настоящего стекла)
    vec3 tint = mix(vec3(0.86, 0.94, 1.0), vec3(1.0, 0.95, 0.86), clamp(facing * 0.5 + 0.5, 0.0, 1.0));
    tint = mix(vec3(0.97, 0.98, 1.0), tint, edge * 0.9);

    float light = hi + top;
    vec3  rgb   = tint * light;
    float a     = clamp(light + shade, 0.0, 1.0);
    fragColor = vec4(rgb, a) * cov * qt_Opacity;
}
