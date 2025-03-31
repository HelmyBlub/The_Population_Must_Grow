const std = @import("std");
const vk = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", "1");
    @cInclude("vulkan.h");
});
const main = @import("../main.zig");
const paintVulkanZig = @import("paintVulkan.zig");
const imageZig = @import("../image.zig");

pub const VkFont = struct {
    pipelineLayout: vk.VkPipelineLayout = undefined,
    graphicsPipeline: vk.VkPipeline = undefined,
    vertexBuffer: vk.VkBuffer = undefined,
    vertexBufferMemory: vk.VkDeviceMemory = undefined,
    vertices: []FontVertex = undefined,
    mipLevels: u32 = undefined,
    textureImage: vk.VkImage = undefined,
    textureImageMemory: vk.VkDeviceMemory = undefined,
    textureImageView: vk.VkImageView = undefined,
};

const FontVertex = struct {
    pos: [2]f32,
    texX: f32,
    texWidth: f32,
    size: f32,
    color: [3]f32,

    fn getBindingDescription() vk.VkVertexInputBindingDescription {
        const bindingDescription: vk.VkVertexInputBindingDescription = .{
            .binding = 0,
            .stride = @sizeOf(FontVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        return bindingDescription;
    }

    fn getAttributeDescriptions() [5]vk.VkVertexInputAttributeDescription {
        const attributeDescriptions = [_]vk.VkVertexInputAttributeDescription{ .{
            .binding = 0,
            .location = 0,
            .format = vk.VK_FORMAT_R32G32_SFLOAT,
            .offset = @offsetOf(FontVertex, "pos"),
        }, .{
            .binding = 0,
            .location = 1,
            .format = vk.VK_FORMAT_R32_SFLOAT,
            .offset = @offsetOf(FontVertex, "texX"),
        }, .{
            .binding = 0,
            .location = 2,
            .format = vk.VK_FORMAT_R32_SFLOAT,
            .offset = @offsetOf(FontVertex, "texWidth"),
        }, .{
            .binding = 0,
            .location = 3,
            .format = vk.VK_FORMAT_R32_SFLOAT,
            .offset = @offsetOf(FontVertex, "size"),
        }, .{
            .binding = 0,
            .location = 4,
            .format = vk.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @offsetOf(FontVertex, "color"),
        } };
        return attributeDescriptions;
    }
};

pub fn paintChar(char: u8, vulkanSurfacePosition: main.Position, fontSize: f32, state: *main.ChatSimState) !void {
    // height width
    // image vulkan coordinates go from 0 to 1 for both width and height even though is is not a square
    // vulkan surface goes from -1 to 1 even though it is not a square
    // window width goes from 0 to 1600 and height from 0 to 800
    // paint character A
    // texX: A is first in image -> texX = 0
    //    A width is 50pixel in an image width of 1600, pixel height is always 40
    // texWidth: as for vulkan image width goes from 0 to 1 => texWidth = 50/1600 = 0.03125
    // size: size in pixels
    //
    // in geom shader
    // width = inTexWidth[0] * inSize[0] * scale[0].x;
    //       = 0.03125 * 100 * (2 / 1600) =  0.0039
    // height = inSize[0] * scale[0].y;
    //        = 100 * (2 / 800)

    var texX: f32 = 0;
    var texWidth: f32 = 0;
    charToTexCoords(char, &texX, &texWidth);
    state.vkState.font.vertices[0] = .{
        .pos = .{ vulkanSurfacePosition.x, vulkanSurfacePosition.y },
        .color = .{ 1, 0, 0 },
        .texX = texX,
        .texWidth = texWidth,
        .size = fontSize,
    };
    try setupVertexDataForGPU(&state.vkState);
}

pub fn initFont(state: *main.ChatSimState) !void {
    try createGraphicsPipeline(&state.vkState, state.allocator);
    try createVertexBuffer(&state.vkState, state.allocator);
    try imageZig.createVulkanTextureImage(
        &state.vkState,
        state.allocator,
        "images/myfont.png",
        &state.vkState.font.mipLevels,
        &state.vkState.font.textureImage,
        &state.vkState.font.textureImageMemory,
    );
    state.vkState.font.textureImageView = try paintVulkanZig.createImageView(
        state.vkState.font.textureImage,
        vk.VK_FORMAT_R8G8B8A8_SRGB,
        state.vkState.font.mipLevels,
        &state.vkState,
    );
}

pub fn destroyFont(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) void {
    vk.vkDestroyImageView(vkState.logicalDevice, vkState.font.textureImageView, null);
    vk.vkDestroyImage(vkState.logicalDevice, vkState.font.textureImage, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.font.textureImageMemory, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.font.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.font.vertexBufferMemory, null);
    vk.vkDestroyPipeline(vkState.logicalDevice, vkState.font.graphicsPipeline, null);
    vk.vkDestroyPipelineLayout(vkState.logicalDevice, vkState.font.pipelineLayout, null);
    allocator.free(vkState.font.vertices);
}

pub fn setupVertices(state: *main.ChatSimState) !void {
    state.vkState.font.vertices[0] = .{
        .pos = .{ 0, 0 },
        .color = .{ 1, 0, 0 },
        .texCords = .{ 0, 0 },
        .size = .{ 1, 1 },
    };
    try setupVertexDataForGPU(&state.vkState);
}

pub fn setupVertexDataForGPU(vkState: *paintVulkanZig.Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.font.vertexBufferMemory, 0, @sizeOf(FontVertex) * vkState.font.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpu_vertices: [*]FontVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.font.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.font.vertexBufferMemory);
}

pub fn recordFontCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.ChatSimState) !void {
    const vkState = &state.vkState;
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.font.graphicsPipeline);
    const vertexBuffers: [1]vk.VkBuffer = .{vkState.font.vertexBuffer};
    const offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, 1, 1, 0, 0);
}

fn charToTexCoords(char: u8, texX: *f32, texWidth: *f32) void {
    const fontImageWidth = 1600.0;
    switch (char) {
        'a', 'A' => {
            texX.* = 0;
            texWidth.* = 50.0 / fontImageWidth;
        },
        'b', 'B' => {
            texX.* = 50.0 / fontImageWidth;
            texWidth.* = 38.0 / fontImageWidth;
        },
        'c', 'C' => {
            texX.* = 88.0 / fontImageWidth;
            texWidth.* = 29.0 / fontImageWidth;
        },
        'd', 'D' => {
            texX.* = 117.0 / fontImageWidth;
            texWidth.* = 1.0 / fontImageWidth;
        },
        else => {
            texX.* = 0;
            texWidth.* = 1;
        },
    }
}

fn createVertexBuffer(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    vkState.font.vertices = try allocator.alloc(FontVertex, 10);
    try paintVulkanZig.createBuffer(
        @sizeOf(FontVertex) * 10,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.font.vertexBuffer,
        &vkState.font.vertexBufferMemory,
        vkState,
    );
    std.debug.print("font createVertexBuffer finished\n", .{});
}

fn createGraphicsPipeline(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    const vertShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/fontVert.spv", allocator);
    defer allocator.free(vertShaderCode);
    const vertShaderModule = try paintVulkanZig.createShaderModule(vertShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, vertShaderModule, null);
    const vertShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertShaderModule,
        .pName = "main",
    };

    const fragShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/fontFrag.spv", allocator);
    defer allocator.free(fragShaderCode);
    const fragShaderModule = try paintVulkanZig.createShaderModule(fragShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, fragShaderModule, null);
    const fragShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragShaderModule,
        .pName = "main",
    };

    const geomShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/fontGeom.spv", allocator);
    defer allocator.free(geomShaderCode);
    const geomShaderModule = try paintVulkanZig.createShaderModule(geomShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, geomShaderModule, null);
    const geomShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_GEOMETRY_BIT,
        .module = geomShaderModule,
        .pName = "main",
    };

    const shaderStages = [_]vk.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo, geomShaderStageInfo };
    const bindingDescription = FontVertex.getBindingDescription();
    const attributeDescriptions = FontVertex.getAttributeDescriptions();
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

    var pipelineLayoutInfo = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &vkState.descriptorSetLayout,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };
    if (vk.vkCreatePipelineLayout(vkState.logicalDevice, &pipelineLayoutInfo, null, &vkState.font.pipelineLayout) != vk.VK_SUCCESS) return error.createPipelineLayout;

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
        .layout = vkState.font.pipelineLayout,
        .renderPass = vkState.render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .pNext = null,
    };
    if (vk.vkCreateGraphicsPipelines(vkState.logicalDevice, null, 1, &pipelineInfo, null, &vkState.font.graphicsPipeline) != vk.VK_SUCCESS) return error.createGraphicsPipeline;
    std.debug.print("font Graphics Pipeline Created\n", .{});
}
