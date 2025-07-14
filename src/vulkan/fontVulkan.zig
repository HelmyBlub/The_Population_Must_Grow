const std = @import("std");
const main = @import("../main.zig");
const paintVulkanZig = @import("paintVulkan.zig");
const vk = paintVulkanZig.vk;
const imageZig = @import("../image.zig");
const windowSdlZig = @import("../windowSdl.zig");
const codePerformanceZig = @import("../codePerformance.zig");

pub const VkFontData = struct {
    vkFont: VkFont = undefined,
    pipelineLayout: vk.VkPipelineLayout = undefined,
    graphicsPipeline: vk.VkPipeline = undefined,
    verticeMax: u32 = 900,
    mipLevels: u32 = undefined,
    textureImage: vk.VkImage = undefined,
    textureImageMemory: vk.VkDeviceMemory = undefined,
    textureImageView: vk.VkImageView = undefined,
    displayPerformance: bool = false,
};

pub const VkFont = struct {
    vertexBuffer: vk.VkBuffer = undefined,
    vertexBufferMemory: vk.VkDeviceMemory = undefined,
    vertices: []FontVertex = undefined,
    verticeCount: usize = 0,
};

pub const FontVertex = struct {
    pos: [2]f32,
    texX: f32,
    texWidth: f32,
    size: f32,
    color: [3]f32,

    pub fn getBindingDescription() vk.VkVertexInputBindingDescription {
        const bindingDescription: vk.VkVertexInputBindingDescription = .{
            .binding = 0,
            .stride = @sizeOf(FontVertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        return bindingDescription;
    }

    pub fn getAttributeDescriptions() [5]vk.VkVertexInputAttributeDescription {
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

pub fn clear(font: *VkFontData) void {
    font.vkFont.verticeCount = 0;
}

fn dataUpdate(state: *main.GameState) !void {
    clear(&state.vkState.font);
    try displayPerformanceDebugInfo(state);
    if (state.vkState.buildOptionsUx.uiButtons.len > 14) {
        const textOntoButton = state.vkState.buildOptionsUx.uiButtons[11];
        if (state.actualGameSpeed == state.desiredGameSpeed) {
            const speedFontSize = 30 * state.vkState.uiSizeFactor;
            const textWidth = paintText("Speed: ", .{ .x = textOntoButton.pos.x, .y = textOntoButton.pos.y + textOntoButton.height / 8 }, speedFontSize, &state.vkState.font.vkFont);
            if (1 > state.desiredGameSpeed) {
                _ = try paintNumber(state.actualGameSpeed, .{ .x = textOntoButton.pos.x + textWidth, .y = textOntoButton.pos.y + textOntoButton.height / 8 }, speedFontSize, &state.vkState.font.vkFont);
            } else {
                _ = try paintNumber(@as(u32, @intFromFloat(state.actualGameSpeed)), .{ .x = textOntoButton.pos.x + textWidth, .y = textOntoButton.pos.y + textOntoButton.height / 8 }, speedFontSize, &state.vkState.font.vkFont);
            }
        } else {
            const speedFontSize = 16 * state.vkState.uiSizeFactor;
            const textWidth = paintText("Speed: ", .{ .x = textOntoButton.pos.x, .y = textOntoButton.pos.y }, speedFontSize, &state.vkState.font.vkFont);
            if (1 > state.desiredGameSpeed) {
                _ = try paintNumber(state.desiredGameSpeed, .{ .x = textOntoButton.pos.x + textWidth, .y = textOntoButton.pos.y }, speedFontSize, &state.vkState.font.vkFont);
            } else {
                _ = try paintNumber(@as(u32, @intFromFloat(state.desiredGameSpeed)), .{ .x = textOntoButton.pos.x + textWidth, .y = textOntoButton.pos.y }, speedFontSize, &state.vkState.font.vkFont);
            }
            const textWidthLimit = paintText("limit: ", .{ .x = textOntoButton.pos.x, .y = textOntoButton.pos.y + textOntoButton.height / 2 }, speedFontSize, &state.vkState.font.vkFont);
            _ = try paintNumber(@as(u32, @intFromFloat(state.actualGameSpeed)), .{ .x = textOntoButton.pos.x + textWidthLimit, .y = textOntoButton.pos.y + textOntoButton.height / 2 }, speedFontSize, &state.vkState.font.vkFont);
        }

        const textOntoZoomButton = state.vkState.buildOptionsUx.uiButtons[14];
        const zoomFontSize = 30 * state.vkState.uiSizeFactor;
        const textWidth = paintText("Zoom: ", .{ .x = textOntoZoomButton.pos.x, .y = textOntoZoomButton.pos.y + textOntoZoomButton.height / 8 }, zoomFontSize, &state.vkState.font.vkFont);
        _ = try paintNumber(state.camera.zoom, .{ .x = textOntoZoomButton.pos.x + textWidth, .y = textOntoZoomButton.pos.y + textOntoZoomButton.height / 8 }, zoomFontSize, &state.vkState.font.vkFont);
    }
    try main.pathfindingZig.paintDebugPathfindingVisualizationFont(state);
}

fn displayPerformanceDebugInfo(state: *main.GameState) !void {
    if (state.vkState.font.displayPerformance) {
        const onePixelYInVulkan = 2 / windowSdlZig.windowData.heightFloat;
        const performanceFontSize = 20.0;
        var offsetY: f32 = -0.99;
        const fpsTextWidth = paintText("FPS: ", .{ .x = -0.99, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
        _ = try paintNumber(@as(u32, @intFromFloat(state.fpsCounter)), .{ .x = -0.99 + fpsTextWidth, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
        offsetY += onePixelYInVulkan * performanceFontSize;
        const tickDurationTextWidth = paintText("Single Tick: ", .{ .x = -0.99, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
        _ = try paintNumber(@as(u32, @intFromFloat(state.tickDurationSmoothedMircoSeconds)), .{ .x = -0.99 + tickDurationTextWidth, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
        offsetY += onePixelYInVulkan * performanceFontSize;
        _ = try paintNumber(state.pathfindTestValue, .{ .x = -0.99 + tickDurationTextWidth, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
        offsetY += onePixelYInVulkan * performanceFontSize;

        if (state.cpuPerCent) |cpuPerCent| {
            var cpuTextWidth = paintText("CPU: ", .{ .x = -0.99, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            cpuTextWidth += try paintNumber(@as(u32, @intFromFloat(cpuPerCent * 100)), .{ .x = -0.99 + cpuTextWidth, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            _ = paintText("%", .{ .x = -0.99 + cpuTextWidth, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            offsetY += onePixelYInVulkan * performanceFontSize;
        }
        for (0..state.usedThreadsCount) |threadIndex| {
            const thread = state.threadData[threadIndex];
            var textWidth = paintText("Thread", .{ .x = -0.99, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            textWidth += try paintNumber(@as(u32, @intCast(threadIndex)), .{ .x = -0.99 + textWidth, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            textWidth += paintText("  ", .{ .x = -0.99, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            textWidth += try paintNumber(@as(u32, @intCast(thread.recentlyRemovedChunkAreaKeys.items.len)), .{ .x = -0.99 + textWidth, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            textWidth += paintText("  ", .{ .x = -0.99, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            textWidth += try paintNumber(@as(u32, @intCast(thread.chunkAreaKeys.items.len)), .{ .x = -0.99 + textWidth, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            textWidth += paintText("  ", .{ .x = -0.99, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            _ = try paintNumber(@as(u32, @intCast(thread.tickedCitizenCounter)), .{ .x = -0.99 + textWidth, .y = offsetY }, performanceFontSize, &state.vkState.font.vkFont);
            offsetY += onePixelYInVulkan * performanceFontSize;
        }
        try codePerformanceZig.paintData(state, offsetY);
    }
}

/// returns vulkan surface width of text
pub fn paintText(chars: []const u8, vulkanSurfacePosition: main.PositionF32, fontSize: f32, vkFont: *VkFont) f32 {
    var texX: f32 = 0;
    var texWidth: f32 = 0;
    var xOffset: f32 = 0;
    for (chars) |char| {
        if (vkFont.verticeCount >= vkFont.vertices.len) break;
        charToTexCoords(char, &texX, &texWidth);
        vkFont.vertices[vkFont.verticeCount] = .{
            .pos = .{ vulkanSurfacePosition.x + xOffset, vulkanSurfacePosition.y },
            .color = .{ 1, 0, 0 },
            .texX = texX,
            .texWidth = texWidth,
            .size = fontSize,
        };
        xOffset += texWidth * 1600 / windowSdlZig.windowData.widthFloat * 2 / 40 * fontSize * 0.8;
        vkFont.verticeCount += 1;
    }
    return xOffset;
}

pub fn getCharFontVertex(char: u8, vulkanSurfacePosition: main.PositionF32, fontSize: f32) FontVertex {
    var texX: f32 = 0;
    var texWidth: f32 = 0;
    charToTexCoords(char, &texX, &texWidth);
    return .{
        .pos = .{ vulkanSurfacePosition.x, vulkanSurfacePosition.y },
        .color = .{ 1, 0, 0 },
        .texX = texX,
        .texWidth = texWidth,
        .size = fontSize,
    };
}

pub fn paintNumber(number: anytype, vulkanSurfacePosition: main.PositionF32, fontSize: f32, vkFont: *VkFont) !f32 {
    const max_len = 20;
    var buf: [max_len]u8 = undefined;
    var numberAsString: []u8 = undefined;
    if (@TypeOf(number) == f32) {
        numberAsString = try std.fmt.bufPrint(&buf, "{d:.1}", .{number});
    } else {
        numberAsString = try std.fmt.bufPrint(&buf, "{d}", .{number});
    }

    var texX: f32 = 0;
    var texWidth: f32 = 0;
    var xOffset: f32 = 0;
    const spacingPosition = (numberAsString.len + 2) % 3;
    const spacing = 20 / windowSdlZig.windowData.widthFloat * 2 / 40 * fontSize * 0.8;
    for (numberAsString, 0..) |char, i| {
        if (vkFont.verticeCount >= vkFont.vertices.len) break;
        charToTexCoords(char, &texX, &texWidth);
        vkFont.vertices[vkFont.verticeCount] = .{
            .pos = .{ vulkanSurfacePosition.x + xOffset, vulkanSurfacePosition.y },
            .color = .{ 1, 0, 0 },
            .texX = texX,
            .texWidth = texWidth,
            .size = fontSize,
        };
        xOffset += texWidth * 1600 / windowSdlZig.windowData.widthFloat * 2 / 40 * fontSize * 0.8;
        if (i % 3 == spacingPosition) xOffset += spacing;
        vkFont.verticeCount += 1;
    }
    return xOffset;
}

pub fn initFont(state: *main.GameState) !void {
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
        vk.VK_IMAGE_ASPECT_COLOR_BIT,
        &state.vkState,
    );
}

pub fn destroyFont(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) void {
    vk.vkDestroyImageView.?(vkState.logicalDevice, vkState.font.textureImageView, null);
    vk.vkDestroyImage.?(vkState.logicalDevice, vkState.font.textureImage, null);
    vk.vkFreeMemory.?(vkState.logicalDevice, vkState.font.textureImageMemory, null);
    vk.vkDestroyBuffer.?(vkState.logicalDevice, vkState.font.vkFont.vertexBuffer, null);
    vk.vkFreeMemory.?(vkState.logicalDevice, vkState.font.vkFont.vertexBufferMemory, null);
    vk.vkDestroyPipeline.?(vkState.logicalDevice, vkState.font.graphicsPipeline, null);
    vk.vkDestroyPipelineLayout.?(vkState.logicalDevice, vkState.font.pipelineLayout, null);
    allocator.free(vkState.font.vkFont.vertices);
}

fn setupVertexDataForGPU(vkState: *paintVulkanZig.Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory.?(vkState.logicalDevice, vkState.font.vkFont.vertexBufferMemory, 0, @sizeOf(FontVertex) * vkState.font.vkFont.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpu_vertices: [*]FontVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.font.vkFont.vertices[0..]);
    vk.vkUnmapMemory.?(vkState.logicalDevice, vkState.font.vkFont.vertexBufferMemory);
}

pub fn recordFontCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.GameState) !void {
    try dataUpdate(state);
    const vkState = &state.vkState;
    try setupVertexDataForGPU(vkState);
    vk.vkCmdBindPipeline.?(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.font.graphicsPipeline);
    const vertexBuffers: [1]vk.VkBuffer = .{vkState.font.vkFont.vertexBuffer};
    const offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers.?(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw.?(commandBuffer, @intCast(vkState.font.vkFont.verticeCount), 1, 0, 0);
}

pub fn charToTexCoords(char: u8, texX: *f32, texWidth: *f32) void {
    const fontImageWidth = 1600.0;
    const imageCharSeperatePixels = [_]f32{ 0, 50, 88, 117, 142, 170, 198, 232, 262, 277, 307, 338, 365, 413, 445, 481, 508, 541, 569, 603, 638, 674, 711, 760, 801, 837, 873, 902, 931, 968, 1000, 1037, 1072, 1104, 1142, 1175, 1205, 1238, 1282, 1302, 1322, 1367, 1410 };
    var index: usize = 0;
    switch (char) {
        'a', 'A' => {
            index = 0;
        },
        'b', 'B' => {
            index = 1;
        },
        'c', 'C' => {
            index = 2;
        },
        'd', 'D' => {
            index = 3;
        },
        'e', 'E' => {
            index = 4;
        },
        'f', 'F' => {
            index = 5;
        },
        'g', 'G' => {
            index = 6;
        },
        'h', 'H' => {
            index = 7;
        },
        'i', 'I' => {
            index = 8;
        },
        'j', 'J' => {
            index = 9;
        },
        'k', 'K' => {
            index = 10;
        },
        'l', 'L' => {
            index = 11;
        },
        'm', 'M' => {
            index = 12;
        },
        'n', 'N' => {
            index = 13;
        },
        'o', 'O' => {
            index = 14;
        },
        'p', 'P' => {
            index = 15;
        },
        'q', 'Q' => {
            index = 16;
        },
        'r', 'R' => {
            index = 17;
        },
        's', 'S' => {
            index = 18;
        },
        't', 'T' => {
            index = 19;
        },
        'u', 'U' => {
            index = 20;
        },
        'v', 'V' => {
            index = 21;
        },
        'w', 'W' => {
            index = 22;
        },
        'x', 'X' => {
            index = 23;
        },
        'y', 'Y' => {
            index = 24;
        },
        'z', 'Z' => {
            index = 25;
        },
        '0' => {
            index = 26;
        },
        '1' => {
            index = 27;
        },
        '2' => {
            index = 28;
        },
        '3' => {
            index = 29;
        },
        '4' => {
            index = 30;
        },
        '5' => {
            index = 31;
        },
        '6' => {
            index = 32;
        },
        '7' => {
            index = 33;
        },
        '8' => {
            index = 34;
        },
        '9' => {
            index = 35;
        },
        ':' => {
            index = 36;
        },
        '%' => {
            index = 37;
        },
        ' ' => {
            index = 38;
        },
        '.' => {
            index = 39;
        },
        '+' => {
            index = 40;
        },
        '-' => {
            index = 41;
        },
        else => {
            texX.* = 0;
            texWidth.* = 1;
        },
    }
    texX.* = imageCharSeperatePixels[index] / fontImageWidth;
    texWidth.* = (imageCharSeperatePixels[index + 1] - imageCharSeperatePixels[index]) / fontImageWidth;
}

fn createVertexBuffer(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    vkState.font.vkFont.vertices = try allocator.alloc(FontVertex, vkState.font.verticeMax);
    try paintVulkanZig.createBuffer(
        @sizeOf(FontVertex) * vkState.font.verticeMax,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.font.vkFont.vertexBuffer,
        &vkState.font.vkFont.vertexBufferMemory,
        vkState,
    );
}

fn createGraphicsPipeline(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    const vertShaderCode = try paintVulkanZig.readShaderFile("shaders/fontVert.spv", allocator);
    defer allocator.free(vertShaderCode);
    const vertShaderModule = try paintVulkanZig.createShaderModule(vertShaderCode, vkState);
    defer vk.vkDestroyShaderModule.?(vkState.logicalDevice, vertShaderModule, null);
    const vertShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertShaderModule,
        .pName = "main",
    };

    const fragShaderCode = try paintVulkanZig.readShaderFile("shaders/fontFrag.spv", allocator);
    defer allocator.free(fragShaderCode);
    const fragShaderModule = try paintVulkanZig.createShaderModule(fragShaderCode, vkState);
    defer vk.vkDestroyShaderModule.?(vkState.logicalDevice, fragShaderModule, null);
    const fragShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragShaderModule,
        .pName = "main",
    };

    const geomShaderCode = try paintVulkanZig.readShaderFile("shaders/fontGeom.spv", allocator);
    defer allocator.free(geomShaderCode);
    const geomShaderModule = try paintVulkanZig.createShaderModule(geomShaderCode, vkState);
    defer vk.vkDestroyShaderModule.?(vkState.logicalDevice, geomShaderModule, null);
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
    if (vk.vkCreatePipelineLayout.?(vkState.logicalDevice, &pipelineLayoutInfo, null, &vkState.font.pipelineLayout) != vk.VK_SUCCESS) return error.createPipelineLayout;

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
        .subpass = 2,
        .basePipelineHandle = null,
        .pNext = null,
    };
    if (vk.vkCreateGraphicsPipelines.?(vkState.logicalDevice, null, 1, &pipelineInfo, null, &vkState.font.graphicsPipeline) != vk.VK_SUCCESS) return error.createGraphicsPipeline;
}
