const std = @import("std");
const imageZig = @import("../image.zig");
const mapZig = @import("../map.zig");
const windowSdlZig = @import("../windowSdl.zig");
const vk = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", "1");
    @cInclude("vulkan.h");
});
const main = @import("../main.zig");
const rectangleVulkanZig = @import("rectangleVulkan.zig");
const fontVulkanZig = @import("fontVulkan.zig");

pub const Vk_State = struct {
    hInstance: vk.HINSTANCE = undefined,
    instance: vk.VkInstance = undefined,
    surface: vk.VkSurfaceKHR = undefined,
    graphics_queue_family_idx: u32 = undefined,
    physical_device: vk.VkPhysicalDevice = undefined,
    logicalDevice: vk.VkDevice = undefined,
    queue: vk.VkQueue = undefined,
    swapchain: vk.VkSwapchainKHR = undefined,
    swapchain_info: struct {
        support: SwapChainSupportDetails = undefined,
        format: vk.VkSurfaceFormatKHR = undefined,
        present: vk.VkPresentModeKHR = undefined,
        extent: vk.VkExtent2D = undefined,
        images: []vk.VkImage = &.{},
    } = undefined,
    swapchain_imageviews: []vk.VkImageView = undefined,
    render_pass: vk.VkRenderPass = undefined,
    pipeline_layout: vk.VkPipelineLayout = undefined,
    graphics_pipeline: vk.VkPipeline = undefined,
    framebuffers: []vk.VkFramebuffer = undefined,
    command_pool: vk.VkCommandPool = undefined,
    command_buffer: []vk.VkCommandBuffer = undefined,
    imageAvailableSemaphore: []vk.VkSemaphore = undefined,
    renderFinishedSemaphore: []vk.VkSemaphore = undefined,
    inFlightFence: []vk.VkFence = undefined,
    currentFrame: u16 = 0,
    vertexBufferSize: u64 = 0,
    vertexBuffer: vk.VkBuffer = undefined,
    vertexBufferMemory: vk.VkDeviceMemory = undefined,
    vertexBufferCleanUp: []?vk.VkBuffer = undefined,
    vertexBufferMemoryCleanUp: []?vk.VkDeviceMemory = undefined,
    descriptorSetLayout: vk.VkDescriptorSetLayout = undefined,
    uniformBuffers: []vk.VkBuffer = undefined,
    uniformBuffersMemory: []vk.VkDeviceMemory = undefined,
    uniformBuffersMapped: []?*anyopaque = undefined,
    descriptorPool: vk.VkDescriptorPool = undefined,
    descriptorSets: []vk.VkDescriptorSet = undefined,
    mipLevels: []u32 = undefined,
    textureImage: []vk.VkImage = undefined,
    textureImageMemory: []vk.VkDeviceMemory = undefined,
    textureImageView: []vk.VkImageView = undefined,
    textureSampler: vk.VkSampler = undefined,
    msaaSamples: vk.VkSampleCountFlagBits = vk.VK_SAMPLE_COUNT_1_BIT,
    colorImage: vk.VkImage = undefined,
    colorImageMemory: vk.VkDeviceMemory = undefined,
    colorImageView: vk.VkImageView = undefined,
    entityPaintCount: u32 = 0,
    vertices: []Vertex = undefined,
    rectangle: rectangleVulkanZig.VkRectangle = undefined,
    font: fontVulkanZig.VkFont = .{},
    const MAX_FRAMES_IN_FLIGHT: u16 = 2;
    const BUFFER_ADDITIOAL_SIZE: u16 = 50;
};

const VkCameraData = struct {
    transform: [4][4]f32,
    translate: [2]f32,
};

const SwapChainSupportDetails = struct {
    capabilities: vk.VkSurfaceCapabilitiesKHR,
    formats: []vk.VkSurfaceFormatKHR,
    presentModes: []vk.VkPresentModeKHR,
};

const Vertex = struct {
    pos: [2]f32,
    imageIndex: u8,
    size: u8,

    fn getBindingDescription() vk.VkVertexInputBindingDescription {
        const bindingDescription: vk.VkVertexInputBindingDescription = .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        return bindingDescription;
    }

    fn getAttributeDescriptions() [3]vk.VkVertexInputAttributeDescription {
        var attributeDescriptions: [3]vk.VkVertexInputAttributeDescription = .{ undefined, undefined, undefined };
        attributeDescriptions[0].binding = 0;
        attributeDescriptions[0].location = 0;
        attributeDescriptions[0].format = vk.VK_FORMAT_R32G32_SFLOAT;
        attributeDescriptions[0].offset = @offsetOf(Vertex, "pos");
        attributeDescriptions[1].binding = 0;
        attributeDescriptions[1].location = 1;
        attributeDescriptions[1].format = vk.VK_FORMAT_R8_UINT;
        attributeDescriptions[1].offset = @offsetOf(Vertex, "imageIndex");
        attributeDescriptions[2].binding = 0;
        attributeDescriptions[2].location = 2;
        attributeDescriptions[2].format = vk.VK_FORMAT_R8_UINT;
        attributeDescriptions[2].offset = @offsetOf(Vertex, "size");
        return attributeDescriptions;
    }
};

pub const validation_layers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};

pub fn setupVerticesForCitizens(state: *main.ChatSimState) !void {
    var vkState = &state.vkState;
    var entityPaintCount: usize = 0;
    var chunkVisible = mapZig.getTopLeftVisibleChunkXY(state);
    const minSize = 8;
    if (state.camera.zoom > 1 and (chunkVisible.columns < minSize or chunkVisible.rows < minSize)) {
        // citizens can be far away from their chunks, so they need to be considered for painting too
        const increaseBy: usize = minSize - chunkVisible.columns;
        chunkVisible.left -= @intCast(increaseBy);
        chunkVisible.top -= @intCast(increaseBy);
        chunkVisible.columns += 2 * increaseBy;
        chunkVisible.rows += 2 * increaseBy;
    }
    for (0..chunkVisible.columns) |x| {
        for (0..chunkVisible.rows) |y| {
            const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(
                chunkVisible.left + @as(i32, @intCast(x)),
                chunkVisible.top + @as(i32, @intCast(y)),
                state,
            );
            entityPaintCount += chunk.citizens.items.len;
            entityPaintCount += chunk.buildings.items.len;
            entityPaintCount += chunk.bigBuildings.items.len;
            entityPaintCount += chunk.trees.items.len;
            entityPaintCount += chunk.potatoFields.items.len * 2;
            entityPaintCount += chunk.pathes.items.len;
        }
    }
    state.vkState.entityPaintCount = @intCast(entityPaintCount);
    // recreate buffer with new size
    if (vkState.vertexBufferSize == 0) return;
    if (vkState.vertexBufferCleanUp[vkState.currentFrame] != null) {
        vk.vkDestroyBuffer(vkState.logicalDevice, vkState.vertexBufferCleanUp[vkState.currentFrame].?, null);
        vk.vkFreeMemory(vkState.logicalDevice, vkState.vertexBufferMemoryCleanUp[vkState.currentFrame].?, null);
        vkState.vertexBufferCleanUp[vkState.currentFrame] = null;
        vkState.vertexBufferMemoryCleanUp[vkState.currentFrame] = null;
    }
    if ((vkState.vertexBufferSize < entityPaintCount or vkState.vertexBufferSize -| Vk_State.BUFFER_ADDITIOAL_SIZE * 2 > entityPaintCount)) {
        vkState.vertexBufferCleanUp[vkState.currentFrame] = vkState.vertexBuffer;
        vkState.vertexBufferMemoryCleanUp[vkState.currentFrame] = vkState.vertexBufferMemory;
        try createVertexBuffer(vkState, entityPaintCount, state.allocator);
    }

    var index: u32 = 0;
    for (0..chunkVisible.columns) |x| {
        for (0..chunkVisible.rows) |y| {
            const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(
                chunkVisible.left + @as(i32, @intCast(x)),
                chunkVisible.top + @as(i32, @intCast(y)),
                state,
            );
            for (chunk.citizens.items) |*citizen| {
                vkState.vertices[index] = .{ .pos = .{ citizen.position.x, citizen.position.y }, .imageIndex = imageZig.IMAGE_DOG, .size = mapZig.GameMap.TILE_SIZE };
                index += 1;
            }
            for (chunk.trees.items) |*tree| {
                var size: u8 = mapZig.GameMap.TILE_SIZE;
                var imageIndex: u8 = imageZig.IMAGE_GREEN_RECTANGLE;
                if (tree.planted) {
                    size = @intFromFloat(mapZig.GameMap.TILE_SIZE * tree.grow);
                    imageIndex = imageZig.IMAGE_TREE;
                }
                vkState.vertices[index] = .{ .pos = .{ tree.position.x, tree.position.y }, .imageIndex = imageIndex, .size = size };
                index += 1;
            }
            for (chunk.buildings.items) |*building| {
                var imageIndex: u8 = imageZig.IMAGE_WHITE_RECTANGLE;
                if (!building.inConstruction) {
                    imageIndex = imageZig.IMAGE_HOUSE;
                }
                vkState.vertices[index] = .{ .pos = .{ building.position.x, building.position.y }, .imageIndex = imageIndex, .size = mapZig.GameMap.TILE_SIZE };
                index += 1;
            }
            for (chunk.bigBuildings.items) |*building| {
                var imageIndex: u8 = imageZig.IMAGE_WHITE_RECTANGLE;
                if (!building.inConstruction) {
                    imageIndex = imageZig.IMAGE_BIG_HOUSE;
                }
                vkState.vertices[index] = .{ .pos = .{ building.position.x, building.position.y }, .imageIndex = imageIndex, .size = mapZig.GameMap.TILE_SIZE * 2 };
                index += 1;
            }
            for (chunk.potatoFields.items) |*field| {
                vkState.vertices[index] = .{ .pos = .{ field.position.x, field.position.y }, .imageIndex = imageZig.IMAGE_FARM_FIELD, .size = mapZig.GameMap.TILE_SIZE };
                index += 1;
                const size: u8 = @intFromFloat(mapZig.GameMap.TILE_SIZE * field.grow);
                vkState.vertices[index] = .{ .pos = .{ field.position.x, field.position.y }, .imageIndex = imageZig.IMAGE_POTATO_PLANT, .size = size };
                index += 1;
            }
            for (chunk.pathes.items) |*pathPos| {
                vkState.vertices[index] = .{ .pos = .{ pathPos.x, pathPos.y }, .imageIndex = imageZig.IMAGE_PATH, .size = mapZig.GameMap.TILE_SIZE };
                index += 1;
            }
        }
    }
}

pub fn initVulkan(state: *main.ChatSimState) !void {
    const vkState: *Vk_State = &state.vkState;
    vkState.vertexBufferCleanUp = try state.allocator.alloc(?vk.VkBuffer, Vk_State.MAX_FRAMES_IN_FLIGHT);
    vkState.vertexBufferMemoryCleanUp = try state.allocator.alloc(?vk.VkDeviceMemory, Vk_State.MAX_FRAMES_IN_FLIGHT);
    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        vkState.vertexBufferCleanUp[i] = null;
        vkState.vertexBufferMemoryCleanUp[i] = null;
    }

    try createInstance(vkState, state.allocator);
    vkState.surface = @ptrCast(windowSdlZig.getSurfaceForVulkan(@ptrCast(vkState.instance)));
    vkState.physical_device = try pickPhysicalDevice(vkState.instance, vkState, state.allocator);
    try createLogicalDevice(vkState.physical_device, vkState);
    try createSwapChain(vkState, state.allocator);
    try createImageViews(vkState, state.allocator);
    try createRenderPass(vkState);
    try createDescriptorSetLayout(vkState);
    try createGraphicsPipeline(vkState, state.allocator);
    try createColorResources(vkState);
    try createFramebuffers(vkState, state.allocator);
    try createCommandPool(vkState, state.allocator);
    try imageZig.createVulkanTextureSprites(vkState, state.allocator);
    try createTextureImageView(vkState, state.allocator);
    try createTextureSampler(vkState);
    try fontVulkanZig.initFont(state);
    try createVertexBuffer(vkState, Vk_State.BUFFER_ADDITIOAL_SIZE, state.allocator);
    try createUniformBuffers(vkState, state.allocator);
    try createDescriptorPool(vkState);
    try createDescriptorSets(vkState, state.allocator);
    try createCommandBuffers(vkState, state.allocator);
    try createSyncObjects(vkState, state.allocator);
    try rectangleVulkanZig.initRectangle(state);
}

fn createColorResources(vkState: *Vk_State) !void {
    const colorFormat: vk.VkFormat = vkState.swapchain_info.format.format;

    try createImage(
        vkState.swapchain_info.extent.width,
        vkState.swapchain_info.extent.height,
        1,
        vkState.msaaSamples,
        colorFormat,
        vk.VK_IMAGE_TILING_OPTIMAL,
        vk.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT | vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        &vkState.colorImage,
        &vkState.colorImageMemory,
        vkState,
    );
    vkState.colorImageView = try createImageView(vkState.colorImage, colorFormat, 1, vkState);
}

fn getMaxUsableSampleCount(physicalDevice: vk.VkPhysicalDevice) vk.VkSampleCountFlagBits {
    var physicalDeviceProperties: vk.VkPhysicalDeviceProperties = undefined;
    vk.vkGetPhysicalDeviceProperties(physicalDevice, &physicalDeviceProperties);

    const counts: vk.VkSampleCountFlags = physicalDeviceProperties.limits.framebufferColorSampleCounts;
    if ((counts & vk.VK_SAMPLE_COUNT_64_BIT) != 0) {
        return vk.VK_SAMPLE_COUNT_64_BIT;
    }
    if ((counts & vk.VK_SAMPLE_COUNT_32_BIT) != 0) {
        return vk.VK_SAMPLE_COUNT_32_BIT;
    }
    if ((counts & vk.VK_SAMPLE_COUNT_16_BIT) != 0) {
        return vk.VK_SAMPLE_COUNT_16_BIT;
    }
    if ((counts & vk.VK_SAMPLE_COUNT_8_BIT) != 0) {
        return vk.VK_SAMPLE_COUNT_8_BIT;
    }
    if ((counts & vk.VK_SAMPLE_COUNT_4_BIT) != 0) {
        return vk.VK_SAMPLE_COUNT_4_BIT;
    }
    if ((counts & vk.VK_SAMPLE_COUNT_2_BIT) != 0) {
        return vk.VK_SAMPLE_COUNT_2_BIT;
    }

    return vk.VK_SAMPLE_COUNT_1_BIT;
}

fn createTextureSampler(vkState: *Vk_State) !void {
    var properties: vk.VkPhysicalDeviceProperties = undefined;
    vk.vkGetPhysicalDeviceProperties(vkState.physical_device, &properties);
    const samplerInfo: vk.VkSamplerCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = vk.VK_FILTER_LINEAR,
        .minFilter = vk.VK_FILTER_LINEAR,
        .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        .anisotropyEnable = vk.VK_TRUE,
        .maxAnisotropy = properties.limits.maxSamplerAnisotropy,
        .borderColor = vk.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = vk.VK_FALSE,
        .compareEnable = vk.VK_FALSE,
        .compareOp = vk.VK_COMPARE_OP_ALWAYS,
        .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .mipLodBias = 0.0,
        .minLod = 0.0,
        .maxLod = vk.VK_LOD_CLAMP_NONE,
    };
    if (vk.vkCreateSampler(vkState.logicalDevice, &samplerInfo, null, &vkState.textureSampler) != vk.VK_SUCCESS) return error.createSampler;
    std.debug.print("createTextureSampler finished\n", .{});
}

fn createTextureImageView(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    vkState.textureImageView = try allocator.alloc(vk.VkImageView, imageZig.IMAGE_DATA.len);
    for (0..imageZig.IMAGE_DATA.len) |i| {
        vkState.textureImageView[i] = try createImageView(vkState.textureImage[i], vk.VK_FORMAT_R8G8B8A8_SRGB, vkState.mipLevels[i], vkState);
    }
    std.debug.print("createTextureImageView finished\n", .{});
}

pub fn createImageView(image: vk.VkImage, format: vk.VkFormat, mipLevels: u32, vkState: *Vk_State) !vk.VkImageView {
    const viewInfo: vk.VkImageViewCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = mipLevels,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var imageView: vk.VkImageView = undefined;
    if (vk.vkCreateImageView(vkState.logicalDevice, &viewInfo, null, &imageView) != vk.VK_SUCCESS) return error.createImageView;
    return imageView;
}

pub fn beginSingleTimeCommands(vkState: *Vk_State) !vk.VkCommandBuffer {
    const allocInfo: vk.VkCommandBufferAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandPool = vkState.command_pool,
        .commandBufferCount = 1,
    };

    var commandBuffer: vk.VkCommandBuffer = undefined;
    _ = vk.vkAllocateCommandBuffers(vkState.logicalDevice, &allocInfo, &commandBuffer);

    const beginInfo: vk.VkCommandBufferBeginInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };

    _ = vk.vkBeginCommandBuffer(commandBuffer, &beginInfo);

    return commandBuffer;
}

pub fn endSingleTimeCommands(commandBuffer: vk.VkCommandBuffer, vkState: *Vk_State) !void {
    _ = vk.vkEndCommandBuffer(commandBuffer);

    const submitInfo: vk.VkSubmitInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &commandBuffer,
    };

    _ = vk.vkQueueSubmit(vkState.queue, 1, &submitInfo, null);
    _ = vk.vkQueueWaitIdle(vkState.queue);

    vk.vkFreeCommandBuffers(vkState.logicalDevice, vkState.command_pool, 1, &commandBuffer);
}

pub fn createImage(width: u32, height: u32, mipLevels: u32, numSamples: vk.VkSampleCountFlagBits, format: vk.VkFormat, tiling: vk.VkImageTiling, usage: vk.VkImageUsageFlags, properties: vk.VkMemoryPropertyFlags, image: *vk.VkImage, imageMemory: *vk.VkDeviceMemory, vkState: *Vk_State) !void {
    const imageInfo: vk.VkImageCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .extent = .{
            .width = width,
            .height = height,
            .depth = 1,
        },
        .mipLevels = mipLevels,
        .arrayLayers = 1,
        .format = format,
        .tiling = tiling,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .usage = usage,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .samples = numSamples,
        .flags = 0,
    };

    if (vk.vkCreateImage(vkState.logicalDevice, &imageInfo, null, image) != vk.VK_SUCCESS) return error.createImage;

    var memRequirements: vk.VkMemoryRequirements = undefined;
    vk.vkGetImageMemoryRequirements(vkState.logicalDevice, image.*, &memRequirements);

    const allocInfo: vk.VkMemoryAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = memRequirements.size,
        .memoryTypeIndex = try findMemoryType(memRequirements.memoryTypeBits, properties, vkState),
    };

    if (vk.vkAllocateMemory(vkState.logicalDevice, &allocInfo, null, imageMemory) != vk.VK_SUCCESS) return error.vkAllocateMemory;
    if (vk.vkBindImageMemory(vkState.logicalDevice, image.*, imageMemory.*, 0) != vk.VK_SUCCESS) return error.bindImageMemory;
}

fn createDescriptorSets(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    const layouts = [_]vk.VkDescriptorSetLayout{vkState.descriptorSetLayout} ** Vk_State.MAX_FRAMES_IN_FLIGHT;
    const allocInfo: vk.VkDescriptorSetAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = vkState.descriptorPool,
        .descriptorSetCount = Vk_State.MAX_FRAMES_IN_FLIGHT,
        .pSetLayouts = &layouts,
    };
    vkState.descriptorSets = try allocator.alloc(vk.VkDescriptorSet, Vk_State.MAX_FRAMES_IN_FLIGHT);
    if (vk.vkAllocateDescriptorSets(vkState.logicalDevice, &allocInfo, @ptrCast(vkState.descriptorSets)) != vk.VK_SUCCESS) return error.allocateDescriptorSets;

    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        const bufferInfo: vk.VkDescriptorBufferInfo = .{
            .buffer = vkState.uniformBuffers[i],
            .offset = 0,
            .range = @sizeOf(VkCameraData),
        };

        const imageInfo: []vk.VkDescriptorImageInfo = try allocator.alloc(vk.VkDescriptorImageInfo, imageZig.IMAGE_DATA.len);
        defer allocator.free(imageInfo);
        for (0..imageZig.IMAGE_DATA.len) |j| {
            imageInfo[j] = .{
                .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .imageView = vkState.textureImageView[j],
                .sampler = vkState.textureSampler,
            };
        }

        const imageInfoFont: vk.VkDescriptorImageInfo = .{
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = vkState.font.textureImageView,
            .sampler = vkState.textureSampler,
        };

        const descriptorWrites = [_]vk.VkWriteDescriptorSet{
            .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = vkState.descriptorSets[i],
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 1,
                .pBufferInfo = &bufferInfo,
                .pImageInfo = null,
                .pTexelBufferView = null,
            },
            .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = vkState.descriptorSets[i],
                .dstBinding = 1,
                .dstArrayElement = 0,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = @as(u32, @intCast(imageInfo.len)),
                .pImageInfo = @ptrCast(imageInfo),
            },
            .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = vkState.descriptorSets[i],
                .dstBinding = 2,
                .dstArrayElement = 0,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .pImageInfo = @ptrCast(&imageInfoFont),
            },
        };
        vk.vkUpdateDescriptorSets(vkState.logicalDevice, descriptorWrites.len, &descriptorWrites, 0, null);
    }
}

fn createDescriptorPool(vkState: *Vk_State) !void {
    const poolSizes = [_]vk.VkDescriptorPoolSize{
        .{
            .type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = Vk_State.MAX_FRAMES_IN_FLIGHT,
        },
        .{
            .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = Vk_State.MAX_FRAMES_IN_FLIGHT,
        },
    };

    const poolInfo: vk.VkDescriptorPoolCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = poolSizes.len,
        .pPoolSizes = &poolSizes,
        .maxSets = Vk_State.MAX_FRAMES_IN_FLIGHT,
    };
    if (vk.vkCreateDescriptorPool(vkState.logicalDevice, &poolInfo, null, &vkState.descriptorPool) != vk.VK_SUCCESS) return error.descriptionPool;
    std.debug.print("createDescriptorPool finished\n", .{});
}

fn createUniformBuffers(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    const bufferSize: vk.VkDeviceSize = @sizeOf(VkCameraData);

    vkState.uniformBuffers = try allocator.alloc(vk.VkBuffer, Vk_State.MAX_FRAMES_IN_FLIGHT);
    vkState.uniformBuffersMemory = try allocator.alloc(vk.VkDeviceMemory, Vk_State.MAX_FRAMES_IN_FLIGHT);
    vkState.uniformBuffersMapped = try allocator.alloc(?*anyopaque, Vk_State.MAX_FRAMES_IN_FLIGHT);

    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        try createBuffer(
            bufferSize,
            vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &vkState.uniformBuffers[i],
            &vkState.uniformBuffersMemory[i],
            vkState,
        );
        if (vk.vkMapMemory(vkState.logicalDevice, vkState.uniformBuffersMemory[i], 0, bufferSize, 0, &vkState.uniformBuffersMapped[i]) != vk.VK_SUCCESS) return error.uniformMapMemory;
    }
    std.debug.print("createUniformBuffers finished\n", .{});
}

fn createDescriptorSetLayout(vkState: *Vk_State) !void {
    const uboLayoutBinding: vk.VkDescriptorSetLayoutBinding = .{
        .binding = 0,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_GEOMETRY_BIT,
    };
    const samplerLayoutBinding: vk.VkDescriptorSetLayoutBinding = .{
        .binding = 1,
        .descriptorCount = imageZig.IMAGE_DATA.len,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImmutableSamplers = null,
        .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };
    const samplerLayoutFontBinding: vk.VkDescriptorSetLayoutBinding = .{
        .binding = 2,
        .descriptorCount = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImmutableSamplers = null,
        .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const bindings = [_]vk.VkDescriptorSetLayoutBinding{ uboLayoutBinding, samplerLayoutBinding, samplerLayoutFontBinding };

    const layoutInfo: vk.VkDescriptorSetLayoutCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = bindings.len,
        .pBindings = &bindings,
    };

    if (vk.vkCreateDescriptorSetLayout(vkState.logicalDevice, &layoutInfo, null, &vkState.descriptorSetLayout) != vk.VK_SUCCESS) return error.createDescriptorSetLayout;
}

fn findMemoryType(typeFilter: u32, properties: vk.VkMemoryPropertyFlags, vkState: *Vk_State) !u32 {
    var memProperties: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.vkGetPhysicalDeviceMemoryProperties(vkState.physical_device, &memProperties);

    for (0..memProperties.memoryTypeCount) |i| {
        if ((typeFilter & (@as(u32, 1) << @as(u5, @intCast(i))) != 0) and (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return @as(u32, @intCast(i));
        }
    }
    return error.findMemoryType;
}

pub fn createBuffer(size: vk.VkDeviceSize, usage: vk.VkBufferUsageFlags, properties: vk.VkMemoryPropertyFlags, buffer: *vk.VkBuffer, bufferMemory: *vk.VkDeviceMemory, vkState: *Vk_State) !void {
    const bufferInfo: vk.VkBufferCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
    };

    if (vk.vkCreateBuffer(vkState.logicalDevice, &bufferInfo, null, &buffer.*) != vk.VK_SUCCESS) return error.CreateBuffer;
    var memRequirements: vk.VkMemoryRequirements = undefined;
    vk.vkGetBufferMemoryRequirements(vkState.logicalDevice, buffer.*, &memRequirements);

    const allocInfo: vk.VkMemoryAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = memRequirements.size,
        .memoryTypeIndex = try findMemoryType(memRequirements.memoryTypeBits, properties, vkState),
    };
    if (vk.vkAllocateMemory(vkState.logicalDevice, &allocInfo, null, &bufferMemory.*) != vk.VK_SUCCESS) return error.allocateMemory;
    if (vk.vkBindBufferMemory(vkState.logicalDevice, buffer.*, bufferMemory.*, 0) != vk.VK_SUCCESS) return error.bindMemory;
}

fn createVertexBuffer(vkState: *Vk_State, entityCount: u64, allocator: std.mem.Allocator) !void {
    if (vkState.vertexBufferSize != 0) allocator.free(vkState.vertices);
    vkState.vertexBufferSize = entityCount + Vk_State.BUFFER_ADDITIOAL_SIZE;
    vkState.vertices = try allocator.alloc(Vertex, vkState.vertexBufferSize);
    try createBuffer(
        @sizeOf(Vertex) * vkState.vertexBufferSize,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.vertexBuffer,
        &vkState.vertexBufferMemory,
        vkState,
    );
}

pub fn destroyPaintVulkan(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    _ = vk.vkDeviceWaitIdle(vkState.logicalDevice);
    rectangleVulkanZig.destroyRectangle(vkState, allocator);
    fontVulkanZig.destroyFont(vkState, allocator);
    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        if (vkState.vertexBufferSize != 0 and vkState.vertexBufferCleanUp[i] != null) {
            vk.vkDestroyBuffer(vkState.logicalDevice, vkState.vertexBufferCleanUp[i].?, null);
            vk.vkFreeMemory(vkState.logicalDevice, vkState.vertexBufferMemoryCleanUp[i].?, null);
            vkState.vertexBufferCleanUp[i] = null;
            vkState.vertexBufferMemoryCleanUp[i] = null;
        }
    }
    vk.vkDestroyImageView(vkState.logicalDevice, vkState.colorImageView, null);
    vk.vkDestroyImage(vkState.logicalDevice, vkState.colorImage, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.colorImageMemory, null);
    for (vkState.swapchain_imageviews) |imgvw| {
        vk.vkDestroyImageView(vkState.logicalDevice, imgvw, null);
    }
    allocator.free(vkState.swapchain_imageviews);
    for (vkState.framebuffers) |fb| {
        vk.vkDestroyFramebuffer(vkState.logicalDevice, fb, null);
    }
    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        vk.vkDestroySemaphore(vkState.logicalDevice, vkState.imageAvailableSemaphore[i], null);
        vk.vkDestroySemaphore(vkState.logicalDevice, vkState.renderFinishedSemaphore[i], null);
        vk.vkDestroyFence(vkState.logicalDevice, vkState.inFlightFence[i], null);
    }

    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        vk.vkDestroyBuffer(vkState.logicalDevice, vkState.uniformBuffers[i], null);
        vk.vkFreeMemory(vkState.logicalDevice, vkState.uniformBuffersMemory[i], null);
    }
    vk.vkDestroySampler(vkState.logicalDevice, vkState.textureSampler, null);

    for (0..imageZig.IMAGE_DATA.len) |i| {
        vk.vkDestroyImageView(vkState.logicalDevice, vkState.textureImageView[i], null);
        vk.vkDestroyImage(vkState.logicalDevice, vkState.textureImage[i], null);
        vk.vkFreeMemory(vkState.logicalDevice, vkState.textureImageMemory[i], null);
    }

    vk.vkDestroyDescriptorPool(vkState.logicalDevice, vkState.descriptorPool, null);
    vk.vkDestroyDescriptorSetLayout(vkState.logicalDevice, vkState.descriptorSetLayout, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.vertexBufferMemory, null);
    vk.vkDestroyCommandPool(vkState.logicalDevice, vkState.command_pool, null);
    vk.vkDestroyPipeline(vkState.logicalDevice, vkState.graphics_pipeline, null);
    vk.vkDestroyPipelineLayout(vkState.logicalDevice, vkState.pipeline_layout, null);
    vk.vkDestroyRenderPass(vkState.logicalDevice, vkState.render_pass, null);
    vk.vkDestroySwapchainKHR(vkState.logicalDevice, vkState.swapchain, null);
    vk.vkDestroyDevice(vkState.logicalDevice, null);
    vk.vkDestroySurfaceKHR(vkState.instance, vkState.surface, null);
    vk.vkDestroyInstance(vkState.instance, null);
    allocator.free(vkState.vertices);
    allocator.free(vkState.uniformBuffers);
    allocator.free(vkState.uniformBuffersMemory);
    allocator.free(vkState.uniformBuffersMapped);
    allocator.free(vkState.vertexBufferCleanUp);
    allocator.free(vkState.vertexBufferMemoryCleanUp);
    allocator.free(vkState.textureImageView);
    allocator.free(vkState.descriptorSets);
    allocator.free(vkState.imageAvailableSemaphore);
    allocator.free(vkState.renderFinishedSemaphore);
    allocator.free(vkState.inFlightFence);
    allocator.free(vkState.command_buffer);
    allocator.free(vkState.framebuffers);
    allocator.free(vkState.swapchain_info.images);
    allocator.free(vkState.swapchain_info.support.formats);
    allocator.free(vkState.swapchain_info.support.presentModes);
    allocator.free(vkState.textureImage);
    allocator.free(vkState.textureImageMemory);
    allocator.free(vkState.mipLevels);
}

fn createInstance(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    var app_info = vk.VkApplicationInfo{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "ZigWindowsVulkan",
        .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = vk.VK_API_VERSION_1_2,
    };
    var instance_create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = &app_info,
        .enabledLayerCount = validation_layers.len,
        .ppEnabledLayerNames = &validation_layers,
        .enabledExtensionCount = 0,
        .ppEnabledExtensionNames = null,
    };
    const requiredExtensions = [_][*:0]const u8{
        vk.VK_KHR_SURFACE_EXTENSION_NAME,
        vk.VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
    };
    const extension_count: u32 = requiredExtensions.len;
    const extensions: [*][*c]const u8 = @constCast(@ptrCast(&requiredExtensions));
    instance_create_info.enabledExtensionCount = extension_count;
    instance_create_info.ppEnabledExtensionNames = extensions;

    var extension_list = std.ArrayList([*c]const u8).init(allocator);
    for (requiredExtensions[0..extension_count]) |ext| {
        try extension_list.append(ext);
    }

    try extension_list.append(vk.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    instance_create_info.enabledExtensionCount = @intCast(extension_list.items.len);
    const extensions_ = try extension_list.toOwnedSlice();
    defer allocator.free(extensions_);
    const pp_enabled_layer_names: [*][*c]const u8 = extensions_.ptr;
    instance_create_info.ppEnabledExtensionNames = pp_enabled_layer_names;

    if (vk.vkCreateInstance(&instance_create_info, null, &vkState.instance) != vk.VK_SUCCESS) return error.vkCreateInstance;
}

pub fn setupVertexDataForGPU(vkState: *Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.vertexBufferMemory, 0, @sizeOf(Vertex) * vkState.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.vertexBufferMemory);
}

fn updateUniformBuffer(state: *main.ChatSimState) !void {
    var ubo: VkCameraData = .{
        .transform = .{
            .{ 2 / windowSdlZig.windowData.widthFloat, 0, 0.0, 0.0 },
            .{ 0, 2 / windowSdlZig.windowData.heightFloat, 0.0, 0.0 },
            .{ 0.0, 0.0, 1, 0.0 },
            .{ 0.0, 0.0, 0.0, 1 / state.camera.zoom },
        },
        .translate = .{ -state.camera.position.x, -state.camera.position.y },
    };
    if (state.vkState.uniformBuffersMapped[state.vkState.currentFrame]) |data| {
        @memcpy(
            @as([*]u8, @ptrCast(data))[0..@sizeOf(VkCameraData)],
            @as([*]u8, @ptrCast(&ubo)),
        );
    }
}

pub fn drawFrame(state: *main.ChatSimState) !void {
    var vkState = &state.vkState;
    try updateUniformBuffer(state);

    fontVulkanZig.clear(&vkState.font);

    const citizenTextWidth = fontVulkanZig.paintText("Citizens: ", .{ .x = -0.2, .y = -0.99 }, 50, state);
    _ = try fontVulkanZig.paintNumber(@intCast(state.citizenCounter), .{ .x = -0.2 + citizenTextWidth, .y = -0.99 }, 50, state);

    const fpsTextWidth = fontVulkanZig.paintText("FPS: ", .{ .x = -0.99, .y = -0.99 }, 25, state);
    _ = try fontVulkanZig.paintNumber(@intFromFloat(state.fpsCounter), .{ .x = -0.99 + fpsTextWidth, .y = -0.99 }, 25, state);

    const timeTextWidth = fontVulkanZig.paintText("Time: ", .{ .x = -0.49, .y = -0.99 }, 25, state);
    _ = try fontVulkanZig.paintNumber(@divFloor(state.gameTimeMs, 1000), .{ .x = -0.49 + timeTextWidth, .y = -0.99 }, 25, state);

    if (state.cpuPerCent) |cpuPerCent| {
        var cpuTextWidth = fontVulkanZig.paintText("CPU: ", .{ .x = 0.7, .y = -0.99 }, 25, state);
        cpuTextWidth += try fontVulkanZig.paintNumber(@intFromFloat(cpuPerCent * 100), .{ .x = 0.7 + cpuTextWidth, .y = -0.99 }, 25, state);
        _ = fontVulkanZig.paintText("%", .{ .x = 0.7 + cpuTextWidth, .y = -0.99 }, 25, state);
    }
    main.setupRectangleData(state);
    try rectangleVulkanZig.setupVertices(&state.rectangles, state);

    _ = vk.vkWaitForFences(vkState.logicalDevice, 1, &vkState.inFlightFence[vkState.currentFrame], vk.VK_TRUE, std.math.maxInt(u64));
    _ = vk.vkResetFences(vkState.logicalDevice, 1, &vkState.inFlightFence[vkState.currentFrame]);

    var imageIndex: u32 = undefined;
    _ = vk.vkAcquireNextImageKHR(vkState.logicalDevice, vkState.swapchain, std.math.maxInt(u64), vkState.imageAvailableSemaphore[vkState.currentFrame], null, &imageIndex);

    _ = vk.vkResetCommandBuffer(vkState.command_buffer[vkState.currentFrame], 0);
    try recordCommandBuffer(vkState.command_buffer[vkState.currentFrame], imageIndex, state);

    var submitInfo = vk.VkSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &[_]vk.VkSemaphore{vkState.imageAvailableSemaphore[vkState.currentFrame]},
        .pWaitDstStageMask = &[_]vk.VkPipelineStageFlags{vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT},
        .commandBufferCount = 1,
        .pCommandBuffers = &vkState.command_buffer[vkState.currentFrame],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &[_]vk.VkSemaphore{vkState.renderFinishedSemaphore[vkState.currentFrame]},
    };
    try vkcheck(vk.vkQueueSubmit(vkState.queue, 1, &submitInfo, vkState.inFlightFence[vkState.currentFrame]), "Failed to Queue Submit.");

    var presentInfo = vk.VkPresentInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &[_]vk.VkSemaphore{vkState.renderFinishedSemaphore[vkState.currentFrame]},
        .swapchainCount = 1,
        .pSwapchains = &[_]vk.VkSwapchainKHR{vkState.swapchain},
        .pImageIndices = &imageIndex,
    };
    try vkcheck(vk.vkQueuePresentKHR(vkState.queue, &presentInfo), "Failed to Queue Present KHR.");
    vkState.currentFrame = (vkState.currentFrame + 1) % Vk_State.MAX_FRAMES_IN_FLIGHT;
}

fn createSyncObjects(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    var semaphoreInfo = vk.VkSemaphoreCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    var fenceInfo = vk.VkFenceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    vkState.imageAvailableSemaphore = try allocator.alloc(vk.VkSemaphore, Vk_State.MAX_FRAMES_IN_FLIGHT);
    vkState.renderFinishedSemaphore = try allocator.alloc(vk.VkSemaphore, Vk_State.MAX_FRAMES_IN_FLIGHT);
    vkState.inFlightFence = try allocator.alloc(vk.VkFence, Vk_State.MAX_FRAMES_IN_FLIGHT);

    for (0..Vk_State.MAX_FRAMES_IN_FLIGHT) |i| {
        if (vk.vkCreateSemaphore(vkState.logicalDevice, &semaphoreInfo, null, &vkState.imageAvailableSemaphore[i]) != vk.VK_SUCCESS or
            vk.vkCreateSemaphore(vkState.logicalDevice, &semaphoreInfo, null, &vkState.renderFinishedSemaphore[i]) != vk.VK_SUCCESS or
            vk.vkCreateFence(vkState.logicalDevice, &fenceInfo, null, &vkState.inFlightFence[i]) != vk.VK_SUCCESS)
        {
            std.debug.print("Failed to Create Semaphore or Create Fence.\n", .{});
            return error.FailedToCreateSyncObjects;
        }
    }
}

fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, imageIndex: u32, state: *main.ChatSimState) !void {
    const vkState = &state.vkState;
    var beginInfo = vk.VkCommandBufferBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    };
    try vkcheck(vk.vkBeginCommandBuffer(commandBuffer, &beginInfo), "Failed to Begin Command Buffer.");

    const renderPassInfo = vk.VkRenderPassBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = vkState.render_pass,
        .framebuffer = vkState.framebuffers[imageIndex],
        .renderArea = vk.VkRect2D{
            .offset = vk.VkOffset2D{ .x = 0, .y = 0 },
            .extent = vkState.swapchain_info.extent,
        },
        .clearValueCount = 1,
        .pClearValues = &[_]vk.VkClearValue{.{ .color = vk.VkClearColorValue{ .float32 = [_]f32{ 63.0 / 256.0, 155.0 / 256.0, 11.0 / 256.0, 1.0 } } }},
    };
    vk.vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, vk.VK_SUBPASS_CONTENTS_INLINE);
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.graphics_pipeline);
    var viewport = vk.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(vkState.swapchain_info.extent.width),
        .height = @floatFromInt(vkState.swapchain_info.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vk.vkCmdSetViewport(commandBuffer, 0, 1, &viewport);
    var scissor = vk.VkRect2D{
        .offset = vk.VkOffset2D{ .x = 0, .y = 0 },
        .extent = vkState.swapchain_info.extent,
    };
    vk.vkCmdSetScissor(commandBuffer, 0, 1, &scissor);
    const vertexBuffers: [1]vk.VkBuffer = .{vkState.vertexBuffer};
    const offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdBindDescriptorSets(
        commandBuffer,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        vkState.pipeline_layout,
        0,
        1,
        &vkState.descriptorSets[vkState.currentFrame],
        0,
        null,
    );

    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.entityPaintCount), 1, 0, 0);
    try rectangleVulkanZig.recordRectangleCommandBuffer(commandBuffer, state);
    try fontVulkanZig.recordFontCommandBuffer(commandBuffer, state);
    vk.vkCmdEndRenderPass(commandBuffer);
    try vkcheck(vk.vkEndCommandBuffer(commandBuffer), "Failed to End Command Buffer.");
}

fn createCommandBuffers(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    vkState.command_buffer = try allocator.alloc(vk.VkCommandBuffer, Vk_State.MAX_FRAMES_IN_FLIGHT);

    var allocInfo = vk.VkCommandBufferAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = vkState.command_pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(vkState.command_buffer.len),
    };
    try vkcheck(vk.vkAllocateCommandBuffers(vkState.logicalDevice, &allocInfo, &vkState.command_buffer[0]), "Failed to create Command Pool.");
    std.debug.print("Command Buffer : {any}\n", .{vkState.command_buffer});
}

fn createCommandPool(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    const queueFamilyIndices = try findQueueFamilies(vkState.physical_device, vkState, allocator);
    var poolInfo = vk.VkCommandPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queueFamilyIndices.graphicsFamily.?,
    };
    try vkcheck(vk.vkCreateCommandPool(vkState.logicalDevice, &poolInfo, null, &vkState.command_pool), "Failed to create Command Pool.");
    std.debug.print("Command Pool : {any}\n", .{vkState.command_pool});
}

fn createFramebuffers(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    vkState.framebuffers = try allocator.alloc(vk.VkFramebuffer, vkState.swapchain_imageviews.len);

    for (vkState.swapchain_imageviews, 0..) |imageView, i| {
        var attachments = [_]vk.VkImageView{ vkState.colorImageView, imageView };
        var framebufferInfo = vk.VkFramebufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = vkState.render_pass,
            .attachmentCount = attachments.len,
            .pAttachments = &attachments,
            .width = vkState.swapchain_info.extent.width,
            .height = vkState.swapchain_info.extent.height,
            .layers = 1,
        };
        try vkcheck(vk.vkCreateFramebuffer(vkState.logicalDevice, &framebufferInfo, null, &vkState.framebuffers[i]), "Failed to create Framebuffer.");
        std.debug.print("Framebuffer Created : {any}\n", .{vkState.pipeline_layout});
    }
}

fn createRenderPass(vkState: *Vk_State) !void {
    const colorAttachment = vk.VkAttachmentDescription{
        .format = vkState.swapchain_info.format.format,
        .samples = vkState.msaaSamples,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    var colorAttachmentRef = vk.VkAttachmentReference{
        .attachment = 0,
        .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    const colorAttachmentResolve: vk.VkAttachmentDescription = .{
        .format = vkState.swapchain_info.format.format,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };
    var colorAttachmentResolveRef = vk.VkAttachmentReference{
        .attachment = 1,
        .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    var subpass = vk.VkSubpassDescription{
        .pipelineBindPoint = vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorAttachmentRef,
        .pResolveAttachments = &colorAttachmentResolveRef,
    };

    const attachments = [_]vk.VkAttachmentDescription{ colorAttachment, colorAttachmentResolve };
    var renderPassInfo = vk.VkRenderPassCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = attachments.len,
        .pAttachments = &attachments,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 0,
        .pDependencies = null,
    };
    try vkcheck(vk.vkCreateRenderPass(vkState.logicalDevice, &renderPassInfo, null, &vkState.render_pass), "Failed to create Render Pass.");
    std.debug.print("Render Pass Created : {any}\n", .{vkState.render_pass});
}

fn createGraphicsPipeline(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    const vertShaderCode = try readShaderFile("shaders/compiled/vert.spv", allocator);
    defer allocator.free(vertShaderCode);
    const fragShaderCode = try readShaderFile("shaders/compiled/frag.spv", allocator);
    defer allocator.free(fragShaderCode);
    const geomShaderCode = try readShaderFile("shaders/compiled/geom.spv", allocator);
    defer allocator.free(geomShaderCode);
    const vertShaderModule = try createShaderModule(vertShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, vertShaderModule, null);
    const fragShaderModule = try createShaderModule(fragShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, fragShaderModule, null);
    const geomShaderModule = try createShaderModule(geomShaderCode, vkState);
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
    const bindingDescription = Vertex.getBindingDescription();
    const attributeDescriptions = Vertex.getAttributeDescriptions();
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
    try vkcheck(vk.vkCreatePipelineLayout(vkState.logicalDevice, &pipelineLayoutInfo, null, &vkState.pipeline_layout), "Failed to create pipeline layout.");
    std.debug.print("Pipeline Layout Created : {any}\n", .{vkState.pipeline_layout});

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
    try vkcheck(vk.vkCreateGraphicsPipelines(vkState.logicalDevice, null, 1, &pipelineInfo, null, &vkState.graphics_pipeline), "Failed to create graphics pipeline.");
    std.debug.print("Graphics Pipeline Created : {any}\n", .{vkState.pipeline_layout});
}

pub fn createShaderModule(code: []const u8, vkState: *Vk_State) !vk.VkShaderModule {
    var createInfo = vk.VkShaderModuleCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = @alignCast(@ptrCast(code.ptr)),
    };
    var shaderModule: vk.VkShaderModule = undefined;
    try vkcheck(vk.vkCreateShaderModule(vkState.logicalDevice, &createInfo, null, &shaderModule), "Failed to create Shader Module.");
    std.debug.print("Shader Module Created : {any}\n", .{shaderModule});
    return shaderModule;
}

fn createImageViews(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    vkState.swapchain_imageviews = try allocator.alloc(vk.VkImageView, vkState.swapchain_info.images.len);
    for (vkState.swapchain_info.images, 0..) |image, i| {
        vkState.swapchain_imageviews[i] = try createImageView(image, vkState.swapchain_info.format.format, 1, vkState);
        std.debug.print("Swapchain ImageView Created : {any}\n", .{vkState.swapchain_imageviews[i]});
    }
}

fn createSwapChain(vkState: *Vk_State, allocator: std.mem.Allocator) !void {
    vkState.swapchain_info.support = try querySwapChainSupport(vkState, allocator);
    vkState.swapchain_info.format = chooseSwapSurfaceFormat(vkState.swapchain_info.support.formats);
    vkState.swapchain_info.present = chooseSwapPresentMode(vkState.swapchain_info.support.presentModes);
    vkState.swapchain_info.extent = chooseSwapExtent(vkState.swapchain_info.support.capabilities);

    var imageCount = vkState.swapchain_info.support.capabilities.minImageCount + 1;
    if (vkState.swapchain_info.support.capabilities.maxImageCount > 0 and imageCount > vkState.swapchain_info.support.capabilities.maxImageCount) {
        imageCount = vkState.swapchain_info.support.capabilities.maxImageCount;
    }

    var createInfo = vk.VkSwapchainCreateInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = vkState.surface,
        .minImageCount = imageCount,
        .imageFormat = vkState.swapchain_info.format.format,
        .imageColorSpace = vkState.swapchain_info.format.colorSpace,
        .imageExtent = vkState.swapchain_info.extent,
        .imageArrayLayers = 1,
        .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = vkState.swapchain_info.support.capabilities.currentTransform,
        .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = vkState.swapchain_info.present,
        .clipped = vk.VK_TRUE,
        .oldSwapchain = null,
    };

    const indices = try findQueueFamilies(vkState.physical_device, vkState, allocator);
    const queueFamilyIndices = [_]u32{ indices.graphicsFamily.?, indices.presentFamily.? };
    if (indices.graphicsFamily != indices.presentFamily) {
        createInfo.imageSharingMode = vk.VK_SHARING_MODE_CONCURRENT;
        createInfo.queueFamilyIndexCount = 2;
        createInfo.pQueueFamilyIndices = &queueFamilyIndices;
    } else {
        createInfo.imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE;
    }

    try vkcheck(vk.vkCreateSwapchainKHR(vkState.logicalDevice, &createInfo, null, &vkState.swapchain), "Failed to create swapchain KHR");
    std.debug.print("Swapchain KHR Created : {any}\n", .{vkState.logicalDevice});

    _ = vk.vkGetSwapchainImagesKHR(vkState.logicalDevice, vkState.swapchain, &imageCount, null);
    vkState.swapchain_info.images = try allocator.alloc(vk.VkImage, imageCount);
    _ = vk.vkGetSwapchainImagesKHR(vkState.logicalDevice, vkState.swapchain, &imageCount, vkState.swapchain_info.images.ptr);
}

fn querySwapChainSupport(vkState: *Vk_State, allocator: std.mem.Allocator) !SwapChainSupportDetails {
    var details = SwapChainSupportDetails{
        .capabilities = undefined,
        .formats = &.{},
        .presentModes = &.{},
    };

    var formatCount: u32 = 0;
    var presentModeCount: u32 = 0;
    _ = vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vkState.physical_device, vkState.surface, &details.capabilities);
    _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(vkState.physical_device, vkState.surface, &formatCount, null);
    if (formatCount > 0) {
        details.formats = try allocator.alloc(vk.VkSurfaceFormatKHR, formatCount);
        _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(vkState.physical_device, vkState.surface, &formatCount, details.formats.ptr);
    }
    _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(vkState.physical_device, vkState.surface, &presentModeCount, null);
    if (presentModeCount > 0) {
        details.presentModes = try allocator.alloc(vk.VkPresentModeKHR, presentModeCount);
        _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(vkState.physical_device, vkState.surface, &presentModeCount, details.presentModes.ptr);
    }
    return details;
}

fn chooseSwapSurfaceFormat(formats: []const vk.VkSurfaceFormatKHR) vk.VkSurfaceFormatKHR {
    for (formats) |format| {
        if (format.format == vk.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }
    return formats[0];
}

fn chooseSwapPresentMode(present_modes: []const vk.VkPresentModeKHR) vk.VkPresentModeKHR {
    for (present_modes) |mode| {
        if (mode == vk.VK_PRESENT_MODE_MAILBOX_KHR) {
            return mode;
        }
    }
    return vk.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseSwapExtent(capabilities: vk.VkSurfaceCapabilitiesKHR) vk.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        var width: u32 = 0;
        var height: u32 = 0;
        windowSdlZig.getWindowSize(&width, &height);
        var actual_extent = vk.VkExtent2D{
            .width = width,
            .height = height,
        };
        actual_extent.width = std.math.clamp(actual_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
        actual_extent.height = std.math.clamp(actual_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);
        return actual_extent;
    }
}

fn checkValidationLayerSupport(allocator: std.mem.Allocator) bool {
    var layer_count: u32 = 0;
    _ = vk.vkEnumerateInstanceLayerProperties(&layer_count, null);

    const available_layers = allocator.alloc(vk.VkLayerProperties, layer_count) catch unreachable;
    defer allocator.free(available_layers);
    _ = vk.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

    std.debug.print("Validation check, searching: \n", .{});
    for (validation_layers) |layer_name| {
        const layer_name_span = std.mem.span(layer_name);
        const layer_name_len = layer_name_span.len;
        std.debug.print("  {s}\nValidation properties list :\n", .{layer_name_span});
        var found: bool = false;
        for (available_layers) |layer_properties| {
            std.debug.print("  {s}\n", .{layer_properties.layerName});
            const prop_name_len = std.mem.indexOf(u8, layer_properties.layerName[0..], &[_]u8{0}) orelse 256;
            if (layer_name_len == prop_name_len) {
                std.debug.print("Found:\n  {s}\n", .{&layer_properties.layerName});
                if (std.mem.eql(u8, layer_name_span, layer_properties.layerName[0..prop_name_len])) {
                    found = true;
                    break;
                }
            }
        }
        if (!found) return false;
    }
    return true;
}

fn createLogicalDevice(physical_device: vk.VkPhysicalDevice, vkState: *Vk_State) !void {
    var queue_create_info = vk.VkDeviceQueueCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = vkState.graphics_queue_family_idx,
        .queueCount = 1,
        .pQueuePriorities = &[_]f32{1.0},
    };
    const device_features = vk.VkPhysicalDeviceFeatures{
        .samplerAnisotropy = vk.VK_TRUE,
        .geometryShader = vk.VK_TRUE,
        .fillModeNonSolid = vk.VK_TRUE,
    };
    var vk12Features = vk.VkPhysicalDeviceVulkan12Features{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .shaderSampledImageArrayNonUniformIndexing = vk.VK_TRUE,
        .runtimeDescriptorArray = vk.VK_TRUE,
    };
    var deviceFeatures: vk.VkPhysicalDeviceFeatures2 = .{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        .pNext = &vk12Features,
        .features = device_features,
    };
    var device_create_info = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &deviceFeatures,
        .pQueueCreateInfos = &queue_create_info,
        .queueCreateInfoCount = 1,
        .pEnabledFeatures = null,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = &[_][*c]const u8{vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME},
    };
    device_create_info.enabledLayerCount = 1;
    device_create_info.ppEnabledLayerNames = &validation_layers;
    try vkcheck(vk.vkCreateDevice(physical_device, &device_create_info, null, &vkState.logicalDevice), "Failed to create logical device");
    std.debug.print("Logical Device Created : {any}\n", .{vkState.logicalDevice});
    vk.vkGetDeviceQueue(vkState.logicalDevice, vkState.graphics_queue_family_idx, 0, &vkState.queue);
    std.debug.print("Queue Obtained : {any}\n", .{vkState.queue});
}

fn pickPhysicalDevice(instance: vk.VkInstance, vkState: *Vk_State, allocator: std.mem.Allocator) !vk.VkPhysicalDevice {
    var device_count: u32 = 0;
    try vkcheck(vk.vkEnumeratePhysicalDevices(instance, &device_count, null), "Failed to enumerate physical devices");
    if (device_count == 0) {
        return error.NoGPUsWithVulkanSupport;
    }

    const devices = try allocator.alloc(vk.VkPhysicalDevice, device_count);
    defer allocator.free(devices);
    try vkcheck(vk.vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr), "Failed to enumerate physical devices");

    for (devices) |device| {
        if (try isDeviceSuitable(device, vkState, allocator)) {
            vkState.msaaSamples = getMaxUsableSampleCount(device);
            return device;
        }
    }
    return error.NoSuitableGPU;
}
fn isDeviceSuitable(device: vk.VkPhysicalDevice, vkState: *Vk_State, allocator: std.mem.Allocator) !bool {
    const indices: QueueFamilyIndices = try findQueueFamilies(device, vkState, allocator);
    vkState.graphics_queue_family_idx = indices.graphicsFamily.?;

    var supportedFeatures: vk.VkPhysicalDeviceFeatures = undefined;
    vk.vkGetPhysicalDeviceFeatures(device, &supportedFeatures);

    return indices.isComplete() and supportedFeatures.samplerAnisotropy != 0 and supportedFeatures.geometryShader != 0;
}

fn findQueueFamilies(device: vk.VkPhysicalDevice, vkState: *Vk_State, allocator: std.mem.Allocator) !QueueFamilyIndices {
    var indices = QueueFamilyIndices{
        .graphicsFamily = null,
        .presentFamily = null,
    };
    var queueFamilyCount: u32 = 0;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);

    const queueFamilies = try allocator.alloc(vk.VkQueueFamilyProperties, queueFamilyCount);
    defer allocator.free(queueFamilies);
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);

    for (queueFamilies, 0..) |queueFamily, i| {
        if (queueFamily.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
            indices.graphicsFamily = @intCast(i);
        }
        var presentSupport: vk.VkBool32 = vk.VK_FALSE;
        _ = vk.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), vkState.surface, &presentSupport);
        if (presentSupport == vk.VK_TRUE) {
            indices.presentFamily = @intCast(i);
        }
        if (indices.isComplete()) {
            break;
        }
    }
    return indices;
}

const QueueFamilyIndices = struct {
    graphicsFamily: ?u32,
    presentFamily: ?u32,

    fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphicsFamily != null;
    }
};

fn vkcheck(result: vk.VkResult, comptime err_msg: []const u8) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error : {s}\n", .{err_msg});
        return error.VulkanError;
    }
}

pub fn readShaderFile(filename: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const code = try std.fs.cwd().readFileAlloc(allocator, filename, std.math.maxInt(usize));
    return code;
}
