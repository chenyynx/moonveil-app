//
//  Shaders.metal
//  Effort slider "Ultracode" fire simulation
//
//  Ported from the WebGL2/GLSL shaders in
//  https://github.com/254558/claude-range-slider
//  Algorithm and parameters kept identical to the GLSL source; only the
//  language and texture-binding conventions changed for Metal.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared vertex stage

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Full-screen triangle generated purely from the vertex id — no vertex
// buffer needed. The triangle covers more than the viewport; the parts
// outside [0,1] on either axis are clipped away by the rasterizer.
vertex VertexOut vertex_fullscreen(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VertexOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = p;
    return out;
}

// MARK: - Shared helpers

inline float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// pow(x, 2.0) is technically undefined for negative x in GLSL/MSL (pow is
// spec'd for x >= 0); the GLSL source relies on hardware behaving anyway.
// Using an explicit square avoids depending on that.
inline float sq(float x) {
    return x * x;
}

// MARK: - Pass 1: fire simulation (feeds back on itself, ping-pong)

struct SimUniforms {
    float u_time;
    float u_slider;
    float u_elapsed;
    float u_dt;   // seconds since the previous frame (frame-rate-independent decay)
};

fragment float4 fragment_sim(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> u_back [[texture(0)]],
                              constant SimUniforms &u [[buffer(0)]]) {
    constexpr sampler samp(address::clamp_to_edge, filter::linear);

    float2 uv = in.uv;
    float2 g = uv * float2(72.0, 6.0);
    float2 id = floor(g);
    float2 cf = fract(g);
    float h = hash(id);
    float2 ap = abs(cf - 0.5);
    float cell = smoothstep(0.34, 0.22, max(ap.x * 0.9, ap.y));

    float3 prev = u_back.sample(samp, uv).rgb;
    float fade_mask = smoothstep(0.0, 0.45, uv.x);
    // Frame-rate-independent decay: at 60fps u_dt == 1/60 so this matches the
    // reference 0.90/frame exactly; at 120fps each frame decays a little less
    // so the ember lifetime stays the same number of seconds.
    float decay = prev * pow(0.90, u_dt * 60.0) * fade_mask;

    float act = smoothstep(0.95, 1.0, u.u_slider);
    if (act < 0.01 || u.u_elapsed < 0.0) {
        return float4(decay, 1.0);
    }

    float t = u.u_time;
    float cellDelay = h * 1.2;
    float cellAge   = max(u.u_elapsed - cellDelay, 0.0);
    float ignited   = step(0.001, cellAge);
    float cellSpd   = 0.85 + h * 0.30;
    float eased = 1.0 - pow(1.0 - clamp(cellAge / 2.5, 0.0, 1.0), 3.0);
    float dist  = eased * u.u_slider * cellSpd * ignited;
    float cellOff = (h - 0.5) * 0.05;
    float front   = max(u.u_slider - dist - cellOff, 0.02);
    float tail    = max(u.u_slider - front, 0.001);

    float inZ   = step(front - 0.003, uv.x) * step(uv.x, u.u_slider + 0.003);
    float dn    = clamp(max(u.u_slider - uv.x, 0.0) / tail, 0.0, 1.0);
    float bright = pow(1.0 - dn, 0.65);
    bright = max(bright, 0.04 * ignited) * inZ;
    bright *= 1.0 - smoothstep(0.94, 1.05, dn);

    float es = mix(0.15, 0.5, min(u.u_elapsed / 1.0, 1.0));
    float vy = abs(uv.y - 0.5) * 2.0;
    float vf = pow(max(1.0 - vy * vy * 0.45, 0.0), 0.75);
    float ts = mix(0.85, 1.0, min(u.u_elapsed / 1.5, 1.0));

    float f1 = sin(uv.x * 30.0 + t * 15.0 * ts + h * 6.28);
    float f2 = sin(uv.x * 17.0 + t * 8.0 * ts + h * 3.14);
    float f3 = sin(uv.x * 52.0 + t * 25.0 * ts + h * 10.0);
    float flame = smoothstep(0.08, 0.92, (f1 + f2 * 0.5 + f3 * 0.25) * 0.35 + 0.5);

    float r1 = sin(dn * 16.0 - t * 5.0 * ts + h * 3.0);
    float r2 = sin(dn * 8.0 - t * 2.5 * ts + h * 5.0);
    float rhythm = smoothstep(-0.15, 0.55, r1) * (r2 * 0.5 + 0.5);
    rhythm = pow(max(rhythm, 0.0), 1.2);

    float avgSpd = dist / max(cellAge, 0.001);
    float age    = max(cellAge - max(u.u_slider - uv.x, 0.0) / max(avgSpd, 0.001), 0.0);
    float flash  = step(0.0, age) * exp(-age * 3.2);

    float sp  = fract(t * (0.38 + h * 0.15) + h * 7.0);
    float sX  = u.u_slider - sp * tail;
    float sY  = 0.5 + sin(sp * 11.0 + h * 6.28) * 0.28;
    float spark = smoothstep(0.014, 0.0, abs(uv.x - sX))
                * smoothstep(0.18, 0.0, abs(uv.y - sY))
                * (1.0 - sp) * (1.0 - sp) * es;

    float energy = bright * vf * (flame * 0.42 + rhythm * 0.38)
                 + flash * bright * vf * 0.55
                 + spark * 0.7 * inZ;
    energy *= es;

    float edgeBase = exp(-sq((uv.x - front) * 18.0));
    float ef1 = sin(uv.x * 45.0 + t * 20.0 * ts + h * 6.28) * 0.5 + 0.5;
    float ef2 = sin(uv.x * 28.0 + t * 11.0 * ts + h * 3.14) * 0.5 + 0.5;
    float edge = edgeBase * (0.25 + ef1 * ef2 * 1.5) * 1.6 * act * es;

    float leadD    = front - uv.x;
    float leadZone = smoothstep(0.07, 0.0, leadD) * step(0.0, leadD) * vf;
    float h2       = hash(id + float2(99.0, 33.0));
    float leadF    = sin(leadD * 100.0 + t * 20.0 * ts + h2 * 6.28) * 0.5 + 0.5;
    float leadSpark = leadZone * step(0.6, h2) * leadF * act * es * 0.5;

    float total = energy + edge + leadSpark;

    float3 ember = float3(0.28, 0.10, 0.58);
    float3 wpur  = float3(0.62, 0.32, 1.0);
    float3 wht   = float3(1.0, 0.94, 0.98);
    float temp = 1.0 - dn;
    float3 col = mix(ember, wpur, temp);
    col        = mix(col, wht, pow(temp, 4.5));
    col       *= total;

    float pulse = sin(t * 2.8) * 0.15 + 1.0;
    float core  = exp(-sq((uv.x - u.u_slider) * 16.0));
    col += wht * core * 2.2 * pulse * act * es;
    col += wpur * exp(-sq((uv.x - u.u_slider) * 3.5)) * 0.12 * act * es;

    col *= cell;
    col *= fade_mask;

    return float4(min(decay + col, float3(1.5)), 1.0);
}

// MARK: - Passes 2 & 3: separable Gaussian blur (bloom extraction)

struct BlurUniforms {
    float2 u_dir;
    float2 u_res;
    float u_ext; // > 0.5: cull dark pixels before blurring (bloom threshold pass)
};

inline float3 blurSample(texture2d<float, access::sample> tex,
                          sampler samp,
                          float2 uv,
                          float ext) {
    float3 c = tex.sample(samp, uv).rgb;
    float lum = dot(c, float3(0.2126, 0.7152, 0.0722));
    return (ext > 0.5 && lum < 0.3) ? float3(0.0) : c;
}

fragment float4 fragment_blur(VertexOut in [[stage_in]],
                               texture2d<float, access::sample> u_tex [[texture(0)]],
                               constant BlurUniforms &u [[buffer(0)]]) {
    constexpr sampler samp(address::clamp_to_edge, filter::linear);

    float2 o = u.u_dir * 1.8 / u.u_res;
    float3 r = blurSample(u_tex, samp, in.uv, u.u_ext) * 0.227027;
    r += blurSample(u_tex, samp, in.uv + o, u.u_ext) * 0.194595;
    r += blurSample(u_tex, samp, in.uv - o, u.u_ext) * 0.194595;
    r += blurSample(u_tex, samp, in.uv + o * 2.0, u.u_ext) * 0.121622;
    r += blurSample(u_tex, samp, in.uv - o * 2.0, u.u_ext) * 0.121622;
    r += blurSample(u_tex, samp, in.uv + o * 3.0, u.u_ext) * 0.054054;
    r += blurSample(u_tex, samp, in.uv - o * 3.0, u.u_ext) * 0.054054;

    return float4(r, 1.0);
}

// MARK: - Pass 4: HDR tone-mapped composite

fragment float4 fragment_comp(VertexOut in [[stage_in]],
                               texture2d<float, access::sample> u_scene [[texture(0)]],
                               texture2d<float, access::sample> u_glow [[texture(1)]]) {
    constexpr sampler samp(address::clamp_to_edge, filter::linear);

    float3 s = u_scene.sample(samp, in.uv).rgb;
    float3 g = u_glow.sample(samp, in.uv).rgb;
    float3 result = 1.0 - exp(-(s + g * 1.2 + s * g * 0.35) * 1.15);

    return float4(result, 1.0);
}