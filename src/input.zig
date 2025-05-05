const std = @import("std");
const main = @import("main.zig");
const mapZig = @import("map.zig");
const buildOptionsUxVulkanZig = @import("vulkan/buildOptionsUxVulkan.zig");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

pub const ActionType = enum {
    buildHouse,
    buildHouseArea,
    buildBigHouseArea,
    buildTreeArea,
    buildPotatoFarmArea,
    copyPaste,
    buildPath,
    remove,
};

pub const KeyBinding = struct {
    sdlScanCode: c_int,
    action: ActionType,
    displayChar: u8,
};

pub fn initDefaultKeyBindings(state: *main.ChatSimState) !void {
    state.keybindings = try state.allocator.alloc(KeyBinding, 8);
    state.keybindings[0] = .{ .sdlScanCode = sdl.SDL_SCANCODE_1, .displayChar = '1', .action = ActionType.buildHouse };
    state.keybindings[1] = .{ .sdlScanCode = sdl.SDL_SCANCODE_2, .displayChar = '2', .action = ActionType.buildTreeArea };
    state.keybindings[2] = .{ .sdlScanCode = sdl.SDL_SCANCODE_3, .displayChar = '3', .action = ActionType.buildHouseArea };
    state.keybindings[3] = .{ .sdlScanCode = sdl.SDL_SCANCODE_4, .displayChar = '4', .action = ActionType.buildPotatoFarmArea };
    state.keybindings[4] = .{ .sdlScanCode = sdl.SDL_SCANCODE_5, .displayChar = '5', .action = ActionType.copyPaste };
    state.keybindings[5] = .{ .sdlScanCode = sdl.SDL_SCANCODE_6, .displayChar = '6', .action = ActionType.buildBigHouseArea };
    state.keybindings[6] = .{ .sdlScanCode = sdl.SDL_SCANCODE_7, .displayChar = '7', .action = ActionType.buildPath };
    state.keybindings[7] = .{ .sdlScanCode = sdl.SDL_SCANCODE_9, .displayChar = '9', .action = ActionType.remove };
}

pub fn destory(state: *main.ChatSimState) void {
    state.allocator.free(state.keybindings);
}

pub fn executeActionByKeybind(sdlScanCode: c_uint, state: *main.ChatSimState) !void {
    var optActionType: ?ActionType = null;
    for (state.keybindings) |keybind| {
        if (keybind.sdlScanCode == sdlScanCode) {
            optActionType = keybind.action;
            break;
        }
    }
    if (optActionType) |actionType| {
        var buildModeChanged = false;
        try buildOptionsUxVulkanZig.setSelectedButtonIndex(actionType, state);
        switch (actionType) {
            ActionType.buildHouse => {
                state.currentBuildType = mapZig.BUILD_TYPE_HOUSE;
                state.buildMode = mapZig.BUILD_MODE_SINGLE;
                buildModeChanged = true;
            },
            ActionType.buildTreeArea => {
                state.currentBuildType = mapZig.BUILD_TYPE_TREE_FARM;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            },
            ActionType.buildHouseArea => {
                state.currentBuildType = mapZig.BUILD_TYPE_HOUSE;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            },
            ActionType.buildPotatoFarmArea => {
                state.currentBuildType = mapZig.BUILD_TYPE_POTATO_FARM;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            },
            ActionType.copyPaste => {
                state.currentBuildType = mapZig.BUILD_TYPE_COPY_PASTE;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            },
            ActionType.buildBigHouseArea => {
                state.currentBuildType = mapZig.BUILD_TYPE_BIG_HOUSE;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            },
            ActionType.buildPath => {
                state.currentBuildType = mapZig.BUILD_TYPE_PATHES;
                state.buildMode = mapZig.BUILD_MODE_DRAW;
                buildModeChanged = true;
            },
            ActionType.remove => {
                state.currentBuildType = mapZig.BUILD_TYPE_DEMOLISH;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            },
        }
        if (buildModeChanged) {
            state.copyAreaRectangle = null;
            state.mapMouseDown = null;
            state.rectangles[0] = null;
        }
    }
}
