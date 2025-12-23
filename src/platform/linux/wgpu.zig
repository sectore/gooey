//! wgpu-native C API bindings for Linux GPU rendering
//!
//! These bindings wrap the wgpu-native C API (wgpu.h) to provide
//! WebGPU functionality on native Linux platforms.
//!
//! wgpu-native is the Rust implementation of WebGPU exposed via C.
//! See: https://github.com/gfx-rs/wgpu-native

const std = @import("std");

// =============================================================================
// Basic Types
// =============================================================================

pub const Bool = u32;
pub const Flags = u32;

pub const FALSE: Bool = 0;
pub const TRUE: Bool = 1;

// Opaque handles (all are pointers to opaque structs in wgpu-native)
pub const Instance = *opaque {};
pub const Adapter = *opaque {};
pub const Device = *opaque {};
pub const Queue = *opaque {};
pub const Surface = *opaque {};
pub const SwapChain = *opaque {};
pub const Buffer = *opaque {};
pub const Texture = *opaque {};
pub const TextureView = *opaque {};
pub const Sampler = *opaque {};
pub const ShaderModule = *opaque {};
pub const BindGroupLayout = *opaque {};
pub const BindGroup = *opaque {};
pub const PipelineLayout = *opaque {};
pub const RenderPipeline = *opaque {};
pub const ComputePipeline = *opaque {};
pub const CommandEncoder = *opaque {};
pub const RenderPassEncoder = *opaque {};
pub const ComputePassEncoder = *opaque {};
pub const CommandBuffer = *opaque {};
pub const RenderBundleEncoder = *opaque {};
pub const RenderBundle = *opaque {};
pub const QuerySet = *opaque {};

// Optional handles (can be null)
pub const OptionalInstance = ?Instance;
pub const OptionalAdapter = ?Adapter;
pub const OptionalDevice = ?Device;
pub const OptionalSurface = ?Surface;
pub const OptionalTextureView = ?TextureView;
pub const OptionalBindGroupLayout = ?BindGroupLayout;
pub const OptionalPipelineLayout = ?PipelineLayout;

// =============================================================================
// Enums
// =============================================================================

pub const InstanceBackend = enum(u32) {
    all = 0x00000000,
    vulkan = 0x00000001,
    gl = 0x00000002,
    metal = 0x00000004,
    dx12 = 0x00000008,
    dx11 = 0x00000010,
    browser_webgpu = 0x00000020,
    primary = 0x0000002F, // Vulkan | Metal | DX12 | BrowserWebGPU
    secondary = 0x00000012, // GL | DX11
};

pub const PowerPreference = enum(u32) {
    undefined = 0,
    low_power = 1,
    high_performance = 2,
};

pub const BackendType = enum(u32) {
    undefined = 0,
    null_backend = 1,
    webgpu = 2,
    d3d11 = 3,
    d3d12 = 4,
    metal = 5,
    vulkan = 6,
    opengl = 7,
    opengles = 8,
};

pub const AdapterType = enum(u32) {
    discrete_gpu = 0,
    integrated_gpu = 1,
    cpu = 2,
    unknown = 3,
};

pub const BufferUsage = packed struct(u32) {
    map_read: bool = false,
    map_write: bool = false,
    copy_src: bool = false,
    copy_dst: bool = false,
    index: bool = false,
    vertex: bool = false,
    uniform: bool = false,
    storage: bool = false,
    indirect: bool = false,
    query_resolve: bool = false,
    _padding: u22 = 0,

    pub const none: BufferUsage = .{};
    pub const copy_dst_storage: BufferUsage = .{ .copy_dst = true, .storage = true };
    pub const copy_dst_uniform: BufferUsage = .{ .copy_dst = true, .uniform = true };
    pub const vertex_buffer: BufferUsage = .{ .copy_dst = true, .vertex = true };
    pub const index_buffer: BufferUsage = .{ .copy_dst = true, .index = true };
};

pub const TextureUsage = packed struct(u32) {
    copy_src: bool = false,
    copy_dst: bool = false,
    texture_binding: bool = false,
    storage_binding: bool = false,
    render_attachment: bool = false,
    _padding: u27 = 0,

    pub const none: TextureUsage = .{};
    pub const render_and_sample: TextureUsage = .{ .texture_binding = true, .render_attachment = true };
    pub const copy_dst_sample: TextureUsage = .{ .copy_dst = true, .texture_binding = true };
};

pub const TextureFormat = enum(u32) {
    undefined = 0,
    r8_unorm = 1,
    r8_snorm = 2,
    r8_uint = 3,
    r8_sint = 4,
    r16_uint = 5,
    r16_sint = 6,
    r16_float = 7,
    rg8_unorm = 8,
    rg8_snorm = 9,
    rg8_uint = 10,
    rg8_sint = 11,
    r32_float = 12,
    r32_uint = 13,
    r32_sint = 14,
    rg16_uint = 15,
    rg16_sint = 16,
    rg16_float = 17,
    rgba8_unorm = 18,
    rgba8_unorm_srgb = 19,
    rgba8_snorm = 20,
    rgba8_uint = 21,
    rgba8_sint = 22,
    bgra8_unorm = 23,
    bgra8_unorm_srgb = 24,
    rgb10a2_uint = 25,
    rgb10a2_unorm = 26,
    rg11b10_ufloat = 27,
    rgb9e5_ufloat = 28,
    rg32_float = 29,
    rg32_uint = 30,
    rg32_sint = 31,
    rgba16_uint = 32,
    rgba16_sint = 33,
    rgba16_float = 34,
    rgba32_float = 35,
    rgba32_uint = 36,
    rgba32_sint = 37,
    stencil8 = 38,
    depth16_unorm = 39,
    depth24_plus = 40,
    depth24_plus_stencil8 = 41,
    depth32_float = 42,
    depth32_float_stencil8 = 43,
    // Compressed formats omitted for brevity
};

pub const TextureDimension = enum(u32) {
    @"1d" = 0,
    @"2d" = 1,
    @"3d" = 2,
};

pub const TextureViewDimension = enum(u32) {
    undefined = 0,
    @"1d" = 1,
    @"2d" = 2,
    @"2d_array" = 3,
    cube = 4,
    cube_array = 5,
    @"3d" = 6,
};

pub const TextureAspect = enum(u32) {
    all = 0,
    stencil_only = 1,
    depth_only = 2,
};

pub const AddressMode = enum(u32) {
    repeat = 0,
    mirror_repeat = 1,
    clamp_to_edge = 2,
};

pub const FilterMode = enum(u32) {
    nearest = 0,
    linear = 1,
};

pub const MipmapFilterMode = enum(u32) {
    nearest = 0,
    linear = 1,
};

pub const CompareFunction = enum(u32) {
    undefined = 0,
    never = 1,
    less = 2,
    less_equal = 3,
    greater = 4,
    greater_equal = 5,
    equal = 6,
    not_equal = 7,
    always = 8,
};

pub const ShaderStage = packed struct(u32) {
    vertex: bool = false,
    fragment: bool = false,
    compute: bool = false,
    _padding: u29 = 0,

    pub const none: ShaderStage = .{};
    pub const vertex_fragment: ShaderStage = .{ .vertex = true, .fragment = true };
};

pub const BufferBindingType = enum(u32) {
    undefined = 0,
    uniform = 1,
    storage = 2,
    read_only_storage = 3,
};

pub const SamplerBindingType = enum(u32) {
    undefined = 0,
    filtering = 1,
    non_filtering = 2,
    comparison = 3,
};

pub const TextureSampleType = enum(u32) {
    undefined = 0,
    float = 1,
    unfilterable_float = 2,
    depth = 3,
    sint = 4,
    uint = 5,
};

pub const StorageTextureAccess = enum(u32) {
    undefined = 0,
    write_only = 1,
    read_only = 2,
    read_write = 3,
};

pub const VertexFormat = enum(u32) {
    undefined = 0,
    uint8x2 = 1,
    uint8x4 = 2,
    sint8x2 = 3,
    sint8x4 = 4,
    unorm8x2 = 5,
    unorm8x4 = 6,
    snorm8x2 = 7,
    snorm8x4 = 8,
    uint16x2 = 9,
    uint16x4 = 10,
    sint16x2 = 11,
    sint16x4 = 12,
    unorm16x2 = 13,
    unorm16x4 = 14,
    snorm16x2 = 15,
    snorm16x4 = 16,
    float16x2 = 17,
    float16x4 = 18,
    float32 = 19,
    float32x2 = 20,
    float32x3 = 21,
    float32x4 = 22,
    uint32 = 23,
    uint32x2 = 24,
    uint32x3 = 25,
    uint32x4 = 26,
    sint32 = 27,
    sint32x2 = 28,
    sint32x3 = 29,
    sint32x4 = 30,
};

pub const VertexStepMode = enum(u32) {
    vertex = 0,
    instance = 1,
    vertex_buffer_not_used = 2,
};

pub const PrimitiveTopology = enum(u32) {
    point_list = 0,
    line_list = 1,
    line_strip = 2,
    triangle_list = 3,
    triangle_strip = 4,
};

pub const IndexFormat = enum(u32) {
    undefined = 0,
    uint16 = 1,
    uint32 = 2,
};

pub const FrontFace = enum(u32) {
    ccw = 0,
    cw = 1,
};

pub const CullMode = enum(u32) {
    none = 0,
    front = 1,
    back = 2,
};

pub const BlendOperation = enum(u32) {
    add = 0,
    subtract = 1,
    reverse_subtract = 2,
    min = 3,
    max = 4,
};

pub const BlendFactor = enum(u32) {
    zero = 0,
    one = 1,
    src = 2,
    one_minus_src = 3,
    src_alpha = 4,
    one_minus_src_alpha = 5,
    dst = 6,
    one_minus_dst = 7,
    dst_alpha = 8,
    one_minus_dst_alpha = 9,
    src_alpha_saturated = 10,
    constant = 11,
    one_minus_constant = 12,
};

pub const ColorWriteMask = packed struct(u32) {
    red: bool = false,
    green: bool = false,
    blue: bool = false,
    alpha: bool = false,
    _padding: u28 = 0,

    pub const none: ColorWriteMask = .{};
    pub const all: ColorWriteMask = .{ .red = true, .green = true, .blue = true, .alpha = true };
};

pub const LoadOp = enum(u32) {
    undefined = 0,
    clear = 1,
    load = 2,
};

pub const StoreOp = enum(u32) {
    undefined = 0,
    store = 1,
    discard = 2,
};

pub const PresentMode = enum(u32) {
    fifo = 0,
    fifo_relaxed = 1,
    immediate = 2,
    mailbox = 3,
};

pub const CompositeAlphaMode = enum(u32) {
    auto = 0,
    opaque_mode = 1,
    premultiplied = 2,
    unpremultiplied = 3,
    inherit = 4,
};

// =============================================================================
// Structs
// =============================================================================

pub const ChainedStruct = extern struct {
    next: ?*const ChainedStruct = null,
    s_type: SType = .invalid,
};

pub const ChainedStructOut = extern struct {
    next: ?*ChainedStructOut = null,
    s_type: SType = .invalid,
};

pub const SType = enum(u32) {
    invalid = 0,
    surface_descriptor_from_metal_layer = 1,
    surface_descriptor_from_windows_hwnd = 2,
    surface_descriptor_from_xlib_window = 3,
    surface_descriptor_from_canvas_html_selector = 4,
    shader_module_spirv_descriptor = 5,
    shader_module_wgsl_descriptor = 6,
    surface_descriptor_from_wayland_surface = 8,
    surface_descriptor_from_android_native_window = 9,
    surface_descriptor_from_xcb_window = 10,
    // wgpu-native extensions
    device_extras = 0x00030001,
    required_limits_extras = 0x00030002,
    pipeline_layout_extras = 0x00030003,
    shader_module_glsl_descriptor = 0x00030004,
    supported_limits_extras = 0x00030005,
    instance_extras = 0x00030006,
    bind_group_entry_extras = 0x00030007,
    bind_group_layout_entry_extras = 0x00030008,
    query_set_descriptor_extras = 0x00030009,
    surface_configuration_extras = 0x0003000A,
};

pub const Limits = extern struct {
    max_texture_dimension_1d: u32 = 0,
    max_texture_dimension_2d: u32 = 0,
    max_texture_dimension_3d: u32 = 0,
    max_texture_array_layers: u32 = 0,
    max_bind_groups: u32 = 0,
    max_bind_groups_plus_vertex_buffers: u32 = 0,
    max_bindings_per_bind_group: u32 = 0,
    max_dynamic_uniform_buffers_per_pipeline_layout: u32 = 0,
    max_dynamic_storage_buffers_per_pipeline_layout: u32 = 0,
    max_sampled_textures_per_shader_stage: u32 = 0,
    max_samplers_per_shader_stage: u32 = 0,
    max_storage_buffers_per_shader_stage: u32 = 0,
    max_storage_textures_per_shader_stage: u32 = 0,
    max_uniform_buffers_per_shader_stage: u32 = 0,
    max_uniform_buffer_binding_size: u64 = 0,
    max_storage_buffer_binding_size: u64 = 0,
    min_uniform_buffer_offset_alignment: u32 = 0,
    min_storage_buffer_offset_alignment: u32 = 0,
    max_vertex_buffers: u32 = 0,
    max_buffer_size: u64 = 0,
    max_vertex_attributes: u32 = 0,
    max_vertex_buffer_array_stride: u32 = 0,
    max_inter_stage_shader_components: u32 = 0,
    max_inter_stage_shader_variables: u32 = 0,
    max_color_attachments: u32 = 0,
    max_color_attachment_bytes_per_sample: u32 = 0,
    max_compute_workgroup_storage_size: u32 = 0,
    max_compute_invocations_per_workgroup: u32 = 0,
    max_compute_workgroup_size_x: u32 = 0,
    max_compute_workgroup_size_y: u32 = 0,
    max_compute_workgroup_size_z: u32 = 0,
    max_compute_workgroups_per_dimension: u32 = 0,
};

pub const InstanceDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
};

pub const InstanceExtras = extern struct {
    chain: ChainedStruct = .{ .s_type = .instance_extras },
    backends: InstanceBackend = .all,
    flags: u32 = 0,
    dx12_shader_compiler: u32 = 0, // Dx12Compiler enum
    gles3_minor_version: u32 = 0, // Gles3MinorVersion enum
    dxil_path: ?[*:0]const u8 = null,
    dxc_path: ?[*:0]const u8 = null,
};

pub const RequestAdapterOptions = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    compatible_surface: OptionalSurface = null,
    power_preference: PowerPreference = .undefined,
    backend_type: BackendType = .undefined,
    force_fallback_adapter: Bool = FALSE,
};

pub const DeviceDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
    required_feature_count: usize = 0,
    required_features: ?[*]const u32 = null,
    required_limits: ?*const RequiredLimits = null,
    default_queue: QueueDescriptor = .{},
    device_lost_callback: ?*const fn (u32, ?[*:0]const u8, ?*anyopaque) callconv(.C) void = null,
    device_lost_userdata: ?*anyopaque = null,
};

pub const RequiredLimits = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    limits: Limits = .{},
};

pub const QueueDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
};

pub const SurfaceDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
};

pub const SurfaceDescriptorFromXlibWindow = extern struct {
    chain: ChainedStruct = .{ .s_type = .surface_descriptor_from_xlib_window },
    display: *anyopaque, // Display*
    window: u64, // Window (X11 Window is unsigned long)
};

pub const SurfaceDescriptorFromWaylandSurface = extern struct {
    chain: ChainedStruct = .{ .s_type = .surface_descriptor_from_wayland_surface },
    display: *anyopaque, // wl_display*
    surface: *anyopaque, // wl_surface*
};

pub const SurfaceConfiguration = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    device: Device,
    format: TextureFormat,
    usage: TextureUsage = .{ .render_attachment = true },
    view_format_count: usize = 0,
    view_formats: ?[*]const TextureFormat = null,
    alpha_mode: CompositeAlphaMode = .auto,
    width: u32,
    height: u32,
    present_mode: PresentMode = .fifo,
};

pub const SurfaceTexture = extern struct {
    texture: ?Texture = null,
    suboptimal: Bool = FALSE,
    status: SurfaceGetCurrentTextureStatus = .success,
};

pub const SurfaceGetCurrentTextureStatus = enum(u32) {
    success = 0,
    timeout = 1,
    outdated = 2,
    lost = 3,
    out_of_memory = 4,
    device_lost = 5,
};

pub const BufferDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
    usage: BufferUsage,
    size: u64,
    mapped_at_creation: Bool = FALSE,
};

pub const TextureDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
    usage: TextureUsage,
    dimension: TextureDimension = .@"2d",
    size: Extent3D,
    format: TextureFormat,
    mip_level_count: u32 = 1,
    sample_count: u32 = 1,
    view_format_count: usize = 0,
    view_formats: ?[*]const TextureFormat = null,
};

pub const Extent3D = extern struct {
    width: u32,
    height: u32 = 1,
    depth_or_array_layers: u32 = 1,
};

pub const TextureViewDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
    format: TextureFormat = .undefined,
    dimension: TextureViewDimension = .undefined,
    base_mip_level: u32 = 0,
    mip_level_count: u32 = 0xFFFFFFFF, // WGPU_MIP_LEVEL_COUNT_UNDEFINED
    base_array_layer: u32 = 0,
    array_layer_count: u32 = 0xFFFFFFFF, // WGPU_ARRAY_LAYER_COUNT_UNDEFINED
    aspect: TextureAspect = .all,
};

pub const SamplerDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
    address_mode_u: AddressMode = .clamp_to_edge,
    address_mode_v: AddressMode = .clamp_to_edge,
    address_mode_w: AddressMode = .clamp_to_edge,
    mag_filter: FilterMode = .nearest,
    min_filter: FilterMode = .nearest,
    mipmap_filter: MipmapFilterMode = .nearest,
    lod_min_clamp: f32 = 0.0,
    lod_max_clamp: f32 = 32.0,
    compare: CompareFunction = .undefined,
    max_anisotropy: u16 = 1,
};

pub const ShaderModuleDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
};

pub const ShaderModuleWGSLDescriptor = extern struct {
    chain: ChainedStruct = .{ .s_type = .shader_module_wgsl_descriptor },
    code: [*:0]const u8,
};

pub const BindGroupLayoutDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
    entry_count: usize,
    entries: [*]const BindGroupLayoutEntry,
};

pub const BindGroupLayoutEntry = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    binding: u32,
    visibility: ShaderStage,
    buffer: BufferBindingLayout = .{},
    sampler: SamplerBindingLayout = .{},
    texture: TextureBindingLayout = .{},
    storage_texture: StorageTextureBindingLayout = .{},
};

pub const BufferBindingLayout = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    binding_type: BufferBindingType = .undefined,
    has_dynamic_offset: Bool = FALSE,
    min_binding_size: u64 = 0,
};

pub const SamplerBindingLayout = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    binding_type: SamplerBindingType = .undefined,
};

pub const TextureBindingLayout = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    sample_type: TextureSampleType = .undefined,
    view_dimension: TextureViewDimension = .undefined,
    multisampled: Bool = FALSE,
};

pub const StorageTextureBindingLayout = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    access: StorageTextureAccess = .undefined,
    format: TextureFormat = .undefined,
    view_dimension: TextureViewDimension = .undefined,
};

pub const BindGroupDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
    layout: BindGroupLayout,
    entry_count: usize,
    entries: [*]const BindGroupEntry,
};

pub const BindGroupEntry = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    binding: u32,
    buffer: ?Buffer = null,
    offset: u64 = 0,
    size: u64 = 0xFFFFFFFFFFFFFFFF, // WGPU_WHOLE_SIZE
    sampler: ?Sampler = null,
    texture_view: ?TextureView = null,
};

pub const PipelineLayoutDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
    bind_group_layout_count: usize,
    bind_group_layouts: [*]const BindGroupLayout,
};

pub const RenderPipelineDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
    layout: OptionalPipelineLayout = null,
    vertex: VertexState,
    primitive: PrimitiveState = .{},
    depth_stencil: ?*const DepthStencilState = null,
    multisample: MultisampleState = .{},
    fragment: ?*const FragmentState = null,
};

pub const VertexState = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    module: ShaderModule,
    entry_point: ?[*:0]const u8 = null,
    constant_count: usize = 0,
    constants: ?[*]const ConstantEntry = null,
    buffer_count: usize = 0,
    buffers: ?[*]const VertexBufferLayout = null,
};

pub const ConstantEntry = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    key: [*:0]const u8,
    value: f64,
};

pub const VertexBufferLayout = extern struct {
    array_stride: u64,
    step_mode: VertexStepMode = .vertex,
    attribute_count: usize,
    attributes: [*]const VertexAttribute,
};

pub const VertexAttribute = extern struct {
    format: VertexFormat,
    offset: u64,
    shader_location: u32,
};

pub const PrimitiveState = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    topology: PrimitiveTopology = .triangle_list,
    strip_index_format: IndexFormat = .undefined,
    front_face: FrontFace = .ccw,
    cull_mode: CullMode = .none,
};

pub const DepthStencilState = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    format: TextureFormat,
    depth_write_enabled: Bool = FALSE,
    depth_compare: CompareFunction = .always,
    stencil_front: StencilFaceState = .{},
    stencil_back: StencilFaceState = .{},
    stencil_read_mask: u32 = 0xFFFFFFFF,
    stencil_write_mask: u32 = 0xFFFFFFFF,
    depth_bias: i32 = 0,
    depth_bias_slope_scale: f32 = 0.0,
    depth_bias_clamp: f32 = 0.0,
};

pub const StencilFaceState = extern struct {
    compare: CompareFunction = .always,
    fail_op: StencilOperation = .keep,
    depth_fail_op: StencilOperation = .keep,
    pass_op: StencilOperation = .keep,
};

pub const StencilOperation = enum(u32) {
    keep = 0,
    zero = 1,
    replace = 2,
    invert = 3,
    increment_clamp = 4,
    decrement_clamp = 5,
    increment_wrap = 6,
    decrement_wrap = 7,
};

pub const MultisampleState = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    count: u32 = 1,
    mask: u32 = 0xFFFFFFFF,
    alpha_to_coverage_enabled: Bool = FALSE,
};

pub const FragmentState = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    module: ShaderModule,
    entry_point: ?[*:0]const u8 = null,
    constant_count: usize = 0,
    constants: ?[*]const ConstantEntry = null,
    target_count: usize,
    targets: [*]const ColorTargetState,
};

pub const ColorTargetState = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    format: TextureFormat,
    blend: ?*const BlendState = null,
    write_mask: ColorWriteMask = ColorWriteMask.all,
};

pub const BlendState = extern struct {
    color: BlendComponent = .{},
    alpha: BlendComponent = .{},
};

pub const BlendComponent = extern struct {
    operation: BlendOperation = .add,
    src_factor: BlendFactor = .one,
    dst_factor: BlendFactor = .zero,
};

pub const CommandEncoderDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
};

pub const RenderPassDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
    color_attachment_count: usize,
    color_attachments: [*]const RenderPassColorAttachment,
    depth_stencil_attachment: ?*const RenderPassDepthStencilAttachment = null,
    occlusion_query_set: ?QuerySet = null,
    timestamp_writes: ?*const RenderPassTimestampWrites = null,
};

pub const RenderPassColorAttachment = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    view: ?TextureView = null,
    depth_slice: u32 = 0xFFFFFFFF, // WGPU_DEPTH_SLICE_UNDEFINED
    resolve_target: OptionalTextureView = null,
    load_op: LoadOp,
    store_op: StoreOp,
    clear_value: Color = .{},
};

pub const Color = extern struct {
    r: f64 = 0.0,
    g: f64 = 0.0,
    b: f64 = 0.0,
    a: f64 = 1.0,
};

pub const RenderPassDepthStencilAttachment = extern struct {
    view: TextureView,
    depth_load_op: LoadOp = .undefined,
    depth_store_op: StoreOp = .undefined,
    depth_clear_value: f32 = 0.0,
    depth_read_only: Bool = FALSE,
    stencil_load_op: LoadOp = .undefined,
    stencil_store_op: StoreOp = .undefined,
    stencil_clear_value: u32 = 0,
    stencil_read_only: Bool = FALSE,
};

pub const RenderPassTimestampWrites = extern struct {
    query_set: QuerySet,
    beginning_of_pass_write_index: u32 = 0xFFFFFFFF,
    end_of_pass_write_index: u32 = 0xFFFFFFFF,
};

pub const CommandBufferDescriptor = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    label: ?[*:0]const u8 = null,
};

pub const ImageCopyTexture = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    texture: Texture,
    mip_level: u32 = 0,
    origin: Origin3D = .{},
    aspect: TextureAspect = .all,
};

pub const Origin3D = extern struct {
    x: u32 = 0,
    y: u32 = 0,
    z: u32 = 0,
};

pub const TextureDataLayout = extern struct {
    next_in_chain: ?*const ChainedStruct = null,
    offset: u64 = 0,
    bytes_per_row: u32 = 0xFFFFFFFF, // WGPU_COPY_STRIDE_UNDEFINED
    rows_per_image: u32 = 0xFFFFFFFF, // WGPU_COPY_STRIDE_UNDEFINED
};

// =============================================================================
// C API Function Declarations
// =============================================================================

// Instance
pub extern "wgpu_native" fn wgpuCreateInstance(descriptor: ?*const InstanceDescriptor) OptionalInstance;
pub extern "wgpu_native" fn wgpuInstanceRelease(instance: Instance) void;
pub extern "wgpu_native" fn wgpuInstanceRequestAdapter(
    instance: Instance,
    options: ?*const RequestAdapterOptions,
    callback: *const fn (u32, ?Adapter, ?[*:0]const u8, ?*anyopaque) callconv(.C) void,
    userdata: ?*anyopaque,
) void;
pub extern "wgpu_native" fn wgpuInstanceCreateSurface(instance: Instance, descriptor: *const SurfaceDescriptor) ?Surface;

// Adapter
pub extern "wgpu_native" fn wgpuAdapterRelease(adapter: Adapter) void;
pub extern "wgpu_native" fn wgpuAdapterRequestDevice(
    adapter: Adapter,
    descriptor: ?*const DeviceDescriptor,
    callback: *const fn (u32, ?Device, ?[*:0]const u8, ?*anyopaque) callconv(.C) void,
    userdata: ?*anyopaque,
) void;
pub extern "wgpu_native" fn wgpuAdapterGetLimits(adapter: Adapter, limits: *Limits) Bool;

// Device
pub extern "wgpu_native" fn wgpuDeviceRelease(device: Device) void;
pub extern "wgpu_native" fn wgpuDeviceGetQueue(device: Device) Queue;
pub extern "wgpu_native" fn wgpuDeviceCreateBuffer(device: Device, descriptor: *const BufferDescriptor) ?Buffer;
pub extern "wgpu_native" fn wgpuDeviceCreateTexture(device: Device, descriptor: *const TextureDescriptor) ?Texture;
pub extern "wgpu_native" fn wgpuDeviceCreateSampler(device: Device, descriptor: ?*const SamplerDescriptor) ?Sampler;
pub extern "wgpu_native" fn wgpuDeviceCreateShaderModule(device: Device, descriptor: *const ShaderModuleDescriptor) ?ShaderModule;
pub extern "wgpu_native" fn wgpuDeviceCreateBindGroupLayout(device: Device, descriptor: *const BindGroupLayoutDescriptor) ?BindGroupLayout;
pub extern "wgpu_native" fn wgpuDeviceCreateBindGroup(device: Device, descriptor: *const BindGroupDescriptor) ?BindGroup;
pub extern "wgpu_native" fn wgpuDeviceCreatePipelineLayout(device: Device, descriptor: *const PipelineLayoutDescriptor) ?PipelineLayout;
pub extern "wgpu_native" fn wgpuDeviceCreateRenderPipeline(device: Device, descriptor: *const RenderPipelineDescriptor) ?RenderPipeline;
pub extern "wgpu_native" fn wgpuDeviceCreateCommandEncoder(device: Device, descriptor: ?*const CommandEncoderDescriptor) ?CommandEncoder;
pub extern "wgpu_native" fn wgpuDevicePoll(device: Device, wait: Bool, wrapped_submission_index: ?*anyopaque) Bool;

// Queue
pub extern "wgpu_native" fn wgpuQueueRelease(queue: Queue) void;
pub extern "wgpu_native" fn wgpuQueueSubmit(queue: Queue, command_count: usize, commands: [*]const CommandBuffer) void;
pub extern "wgpu_native" fn wgpuQueueWriteBuffer(queue: Queue, buffer: Buffer, buffer_offset: u64, data: [*]const u8, size: usize) void;
pub extern "wgpu_native" fn wgpuQueueWriteTexture(
    queue: Queue,
    destination: *const ImageCopyTexture,
    data: [*]const u8,
    data_size: usize,
    data_layout: *const TextureDataLayout,
    write_size: *const Extent3D,
) void;

// Surface
pub extern "wgpu_native" fn wgpuSurfaceRelease(surface: Surface) void;
pub extern "wgpu_native" fn wgpuSurfaceConfigure(surface: Surface, config: *const SurfaceConfiguration) void;
pub extern "wgpu_native" fn wgpuSurfaceUnconfigure(surface: Surface) void;
pub extern "wgpu_native" fn wgpuSurfaceGetCurrentTexture(surface: Surface, surface_texture: *SurfaceTexture) void;
pub extern "wgpu_native" fn wgpuSurfacePresent(surface: Surface) void;
pub extern "wgpu_native" fn wgpuSurfaceGetCapabilities(surface: Surface, adapter: Adapter, capabilities: *SurfaceCapabilities) void;

pub const SurfaceCapabilities = extern struct {
    next_in_chain: ?*ChainedStructOut = null,
    format_count: usize = 0,
    formats: ?[*]TextureFormat = null,
    present_mode_count: usize = 0,
    present_modes: ?[*]PresentMode = null,
    alpha_mode_count: usize = 0,
    alpha_modes: ?[*]CompositeAlphaMode = null,
};

// Buffer
pub extern "wgpu_native" fn wgpuBufferRelease(buffer: Buffer) void;
pub extern "wgpu_native" fn wgpuBufferDestroy(buffer: Buffer) void;

// Texture
pub extern "wgpu_native" fn wgpuTextureRelease(texture: Texture) void;
pub extern "wgpu_native" fn wgpuTextureDestroy(texture: Texture) void;
pub extern "wgpu_native" fn wgpuTextureCreateView(texture: Texture, descriptor: ?*const TextureViewDescriptor) ?TextureView;

// TextureView
pub extern "wgpu_native" fn wgpuTextureViewRelease(texture_view: TextureView) void;

// Sampler
pub extern "wgpu_native" fn wgpuSamplerRelease(sampler: Sampler) void;

// ShaderModule
pub extern "wgpu_native" fn wgpuShaderModuleRelease(shader_module: ShaderModule) void;

// BindGroupLayout
pub extern "wgpu_native" fn wgpuBindGroupLayoutRelease(bind_group_layout: BindGroupLayout) void;

// BindGroup
pub extern "wgpu_native" fn wgpuBindGroupRelease(bind_group: BindGroup) void;

// PipelineLayout
pub extern "wgpu_native" fn wgpuPipelineLayoutRelease(pipeline_layout: PipelineLayout) void;

// RenderPipeline
pub extern "wgpu_native" fn wgpuRenderPipelineRelease(render_pipeline: RenderPipeline) void;
pub extern "wgpu_native" fn wgpuRenderPipelineGetBindGroupLayout(render_pipeline: RenderPipeline, group_index: u32) ?BindGroupLayout;

// CommandEncoder
pub extern "wgpu_native" fn wgpuCommandEncoderRelease(command_encoder: CommandEncoder) void;
pub extern "wgpu_native" fn wgpuCommandEncoderBeginRenderPass(command_encoder: CommandEncoder, descriptor: *const RenderPassDescriptor) ?RenderPassEncoder;
pub extern "wgpu_native" fn wgpuCommandEncoderFinish(command_encoder: CommandEncoder, descriptor: ?*const CommandBufferDescriptor) ?CommandBuffer;

// RenderPassEncoder
pub extern "wgpu_native" fn wgpuRenderPassEncoderRelease(render_pass_encoder: RenderPassEncoder) void;
pub extern "wgpu_native" fn wgpuRenderPassEncoderEnd(render_pass_encoder: RenderPassEncoder) void;
pub extern "wgpu_native" fn wgpuRenderPassEncoderSetPipeline(render_pass_encoder: RenderPassEncoder, pipeline: RenderPipeline) void;
pub extern "wgpu_native" fn wgpuRenderPassEncoderSetBindGroup(
    render_pass_encoder: RenderPassEncoder,
    group_index: u32,
    group: ?BindGroup,
    dynamic_offset_count: usize,
    dynamic_offsets: ?[*]const u32,
) void;
pub extern "wgpu_native" fn wgpuRenderPassEncoderDraw(
    render_pass_encoder: RenderPassEncoder,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void;
pub extern "wgpu_native" fn wgpuRenderPassEncoderSetViewport(
    render_pass_encoder: RenderPassEncoder,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    min_depth: f32,
    max_depth: f32,
) void;
pub extern "wgpu_native" fn wgpuRenderPassEncoderSetScissorRect(
    render_pass_encoder: RenderPassEncoder,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) void;

// CommandBuffer
pub extern "wgpu_native" fn wgpuCommandBufferRelease(command_buffer: CommandBuffer) void;

// =============================================================================
// Helper Functions
// =============================================================================

/// Create a standard alpha-blending state for premultiplied alpha
pub fn alphaBlendState() BlendState {
    return .{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .one_minus_src_alpha,
        },
    };
}

/// Create WGSL shader module from source code
pub fn createWgslShaderModule(device: Device, code: [:0]const u8, label: ?[*:0]const u8) ?ShaderModule {
    var wgsl_desc = ShaderModuleWGSLDescriptor{
        .code = code.ptr,
    };
    const desc = ShaderModuleDescriptor{
        .next_in_chain = @ptrCast(&wgsl_desc),
        .label = label,
    };
    return wgpuDeviceCreateShaderModule(device, &desc);
}
