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
const spritePathVulkanZig = @import("spritePathVulkan.zig");

pub const VkTreeVertices = struct {
    graphicsPipeline: vk.VkPipeline = undefined,
    entityPaintCount: u32 = 0,
    nextEntityPaintCount: u32 = 0,
    vertices: []spritePathVulkanZig.SpriteJustPosVertex = undefined,
    vertexBufferSize: u64 = 0,
    vertexBuffer: vk.VkBuffer = undefined,
    vertexBufferMemory: vk.VkDeviceMemory = undefined,
    vertexBufferCleanUp: []?vk.VkBuffer = undefined,
    vertexBufferMemoryCleanUp: []?vk.VkDeviceMemory = undefined,
    pub const SWITCH_TO_SIMPLE_ZOOM: f32 = 0.25;
};

pub fn setupVertices(state: *main.ChatSimState, chunkVisible: mapZig.VisibleChunksData, generalIndex: *u32) !void {
    var vkState = &state.vkState;
    const pathData = &vkState.trees;
    const buffer = 500;
    pathData.entityPaintCount = pathData.nextEntityPaintCount;
    const pathCount = pathData.entityPaintCount + buffer;

    // recreate buffer with new size
    if (vkState.trees.vertexBufferSize == 0) return;
    if (vkState.trees.vertexBufferCleanUp[vkState.currentFrame] != null) {
        vk.vkDestroyBuffer(vkState.logicalDevice, vkState.trees.vertexBufferCleanUp[vkState.currentFrame].?, null);
        vk.vkFreeMemory(vkState.logicalDevice, vkState.trees.vertexBufferMemoryCleanUp[vkState.currentFrame].?, null);
        vkState.trees.vertexBufferCleanUp[vkState.currentFrame] = null;
        vkState.trees.vertexBufferMemoryCleanUp[vkState.currentFrame] = null;
    }
    if ((vkState.trees.vertexBufferSize < pathCount or vkState.trees.vertexBufferSize -| paintVulkanZig.Vk_State.BUFFER_ADDITIOAL_SIZE * 2 > pathCount)) {
        vkState.trees.vertexBufferCleanUp[vkState.currentFrame] = vkState.trees.vertexBuffer;
        vkState.trees.vertexBufferMemoryCleanUp[vkState.currentFrame] = vkState.trees.vertexBufferMemory;
        try createVertexBuffer(vkState, pathCount, state.allocator);
    }

    var index: u32 = 0;
    var entitiesCounter: u32 = 0;
    const max = vkState.trees.vertices.len;
    const simple: bool = state.camera.zoom < VkTreeVertices.SWITCH_TO_SIMPLE_ZOOM;
    for (0..chunkVisible.columns) |x| {
        for (0..chunkVisible.rows) |y| {
            const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(
                .{
                    .chunkX = chunkVisible.left + @as(i32, @intCast(x)),
                    .chunkY = chunkVisible.top + @as(i32, @intCast(y)),
                },
                state,
            );

            if (simple) {
                const len = chunk.treesPos.items.len;
                if (index + len < max) {
                    const dest: [*]main.Position = @ptrCast(@alignCast(vkState.trees.vertices[index..(index + len)]));
                    @memcpy(dest, chunk.treesPos.items[0..len]);
                    entitiesCounter += @intCast(len);
                }
                index += @intCast(len);
            } else {
                for (chunk.trees.items, 0..) |*tree, treeIndex| {
                    if (index < max) {
                        var size: u8 = mapZig.GameMap.TILE_SIZE;
                        var imageIndex: u8 = imageZig.IMAGE_GREEN_RECTANGLE;
                        if (tree.fullyGrown) {
                            imageIndex = imageZig.IMAGE_TREE;
                        } else if (tree.growStartTimeMs) |time| {
                            size = @intCast(@divFloor(mapZig.GameMap.TILE_SIZE * (state.gameTimeMs - time), mapZig.GROW_TIME_MS));
                            imageIndex = imageZig.IMAGE_TREE;
                        }
                        var rotate: f32 = 0;
                        if (tree.beginCuttingTime) |cutTime| {
                            const fallTime = main.CITIZEN_TREE_CUT_PART2_DURATION_TREE_FALLING;
                            const startFalling = main.CITIZEN_TREE_CUT_PART1_DURATION;
                            const timePassed = state.gameTimeMs - cutTime;
                            if (timePassed > startFalling) {
                                const fallingTimePerCent = @min(@as(f32, @floatFromInt(timePassed - startFalling)) / fallTime, 1);
                                const fallingAngle = std.math.pow(f32, fallingTimePerCent, 3.0) * std.math.pi / 2.0;
                                rotate = fallingAngle;
                            }
                        }
                        const treePos = chunk.treesPos.items[treeIndex];
                        vkState.vertices[generalIndex.*] = .{ .pos = .{ treePos.x, treePos.y }, .imageIndex = imageIndex, .size = size, .rotate = rotate, .cutY = 0 };
                    }
                    generalIndex.* += 1;
                }
            }
        }
    }
    pathData.entityPaintCount = entitiesCounter;
    pathData.nextEntityPaintCount = index;
    try setupVertexDataForGPU(vkState);
}

pub fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.ChatSimState) !void {
    const vkState = &state.vkState;
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.trees.graphicsPipeline);
    const vertexBuffers: [1]vk.VkBuffer = .{vkState.trees.vertexBuffer};
    const offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(vkState.trees.entityPaintCount), 1, 0, 0);
}

pub fn init(state: *main.ChatSimState) !void {
    state.vkState.trees.vertexBufferCleanUp = try state.allocator.alloc(?vk.VkBuffer, paintVulkanZig.Vk_State.MAX_FRAMES_IN_FLIGHT);
    state.vkState.trees.vertexBufferMemoryCleanUp = try state.allocator.alloc(?vk.VkDeviceMemory, paintVulkanZig.Vk_State.MAX_FRAMES_IN_FLIGHT);
    for (0..paintVulkanZig.Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        state.vkState.trees.vertexBufferCleanUp[i] = null;
        state.vkState.trees.vertexBufferMemoryCleanUp[i] = null;
    }
    try createGraphicsPipeline(&state.vkState, state.allocator);
    try createVertexBuffer(&state.vkState, 10, state.allocator);
}

pub fn destroy(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) void {
    for (0..paintVulkanZig.Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        if (vkState.trees.vertexBufferSize != 0 and vkState.trees.vertexBufferCleanUp[i] != null) {
            vk.vkDestroyBuffer(vkState.logicalDevice, vkState.trees.vertexBufferCleanUp[i].?, null);
            vk.vkFreeMemory(vkState.logicalDevice, vkState.trees.vertexBufferMemoryCleanUp[i].?, null);
            vkState.trees.vertexBufferCleanUp[i] = null;
            vkState.trees.vertexBufferMemoryCleanUp[i] = null;
        }
    }

    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.trees.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.trees.vertexBufferMemory, null);
    vk.vkDestroyPipeline(vkState.logicalDevice, vkState.trees.graphicsPipeline, null);
    allocator.free(vkState.trees.vertices);
    allocator.free(vkState.trees.vertexBufferCleanUp);
    allocator.free(vkState.trees.vertexBufferMemoryCleanUp);
}

fn setupVertexDataForGPU(vkState: *paintVulkanZig.Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.trees.vertexBufferMemory, 0, @sizeOf(spritePathVulkanZig.SpriteJustPosVertex) * vkState.trees.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpu_vertices: [*]spritePathVulkanZig.SpriteJustPosVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.trees.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.trees.vertexBufferMemory);
}

fn createVertexBuffer(vkState: *paintVulkanZig.Vk_State, entityCount: u64, allocator: std.mem.Allocator) !void {
    if (vkState.trees.vertexBufferSize != 0) allocator.free(vkState.trees.vertices);
    vkState.trees.vertexBufferSize = entityCount + paintVulkanZig.Vk_State.BUFFER_ADDITIOAL_SIZE;
    vkState.trees.vertices = try allocator.alloc(spritePathVulkanZig.SpriteJustPosVertex, vkState.trees.vertexBufferSize);
    try paintVulkanZig.createBuffer(
        @sizeOf(spritePathVulkanZig.SpriteJustPosVertex) * vkState.trees.vertexBufferSize,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.trees.vertexBuffer,
        &vkState.trees.vertexBufferMemory,
        vkState,
    );
}

fn createGraphicsPipeline(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    const vertShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/spriteTreeWithGlobalTransformVert.spv", allocator);
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
    const bindingDescription = spritePathVulkanZig.SpriteJustPosVertex.getBindingDescription();
    const attributeDescriptions = spritePathVulkanZig.SpriteJustPosVertex.getAttributeDescriptions();
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

    vkState.depthStencil = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = vk.VK_TRUE,
        .depthWriteEnable = vk.VK_TRUE,
        .depthCompareOp = vk.VK_COMPARE_OP_LESS,
        .depthBoundsTestEnable = vk.VK_FALSE,
        .minDepthBounds = 0.0,
        .maxDepthBounds = 1.0,
        .stencilTestEnable = vk.VK_FALSE,
        .front = .{},
        .back = .{},
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
        .subpass = 1,
        .basePipelineHandle = null,
        .pNext = null,
        .pDepthStencilState = &vkState.depthStencil,
    };
    if (vk.vkCreateGraphicsPipelines(vkState.logicalDevice, null, 1, &pipelineInfo, null, &vkState.trees.graphicsPipeline) != vk.VK_SUCCESS) return error.FailedToCreateGraphicsPipeline;
}
