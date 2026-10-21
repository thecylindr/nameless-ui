#version 440
// «Реалистичное» жидкое стекло карточек и панелей (GlassCard, LiquidGlassLayer.qml).
// Основа — шейдер Liquid Glass из MacShell (iOSDesign), MIT License, Copyright (c) 2026 Rickky.
// Сборка: qsb --qt6 -o liquidglass.frag.qsb liquidglass.frag (готовый .qsb лежит рядом — в наборе Android нет qsb)
//
// Карточка — пластина изогнутого стекла поверх фона окна:
//   * расстояние до края скруглённого прямоугольника и направление края — по полю расстояний
//   * выпуклый профиль края («сквиркл») даёт нормаль поверхности, закон Снелла — сдвиг фона (преломление)
//   * фон читается раздельно по каналам (дисперсия) через размытие с подбором уровня mip
//   * насыщенность, подкраска цветом темы, затем блик по краю, «мениск» внутри края и затенение глубины
// Отличия от исходного: число выборок задаётся (taps: телефон 8, компьютер 20), без дисперсии каждая выборка —
// одно чтение вместо трёх, тень снаружи не рисуется (её рисует GlassShadow).
// Вершинный шейдер свой (liquidglass.vert): встроенный в Qt собран только под GLSL ES 100, а Adreno
// не связывает его с фрагментным 300 es («shader version mismatch»).
// Фон — один общий снимок окна (GlassBackground.glassBackdrop): точка фона берётся по положению пикселя в окне
// (gl_FragCoord), поэтому прокрутка, сдвиг и сжатие карточки при нажатии совпадают с фоном сразу, без пересчётов

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 glassSize;     // размер карточки, px
    vec2 winSize;       // размер окна (и общего снимка фона), логические px
    float radius;       // радиус углов, px
    float bezel;        // ширина преломляющего края, px
    float thickness;    // насколько край сдвигает фон, px
    float dispersion;   // расхождение по цветам (0 — без него)
    float blurPx;       // радиус размытия фона, px
    float tintMix;      // 0..1 — доля подкраски
    float saturation;   // насыщенность фона
    float dark;         // 0 — светлая тема, 1 — тёмная
    float rim;          // сила блика по краю
    float grain;        // мелкое зерно по всему стеклу
    float magnify;      // вертикальное увеличение «линзой» всей пластины
    float taps;         // число выборок размытия (не больше MAX_TAPS)
    float dpr;          // физических пикселей на логический
    float fbHeight;     // высота кадра окна, физические px
    float yUp;          // 1 — ось Y кадра снизу вверх (OpenGL)
    vec2 lightDir;      // направление света (общее на окно)
    float texScale;     // текселей снимка фона на логический пиксель
    float edgeColor;    // 0..1 — край впитывает цвета позади (в конце буфера: старые сборки .qsb совместимы)
};

layout(binding = 1) uniform sampler2D src;

const int   MAX_TAPS = 24;
const float GOLDEN   = 2.39996323;

// положение текущего пикселя в окне (логические px) и его же — в координатах карточки
vec2 fragWin;
vec2 fragLocal;

// точка фона: смещение от текущего пикселя в координатах карточки переносится в окно
vec3 backdropLod(vec2 p, float lod)
{
    vec2 uv = (fragWin + (p - fragLocal)) / winSize;
    return textureLod(src, clamp(uv, vec2(0.001), vec2(0.999)), lod).rgb;
}

float ign(vec2 p)
{
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// размытие с гауссовыми весами: каждая выборка читает заранее размытый уровень mip под шаг между выборками,
// узор поворачивается на каждой точке — вместо «призраков» фона остаётся мелкое зерно
// число выборок одинаково по всей карточке: разное у края и в середине давало видимую границу («квадрат» внутри)
vec3 blurredDisp(vec2 p, vec2 disp, float disperse, float rad)
{
    float n    = clamp(taps, 4.0, float(MAX_TAPS));
    float R    = max(rad, 0.5) * 1.5;
    float gap  = R * sqrt(3.14159265 / n);
    // уровень mip — по шагу между выборками в текселях снимка, а не в пикселях окна: иначе на телефоне брался
    // слишком грубый уровень и проступали «квадраты»
    float lod  = clamp(log2(max(gap * texScale, 1.0)) + 0.35, 0.0, 6.0);
    float rot  = ign(gl_FragCoord.xy) * 6.2831853;
    bool split = disperse > 0.001 && dot(disp, disp) > 0.0025;
    vec3  acc  = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < MAX_TAPS; ++i) {
        if (float(i) >= n) break;
        float fi = float(i) + 0.5;
        float r  = sqrt(fi / n);
        float a  = fi * GOLDEN + rot;
        float w  = exp(-2.2 * r * r);
        vec2  o  = vec2(cos(a), sin(a)) * r * R;
        vec3  c;
        if (split) {
            c.r = backdropLod(p + o + disp * (1.0 + disperse), lod).r;
            c.g = backdropLod(p + o + disp,                    lod).g;
            c.b = backdropLod(p + o + disp * (1.0 - disperse), lod).b;
        } else {
            c = backdropLod(p + o + disp, lod);
        }
        acc  += c * w;
        wsum += w;
    }
    return acc / wsum;
}

float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float roundBox(vec2 q, vec2 hs, float r)
{
    vec2 d = abs(q) - (hs - r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void main()
{
    vec2 p  = qt_TexCoord0 * glassSize;
    vec2 hs = glassSize * 0.5;
    fragLocal = p;
    fragWin   = vec2(gl_FragCoord.x, yUp > 0.5 ? fbHeight - gl_FragCoord.y : gl_FragCoord.y) / max(dpr, 0.01);
    vec2 q  = p - hs;
    float r = min(radius, min(hs.x, hs.y));

    float sd  = roundBox(q, hs, r);               // < 0 — внутри стекла
    float cov = clamp(0.5 - sd, 0.0, 1.0);        // сглаженное покрытие края
    if (cov <= 0.0) { fragColor = vec4(0.0); return; }

    // расстояние до края и направление края наружу
    float t = max(-sd, 0.0);
    vec2 d2 = abs(q) - (hs - r);
    vec2 sg = vec2(q.x >= 0.0 ? 1.0 : -1.0, q.y >= 0.0 ? 1.0 : -1.0);
    vec2 m  = max(d2, 0.0);
    vec2 g  = (length(m) > 1e-4) ? normalize(m) * sg
                                 : ((d2.x > d2.y) ? vec2(sg.x, 0.0) : vec2(0.0, sg.y));

    // выпуклый край («сквиркл») → нормаль поверхности
    float bz    = max(bezel, 1.0) * 1.45;
    float u     = clamp(t / bz, 0.0, 1.0);
    float om    = 1.0 - u;
    float om4   = om * om * om * om;
    float slope = min((om * om * om) / pow(max(1.0 - om4, 1e-3), 0.75), 7.0);
    vec3 nrm    = normalize(vec3(g * slope, 1.0));

    // преломление: стекло n≈1.5, луч входит сверху
    vec3 rd   = refract(vec3(0.0, 0.0, -1.0), nrm, 1.0 / 1.5);
    vec2 disp = rd.xy / max(-rd.z, 0.2) * thickness * 1.35;

    // вся пластина — пологая линза по вертикали; у изогнутого края размытие меньше — край читается чётче
    vec2 ps   = vec2(p.x, (p.y - hs.y) * (1.0 - magnify * 1.5) + hs.y);
    float rad = blurPx * mix(0.45, 1.0, smoothstep(0.0, bz, t));
    vec3 col = blurredDisp(ps, disp, dispersion * 0.6, rad);

    // край впитывает цвета позади: у кромки подкраска слабее, а насыщенность выше — пятна атмосферы «затекают»
    // в изгиб стекла; в середине подкраска чуть плотнее, текст читается
    float edgeK = exp(-t / (bz * 0.55)) * edgeColor;

    // цвет: живость, подкраска (светлая — белым, тёмная — почти чёрным), лёгкое «молочное» осветление
    float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(l), col, saturation * (1.0 + 0.5 * edgeK));
    float tintLocal = clamp(tintMix * (1.0 + 0.15 * edgeColor) * (1.0 - 0.7 * edgeK), 0.0, 1.0);
    col = mix(col, mix(vec3(1.0), vec3(0.09, 0.09, 0.10), dark), tintLocal);
    col += mix(0.055, 0.020, dark);

    // глубина: мягкий свет сверху, темнее у нижнего внутреннего края, край толще поглощает свет
    float ty = clamp((q.y + hs.y) / glassSize.y, 0.0, 1.0);
    col += (1.0 - ty) * mix(0.040, 0.030, dark);
    col *= 1.0 - 0.12 * exp(-t / 6.0) * clamp(g.y, 0.0, 1.0);
    col *= 1.0 - 0.10 * exp(-t / (bz * 0.45));

    // цвет блика — от того, что лежит сразу за краем: одно чтение крупного уровня mip, усиленное по насыщенности
    vec3 env = backdropLod(p + g * bz * 0.9, 3.5);
    float envL = dot(env, vec3(0.2126, 0.7152, 0.0722));
    env = clamp(mix(vec3(envL), env, 1.8), 0.0, 1.0);
    vec3 rimC = mix(vec3(0.96, 0.98, 1.0), 0.35 + env * 0.9, 0.6 * edgeColor);

    // блик по краю, свет сверху слева
    vec2  L      = normalize(lightDir);
    float facing = dot(g, L);
    float spec   = pow(max(facing, 0.0), 1.6) + 0.55 * pow(max(-facing, 0.0), 2.2);
    float edgeHi = exp(-t / 1.1) * (0.18 + 0.78 * spec) + exp(-t / 5.0) * 0.10 * (0.30 + spec);
    col += edgeHi * rim * mix(0.85, 1.0, dark) * rimC;

    // «мениск»: второй мягкий блик внутри края — как поверхностное натяжение
    float mx  = (t - bz * 0.5) / (bz * 0.2 + 1.0);
    col += exp(-mx * mx) * 0.07 * (0.35 + spec) * rim * rimC;

    // зерно с треугольным распределением, одинаковое по каналам — читается как фактура, а не цветной шум
    col += (hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy * 1.7 + 17.0) - 1.0) * grain;

    fragColor = vec4(clamp(col, 0.0, 1.0) * cov, cov) * qt_Opacity;   // альфа умножена
}
