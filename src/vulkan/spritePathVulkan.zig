const std = @import("std");
const vk = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", "1");
    @cInclude("vulkan.h");
});
const main = @import("../main.zig");
const mapZig = @import("../map.zig");
const paintVulkanZig = @import("paintVulkan.zig");
const imageZig = @import("../image.zig");
const windowSdlZig = @import("../windowSdl.zig");

pub const VkPathVertices = struct {
    graphicsPipeline: vk.VkPipeline = undefined,
    entityPaintCount: u32 = 0,
    nextEntityPaintCount: u32 = 0,
    vertices: []SpritePathVertex = undefined,
    vertexBufferSize: u64 = 0,
    vertexBuffer: vk.VkBuffer = undefined,
    vertexBufferMemory: vk.VkDeviceMemory = undefined,
    vertexBufferCleanUp: []?vk.VkBuffer = undefined,
    vertexBufferMemoryCleanUp: []?vk.VkDeviceMemory = undefined,
};

pub const SpritePathVertex = struct {
    pos: [2]f32,

    pub fn getBindingDescription() vk.VkVertexInputBindingDescription {
        const bindingDescription: vk.VkVertexInputBindingDescription = .{
            .binding = 0,
            .stride = @sizeOf(SpritePathVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        return bindingDescription;
    }

    pub fn getAttributeDescriptions() [1]vk.VkVertexInputAttributeDescription {
        var attributeDescriptions: [1]vk.VkVertexInputAttributeDescription = .{undefined};
        attributeDescriptions[0].binding = 0;
        attributeDescriptions[0].location = 0;
        attributeDescriptions[0].format = vk.VK_FORMAT_R32G32_SFLOAT;
        attributeDescriptions[0].offset = @offsetOf(SpritePathVertex, "pos");
        return attributeDescriptions;
    }
};

pub fn setupVertices(state: *main.ChatSimState, chunkVisible: mapZig.VisibleChunksData) !void {
    var vkState = &state.vkState;
    const pathData = &vkState.path;
    const buffer = 500;
    pathData.entityPaintCount = pathData.nextEntityPaintCount;
    const pathCount = pathData.entityPaintCount + buffer;

    // recreate buffer with new size
    if (vkState.path.vertexBufferSize == 0) return;
    if (vkState.path.vertexBufferCleanUp[vkState.currentFrame] != null) {
        vk.vkDestroyBuffer(vkState.logicalDevice, vkState.path.vertexBufferCleanUp[vkState.currentFrame].?, null);
        vk.vkFreeMemory(vkState.logicalDevice, vkState.path.vertexBufferMemoryCleanUp[vkState.currentFrame].?, null);
        vkState.path.vertexBufferCleanUp[vkState.currentFrame] = null;
        vkState.path.vertexBufferMemoryCleanUp[vkState.currentFrame] = null;
    }
    if ((vkState.path.vertexBufferSize < pathCount or vkState.path.vertexBufferSize -| paintVulkanZig.Vk_State.BUFFER_ADDITIOAL_SIZE * 2 > pathCount)) {
        vkState.path.vertexBufferCleanUp[vkState.currentFrame] = vkState.path.vertexBuffer;
        vkState.path.vertexBufferMemoryCleanUp[vkState.currentFrame] = vkState.path.vertexBufferMemory;
        try createVertexBuffer(vkState, pathCount, state.allocator);
    }

    var index: u32 = 0;
    var entitiesCounter: u32 = 0;
    const max = vkState.path.vertices.len;
    for (0..chunkVisible.columns) |x| {
        for (0..chunkVisible.rows) |y| {
            const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(
                .{
                    .chunkX = chunkVisible.left + @as(i32, @intCast(x)),
                    .chunkY = chunkVisible.top + @as(i32, @intCast(y)),
                },
                state,
            );
            const len = chunk.pathes.items.len;
            if (index + len < max) {
                const dest: [*]main.Position = @ptrCast(@alignCast(vkState.path.vertices[index..(index + len)]));
                @memcpy(dest, chunk.pathes.items[0..len]);
                entitiesCounter += @intCast(len);
            }
            index += @intCast(len);
        }
    }
    pathData.entityPaintCount = entitiesCounter;
    pathData.nextEntityPaintCount = index;
    try setupVertexDataForGPU(vkState);
}

pub fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.ChatSimState) !void {
    const vkState = &state.vkState;
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.path.graphicsPipeline);
    const vertexBuffers: [1]vk.VkBuffer = .{vkState.path.vertexBuffer};
    const offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(vkState.path.entityPaintCount), 1, 0, 0);
}

pub fn init(state: *main.ChatSimState) !void {
    state.vkState.path.vertexBufferCleanUp = try state.allocator.alloc(?vk.VkBuffer, paintVulkanZig.Vk_State.MAX_FRAMES_IN_FLIGHT);
    state.vkState.path.vertexBufferMemoryCleanUp = try state.allocator.alloc(?vk.VkDeviceMemory, paintVulkanZig.Vk_State.MAX_FRAMES_IN_FLIGHT);
    for (0..paintVulkanZig.Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        state.vkState.path.vertexBufferCleanUp[i] = null;
        state.vkState.path.vertexBufferMemoryCleanUp[i] = null;
    }
    try createGraphicsPipeline(&state.vkState, state.allocator);
    try createVertexBuffer(&state.vkState, 10, state.allocator);
}

pub fn destroy(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) void {
    for (0..paintVulkanZig.Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        if (vkState.path.vertexBufferSize != 0 and vkState.path.vertexBufferCleanUp[i] != null) {
            vk.vkDestroyBuffer(vkState.logicalDevice, vkState.path.vertexBufferCleanUp[i].?, null);
            vk.vkFreeMemory(vkState.logicalDevice, vkState.path.vertexBufferMemoryCleanUp[i].?, null);
            vkState.path.vertexBufferCleanUp[i] = null;
            vkState.path.vertexBufferMemoryCleanUp[i] = null;
        }
    }

    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.path.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.path.vertexBufferMemory, null);
    vk.vkDestroyPipeline(vkState.logicalDevice, vkState.path.graphicsPipeline, null);
    allocator.free(vkState.path.vertices);
    allocator.free(vkState.path.vertexBufferCleanUp);
    allocator.free(vkState.path.vertexBufferMemoryCleanUp);
}

fn setupVertexDataForGPU(vkState: *paintVulkanZig.Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.path.vertexBufferMemory, 0, @sizeOf(SpritePathVertex) * vkState.path.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpu_vertices: [*]SpritePathVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.path.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.path.vertexBufferMemory);
}

fn createVertexBuffer(vkState: *paintVulkanZig.Vk_State, entityCount: u64, allocator: std.mem.Allocator) !void {
    if (vkState.path.vertexBufferSize != 0) allocator.free(vkState.path.vertices);
    vkState.path.vertexBufferSize = entityCount + paintVulkanZig.Vk_State.BUFFER_ADDITIOAL_SIZE;
    vkState.path.vertices = try allocator.alloc(SpritePathVertex, vkState.path.vertexBufferSize);
    try paintVulkanZig.createBuffer(
        @sizeOf(SpritePathVertex) * vkState.path.vertexBufferSize,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.path.vertexBuffer,
        &vkState.path.vertexBufferMemory,
        vkState,
    );
}

fn createGraphicsPipeline(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    const vertShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/spritePathWithGlobalTransformVert.spv", allocator);
    defer allocator.free(vertShaderCode);
    const fragShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/imageFrag.spv", allocator);
    defer allocator.free(fragShaderCode);
    const geomShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/spriteWithGlobalTransformGeom.spv", allocator);
    defer allocator.free(geomShaderCode);
    const vertShaderModule = try paintVulkanZig.createShaderModule(vertShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, vertShaderModule, null);
    const fragShaderModule = try paintVulkanZig.createShaderModule(fragShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, fragShaderModule, null);
    const geomShaderModule = try paintVulkanZig.createShaderModule(geomShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, geomShaderModule, null);

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

    const geomShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_GEOMETRY_BIT,
        .module = geomShaderModule,
        .pName = "main",
    };

    const shaderStages = [_]vk.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo, geomShaderStageInfo };
    const bindingDescription = SpritePathVertex.getBindingDescription();
    const attributeDescriptions = SpritePathVertex.getAttributeDescriptions();
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
        .subpass = 0,
        .basePipelineHandle = null,
        .pNext = null,
    };
    if (vk.vkCreateGraphicsPipelines(vkState.logicalDevice, null, 1, &pipelineInfo, null, &vkState.path.graphicsPipeline) != vk.VK_SUCCESS) return error.FailedToCreateGraphicsPipeline;
}
