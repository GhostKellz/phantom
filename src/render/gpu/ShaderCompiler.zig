//! Shader Compiler - Placeholder for GLSL/SPIR-V shader compilation
//! Will compile shaders for Vulkan rendering pipeline
//!
//! STATUS: Experimental - GPU rendering is not enabled by default
//! Enable with: zig build -Dgpu=true (not yet implemented)
//!
//! ROADMAP:
//! - v0.9.0: Basic shader loading from pre-compiled SPIR-V
//! - v1.0.0: Runtime GLSL→SPIR-V compilation via glslang/shaderc
//! - v1.1.0: Hot-reload support for shader development

const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,

pub fn init(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
    // No resources to cleanup in stub implementation
}

pub const ShaderType = enum {
    vertex,
    fragment,
    compute,
};

pub const CompiledShader = struct {
    spirv: []const u8,
    entry_point: []const u8,

    pub fn deinit(self: *CompiledShader, allocator: Allocator) void {
        allocator.free(self.spirv);
        allocator.free(self.entry_point);
    }
};

/// Compile GLSL shader to SPIR-V
/// NOTE: Not implemented - requires glslang or shaderc integration
/// Planned for v1.0.0 when GPU rendering backend is production-ready
pub fn compileGLSL(self: *Self, source: []const u8, shader_type: ShaderType) !CompiledShader {
    _ = self;
    _ = source;
    _ = shader_type;
    return error.NotImplemented;
}

/// Load pre-compiled SPIR-V shader from file
/// NOTE: Not implemented - will support .spv files in v0.9.0
/// For now, GPU rendering uses CPU fallback automatically
pub fn loadSPIRV(self: *Self, path: []const u8) !CompiledShader {
    _ = self;
    _ = path;
    return error.NotImplemented;
}

/// Validate SPIR-V shader bytecode
/// NOTE: Not implemented - requires SPIRV-Tools integration
/// Basic validation will be added in v0.9.0
pub fn validateSPIRV(self: *Self, spirv: []const u8) !bool {
    _ = self;
    _ = spirv;
    return error.NotImplemented;
}
