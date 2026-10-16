#include <metal_stdlib>
using namespace metal;

kernel void focusPeakingKernel(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float &threshold [[buffer(0)]],
    constant float4 &peakingColor [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) {
        return;
    }

    // Border handling
    if (gid.x == 0 || gid.y == 0 || gid.x >= inTexture.get_width() - 1 || gid.y >= inTexture.get_height() - 1) {
        float4 original = inTexture.read(gid);
        outTexture.write(original, gid);
        return;
    }

    // 3x3 Sobel Edge Detection Kernels
    // Gx:
    // [-1  0  1]
    // [-2  0  2]
    // [-1  0  1]
    // Gy:
    // [-1 -2 -1]
    // [ 0  0  0]
    // [ 1  2  1]

    auto luma = [](float4 color) -> float {
        return dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    };

    float p00 = luma(inTexture.read(uint2(gid.x - 1, gid.y - 1)));
    float p01 = luma(inTexture.read(uint2(gid.x,     gid.y - 1)));
    float p02 = luma(inTexture.read(uint2(gid.x + 1, gid.y - 1)));

    float p10 = luma(inTexture.read(uint2(gid.x - 1, gid.y)));
    float p12 = luma(inTexture.read(uint2(gid.x + 1, gid.y)));

    float p20 = luma(inTexture.read(uint2(gid.x - 1, gid.y + 1)));
    float p21 = luma(inTexture.read(uint2(gid.x,     gid.y + 1)));
    float p22 = luma(inTexture.read(uint2(gid.x + 1, gid.y + 1)));

    float gx = (-1.0 * p00) + (1.0 * p02) +
               (-2.0 * p10) + (2.0 * p12) +
               (-1.0 * p20) + (1.0 * p22);

    float gy = (-1.0 * p00) + (-2.0 * p01) + (-1.0 * p02) +
               ( 1.0 * p20) + ( 2.0 * p21) + ( 1.0 * p22);

    float gradient = sqrt(gx * gx + gy * gy);
    float4 originalColor = inTexture.read(gid);

    if (gradient > threshold) {
        // Blend peaking highlight over edge
        float4 highlighted = mix(originalColor, peakingColor, 0.85);
        outTexture.write(highlighted, gid);
    } else {
        outTexture.write(originalColor, gid);
    }
}
