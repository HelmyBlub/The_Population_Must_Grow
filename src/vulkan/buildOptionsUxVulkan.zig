const std = @import("std");
const vk = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", "1");
    @cInclude("vulkan.h");
});
const main = @import("../main.zig");
const paintVulkanZig = @import("paintVulkan.zig");
const fontVulkanZig = @import("fontVulkan.zig");
const imageZig = @import("../image.zig");
const mapZig = @import("../map.zig");
const windowSdlZig = @import("../windowSdl.zig");

pub const VkBuildOptionsUx = struct {
    triangles: struct {
        vertexBuffer: vk.VkBuffer = undefined,
        vertexBufferMemory: vk.VkDeviceMemory = undefined,
        vertices: []paintVulkanZig.ColoredVertex = undefined,
        verticeCount: usize = 0,
    } = undefined,
    lines: struct {
        vertexBuffer: vk.VkBuffer = undefined,
        vertexBufferMemory: vk.VkDeviceMemory = undefined,
        vertices: []paintVulkanZig.ColoredVertex = undefined,
        verticeCount: usize = 0,
    } = undefined,
    sprites: struct {
        vertexBuffer: vk.VkBuffer = undefined,
        vertexBufferMemory: vk.VkDeviceMemory = undefined,
        vertices: []paintVulkanZig.SpriteVertex = undefined,
        verticeCount: usize = 0,
    } = undefined,
    font: struct {
        vertexBuffer: vk.VkBuffer = undefined,
        vertexBufferMemory: vk.VkDeviceMemory = undefined,
        vertices: []fontVulkanZig.FontVertex = undefined,
        verticeCount: usize = 0,
    } = undefined,
    const UX_RECTANGLES = 10;
    pub const MAX_VERTICES_TRIANGLES = 6 * UX_RECTANGLES;
    pub const MAX_VERTICES_LINES = 8 * UX_RECTANGLES;
    pub const MAX_VERTICES_SPRITES = UX_RECTANGLES;
    pub const MAX_VERTICES_FONT = UX_RECTANGLES;
};

pub fn init(state: *main.ChatSimState) !void {
    try createVertexBuffers(&state.vkState, state.allocator);
    try createGraphicsPipeline(&state.vkState, state.allocator);
    try setupVertices(state);
}

pub fn destroy(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) void {
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.buildOptionsUx.lines.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.buildOptionsUx.sprites.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.buildOptionsUx.font.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.buildOptionsUx.lines.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.buildOptionsUx.sprites.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.buildOptionsUx.font.vertexBufferMemory, null);
    allocator.free(vkState.buildOptionsUx.triangles.vertices);
    allocator.free(vkState.buildOptionsUx.lines.vertices);
    allocator.free(vkState.buildOptionsUx.sprites.vertices);
    allocator.free(vkState.buildOptionsUx.font.vertices);
}

fn createVertexBuffers(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    vkState.buildOptionsUx.triangles.vertices = try allocator.alloc(paintVulkanZig.ColoredVertex, VkBuildOptionsUx.MAX_VERTICES_TRIANGLES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.ColoredVertex) * VkBuildOptionsUx.MAX_VERTICES_TRIANGLES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.buildOptionsUx.triangles.vertexBuffer,
        &vkState.buildOptionsUx.triangles.vertexBufferMemory,
        vkState,
    );
    vkState.buildOptionsUx.lines.vertices = try allocator.alloc(paintVulkanZig.ColoredVertex, VkBuildOptionsUx.MAX_VERTICES_LINES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.ColoredVertex) * VkBuildOptionsUx.MAX_VERTICES_LINES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.buildOptionsUx.lines.vertexBuffer,
        &vkState.buildOptionsUx.lines.vertexBufferMemory,
        vkState,
    );
    vkState.buildOptionsUx.sprites.vertices = try allocator.alloc(paintVulkanZig.SpriteVertex, VkBuildOptionsUx.MAX_VERTICES_SPRITES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.SpriteVertex) * VkBuildOptionsUx.MAX_VERTICES_SPRITES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.buildOptionsUx.sprites.vertexBuffer,
        &vkState.buildOptionsUx.sprites.vertexBufferMemory,
        vkState,
    );

    vkState.buildOptionsUx.font.vertices = try allocator.alloc(fontVulkanZig.FontVertex, VkBuildOptionsUx.MAX_VERTICES_FONT);
    try paintVulkanZig.createBuffer(
        @sizeOf(fontVulkanZig.FontVertex) * VkBuildOptionsUx.MAX_VERTICES_FONT,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.buildOptionsUx.font.vertexBuffer,
        &vkState.buildOptionsUx.font.vertexBufferMemory,
        vkState,
    );

    std.debug.print("buildOptionsUx createVertexBuffer finished\n", .{});
}

pub fn setupVertices(state: *main.ChatSimState) !void {
    const vulkanRectanlge = mapZig.MapRectangle{
        .pos = .{ .x = 0, .y = 0.85 },
        .width = 0.05,
        .height = 0.1,
    };
    const fillColor: [3]f32 = .{ 0.25, 0.25, 0.25 };
    const borderColor: [3]f32 = .{ 0, 0, 0 };
    const triangles = &state.vkState.buildOptionsUx.triangles;
    triangles.verticeCount = 6;
    triangles.vertices[0] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y }, .color = fillColor };
    triangles.vertices[1] = .{ .pos = .{ vulkanRectanlge.pos.x + vulkanRectanlge.width, vulkanRectanlge.pos.y }, .color = fillColor };
    triangles.vertices[2] = .{ .pos = .{ vulkanRectanlge.pos.x + vulkanRectanlge.width, vulkanRectanlge.pos.y + vulkanRectanlge.height }, .color = fillColor };
    triangles.vertices[3] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y }, .color = fillColor };
    triangles.vertices[4] = .{ .pos = .{ vulkanRectanlge.pos.x + vulkanRectanlge.width, vulkanRectanlge.pos.y + vulkanRectanlge.height }, .color = fillColor };
    triangles.vertices[5] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y + vulkanRectanlge.height }, .color = fillColor };

    const lines = &state.vkState.buildOptionsUx.lines;
    lines.verticeCount = 8;
    lines.vertices[0] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y }, .color = borderColor };
    lines.vertices[1] = .{ .pos = .{ vulkanRectanlge.pos.x + vulkanRectanlge.width, vulkanRectanlge.pos.y }, .color = borderColor };
    lines.vertices[2] = .{ .pos = .{ vulkanRectanlge.pos.x + vulkanRectanlge.width, vulkanRectanlge.pos.y }, .color = borderColor };
    lines.vertices[3] = .{ .pos = .{ vulkanRectanlge.pos.x + vulkanRectanlge.width, vulkanRectanlge.pos.y + vulkanRectanlge.height }, .color = borderColor };
    lines.vertices[4] = .{ .pos = .{ vulkanRectanlge.pos.x + vulkanRectanlge.width, vulkanRectanlge.pos.y + vulkanRectanlge.height }, .color = borderColor };
    lines.vertices[5] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y + vulkanRectanlge.height }, .color = borderColor };
    lines.vertices[6] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y + vulkanRectanlge.height }, .color = borderColor };
    lines.vertices[7] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y }, .color = borderColor };

    const sprites = &state.vkState.buildOptionsUx.sprites;
    sprites.verticeCount = 1;
    sprites.vertices[0] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y }, .imageIndex = imageZig.IMAGE_HOUSE, .width = vulkanRectanlge.width, .height = vulkanRectanlge.height };

    const font = &state.vkState.buildOptionsUx.font;
    font.verticeCount = 1;
    font.vertices[0] = fontVulkanZig.getCharFontVertex('1', vulkanRectanlge.pos, 16);
    try setupVertexDataForGPU(&state.vkState);
}

fn setupVertexDataForGPU(vkState: *paintVulkanZig.Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.buildOptionsUx.triangles.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    var gpu_vertices: [*]paintVulkanZig.ColoredVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.buildOptionsUx.triangles.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.buildOptionsUx.lines.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.buildOptionsUx.lines.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    gpu_vertices = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.buildOptionsUx.lines.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.buildOptionsUx.lines.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.buildOptionsUx.sprites.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.SpriteVertex) * vkState.buildOptionsUx.sprites.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpuVerticesSprite: [*]paintVulkanZig.SpriteVertex = @ptrCast(@alignCast(data));
    @memcpy(gpuVerticesSprite, vkState.buildOptionsUx.sprites.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.buildOptionsUx.sprites.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.buildOptionsUx.font.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.SpriteVertex) * vkState.buildOptionsUx.font.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpuVerticesFont: [*]fontVulkanZig.FontVertex = @ptrCast(@alignCast(data));
    @memcpy(gpuVerticesFont, vkState.buildOptionsUx.font.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.buildOptionsUx.font.vertexBufferMemory);
}

pub fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.ChatSimState) !void {
    if (state.vkState.buildOptionsUx.triangles.verticeCount <= 0) return;
    const vkState = &state.vkState;
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.triangleGraphicsPipeline);
    var vertexBuffers: [1]vk.VkBuffer = .{vkState.buildOptionsUx.triangles.vertexBuffer};
    var offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.buildOptionsUx.triangles.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.rectangle.graphicsPipeline);
    vertexBuffers = .{vkState.buildOptionsUx.lines.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.buildOptionsUx.lines.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.spriteGraphicsPipeline);
    vertexBuffers = .{vkState.buildOptionsUx.sprites.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.buildOptionsUx.sprites.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.font.graphicsPipeline);
    vertexBuffers = .{vkState.buildOptionsUx.font.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.buildOptionsUx.font.verticeCount), 1, 0, 0);
}

fn createGraphicsPipeline(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    const vertShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/spriteVert.spv", allocator);
    defer allocator.free(vertShaderCode);
    const geomShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/spriteGeom.spv", allocator);
    defer allocator.free(geomShaderCode);
    const fragShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/imageFrag.spv", allocator);
    defer allocator.free(fragShaderCode);
    const vertShaderModule = try paintVulkanZig.createShaderModule(vertShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, vertShaderModule, null);
    const geomShaderModule = try paintVulkanZig.createShaderModule(geomShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, geomShaderModule, null);
    const fragShaderModule = try paintVulkanZig.createShaderModule(fragShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, fragShaderModule, null);

    const vertShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertShaderModule,
        .pName = "main",
    };

    const geomShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_GEOMETRY_BIT,
        .module = geomShaderModule,
        .pName = "main",
    };

    const fragShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragShaderModule,
        .pName = "main",
    };

    const shaderStages = [_]vk.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo, geomShaderStageInfo };
    const bindingDescription = paintVulkanZig.SpriteVertex.getBindingDescription();
    const attributeDescriptions = paintVulkanZig.SpriteVertex.getAttributeDescriptions();
    var vertexInputInfo = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &bindingDescription,
        .vertexAttributeDescriptionCount = attributeDescriptions.len,
        .pVertexAttributeDescriptions = &attributeDescriptions,
    };

    var inputAssembly = vk.VkPipelineInputAssemblyStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
        .primitiveRestartEnable = vk.VK_FALSE,
    };

    var viewportState = vk.VkPipelineViewportStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = null,
        .scissorCount = 1,
        .pScissors = null,
    };

    var rasterizer = vk.VkPipelineRasterizationStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = vk.VK_FALSE,
        .rasterizerDiscardEnable = vk.VK_FALSE,
        .polygonMode = vk.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = vk.VK_CULL_MODE_BACK_BIT,
        .frontFace = vk.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = vk.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
    };

    var multisampling = vk.VkPipelineMultisampleStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = vk.VK_FALSE,
        .rasterizationSamples = vkState.msaaSamples,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = vk.VK_FALSE,
        .alphaToOneEnable = vk.VK_FALSE,
    };

    var colorBlendAttachment = vk.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = vk.VK_TRUE,
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
    };

    var colorBlending = vk.VkPipelineColorBlendStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = vk.VK_FALSE,
        .logicOp = vk.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &colorBlendAttachment,
        .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    const dynamicStates = [_]vk.VkDynamicState{
        vk.VK_DYNAMIC_STATE_VIEWPORT,
        vk.VK_DYNAMIC_STATE_SCISSOR,
    };

    var dynamicState = vk.VkPipelineDynamicStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamicStates.len,
        .pDynamicStates = &dynamicStates,
    };

    var pipelineInfo = vk.VkGraphicsPipelineCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = shaderStages.len,
        .pStages = &shaderStages,
        .pVertexInputState = &vertexInputInfo,
        .pInputAssemblyState = &inputAssembly,
        .pViewportState = &viewportState,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pColorBlendState = &colorBlending,
        .pDynamicState = &dynamicState,
        .layout = vkState.pipeline_layout,
        .renderPass = vkState.render_pass,
        .subpass = 2,
        .basePipelineHandle = null,
        .pNext = null,
    };
    if (vk.vkCreateGraphicsPipelines(vkState.logicalDevice, null, 1, &pipelineInfo, null, &vkState.spriteGraphicsPipeline) != vk.VK_SUCCESS) return error.FailedToCreateGraphicsPipeline;

    std.debug.print("sprite graphics Pipeline Created : {any}\n", .{vkState.pipeline_layout});
}
