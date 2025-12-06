const std = @import("std");
const objc = @import("objc");
const geometry = @import("../../core/geometry.zig");

// Metal Shading Language source for triangle
const shader_source =
    \\#include <metal_stdlib>
    \\using namespace metal;
    \\
    \\struct VertexIn {
    \\    float2 position [[attribute(0)]];
    \\    float4 color [[attribute(1)]];
    \\};
    \\
    \\struct VertexOut {
    \\    float4 position [[position]];
    \\    float4 color;
    \\};
    \\
    \\vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
    \\    VertexOut out;
    \\    out.position = float4(in.position, 0.0, 1.0);
    \\    out.color = in.color;
    \\    return out;
    \\}
    \\
    \\fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    \\    return in.color;
    \\}
;

// Vertex data: position (x, y) + color (r, g, b, a)
const Vertex = extern struct {
    position: [2]f32,
    color: [4]f32,
};

// Triangle vertices with RGB colors at each corner
const triangle_vertices = [_]Vertex{
    // Top vertex - Red
    .{ .position = .{ 0.0, 0.5 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    // Bottom left - Green
    .{ .position = .{ -0.5, -0.5 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    // Bottom right - Blue
    .{ .position = .{ 0.5, -0.5 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
};

pub const Renderer = struct {
    device: objc.Object,
    command_queue: objc.Object,
    layer: objc.Object,
    pipeline_state: ?objc.Object,
    vertex_buffer: ?objc.Object,
    msaa_texture: ?objc.Object,
    size: geometry.Size(f64),
    sample_count: u32,

    const Self = @This();

    pub fn init(layer: objc.Object, size: geometry.Size(f64)) !Self {
        // Get default Metal device
        const MTLCreateSystemDefaultDevice = getMTLCreateSystemDefaultDevice() orelse
            return error.MetalNotAvailable;

        const device_ptr = MTLCreateSystemDefaultDevice();
        if (device_ptr == null) return error.MetalNotAvailable;

        const device = objc.Object.fromId(device_ptr);

        // Create command queue
        const command_queue = device.msgSend(objc.Object, "newCommandQueue", .{});

        // Set device on layer
        layer.msgSend(void, "setDevice:", .{device.value});

        // Set drawable size on layer
        const drawable_size = CGSize{
            .width = size.width,
            .height = size.height,
        };
        layer.msgSend(void, "setDrawableSize:", .{drawable_size});

        var self = Self{
            .device = device,
            .command_queue = command_queue,
            .layer = layer,
            .pipeline_state = null,
            .vertex_buffer = null,
            .msaa_texture = null,
            .size = size,
            .sample_count = 4, // MSAA 4x
        };

        // Create MSAA texture
        try self.createMSAATexture();

        // Setup pipeline for triangle rendering
        try self.setupPipeline();

        return self;
    }

    fn createMSAATexture(self: *Self) !void {
        // Release old texture if it exists
        if (self.msaa_texture) |tex| {
            tex.msgSend(void, "release", .{});
            self.msaa_texture = null;
        }

        const MTLTextureDescriptor = objc.getClass("MTLTextureDescriptor") orelse return error.ClassNotFound;

        // Create 2D multisample texture descriptor
        const desc = MTLTextureDescriptor.msgSend(
            objc.Object,
            "texture2DDescriptorWithPixelFormat:width:height:mipmapped:",
            .{
                @as(u64, 80), // MTLPixelFormatBGRA8Unorm
                @as(u64, @intFromFloat(self.size.width)),
                @as(u64, @intFromFloat(self.size.height)),
                false,
            },
        );

        // Set texture type to 2DMultisample
        desc.msgSend(void, "setTextureType:", .{@as(u64, 4)}); // MTLTextureType2DMultisample
        desc.msgSend(void, "setSampleCount:", .{@as(u64, self.sample_count)});
        desc.msgSend(void, "setUsage:", .{@as(u64, 1)}); // MTLTextureUsageRenderTarget
        desc.msgSend(void, "setStorageMode:", .{@as(u64, 2)}); // MTLStorageModePrivate (GPU only)

        const texture_ptr = self.device.msgSend(?*anyopaque, "newTextureWithDescriptor:", .{desc.value});
        if (texture_ptr == null) {
            return error.MSAATextureCreationFailed;
        }
        self.msaa_texture = objc.Object.fromId(texture_ptr);
    }

    fn setupPipeline(self: *Self) !void {
        // Create shader library from source
        const NSString = objc.getClass("NSString") orelse return error.ClassNotFound;
        const source_str = NSString.msgSend(
            objc.Object,
            "stringWithUTF8String:",
            .{shader_source.ptr},
        );

        // Compile shader library
        const library_ptr = self.device.msgSend(
            ?*anyopaque,
            "newLibraryWithSource:options:error:",
            .{ source_str.value, @as(?*anyopaque, null), @as(?*anyopaque, null) },
        );
        if (library_ptr == null) {
            std.debug.print("Failed to compile shader library\n", .{});
            return error.ShaderCompilationFailed;
        }
        const library = objc.Object.fromId(library_ptr);

        // Get vertex and fragment functions
        const vertex_name = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{"vertex_main"});
        const fragment_name = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{"fragment_main"});

        const vertex_fn_ptr = library.msgSend(?*anyopaque, "newFunctionWithName:", .{vertex_name.value});
        const fragment_fn_ptr = library.msgSend(?*anyopaque, "newFunctionWithName:", .{fragment_name.value});

        if (vertex_fn_ptr == null or fragment_fn_ptr == null) {
            std.debug.print("Failed to get shader functions\n", .{});
            return error.ShaderFunctionNotFound;
        }
        const vertex_fn = objc.Object.fromId(vertex_fn_ptr);
        const fragment_fn = objc.Object.fromId(fragment_fn_ptr);

        // Create vertex descriptor
        const MTLVertexDescriptor = objc.getClass("MTLVertexDescriptor") orelse return error.ClassNotFound;
        const vertex_desc = MTLVertexDescriptor.msgSend(objc.Object, "vertexDescriptor", .{});

        // Position attribute (float2)
        const attributes = vertex_desc.msgSend(objc.Object, "attributes", .{});
        const attr0 = attributes.msgSend(objc.Object, "objectAtIndexedSubscript:", .{@as(u64, 0)});
        attr0.msgSend(void, "setFormat:", .{@as(u64, 29)}); // MTLVertexFormatFloat2
        attr0.msgSend(void, "setOffset:", .{@as(u64, 0)});
        attr0.msgSend(void, "setBufferIndex:", .{@as(u64, 0)});

        // Color attribute (float4)
        const attr1 = attributes.msgSend(objc.Object, "objectAtIndexedSubscript:", .{@as(u64, 1)});
        attr1.msgSend(void, "setFormat:", .{@as(u64, 31)}); // MTLVertexFormatFloat4
        attr1.msgSend(void, "setOffset:", .{@as(u64, 8)}); // After float2 (8 bytes)
        attr1.msgSend(void, "setBufferIndex:", .{@as(u64, 0)});

        // Layout
        const layouts = vertex_desc.msgSend(objc.Object, "layouts", .{});
        const layout0 = layouts.msgSend(objc.Object, "objectAtIndexedSubscript:", .{@as(u64, 0)});
        layout0.msgSend(void, "setStride:", .{@as(u64, @sizeOf(Vertex))});

        // Create pipeline descriptor
        const MTLRenderPipelineDescriptor = objc.getClass("MTLRenderPipelineDescriptor") orelse return error.ClassNotFound;
        const pipeline_desc = MTLRenderPipelineDescriptor.msgSend(objc.Object, "alloc", .{});
        const pipeline_desc_init = pipeline_desc.msgSend(objc.Object, "init", .{});

        pipeline_desc_init.msgSend(void, "setVertexFunction:", .{vertex_fn.value});
        pipeline_desc_init.msgSend(void, "setFragmentFunction:", .{fragment_fn.value});
        pipeline_desc_init.msgSend(void, "setVertexDescriptor:", .{vertex_desc.value});

        // Set MSAA sample count on pipeline
        pipeline_desc_init.msgSend(void, "setSampleCount:", .{@as(u64, self.sample_count)});

        // Set pixel format
        const color_attachments = pipeline_desc_init.msgSend(objc.Object, "colorAttachments", .{});
        const color_attachment_0 = color_attachments.msgSend(objc.Object, "objectAtIndexedSubscript:", .{@as(u64, 0)});
        color_attachment_0.msgSend(void, "setPixelFormat:", .{@as(u64, 80)}); // MTLPixelFormatBGRA8Unorm

        // Create pipeline state
        const pipeline_ptr = self.device.msgSend(
            ?*anyopaque,
            "newRenderPipelineStateWithDescriptor:error:",
            .{ pipeline_desc_init.value, @as(?*anyopaque, null) },
        );
        if (pipeline_ptr == null) {
            std.debug.print("Failed to create pipeline state\n", .{});
            return error.PipelineCreationFailed;
        }
        self.pipeline_state = objc.Object.fromId(pipeline_ptr);

        // Create vertex buffer
        const buffer_ptr = self.device.msgSend(
            ?*anyopaque,
            "newBufferWithBytes:length:options:",
            .{
                @as(*const anyopaque, @ptrCast(&triangle_vertices)),
                @as(u64, @sizeOf(@TypeOf(triangle_vertices))),
                @as(u64, 0), // MTLResourceStorageModeShared
            },
        );
        if (buffer_ptr == null) {
            std.debug.print("Failed to create vertex buffer\n", .{});
            return error.BufferCreationFailed;
        }
        self.vertex_buffer = objc.Object.fromId(buffer_ptr);

        // Release temporary objects
        library.msgSend(void, "release", .{});
        vertex_fn.msgSend(void, "release", .{});
        fragment_fn.msgSend(void, "release", .{});
    }

    pub fn deinit(self: *Self) void {
        if (self.msaa_texture) |tex| tex.msgSend(void, "release", .{});
        if (self.pipeline_state) |ps| ps.msgSend(void, "release", .{});
        if (self.vertex_buffer) |vb| vb.msgSend(void, "release", .{});
        self.command_queue.msgSend(void, "release", .{});
        self.device.msgSend(void, "release", .{});
    }

    pub fn clear(self: *Self, color: geometry.Color) void {
        self.render(color, true);
    }

    pub fn render(self: *Self, clear_color: geometry.Color, draw_triangle: bool) void {
        // Get next drawable
        const drawable_ptr = self.layer.msgSend(?*anyopaque, "nextDrawable", .{});
        if (drawable_ptr == null) {
            return;
        }
        const drawable = objc.Object.fromId(drawable_ptr);

        const texture_ptr = drawable.msgSend(?*anyopaque, "texture", .{});
        if (texture_ptr == null) return;
        const resolve_texture = objc.Object.fromId(texture_ptr);

        // Need MSAA texture to render
        const msaa_tex = self.msaa_texture orelse return;

        // Create render pass descriptor
        const MTLRenderPassDescriptor = objc.getClass("MTLRenderPassDescriptor") orelse return;
        const render_pass = MTLRenderPassDescriptor.msgSend(objc.Object, "renderPassDescriptor", .{});

        const color_attachments = render_pass.msgSend(objc.Object, "colorAttachments", .{});
        const color_attachment_0 = color_attachments.msgSend(objc.Object, "objectAtIndexedSubscript:", .{@as(u64, 0)});

        // Render to MSAA texture, resolve to drawable
        color_attachment_0.msgSend(void, "setTexture:", .{msaa_tex.value});
        color_attachment_0.msgSend(void, "setResolveTexture:", .{resolve_texture.value});
        color_attachment_0.msgSend(void, "setLoadAction:", .{@as(u64, 2)}); // MTLLoadActionClear
        color_attachment_0.msgSend(void, "setStoreAction:", .{@as(u64, 2)}); // MTLStoreActionMultisampleResolve

        const mtl_clear_color = MTLClearColor{
            .red = @floatCast(clear_color.r),
            .green = @floatCast(clear_color.g),
            .blue = @floatCast(clear_color.b),
            .alpha = @floatCast(clear_color.a),
        };
        color_attachment_0.msgSend(void, "setClearColor:", .{mtl_clear_color});

        // Create command buffer
        const command_buffer = self.command_queue.msgSend(objc.Object, "commandBuffer", .{});

        // Create render encoder
        const encoder_ptr = command_buffer.msgSend(?*anyopaque, "renderCommandEncoderWithDescriptor:", .{render_pass.value});
        if (encoder_ptr == null) return;
        const encoder = objc.Object.fromId(encoder_ptr);

        // Draw triangle if requested and pipeline is ready
        if (draw_triangle) {
            if (self.pipeline_state) |pipeline| {
                if (self.vertex_buffer) |buffer| {
                    encoder.msgSend(void, "setRenderPipelineState:", .{pipeline.value});
                    encoder.msgSend(void, "setVertexBuffer:offset:atIndex:", .{ buffer.value, @as(u64, 0), @as(u64, 0) });
                    encoder.msgSend(void, "drawPrimitives:vertexStart:vertexCount:", .{
                        @as(u64, 3), // MTLPrimitiveTypeTriangle
                        @as(u64, 0),
                        @as(u64, 3),
                    });
                }
            }
        }

        encoder.msgSend(void, "endEncoding", .{});
        command_buffer.msgSend(void, "presentDrawable:", .{drawable.value});
        command_buffer.msgSend(void, "commit", .{});
    }

    pub fn resize(self: *Self, size: geometry.Size(f64)) void {
        self.size = size;
        const drawable_size = CGSize{
            .width = size.width,
            .height = size.height,
        };
        self.layer.msgSend(void, "setDrawableSize:", .{drawable_size});

        // Recreate MSAA texture for new size
        self.createMSAATexture() catch {};
    }
};

// Metal types
const MTLClearColor = extern struct {
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
};

const CGSize = extern struct {
    width: f64,
    height: f64,
};

// Function pointer type for MTLCreateSystemDefaultDevice
const MTLCreateSystemDefaultDeviceFn = *const fn () callconv(.c) ?*anyopaque;

fn getMTLCreateSystemDefaultDevice() ?MTLCreateSystemDefaultDeviceFn {
    var lib = std.DynLib.open("/System/Library/Frameworks/Metal.framework/Metal") catch return null;
    return lib.lookup(MTLCreateSystemDefaultDeviceFn, "MTLCreateSystemDefaultDevice");
}
