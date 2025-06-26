const std = @import("std");
const vk = @cImport({
    @cInclude("vulkan.h");
});
const main = @import("../main.zig");
const paintVulkanZig = @import("paintVulkan.zig");
const mapZig = @import("../map.zig");

pub const VkRectangle = struct {
    pipelineLayout: vk.VkPipelineLayout = undefined,
    graphicsPipeline: vk.VkPipeline = undefined,
    vertexBuffer: vk.VkBuffer = undefined,
    vertexBufferMemory: vk.VkDeviceMemory = undefined,
    vertices: []paintVulkanZig.ColoredVertex = undefined,
    verticeCount: usize = 0,
    pub const MAX_VERTICES = 8 * 1200;
};

pub fn initRectangle(state: *main.GameState) !void {
    try createGraphicsPipeline(&state.vkState, state.allocator);
    try createVertexBuffer(&state.vkState, state.allocator);
}

pub fn destroyRectangle(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) void {
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.rectangle.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.rectangle.vertexBufferMemory, null);
    vk.vkDestroyPipeline(vkState.logicalDevice, vkState.rectangle.graphicsPipeline, null);
    vk.vkDestroyPipelineLayout(vkState.logicalDevice, vkState.rectangle.pipelineLayout, null);
    allocator.free(vkState.rectangle.vertices);
}

pub fn setupVertices(rectangles: []?main.VulkanRectangle, state: *main.GameState) !void {
    state.vkState.rectangle.verticeCount = 0;
    const recVertCount = 8;
    for (rectangles) |optRectangle| {
        if (optRectangle) |rectangle| {
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount] = .{ .pos = .{ rectangle.pos[0].x, rectangle.pos[0].y }, .color = rectangle.color };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 1] = .{ .pos = .{ rectangle.pos[1].x, rectangle.pos[0].y }, .color = rectangle.color };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 2] = .{ .pos = .{ rectangle.pos[1].x, rectangle.pos[0].y }, .color = rectangle.color };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 3] = .{ .pos = .{ rectangle.pos[1].x, rectangle.pos[1].y }, .color = rectangle.color };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 4] = .{ .pos = .{ rectangle.pos[1].x, rectangle.pos[1].y }, .color = rectangle.color };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 5] = .{ .pos = .{ rectangle.pos[0].x, rectangle.pos[1].y }, .color = rectangle.color };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 6] = .{ .pos = .{ rectangle.pos[0].x, rectangle.pos[1].y }, .color = rectangle.color };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 7] = .{ .pos = .{ rectangle.pos[0].x, rectangle.pos[0].y }, .color = rectangle.color };
            state.vkState.rectangle.verticeCount += recVertCount;
        } else {
            break;
        }
    }
    try main.pathfindingZig.paintDebugPathfindingVisualization(state);
    try setupVertexDataForGPU(&state.vkState);
}

pub fn setupVertexDataForGPU(vkState: *paintVulkanZig.Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.rectangle.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.rectangle.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpu_vertices: [*]paintVulkanZig.ColoredVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.rectangle.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.rectangle.vertexBufferMemory);
}

pub fn recordRectangleCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.GameState) !void {
    if (state.vkState.rectangle.verticeCount <= 0) return;
    const vkState = &state.vkState;
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.rectangle.graphicsPipeline);
    const vertexBuffers: [1]vk.VkBuffer = .{vkState.rectangle.vertexBuffer};
    const offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.rectangle.verticeCount), 1, 0, 0);
}

fn createVertexBuffer(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    vkState.rectangle.vertices = try allocator.alloc(paintVulkanZig.ColoredVertex, VkRectangle.MAX_VERTICES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.ColoredVertex) * VkRectangle.MAX_VERTICES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.rectangle.vertexBuffer,
        &vkState.rectangle.vertexBufferMemory,
        vkState,
    );
}

fn createGraphicsPipeline(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    const vertShaderCode = try paintVulkanZig.readShaderFile("shaders/rectangleVert.spv", allocator);
    defer allocator.free(vertShaderCode);
    const fragShaderCode = try paintVulkanZig.readShaderFile("shaders/rectangleFrag.spv", allocator);
    defer allocator.free(fragShaderCode);
    const vertShaderModule = try paintVulkanZig.createShaderModule(vertShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, vertShaderModule, null);
    const fragShaderModule = try paintVulkanZig.createShaderModule(fragShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, fragShaderModule, null);

    const vertShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertShaderModule,
        .pName = "main",
    };

    const fragShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragShaderModule,
        .pName = "main",
    };

    const shaderStages = [_]vk.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo };
    const bindingDescription = paintVulkanZig.ColoredVertex.getBindingDescription();
    const attributeDescriptions = paintVulkanZig.ColoredVertex.getAttributeDescriptions();
    var vertexInputInfo = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &bindingDescription,
        .vertexAttributeDescriptionCount = attributeDescriptions.len,
        .pVertexAttributeDescriptions = &attributeDescriptions,
    };

    var inputAssembly = vk.VkPipelineInputAssemblyStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
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
        .polygonMode = vk.VK_POLYGON_MODE_LINE,
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

    var pipelineLayoutInfo = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &vkState.descriptorSetLayout,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };
    if (vk.vkCreatePipelineLayout(vkState.logicalDevice, &pipelineLayoutInfo, null, &vkState.rectangle.pipelineLayout) != vk.VK_SUCCESS) return error.createPipelineLayout;

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
        .layout = vkState.rectangle.pipelineLayout,
        .renderPass = vkState.render_pass,
        .subpass = 2,
        .basePipelineHandle = null,
        .pNext = null,
    };
    if (vk.vkCreateGraphicsPipelines(vkState.logicalDevice, null, 1, &pipelineInfo, null, &vkState.rectangle.graphicsPipeline) != vk.VK_SUCCESS) return error.createGraphicsPipeline;

    var triangleInputAssembly = vk.VkPipelineInputAssemblyStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = vk.VK_FALSE,
    };
    var fillRasterizer = vk.VkPipelineRasterizationStateCreateInfo{
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
    var trianglePipelineInfo = vk.VkGraphicsPipelineCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = shaderStages.len,
        .pStages = &shaderStages,
        .pVertexInputState = &vertexInputInfo,
        .pInputAssemblyState = &triangleInputAssembly,
        .pViewportState = &viewportState,
        .pRasterizationState = &fillRasterizer,
        .pMultisampleState = &multisampling,
        .pColorBlendState = &colorBlending,
        .pDynamicState = &dynamicState,
        .layout = vkState.pipeline_layout,
        .renderPass = vkState.render_pass,
        .subpass = 2,
        .basePipelineHandle = null,
        .pNext = null,
    };
    if (vk.vkCreateGraphicsPipelines(vkState.logicalDevice, null, 1, &trianglePipelineInfo, null, &vkState.triangleGraphicsPipeline) != vk.VK_SUCCESS) return error.FailedToCreateTriangleGraphicsPipeline;
}
