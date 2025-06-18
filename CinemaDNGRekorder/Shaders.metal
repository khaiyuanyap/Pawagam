//
//  SHaders.metal
//  CinemaDNGRekorder
//
//  Created by Khai Yuan Yap on 18/06/2025.
//

#include <metal_stdlib>
using namespace metal;

kernel void luminanceHistogram(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    device atomic_uint *histogram [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x < inputTexture.get_width() && gid.y < inputTexture.get_height()) {
        float4 color = inputTexture.read(gid);
        float luminance = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
        
        // Convert to 0-255 and bin index
        uint binIndex = uint(luminance * 255.0);
        binIndex = clamp(binIndex, 0u, 255u);
        
        // Atomic increment
        atomic_fetch_add_explicit(&histogram[binIndex], 1, memory_order_relaxed);
    }
}
