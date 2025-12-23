//! LinuxRenderer - GPU rendering for Linux via wgpu-native
//!
//! Takes a gooey Scene and renders it using wgpu-native (WebGPU).
//! This is the Linux equivalent of the Metal renderer on macOS.

const std = @import("std");
const wgpu = @import("wgpu.zig");
const unified = @import("../wgpu/unified.zig");
const scene_mod = @import("../../core/scene.zig");
const text_mod = @import("../../text/mod.zig");

const Scene = scene_mod.Scene;
const TextSystem = text_mod.TextSystem;
const Allocator = std.mem.Allocator;

// =============================================================================
// Constants
// =============================================================================

pub const MAX_PRIMITIVES: u32 = 4096;
pub const MAX_GLYPHS: u32 = 8192;

// =============================================================================
// GPU Types
// =============================================================================

pub const Uniforms = extern struct {
    viewport_width: f32,
    viewport_height: f32,
    _pad0: f32 = 0,
    _pad1: f32 = 0,
};

pub const GpuGlyph = extern struct {
    pos_x: f32 = 0,
    pos_y: f32 = 0,
    size_x: f32 = 0,
    size_y: f32 = 0,
    uv_left: f32 = 0,
    uv_top: f32 = 0,
    uv_right: f32 = 0,
    uv_bottom: f32 = 0,
    color_h: f32 = 0,
    color_s: f32 = 0,
    color_l: f32 = 1,
    color_a: f32 = 1,
    clip_x: f32 = 0,
    clip_y: f32 = 0,
    clip_width: f32 = 99999,
    clip_height: f32 = 99999,

    pub fn fromScene(g: scene_mod.GlyphInstance) GpuGlyph {
        return .{
            .pos_x = g.pos_x,
            .pos_y = g.pos_y,
            .size_x = g.size_x,
            .size_y = g.size_y,
            .uv_left = g.uv_left,
            .uv_top = g.uv_top,
            .uv_right = g.uv_right,
            .uv_bottom = g.uv_bottom,
            .color_h = g.color.h,
            .color_s = g.color.s,
            .color_l = g.color.l,
            .color_a = g.color.a,
            .clip_x = g.clip_x,
            .clip_y = g.clip_y,
            .clip_width = g.clip_width,
            .clip_height = g.clip_height,
        };
    }
};

// =============================================================================
// LinuxRenderer
// =============================================================================

pub const LinuxRenderer = struct {
    allocator: Allocator,

    // Core wgpu objects
    instance: ?wgpu.Instance = null,
    adapter: ?wgpu.Adapter = null,
    device: ?wgpu.Device = null,
    queue: ?wgpu.Queue = null,
    surface: ?wgpu.Surface = null,

    // Surface configuration
    surface_format: wgpu.TextureFormat = .bgra8_unorm,
    surface_width: u32 = 0,
    surface_height: u32 = 0,

    // Pipelines
    pipeline: ?wgpu.RenderPipeline = null,
    text_pipeline: ?wgpu.RenderPipeline = null,

    // Buffers
    primitive_buffer: ?wgpu.Buffer = null,
    uniform_buffer: ?wgpu.Buffer = null,
    glyph_buffer: ?wgpu.Buffer = null,

    // Bind groups
    bind_group_layout: ?wgpu.BindGroupLayout = null,
    bind_group: ?wgpu.BindGroup = null,
    text_bind_group_layout: ?wgpu.BindGroupLayout = null,
    text_bind_group: ?wgpu.BindGroup = null,

    // Text rendering
    atlas_texture: ?wgpu.Texture = null,
    atlas_texture_view: ?wgpu.TextureView = null,
    sampler: ?wgpu.Sampler = null,
    atlas_generation: u32 = 0,

    // CPU-side buffers
    primitives: [MAX_PRIMITIVES]unified.Primitive = undefined,
    gpu_glyphs: [MAX_GLYPHS]GpuGlyph = undefined,

    initialized: bool = false,

    const Self = @This();

    // Embedded shaders
    const unified_shader = @embedFile("unified_wgsl");
    const text_shader = @embedFile("text_wgsl");

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        // Release all wgpu resources in reverse order
        if (self.text_bind_group) |bg| wgpu.wgpuBindGroupRelease(bg);
        if (self.bind_group) |bg| wgpu.wgpuBindGroupRelease(bg);
        if (self.text_bind_group_layout) |bgl| wgpu.wgpuBindGroupLayoutRelease(bgl);
        if (self.bind_group_layout) |bgl| wgpu.wgpuBindGroupLayoutRelease(bgl);

        if (self.text_pipeline) |p| wgpu.wgpuRenderPipelineRelease(p);
        if (self.pipeline) |p| wgpu.wgpuRenderPipelineRelease(p);

        if (self.atlas_texture_view) |tv| wgpu.wgpuTextureViewRelease(tv);
        if (self.atlas_texture) |t| {
            wgpu.wgpuTextureDestroy(t);
            wgpu.wgpuTextureRelease(t);
        }
        if (self.sampler) |s| wgpu.wgpuSamplerRelease(s);

        if (self.glyph_buffer) |b| {
            wgpu.wgpuBufferDestroy(b);
            wgpu.wgpuBufferRelease(b);
        }
        if (self.uniform_buffer) |b| {
            wgpu.wgpuBufferDestroy(b);
            wgpu.wgpuBufferRelease(b);
        }
        if (self.primitive_buffer) |b| {
            wgpu.wgpuBufferDestroy(b);
            wgpu.wgpuBufferRelease(b);
        }

        if (self.surface) |s| wgpu.wgpuSurfaceRelease(s);
        if (self.queue) |q| wgpu.wgpuQueueRelease(q);
        if (self.device) |d| wgpu.wgpuDeviceRelease(d);
        if (self.adapter) |a| wgpu.wgpuAdapterRelease(a);
        if (self.instance) |i| wgpu.wgpuInstanceRelease(i);

        self.initialized = false;
    }

    /// Initialize the renderer with a Wayland surface
    pub fn initWithWaylandSurface(
        self: *Self,
        wl_display: *anyopaque,
        wl_surface: *anyopaque,
        width: u32,
        height: u32,
    ) !void {
        // Create wgpu instance (prefer Vulkan on Linux)
        var instance_extras = wgpu.InstanceExtras{
            .backends = .vulkan,
        };
        const instance_desc = wgpu.InstanceDescriptor{
            .next_in_chain = @ptrCast(&instance_extras),
        };
        self.instance = wgpu.wgpuCreateInstance(&instance_desc) orelse {
            return error.FailedToCreateInstance;
        };

        // Create Wayland surface
        var wayland_surface_desc = wgpu.SurfaceDescriptorFromWaylandSurface{
            .display = wl_display,
            .surface = wl_surface,
        };
        const surface_desc = wgpu.SurfaceDescriptor{
            .next_in_chain = @ptrCast(&wayland_surface_desc),
        };
        self.surface = wgpu.wgpuInstanceCreateSurface(self.instance.?, &surface_desc) orelse {
            return error.FailedToCreateSurface;
        };

        // Request adapter
        try self.requestAdapter();

        // Request device
        try self.requestDevice();

        // Get queue
        self.queue = wgpu.wgpuDeviceGetQueue(self.device.?);

        // Configure surface
        self.surface_width = width;
        self.surface_height = height;
        try self.configureSurface();

        // Create pipelines and buffers
        try self.createResources();

        self.initialized = true;
    }

    fn requestAdapter(self: *Self) !void {
        const AdapterCallback = struct {
            adapter: ?wgpu.Adapter = null,
            ready: bool = false,

            fn callback(status: u32, adapter: ?wgpu.Adapter, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
                _ = message;
                const ctx: *@This() = @ptrCast(@alignCast(userdata));
                if (status == 0) { // WGPURequestAdapterStatus_Success
                    ctx.adapter = adapter;
                }
                ctx.ready = true;
            }
        };

        var ctx = AdapterCallback{};
        const options = wgpu.RequestAdapterOptions{
            .compatible_surface = self.surface,
            .power_preference = .high_performance,
        };
        wgpu.wgpuInstanceRequestAdapter(self.instance.?, &options, AdapterCallback.callback, &ctx);

        // Poll until ready (synchronous wait)
        while (!ctx.ready) {
            // In a real async implementation, we'd integrate with the event loop
            std.time.sleep(1_000_000); // 1ms
        }

        self.adapter = ctx.adapter orelse return error.FailedToGetAdapter;
    }

    fn requestDevice(self: *Self) !void {
        const DeviceCallback = struct {
            device: ?wgpu.Device = null,
            ready: bool = false,

            fn callback(status: u32, device: ?wgpu.Device, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
                _ = message;
                const ctx: *@This() = @ptrCast(@alignCast(userdata));
                if (status == 0) { // WGPURequestDeviceStatus_Success
                    ctx.device = device;
                }
                ctx.ready = true;
            }
        };

        var ctx = DeviceCallback{};
        wgpu.wgpuAdapterRequestDevice(self.adapter.?, null, DeviceCallback.callback, &ctx);

        while (!ctx.ready) {
            std.time.sleep(1_000_000);
        }

        self.device = ctx.device orelse return error.FailedToGetDevice;
    }

    fn configureSurface(self: *Self) !void {
        const config = wgpu.SurfaceConfiguration{
            .device = self.device.?,
            .format = self.surface_format,
            .usage = .{ .render_attachment = true },
            .width = self.surface_width,
            .height = self.surface_height,
            .present_mode = .fifo, // VSync
            .alpha_mode = .opaque_mode,
        };
        wgpu.wgpuSurfaceConfigure(self.surface.?, &config);
    }

    fn createResources(self: *Self) !void {
        const device = self.device.?;

        // Create shader modules
        const unified_module = wgpu.createWgslShaderModule(device, unified_shader, "unified") orelse {
            return error.FailedToCreateShader;
        };
        defer wgpu.wgpuShaderModuleRelease(unified_module);

        const text_module = wgpu.createWgslShaderModule(device, text_shader, "text") orelse {
            return error.FailedToCreateShader;
        };
        defer wgpu.wgpuShaderModuleRelease(text_module);

        // Create buffers
        self.primitive_buffer = wgpu.wgpuDeviceCreateBuffer(device, &.{
            .label = "primitives",
            .usage = .copy_dst_storage,
            .size = @sizeOf(unified.Primitive) * MAX_PRIMITIVES,
        }) orelse return error.FailedToCreateBuffer;

        self.uniform_buffer = wgpu.wgpuDeviceCreateBuffer(device, &.{
            .label = "uniforms",
            .usage = .copy_dst_uniform,
            .size = @sizeOf(Uniforms),
        }) orelse return error.FailedToCreateBuffer;

        self.glyph_buffer = wgpu.wgpuDeviceCreateBuffer(device, &.{
            .label = "glyphs",
            .usage = .copy_dst_storage,
            .size = @sizeOf(GpuGlyph) * MAX_GLYPHS,
        }) orelse return error.FailedToCreateBuffer;

        // Create sampler
        self.sampler = wgpu.wgpuDeviceCreateSampler(device, &.{
            .label = "atlas_sampler",
            .mag_filter = .linear,
            .min_filter = .linear,
        }) orelse return error.FailedToCreateSampler;

        // Create bind group layout for unified pipeline
        const bgl_entries = [_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = .vertex_fragment,
                .buffer = .{ .binding_type = .read_only_storage },
            },
            .{
                .binding = 1,
                .visibility = .vertex_fragment,
                .buffer = .{ .binding_type = .uniform },
            },
        };
        self.bind_group_layout = wgpu.wgpuDeviceCreateBindGroupLayout(device, &.{
            .label = "unified_bgl",
            .entry_count = bgl_entries.len,
            .entries = &bgl_entries,
        }) orelse return error.FailedToCreateBindGroupLayout;

        // Create bind group
        const bg_entries = [_]wgpu.BindGroupEntry{
            .{
                .binding = 0,
                .buffer = self.primitive_buffer,
                .size = @sizeOf(unified.Primitive) * MAX_PRIMITIVES,
            },
            .{
                .binding = 1,
                .buffer = self.uniform_buffer,
                .size = @sizeOf(Uniforms),
            },
        };
        self.bind_group = wgpu.wgpuDeviceCreateBindGroup(device, &.{
            .label = "unified_bg",
            .layout = self.bind_group_layout.?,
            .entry_count = bg_entries.len,
            .entries = &bg_entries,
        }) orelse return error.FailedToCreateBindGroup;

        // Create pipeline layout
        const layouts = [_]wgpu.BindGroupLayout{self.bind_group_layout.?};
        const pipeline_layout = wgpu.wgpuDeviceCreatePipelineLayout(device, &.{
            .label = "unified_layout",
            .bind_group_layout_count = 1,
            .bind_group_layouts = &layouts,
        }) orelse return error.FailedToCreatePipelineLayout;
        defer wgpu.wgpuPipelineLayoutRelease(pipeline_layout);

        // Create unified render pipeline
        const blend_state = wgpu.alphaBlendState();
        const color_targets = [_]wgpu.ColorTargetState{
            .{
                .format = self.surface_format,
                .blend = &blend_state,
                .write_mask = wgpu.ColorWriteMask.all,
            },
        };
        const fragment_state = wgpu.FragmentState{
            .module = unified_module,
            .entry_point = "fs_main",
            .target_count = 1,
            .targets = &color_targets,
        };

        self.pipeline = wgpu.wgpuDeviceCreateRenderPipeline(device, &.{
            .label = "unified_pipeline",
            .layout = pipeline_layout,
            .vertex = .{
                .module = unified_module,
                .entry_point = "vs_main",
            },
            .fragment = &fragment_state,
            .primitive = .{
                .topology = .triangle_list,
            },
        }) orelse return error.FailedToCreatePipeline;

        // Text pipeline will be created when atlas is uploaded
    }

    /// Create text pipeline and bind group (called after atlas is ready)
    fn createTextPipeline(self: *Self) !void {
        const device = self.device.?;

        const text_module = wgpu.createWgslShaderModule(device, text_shader, "text") orelse {
            return error.FailedToCreateShader;
        };
        defer wgpu.wgpuShaderModuleRelease(text_module);

        // Text bind group layout
        const text_bgl_entries = [_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = .vertex_fragment,
                .buffer = .{ .binding_type = .read_only_storage },
            },
            .{
                .binding = 1,
                .visibility = .vertex_fragment,
                .buffer = .{ .binding_type = .uniform },
            },
            .{
                .binding = 2,
                .visibility = .{ .fragment = true },
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 3,
                .visibility = .{ .fragment = true },
                .sampler = .{ .binding_type = .filtering },
            },
        };
        self.text_bind_group_layout = wgpu.wgpuDeviceCreateBindGroupLayout(device, &.{
            .label = "text_bgl",
            .entry_count = text_bgl_entries.len,
            .entries = &text_bgl_entries,
        }) orelse return error.FailedToCreateBindGroupLayout;

        // Create text bind group
        try self.updateTextBindGroup();

        // Pipeline layout
        const layouts = [_]wgpu.BindGroupLayout{self.text_bind_group_layout.?};
        const text_layout = wgpu.wgpuDeviceCreatePipelineLayout(device, &.{
            .label = "text_layout",
            .bind_group_layout_count = 1,
            .bind_group_layouts = &layouts,
        }) orelse return error.FailedToCreatePipelineLayout;
        defer wgpu.wgpuPipelineLayoutRelease(text_layout);

        // Text pipeline
        const blend_state = wgpu.alphaBlendState();
        const color_targets = [_]wgpu.ColorTargetState{
            .{
                .format = self.surface_format,
                .blend = &blend_state,
                .write_mask = wgpu.ColorWriteMask.all,
            },
        };
        const fragment_state = wgpu.FragmentState{
            .module = text_module,
            .entry_point = "fs_main",
            .target_count = 1,
            .targets = &color_targets,
        };

        self.text_pipeline = wgpu.wgpuDeviceCreateRenderPipeline(device, &.{
            .label = "text_pipeline",
            .layout = text_layout,
            .vertex = .{
                .module = text_module,
                .entry_point = "vs_main",
            },
            .fragment = &fragment_state,
            .primitive = .{
                .topology = .triangle_list,
            },
        }) orelse return error.FailedToCreatePipeline;
    }

    fn updateTextBindGroup(self: *Self) !void {
        if (self.text_bind_group) |bg| {
            wgpu.wgpuBindGroupRelease(bg);
        }

        const entries = [_]wgpu.BindGroupEntry{
            .{
                .binding = 0,
                .buffer = self.glyph_buffer,
                .size = @sizeOf(GpuGlyph) * MAX_GLYPHS,
            },
            .{
                .binding = 1,
                .buffer = self.uniform_buffer,
                .size = @sizeOf(Uniforms),
            },
            .{
                .binding = 2,
                .texture_view = self.atlas_texture_view,
            },
            .{
                .binding = 3,
                .sampler = self.sampler,
            },
        };

        self.text_bind_group = wgpu.wgpuDeviceCreateBindGroup(self.device.?, &.{
            .label = "text_bg",
            .layout = self.text_bind_group_layout.?,
            .entry_count = entries.len,
            .entries = &entries,
        }) orelse return error.FailedToCreateBindGroup;
    }

    /// Upload the text atlas texture
    pub fn uploadAtlas(self: *Self, text_system: *TextSystem) !void {
        const atlas = text_system.getAtlas();
        const pixels = atlas.getData();
        const size = atlas.size;

        // Create texture if needed
        if (self.atlas_texture == null) {
            self.atlas_texture = wgpu.wgpuDeviceCreateTexture(self.device.?, &.{
                .label = "atlas",
                .usage = .copy_dst_sample,
                .dimension = .@"2d",
                .size = .{ .width = size, .height = size },
                .format = .r8_unorm,
            }) orelse return error.FailedToCreateTexture;

            self.atlas_texture_view = wgpu.wgpuTextureCreateView(self.atlas_texture.?, null) orelse return error.FailedToCreateTextureView;

            // Create text pipeline now that we have the texture
            try self.createTextPipeline();
        }

        // Upload texture data
        const dest = wgpu.ImageCopyTexture{
            .texture = self.atlas_texture.?,
        };
        const layout = wgpu.TextureDataLayout{
            .bytes_per_row = size,
            .rows_per_image = size,
        };
        const extent = wgpu.Extent3D{
            .width = size,
            .height = size,
        };
        wgpu.wgpuQueueWriteTexture(self.queue.?, &dest, pixels.ptr, pixels.len, &layout, &extent);

        self.atlas_generation = atlas.generation;
    }

    /// Sync atlas if generation changed
    pub fn syncAtlas(self: *Self, text_system: *TextSystem) void {
        const atlas = text_system.getAtlas();
        if (atlas.generation == self.atlas_generation) return;

        if (self.atlas_texture != null) {
            const pixels = atlas.getData();
            const size = atlas.size;
            const dest = wgpu.ImageCopyTexture{
                .texture = self.atlas_texture.?,
            };
            const layout = wgpu.TextureDataLayout{
                .bytes_per_row = size,
                .rows_per_image = size,
            };
            const extent = wgpu.Extent3D{
                .width = size,
                .height = size,
            };
            wgpu.wgpuQueueWriteTexture(self.queue.?, &dest, pixels.ptr, pixels.len, &layout, &extent);
            self.atlas_generation = atlas.generation;
        }
    }

    /// Resize the surface
    pub fn resize(self: *Self, width: u32, height: u32) void {
        if (width == 0 or height == 0) return;
        if (width == self.surface_width and height == self.surface_height) return;

        self.surface_width = width;
        self.surface_height = height;
        self.configureSurface() catch {};
    }

    /// Render a scene
    pub fn render(
        self: *Self,
        scene: *Scene,
        viewport_width: f32,
        viewport_height: f32,
        clear_r: f32,
        clear_g: f32,
        clear_b: f32,
        clear_a: f32,
    ) void {
        if (!self.initialized) return;

        // Get current surface texture
        var surface_texture: wgpu.SurfaceTexture = .{};
        wgpu.wgpuSurfaceGetCurrentTexture(self.surface.?, &surface_texture);

        if (surface_texture.status != .success) {
            // Handle resize or lost surface
            return;
        }

        const texture = surface_texture.texture orelse return;
        const view = wgpu.wgpuTextureCreateView(texture, null) orelse return;
        defer wgpu.wgpuTextureViewRelease(view);

        // Convert scene to primitives
        const prim_count = unified.convertScene(scene, &self.primitives);

        // Convert glyphs
        var glyph_count: u32 = 0;
        for (scene.getGlyphs()) |g| {
            if (glyph_count >= MAX_GLYPHS) break;
            self.gpu_glyphs[glyph_count] = GpuGlyph.fromScene(g);
            glyph_count += 1;
        }

        // Upload uniforms
        const uniforms = Uniforms{
            .viewport_width = viewport_width,
            .viewport_height = viewport_height,
        };
        wgpu.wgpuQueueWriteBuffer(self.queue.?, self.uniform_buffer.?, 0, std.mem.asBytes(&uniforms), @sizeOf(Uniforms));

        // Upload primitives
        if (prim_count > 0) {
            const prim_data = std.mem.sliceAsBytes(self.primitives[0..prim_count]);
            wgpu.wgpuQueueWriteBuffer(self.queue.?, self.primitive_buffer.?, 0, prim_data.ptr, prim_data.len);
        }

        // Upload glyphs
        if (glyph_count > 0) {
            const glyph_data = std.mem.sliceAsBytes(self.gpu_glyphs[0..glyph_count]);
            wgpu.wgpuQueueWriteBuffer(self.queue.?, self.glyph_buffer.?, 0, glyph_data.ptr, glyph_data.len);
        }

        // Create command encoder
        const encoder = wgpu.wgpuDeviceCreateCommandEncoder(self.device.?, null) orelse return;
        defer wgpu.wgpuCommandEncoderRelease(encoder);

        // Begin render pass
        const color_attachments = [_]wgpu.RenderPassColorAttachment{
            .{
                .view = view,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .r = clear_r, .g = clear_g, .b = clear_b, .a = clear_a },
            },
        };
        const render_pass = wgpu.wgpuCommandEncoderBeginRenderPass(encoder, &.{
            .color_attachment_count = 1,
            .color_attachments = &color_attachments,
        }) orelse return;

        // Draw primitives
        if (prim_count > 0) {
            wgpu.wgpuRenderPassEncoderSetPipeline(render_pass, self.pipeline.?);
            wgpu.wgpuRenderPassEncoderSetBindGroup(render_pass, 0, self.bind_group, 0, null);
            wgpu.wgpuRenderPassEncoderDraw(render_pass, 6, prim_count, 0, 0);
        }

        // Draw text
        if (glyph_count > 0 and self.text_pipeline != null and self.text_bind_group != null) {
            wgpu.wgpuRenderPassEncoderSetPipeline(render_pass, self.text_pipeline.?);
            wgpu.wgpuRenderPassEncoderSetBindGroup(render_pass, 0, self.text_bind_group, 0, null);
            wgpu.wgpuRenderPassEncoderDraw(render_pass, 6, glyph_count, 0, 0);
        }

        // End render pass
        wgpu.wgpuRenderPassEncoderEnd(render_pass);
        wgpu.wgpuRenderPassEncoderRelease(render_pass);

        // Submit
        const command_buffer = wgpu.wgpuCommandEncoderFinish(encoder, null) orelse return;
        defer wgpu.wgpuCommandBufferRelease(command_buffer);

        const commands = [_]wgpu.CommandBuffer{command_buffer};
        wgpu.wgpuQueueSubmit(self.queue.?, 1, &commands);

        // Present
        wgpu.wgpuSurfacePresent(self.surface.?);
    }
};
