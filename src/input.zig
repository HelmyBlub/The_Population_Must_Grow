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
    speedUp,
    speedDown,
    zoomIn,
    zoomOut,
    cameraToWorldCenter,
};

pub const KeyboardInfo = struct {
    cameraMoveX: f32 = 0,
    cameraMoveY: f32 = 0,
    keybindings: []KeyBinding = undefined,
};

pub const KeyBinding = struct {
    sdlScanCode: c_int,
    action: ActionType,
    displayChar: u8,
};

pub fn initDefaultKeyBindings(state: *main.GameState) !void {
    state.keyboardInfo.keybindings = try state.allocator.alloc(KeyBinding, 12);
    state.keyboardInfo.keybindings[0] = .{ .sdlScanCode = sdl.SDL_SCANCODE_1, .displayChar = '1', .action = ActionType.buildPath };
    state.keyboardInfo.keybindings[1] = .{ .sdlScanCode = sdl.SDL_SCANCODE_2, .displayChar = '2', .action = ActionType.buildHouse };
    state.keyboardInfo.keybindings[2] = .{ .sdlScanCode = sdl.SDL_SCANCODE_3, .displayChar = '3', .action = ActionType.buildTreeArea };
    state.keyboardInfo.keybindings[3] = .{ .sdlScanCode = sdl.SDL_SCANCODE_4, .displayChar = '4', .action = ActionType.buildHouseArea };
    state.keyboardInfo.keybindings[4] = .{ .sdlScanCode = sdl.SDL_SCANCODE_5, .displayChar = '5', .action = ActionType.buildPotatoFarmArea };
    state.keyboardInfo.keybindings[5] = .{ .sdlScanCode = sdl.SDL_SCANCODE_6, .displayChar = '6', .action = ActionType.copyPaste };
    state.keyboardInfo.keybindings[6] = .{ .sdlScanCode = sdl.SDL_SCANCODE_7, .displayChar = '7', .action = ActionType.buildBigHouseArea };
    state.keyboardInfo.keybindings[7] = .{ .sdlScanCode = sdl.SDL_SCANCODE_9, .displayChar = '9', .action = ActionType.remove };
    state.keyboardInfo.keybindings[8] = .{ .sdlScanCode = sdl.SDL_SCANCODE_KP_PLUS, .displayChar = '+', .action = ActionType.speedUp };
    state.keyboardInfo.keybindings[9] = .{ .sdlScanCode = sdl.SDL_SCANCODE_KP_MINUS, .displayChar = '-', .action = ActionType.speedDown };
    state.keyboardInfo.keybindings[10] = .{ .sdlScanCode = sdl.SDL_SCANCODE_KP_0, .displayChar = '+', .action = ActionType.zoomIn };
    state.keyboardInfo.keybindings[11] = .{ .sdlScanCode = sdl.SDL_SCANCODE_KP_1, .displayChar = '-', .action = ActionType.zoomOut };
}

pub fn destroy(state: *main.GameState) void {
    state.allocator.free(state.keyboardInfo.keybindings);
}

pub fn tick(state: *main.GameState) void {
    const keyboardInfo = state.keyboardInfo;
    if (keyboardInfo.cameraMoveX != 0) {
        state.camera.position.x += keyboardInfo.cameraMoveX / state.camera.zoom;
    }
    if (keyboardInfo.cameraMoveY != 0) {
        state.camera.position.y += keyboardInfo.cameraMoveY / state.camera.zoom;
    }
    main.limitCameraArea(state);
}

pub fn executeAction(actionType: ActionType, state: *main.GameState) !void {
    var buildModeChanged = false;
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
        .speedUp => {
            main.setGameSpeed(state.desiredGameSpeed * 2, state);
        },
        .speedDown => {
            main.setGameSpeed(state.desiredGameSpeed / 2, state);
        },
        .zoomIn => {
            main.setZoom(state.camera.zoom * 1.2, state, false);
        },
        .zoomOut => {
            main.setZoom(state.camera.zoom * 0.8, state, false);
        },
        .cameraToWorldCenter => {
            state.camera.position = .{ .x = 0, .y = 0 };
        },
    }
    if (buildModeChanged) {
        try buildOptionsUxVulkanZig.setSelectedButtonIndex(actionType, state);
        state.copyAreaRectangle = null;
        state.mouseInfo.leftButtonMapDown = null;
        state.rectangles[0] = null;
    }
}

pub fn executeActionByKeybind(sdlScanCode: c_uint, state: *main.GameState) !void {
    var optActionType: ?ActionType = null;
    for (state.keyboardInfo.keybindings) |keybind| {
        if (keybind.sdlScanCode == sdlScanCode) {
            optActionType = keybind.action;
            break;
        }
    }
    if (optActionType) |actionType| try executeAction(actionType, state);
}
