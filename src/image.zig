const std = @import("std");
const zigimg = @import("zigimg");
const vulkan = @import("vulkan/paintVulkan.zig");
const vk = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", "1");
    @cInclude("vulkan.h");
});

pub const IMAGE_DOG = 0;
pub const IMAGE_TREE = 1;
pub const IMAGE_HOUSE = 2;
pub const IMAGE_WHITE_RECTANGLE = 3;
pub const IMAGE_GREEN_RECTANGLE = 4;
pub const IMAGE_TREE_FARM = 5;

pub const ImageData = struct {
    path: []const u8,
};

pub const IMAGE_DATA = [_]ImageData{
    .{ .path = "images/dog.png" },
    .{ .path = "images/tree.png" },
    .{ .path = "images/house.png" },
    .{ .path = "images/whiteRectangle.png" },
    .{ .path = "images/greenRectangle.png" },
    .{ .path = "images/treeFarm.png" },
};

pub fn createVulkanTextureImage(vkState: *vulkan.Vk_State, allocator: std.mem.Allocator) !void {
    vkState.textureImage = try allocator.alloc(vk.VkImage, IMAGE_DATA.len);
    vkState.textureImageMemory = try allocator.alloc(vk.VkDeviceMemory, IMAGE_DATA.len);
    vkState.mipLevels = try allocator.alloc(u32, IMAGE_DATA.len);

    for (0..IMAGE_DATA.len) |i| {
        var image = try zigimg.Image.fromFilePath(std.heap.page_allocator, IMAGE_DATA[i].path);
        defer image.deinit();
        try image.convert(.rgba32);

        var stagingBuffer: vk.VkBuffer = undefined;
        defer vk.vkDestroyBuffer(vkState.logicalDevice, stagingBuffer, null);
        var stagingBufferMemory: vk.VkDeviceMemory = undefined;
        defer vk.vkFreeMemory(vkState.logicalDevice, stagingBufferMemory, null);
        try vulkan.createBuffer(
            image.imageByteSize(),
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &stagingBuffer,
            &stagingBufferMemory,
            vkState,
        );

        var data: ?*anyopaque = undefined;
        if (vk.vkMapMemory(vkState.logicalDevice, stagingBufferMemory, 0, image.imageByteSize(), 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
        @memcpy(
            @as([*]u8, @ptrCast(data))[0..image.imageByteSize()],
            @as([*]u8, @ptrCast(image.pixels.asBytes())),
        );
        vk.vkUnmapMemory(vkState.logicalDevice, stagingBufferMemory);
        const imageWidth: u32 = @intCast(image.width);
        const imageHeight: u32 = @intCast(image.height);
        const log2: f32 = @log2(@as(f32, @floatFromInt(@max(imageWidth, imageHeight))));
        vkState.mipLevels[i] = @as(u32, @intFromFloat(log2)) + 1;
        try vulkan.createImage(
            imageWidth,
            imageHeight,
            vkState.mipLevels[i],
            vk.VK_SAMPLE_COUNT_1_BIT,
            vk.VK_FORMAT_R8G8B8A8_SRGB,
            vk.VK_IMAGE_TILING_OPTIMAL,
            vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &vkState.textureImage[i],
            &vkState.textureImageMemory[i],
            vkState,
        );

        try transitionVulkanImageLayout(
            vkState.textureImage[i],
            vk.VK_IMAGE_LAYOUT_UNDEFINED,
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            vkState.mipLevels[i],
            vkState,
        );
        try copyBufferToImage(stagingBuffer, vkState.textureImage[i], imageWidth, imageHeight, vkState);
        try generateVulkanMipmaps(
            vkState.textureImage[i],
            vk.VK_FORMAT_R8G8B8A8_SRGB,
            @intCast(imageWidth),
            @intCast(imageHeight),
            vkState.mipLevels[i],
            vkState,
        );
    }
    std.debug.print("createVulkanTextureImage finished\n", .{});
}

fn generateVulkanMipmaps(image: vk.VkImage, imageFormat: vk.VkFormat, texWidth: i32, texHeight: i32, mipLevels: u32, vkState: *vulkan.Vk_State) !void {
    var formatProperties: vk.VkFormatProperties = undefined;
    vk.vkGetPhysicalDeviceFormatProperties(vkState.physical_device, imageFormat, &formatProperties);

    if ((formatProperties.optimalTilingFeatures & vk.VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT) == 0) return error.doesNotSupportOptimailTiling;

    const commandBuffer: vk.VkCommandBuffer = try vulkan.beginSingleTimeCommands(vkState);

    var barrier: vk.VkImageMemoryBarrier = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .image = image,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .levelCount = 1,
        },
    };
    var mipWidth: i32 = texWidth;
    var mipHeight: i32 = texHeight;

    for (1..mipLevels) |i| {
        barrier.subresourceRange.baseMipLevel = @as(u32, @intCast(i)) - 1;
        barrier.oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = vk.VK_ACCESS_TRANSFER_READ_BIT;

        vk.vkCmdPipelineBarrier(
            commandBuffer,
            vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &barrier,
        );

        const blit: vk.VkImageBlit = .{
            .srcOffsets = .{
                .{ .x = 0, .y = 0, .z = 0 },
                .{ .x = mipWidth, .y = mipHeight, .z = 1 },
            },
            .srcSubresource = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = @as(u32, @intCast(i)) - 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .dstOffsets = .{
                .{ .x = 0, .y = 0, .z = 0 },
                .{ .x = if (mipWidth > 1) @divFloor(mipWidth, 2) else 1, .y = if (mipHeight > 1) @divFloor(mipHeight, 2) else 1, .z = 1 },
            },
            .dstSubresource = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = @as(u32, @intCast(i)),
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        vk.vkCmdBlitImage(
            commandBuffer,
            image,
            vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            image,
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &blit,
            vk.VK_FILTER_LINEAR,
        );
        barrier.oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_READ_BIT;
        barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;

        vk.vkCmdPipelineBarrier(
            commandBuffer,
            vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &barrier,
        );
        if (mipWidth > 1) mipWidth = @divFloor(mipWidth, 2);
        if (mipHeight > 1) mipHeight = @divFloor(mipHeight, 2);
    }

    barrier.subresourceRange.baseMipLevel = mipLevels - 1;
    barrier.oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;

    vk.vkCmdPipelineBarrier(
        commandBuffer,
        vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
        vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        0,
        0,
        null,
        0,
        null,
        1,
        &barrier,
    );

    try vulkan.endSingleTimeCommands(commandBuffer, vkState);
}

fn copyBufferToImage(buffer: vk.VkBuffer, image: vk.VkImage, width: u32, height: u32, vkState: *vulkan.Vk_State) !void {
    const commandBuffer: vk.VkCommandBuffer = try vulkan.beginSingleTimeCommands(vkState);
    const region: vk.VkBufferImageCopy = .{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = width, .height = height, .depth = 1 },
    };
    vk.vkCmdCopyBufferToImage(
        commandBuffer,
        buffer,
        image,
        vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &region,
    );

    try vulkan.endSingleTimeCommands(commandBuffer, vkState);
}

fn transitionVulkanImageLayout(image: vk.VkImage, oldLayout: vk.VkImageLayout, newLayout: vk.VkImageLayout, mipLevels: u32, vkState: *vulkan.Vk_State) !void {
    const commandBuffer = try vulkan.beginSingleTimeCommands(vkState);

    var barrier: vk.VkImageMemoryBarrier = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = oldLayout,
        .newLayout = newLayout,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = mipLevels,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .srcAccessMask = 0,
        .dstAccessMask = 0,
    };

    var sourceStage: vk.VkPipelineStageFlags = undefined;
    var destinationStage: vk.VkPipelineStageFlags = undefined;

    if (oldLayout == vk.VK_IMAGE_LAYOUT_UNDEFINED and newLayout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;

        sourceStage = vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destinationStage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (oldLayout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and newLayout == vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;

        sourceStage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
        destinationStage = vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else {
        return error.unsuportetLayoutTransition;
    }

    vk.vkCmdPipelineBarrier(
        commandBuffer,
        sourceStage,
        destinationStage,
        0,
        0,
        null,
        0,
        null,
        1,
        &barrier,
    );
    try vulkan.endSingleTimeCommands(commandBuffer, vkState);
}
