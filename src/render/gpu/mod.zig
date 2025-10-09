//! Phantom GPU Rendering System
//! Revolutionary GPU-accelerated TUI rendering using Vulkan + CUDA
//! Optimized for NVIDIA GPUs with compute shader acceleration

pub const VulkanBackend = @import("VulkanBackend.zig");
pub const CUDACompute = @import("CUDACompute.zig");
pub const GPUTextRenderer = @import("GPUTextRenderer.zig");
pub const ShaderCompiler = @import("ShaderCompiler.zig");

test {
    _ = VulkanBackend;
    _ = CUDACompute;
    _ = GPUTextRenderer;
    _ = ShaderCompiler;
}
