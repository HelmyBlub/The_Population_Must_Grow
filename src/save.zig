const std = @import("std");
const main = @import("main.zig");
const mapZig = @import("map.zig");
const imageZig = @import("image.zig");
const pathfindingZig = @import("pathfinding.zig");
const chunkAreaZig = @import("chunkArea.zig");
const citizenPopulationCounterUxZig = @import("vulkan/citizenPopulationCounterUxVulkan.zig");
const windowSdlZig = @import("windowSdl.zig");

pub const DEBUG_INFO_SAVE = false;
const SAFE_FILE_VERSION: u8 = 0;

const SAVE_EMPTY = 0;
const SAVE_PATH = 1;
const SAVE_TREE = 2;
const SAVE_TREE_AND_PATH = 3;
const SAVE_TREE_AND_BUILD_ORDER_BUILDING = 4;
const SAVE_TREE_AND_BUILD_ORDER_BIG_BUILDING = 5;
const SAVE_TREE_AND_BUILD_ORDER_POTATO = 6;
const SAVE_TREE_REGROW = 7;
const SAVE_TREE_BUILD_ORDER = 8;
const SAVE_TREE_GROWING = 9;
const SAVE_POTATO = 10;
const SAVE_POTATO_GROWING = 11;
const SAVE_POTATO_BUILD_ORDER = 12;
const SAVE_BUILDING = 13;
const SAVE_BUILDING_BUILD_ORDER = 14;
const SAVE_BIG_BUILDING = 15;
const SAVE_BIG_BUILDING_BUILD_ORDER = 16;
const SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_1 = 17;
const SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_2 = 18;
const SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_3 = 19;
const SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_4 = 20;
const SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE = 21;
const SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_1 = 22;
const SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_2 = 23;
const SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_3 = 24;
const SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_4 = 25;
const SAVE_BLOCKING = 26;
const FILE_NAME_GENERAL_DATA = "general.dat";

pub const SaveAndLoadThread = struct {
    thread: std.Thread,
    ///should only be set by main thread
    addDataIndex: usize,
    ///should only be set by saveAndLoad thread
    saveAndLoadThreadDataIndex: usize,
    data: [DATA_LEN]SaveAndLoadThreadData,
    pub const DATA_LEN = 3;
};

pub const LoadedChunksData = struct {
    chunks: []mapZig.MapChunk,
    areaKey: u64,
};

pub const SaveAndLoadThreadData = struct {
    loadAreaKey: std.ArrayList(u64),
    loadedAreaData: std.ArrayList(LoadedChunksData),
    saveAreaKey: std.ArrayList(u64),
};

pub fn createSaveAndLoadThread(state: *main.GameState) !void {
    state.saveAndLoadThread = .{
        .thread = try std.Thread.spawn(.{}, saveAndLoadThreadTick, .{state}),
        .saveAndLoadThreadDataIndex = 0,
        .addDataIndex = 1,
        .data = .{
            .{
                .loadAreaKey = std.ArrayList(u64).init(state.allocator),
                .saveAreaKey = std.ArrayList(u64).init(state.allocator),
                .loadedAreaData = std.ArrayList(LoadedChunksData).init(state.allocator),
            },
            .{
                .loadAreaKey = std.ArrayList(u64).init(state.allocator),
                .saveAreaKey = std.ArrayList(u64).init(state.allocator),
                .loadedAreaData = std.ArrayList(LoadedChunksData).init(state.allocator),
            },
            .{
                .loadAreaKey = std.ArrayList(u64).init(state.allocator),
                .saveAreaKey = std.ArrayList(u64).init(state.allocator),
                .loadedAreaData = std.ArrayList(LoadedChunksData).init(state.allocator),
            },
        },
    };
}

pub fn destroySaveAndLoadThread(state: *main.GameState) void {
    if (state.saveAndLoadThread) |*saveAndLoad| {
        saveAndLoad.thread.join();
        for (saveAndLoad.data) |data| {
            data.loadAreaKey.deinit();
            data.saveAreaKey.deinit();
            for (data.loadedAreaData.items) |area| {
                for (area.chunks) |*chunk| {
                    mapZig.destroyChunk(chunk);
                }
                state.allocator.free(area.chunks);
            }
            data.loadedAreaData.deinit();
        }
    }
}

fn saveAndLoadThreadTick(state: *main.GameState) !void {
    while (!state.gameEnd) {
        const currentData = &state.saveAndLoadThread.?.data[state.saveAndLoadThread.?.saveAndLoadThreadDataIndex];
        for (currentData.loadAreaKey.items) |areaKey| {
            const areaXY = chunkAreaZig.getAreaXyForKey(areaKey);
            if (DEBUG_INFO_SAVE) std.debug.print("request ", .{}); // load function will log more text
            var chunks: []mapZig.MapChunk = undefined;
            if ((state.testData == null or !state.testData.?.skipSaveAndLoad) and try chunkAreaFileExists(areaXY, state.allocator)) {
                chunks = try loadChunkAreaFromFile(areaXY, state);
            } else {
                chunks = try chunkAreaZig.createChunkAreaDataWhenNoFile(areaXY, state);
            }
            try currentData.loadedAreaData.append(.{ .chunks = chunks, .areaKey = areaKey });
        }
        currentData.loadAreaKey.clearRetainingCapacity();
        while (!state.gameEnd and state.saveAndLoadThread.?.addDataIndex == @mod(state.saveAndLoadThread.?.saveAndLoadThreadDataIndex + 1, SaveAndLoadThread.DATA_LEN)) {
            // wait for next to be ready
            std.time.sleep(10_000_000);
        }
        if (!state.gameEnd) state.saveAndLoadThread.?.saveAndLoadThreadDataIndex = @mod(state.saveAndLoadThread.?.saveAndLoadThreadDataIndex + 1, SaveAndLoadThread.DATA_LEN);
    }
}

fn getSavePath(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    const directory_path = try getSaveDirectoryPath(allocator);
    defer allocator.free(directory_path);
    try std.fs.cwd().makePath(directory_path);

    const full_path = try std.fs.path.join(allocator, &.{ directory_path, filename });
    return full_path;
}

fn getSaveDirectoryPath(allocator: std.mem.Allocator) ![]const u8 {
    const game_name = "ThePopulationMustGrow";
    const save_folder = "saves";

    const base_dir = try std.fs.getAppDataDir(allocator, game_name);
    defer allocator.free(base_dir);

    const directory_path = try std.fs.path.join(allocator, &.{ base_dir, save_folder });
    return directory_path;
}

fn getFileNameForAreaXy(areaXY: chunkAreaZig.ChunkAreaXY, allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const writer = buf.writer();
    try writer.print("region_{d}_{d}.dat", .{ areaXY.areaX, areaXY.areaY });

    return getSavePath(allocator, buf.items);
}

pub fn chunkAreaFileExists(areaXY: chunkAreaZig.ChunkAreaXY, allocator: std.mem.Allocator) !bool {
    const path = try getFileNameForAreaXy(areaXY, allocator);
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    defer file.close();
    return true;
}

pub fn saveGeneralDataToFile(state: *main.GameState) !void {
    if ((state.testData != null and state.testData.?.skipSaveAndLoad)) return;
    const filepath = try getSavePath(state.allocator, FILE_NAME_GENERAL_DATA);
    defer state.allocator.free(filepath);

    const file = try std.fs.cwd().createFile(filepath, .{ .truncate = true });
    defer file.close();

    const writer = file.writer();
    var citizenCounter = state.citizenCounter;
    for (state.threadData) |threadData| {
        citizenCounter += threadData.citizensAddedThisTick;
    }
    _ = try writer.writeByte(SAFE_FILE_VERSION);
    _ = try writer.writeInt(u64, citizenCounter, .little);
    _ = try writer.writeInt(u32, state.gameTimeMs, .little);
    _ = try writer.writeInt(u32, @bitCast(state.soundMixer.volume), .little);
    _ = try writer.writeByte(@intFromBool(state.vkState.settingsMenuUx.fullscreen.checked));

    var activeThreads = std.ArrayList(u64).init(state.allocator);
    defer activeThreads.deinit();

    for (state.threadData) |threadData| {
        for (threadData.chunkAreaKeys.items) |areaKey| {
            try activeThreads.append(areaKey);
        }
    }
    _ = try writer.writeInt(usize, activeThreads.items.len, .little);
    for (activeThreads.items) |item| {
        _ = try writer.writeInt(u64, item, .little);
    }
}

/// returns false if no file loaded
pub fn loadGeneralDataFromFile(state: *main.GameState) !bool {
    if ((state.testData != null and state.testData.?.skipSaveAndLoad)) return false;
    const filepath = try getSavePath(state.allocator, FILE_NAME_GENERAL_DATA);
    defer state.allocator.free(filepath);

    const file = std.fs.cwd().openFile(filepath, .{}) catch return false;
    defer file.close();

    const reader = file.reader();

    const safeFileVersion = try reader.readByte();
    if (safeFileVersion != SAFE_FILE_VERSION) {
        //here i could handle cases instead of returning false which ignores the file and will overwrite it
        return false;
    }
    state.citizenCounter = try reader.readInt(u64, .little);
    state.citizenCounterLastTick = state.citizenCounter;
    state.gameTimeMs = try reader.readInt(u32, .little);
    state.soundMixer.volume = @bitCast(try reader.readInt(u32, .little));
    state.vkState.settingsMenuUx.fullscreen.checked = (try reader.readByte()) == 1;
    if (state.vkState.settingsMenuUx.fullscreen.checked) {
        _ = windowSdlZig.toggleFullscreen();
    }

    const activeChunkAreaKeysLength: usize = try reader.readInt(usize, .little);
    for (0..activeChunkAreaKeysLength) |_| {
        const key = try reader.readInt(u64, .little);
        const areaXY = chunkAreaZig.getAreaXyForKey(key);
        try chunkAreaZig.putChunkArea(areaXY, key, 0, state);
    }
    citizenPopulationCounterUxZig.updateCountryPopulationIndexOnGameLoad(state);
    return true;
}

pub fn deleteSave(allocator: std.mem.Allocator) !void {
    const saveDirectory = try getSaveDirectoryPath(allocator);
    defer allocator.free(saveDirectory);

    var dir = try std.fs.cwd().openDir(saveDirectory, .{
        .access_sub_paths = false,
        .iterate = true,
    });
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            if (std.mem.startsWith(u8, entry.basename, "region_") or std.mem.eql(u8, entry.basename, FILE_NAME_GENERAL_DATA)) {
                try dir.deleteFile(entry.basename);
            }
        }
    }
}

pub fn decideIfUnloadAndSaveAreaKey(areaKey: u64, state: *main.GameState) bool {
    const areaXY = chunkAreaZig.getAreaXyForKey(areaKey);
    const neighborsXY = [_]chunkAreaZig.ChunkAreaXY{
        .{ .areaX = areaXY.areaX - 1, .areaY = areaXY.areaY },
        .{ .areaX = areaXY.areaX - 1, .areaY = areaXY.areaY - 1 },
        .{ .areaX = areaXY.areaX, .areaY = areaXY.areaY - 1 },
        .{ .areaX = areaXY.areaX + 1, .areaY = areaXY.areaY - 1 },
        .{ .areaX = areaXY.areaX + 1, .areaY = areaXY.areaY },
        .{ .areaX = areaXY.areaX + 1, .areaY = areaXY.areaY + 1 },
        .{ .areaX = areaXY.areaX, .areaY = areaXY.areaY + 1 },
        .{ .areaX = areaXY.areaX - 1, .areaY = areaXY.areaY + 1 },
    };
    for (neighborsXY) |neighborXY| {
        const neighborKey = chunkAreaZig.getKeyForAreaXY(neighborXY);
        if (state.chunkAreas.getPtr(neighborKey)) |neighborChunkArea| {
            if ((neighborChunkArea.idleTypeData != .idle and neighborChunkArea.chunks != null) or neighborChunkArea.visible) {
                return false;
            }
        }
    }
    return true;
}

pub fn saveChunkAreaToFile(chunkArea: *chunkAreaZig.ChunkArea, state: *main.GameState) !void {
    if ((state.testData != null and state.testData.?.skipSaveAndLoad)) return;
    if (chunkArea.chunks == null) {
        std.debug.print("should not happen. Tried to save chunkArea which is already unloaded.\n", .{});
        return;
    }
    if (DEBUG_INFO_SAVE) std.debug.print("save {d} {d}, {}\n", .{ chunkArea.areaXY.areaX, chunkArea.areaXY.areaY, state.gameTimeMs });
    const filepath = try getFileNameForAreaXy(chunkArea.areaXY, state.allocator);
    defer state.allocator.free(filepath);
    const file = try std.fs.cwd().createFile(filepath, .{ .truncate = true });
    defer file.close();
    const writer = file.writer();
    var writeValues: [chunkAreaZig.ChunkArea.SIZE * chunkAreaZig.ChunkArea.SIZE * mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH]u8 = undefined;
    for (0..writeValues.len) |index| {
        writeValues[index] = SAVE_EMPTY;
    }

    for (0..chunkAreaZig.ChunkArea.SIZE) |areaChunkX| {
        for (0..chunkAreaZig.ChunkArea.SIZE) |areaChunkY| {
            const chunkXY: mapZig.ChunkXY = .{
                .chunkX = (@as(i32, @intCast(areaChunkX)) + chunkArea.areaXY.areaX * chunkAreaZig.ChunkArea.SIZE),
                .chunkY = (@as(i32, @intCast(areaChunkY)) + chunkArea.areaXY.areaY * chunkAreaZig.ChunkArea.SIZE),
            };
            const writeValueChunkXyIndex: usize = (areaChunkX * chunkAreaZig.ChunkArea.SIZE + areaChunkY) * mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH;
            const chunkIndex = mapZig.getChunkIndexForChunkXY(chunkXY);
            const chunk = &chunkArea.chunks.?[chunkIndex];

            for (chunk.trees.items) |tree| {
                const writeValueIndex: usize = writeValueChunkXyIndex + positionToWriteIndexTilePart(tree.position);
                var writeValue: u8 = SAVE_TREE;
                if (tree.regrow) {
                    if (tree.growStartTimeMs == null and !tree.fullyGrown) {
                        writeValue = SAVE_TREE_BUILD_ORDER;
                    } else if (tree.growStartTimeMs != null) {
                        writeValue = SAVE_TREE_GROWING;
                    } else {
                        writeValue = SAVE_TREE_REGROW;
                    }
                }
                writeValues[writeValueIndex] = writeValue;
            }
            for (chunk.pathes.items) |path| {
                const writeValueIndex = writeValueChunkXyIndex + positionToWriteIndexTilePart(path);
                var writeValue: u8 = SAVE_PATH;
                if (writeValues[writeValueIndex] == SAVE_TREE) {
                    writeValue = SAVE_TREE_AND_PATH;
                }
                writeValues[writeValueIndex] = writeValue;
            }
            for (chunk.blockingTiles.items) |blockingTile| {
                const writeValueIndex = writeValueChunkXyIndex + tileXyToWriteIndexTilePart(blockingTile);
                writeValues[writeValueIndex] = SAVE_BLOCKING;
            }
            for (chunk.potatoFields.items) |potatoField| {
                const writeValueIndex = writeValueChunkXyIndex + positionToWriteIndexTilePart(potatoField.position);
                var writeValue: u8 = SAVE_POTATO;
                if (writeValues[writeValueIndex] == SAVE_TREE) {
                    writeValue = SAVE_TREE_AND_BUILD_ORDER_POTATO;
                } else if (potatoField.growStartTimeMs != null) {
                    writeValue = SAVE_POTATO_GROWING;
                } else if (!potatoField.fullyGrown) {
                    writeValue = SAVE_POTATO_BUILD_ORDER;
                }
                writeValues[writeValueIndex] = writeValue;
            }
            for (chunk.buildings.items) |building| {
                const writeValueIndex = writeValueChunkXyIndex + positionToWriteIndexTilePart(building.position);
                var writeValue: u8 = SAVE_BUILDING;
                if (writeValues[writeValueIndex] == SAVE_TREE) {
                    writeValue = SAVE_TREE_AND_BUILD_ORDER_BUILDING;
                } else if (building.inConstruction) {
                    writeValue = SAVE_BUILDING_BUILD_ORDER;
                }
                writeValues[writeValueIndex] = writeValue;
            }
            for (chunk.bigBuildings.items) |bigBuilding| {
                const writeValueIndex = writeValueChunkXyIndex + positionToWriteIndexTilePart(bigBuilding.position);
                var writeValue: u8 = SAVE_BIG_BUILDING;
                if (writeValues[writeValueIndex] == SAVE_TREE) {
                    writeValue = SAVE_TREE_AND_BUILD_ORDER_BIG_BUILDING;
                } else if (bigBuilding.inConstruction) {
                    if (bigBuilding.woodRequired <= 8) {
                        if (bigBuilding.citizensSpawned == 0) {
                            writeValue = SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE;
                        } else if (bigBuilding.citizensSpawned == 1) {
                            writeValue = SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_1;
                        } else if (bigBuilding.citizensSpawned == 2) {
                            writeValue = SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_2;
                        } else if (bigBuilding.citizensSpawned == 3) {
                            writeValue = SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_3;
                        } else {
                            writeValue = SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_4;
                        }
                    } else {
                        if (bigBuilding.citizensSpawned == 0) {
                            writeValue = SAVE_BIG_BUILDING_BUILD_ORDER;
                        } else if (bigBuilding.citizensSpawned == 1) {
                            writeValue = SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_1;
                        } else if (bigBuilding.citizensSpawned == 2) {
                            writeValue = SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_2;
                        } else if (bigBuilding.citizensSpawned == 3) {
                            writeValue = SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_3;
                        } else {
                            writeValue = SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_4;
                        }
                    }
                }
                writeValues[writeValueIndex] = writeValue;
            }
        }
    }
    try writer.writeAll(&writeValues);
}

fn handleActiveCitizensInChunkToUnload(chunk: *mapZig.MapChunk, areaXY: chunkAreaZig.ChunkAreaXY, state: *main.GameState) !void {
    for (chunk.citizens.items) |citizen| {
        if (citizen.nextThinkingAction != .idle) {
            try mapZig.handleDeleteCitizen(citizen, areaXY, state);
        }
    }
}

fn positionToWriteIndexTilePart(position: main.Position) usize {
    const tileXY = mapZig.mapPositionToTileXy(position);
    return tileXyToWriteIndexTilePart(tileXY);
}

fn tileXyToWriteIndexTilePart(tileXY: mapZig.TileXY) usize {
    const tileUsizeX: usize = @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH));
    const tileUsizeY: usize = @intCast(@mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH));
    return tileUsizeX * mapZig.GameMap.CHUNK_LENGTH + tileUsizeY;
}

pub fn saveAllChunkAreasBeforeQuit(state: *main.GameState) !void {
    if ((state.testData != null and state.testData.?.skipSaveAndLoad)) return;
    for (state.chunkAreas.values()) |*chunkArea| {
        if (chunkArea.chunks != null) {
            try saveChunkAreaToFile(chunkArea, state);
        }
    }
}

pub fn destroyChunksOfUnloadedArea(areaXY: chunkAreaZig.ChunkAreaXY, state: *main.GameState) !void {
    const areaKey = chunkAreaZig.getKeyForAreaXY(areaXY);
    const chunkArea = state.chunkAreas.getPtr(areaKey).?;
    for (chunkArea.chunks.?) |*toDestroyChunk| {
        try disconnectPathingBetweenChunkAreas(toDestroyChunk, state);
        try handleActiveCitizensInChunkToUnload(toDestroyChunk, areaXY, state);
        mapZig.destroyChunk(toDestroyChunk);
    }
    state.allocator.free(chunkArea.chunks.?);
    chunkArea.chunks = null;
}

pub fn loadChunkAreaFromFile(areaXY: chunkAreaZig.ChunkAreaXY, state: *main.GameState) ![]mapZig.MapChunk {
    const path = try getFileNameForAreaXy(areaXY, state.allocator);
    defer state.allocator.free(path);

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    if (DEBUG_INFO_SAVE) std.debug.print("loaded area {} {}, {d}\n", .{ areaXY.areaX, areaXY.areaY, state.gameTimeMs });
    const reader = file.reader();
    var readValues: [chunkAreaZig.ChunkArea.SIZE * chunkAreaZig.ChunkArea.SIZE * mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH]u8 = undefined;
    _ = try reader.readAll(&readValues);

    var currentChunkXY: mapZig.ChunkXY = .{ .chunkX = 0, .chunkY = 0 };
    var currentIndex: usize = mapZig.getChunkIndexForChunkXY(currentChunkXY);
    var currenChunk: ?mapZig.MapChunk = null;
    const chunks = try state.allocator.alloc(mapZig.MapChunk, chunkAreaZig.ChunkArea.SIZE * chunkAreaZig.ChunkArea.SIZE);
    var unknownLoadValue: ?u8 = null;
    for (readValues, 0..) |value, index| {
        const tileXYIndex = @mod(index, mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH);
        if (tileXYIndex == 0) {
            const chunkInAreaIndex = @divFloor(index, mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH);
            if (currenChunk) |chunk| {
                chunks[currentIndex] = chunk;
            }
            currentChunkXY = .{
                .chunkX = areaXY.areaX * chunkAreaZig.ChunkArea.SIZE + @as(i32, @intCast(@divFloor(chunkInAreaIndex, chunkAreaZig.ChunkArea.SIZE))),
                .chunkY = areaXY.areaY * chunkAreaZig.ChunkArea.SIZE + @as(i32, @intCast(@mod(chunkInAreaIndex, chunkAreaZig.ChunkArea.SIZE))),
            };
            currentIndex = mapZig.getChunkIndexForChunkXY(currentChunkXY);
            currenChunk = try mapZig.createEmptyChunk(currentChunkXY, state.allocator);
            var pathfindChunkData: pathfindingZig.PathfindingChunkData = .{
                .pathingData = undefined,
                .graphRectangles = std.ArrayList(pathfindingZig.ChunkGraphRectangle).init(state.allocator),
            };
            for (0..pathfindChunkData.pathingData.len) |i| {
                pathfindChunkData.pathingData[i] = null;
            }
            currenChunk.?.pathingData = pathfindChunkData;
        }

        const tileXY: mapZig.TileXY = .{
            .tileX = @as(i32, @intCast(@divFloor(tileXYIndex, mapZig.GameMap.CHUNK_LENGTH))) + currentChunkXY.chunkX * mapZig.GameMap.CHUNK_LENGTH,
            .tileY = @as(i32, @intCast(@mod(tileXYIndex, mapZig.GameMap.CHUNK_LENGTH))) + currentChunkXY.chunkY * mapZig.GameMap.CHUNK_LENGTH,
        };
        const position: main.Position = mapZig.mapTileXyToTileMiddlePosition(tileXY);

        if (currenChunk) |*chunk| {
            switch (value) {
                SAVE_PATH => {
                    try chunk.pathes.append(position);
                },
                SAVE_TREE => {
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_TREE_AND_PATH => {
                    try chunk.pathes.append(position);
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_TREE_REGROW => {
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                        .regrow = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_TREE_GROWING => {
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .growStartTimeMs = state.gameTimeMs,
                        .regrow = true,
                    };
                    const queueItem = mapZig.ChunkQueueItem{ .itemData = .{ .tree = chunk.trees.items.len }, .executeTime = state.gameTimeMs + mapZig.GROW_TIME_MS };
                    try chunk.queue.append(queueItem);
                    try chunk.trees.append(newTree);
                },
                SAVE_TREE_BUILD_ORDER => {
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .regrow = true,
                        .imageIndex = imageZig.IMAGE_GREEN_RECTANGLE,
                    };
                    try chunk.trees.append(newTree);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = 1 });
                },
                SAVE_POTATO => {
                    const newPotato: mapZig.PotatoField = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.potatoFields.append(newPotato);
                },
                SAVE_TREE_AND_BUILD_ORDER_POTATO => {
                    const newPotato: mapZig.PotatoField = .{
                        .position = position,
                    };
                    try chunk.potatoFields.append(newPotato);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = 1 });
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_POTATO_GROWING => {
                    const newPotato: mapZig.PotatoField = .{
                        .position = position,
                        .growStartTimeMs = state.gameTimeMs,
                    };
                    const queueItem = mapZig.ChunkQueueItem{ .itemData = .{ .potatoField = chunk.potatoFields.items.len }, .executeTime = state.gameTimeMs + mapZig.GROW_TIME_MS };
                    try chunk.queue.append(queueItem);
                    try chunk.potatoFields.append(newPotato);
                },
                SAVE_POTATO_BUILD_ORDER => {
                    const newPotato: mapZig.PotatoField = .{
                        .position = position,
                    };
                    try chunk.potatoFields.append(newPotato);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = 1 });
                },
                SAVE_BUILDING => {
                    const newBuilding: mapZig.Building = .{
                        .type = .house,
                        .position = position,
                        .inConstruction = false,
                        .citizensSpawned = 1,
                        .woodRequired = 0,
                        .imageIndex = imageZig.IMAGE_HOUSE,
                    };
                    var newCitizen = main.Citizen.createCitizen(position, state.allocator);
                    newCitizen.position = position;
                    newCitizen.foodLevel = @as(f32, @floatFromInt(@mod(index, 100))) / 100.0 + 0.5; //should not all want to eat at the same time
                    try chunk.citizens.append(newCitizen);
                    try chunk.buildings.append(newBuilding);
                },
                SAVE_BUILDING_BUILD_ORDER => {
                    const newBuilding: mapZig.Building = .{
                        .type = .house,
                        .position = position,
                    };
                    try chunk.buildings.append(newBuilding);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = 1 });
                },
                SAVE_TREE_AND_BUILD_ORDER_BUILDING => {
                    const newBuilding: mapZig.Building = .{
                        .type = .house,
                        .position = position,
                    };
                    try chunk.buildings.append(newBuilding);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = 1 });
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_BIG_BUILDING => {
                    const newBuilding: mapZig.Building = .{
                        .type = .bigHouse,
                        .position = .{ .x = position.x - mapZig.GameMap.TILE_SIZE / 2, .y = position.y - mapZig.GameMap.TILE_SIZE / 2 },
                        .inConstruction = false,
                        .citizensSpawned = 8,
                        .woodRequired = 0,
                        .imageIndex = imageZig.IMAGE_BIG_HOUSE,
                    };
                    for (0..8) |_| {
                        var newCitizen = main.Citizen.createCitizen(newBuilding.position, state.allocator);
                        newCitizen.position = position;
                        newCitizen.foodLevel = @as(f32, @floatFromInt(@mod(index, 100))) / 100.0 + 0.5; //should not all want to eat at the same time
                        try chunk.citizens.append(newCitizen);
                    }
                    try chunk.bigBuildings.append(newBuilding);
                },
                SAVE_TREE_AND_BUILD_ORDER_BIG_BUILDING => {
                    const newBuilding: mapZig.Building = .{
                        .type = .bigHouse,
                        .position = .{ .x = position.x - mapZig.GameMap.TILE_SIZE / 2, .y = position.y - mapZig.GameMap.TILE_SIZE / 2 },
                        .woodRequired = mapZig.Building.BIG_HOUSE_WOOD,
                    };
                    try chunk.bigBuildings.append(newBuilding);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = newBuilding.woodRequired });
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER => {
                    const newBuilding: mapZig.Building = .{
                        .type = .bigHouse,
                        .position = .{ .x = position.x - mapZig.GameMap.TILE_SIZE / 2, .y = position.y - mapZig.GameMap.TILE_SIZE / 2 },
                        .woodRequired = mapZig.Building.BIG_HOUSE_WOOD,
                    };
                    try chunk.bigBuildings.append(newBuilding);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = newBuilding.woodRequired });
                },
                SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_1 => {
                    try bigBuildingBuildOrderLoad(position, 1, chunk, false, state);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_2 => {
                    try bigBuildingBuildOrderLoad(position, 2, chunk, false, state);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_3 => {
                    try bigBuildingBuildOrderLoad(position, 3, chunk, false, state);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_4 => {
                    try bigBuildingBuildOrderLoad(position, 4, chunk, false, state);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_1 => {
                    try bigBuildingBuildOrderLoad(position, 1, chunk, true, state);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_2 => {
                    try bigBuildingBuildOrderLoad(position, 2, chunk, true, state);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_3 => {
                    try bigBuildingBuildOrderLoad(position, 3, chunk, true, state);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_4 => {
                    try bigBuildingBuildOrderLoad(position, 4, chunk, true, state);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE => {
                    const newBuilding: mapZig.Building = .{
                        .type = .bigHouse,
                        .position = .{ .x = position.x - mapZig.GameMap.TILE_SIZE / 2, .y = position.y - mapZig.GameMap.TILE_SIZE / 2 },
                        .woodRequired = mapZig.Building.BIG_HOUSE_WOOD / 2,
                    };
                    try chunk.bigBuildings.append(newBuilding);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = newBuilding.woodRequired });
                },
                SAVE_BLOCKING => {
                    try chunk.blockingTiles.append(tileXY);
                },
                SAVE_EMPTY => {
                    // nothing to do
                },
                else => {
                    //missing implementation? or bug
                    unknownLoadValue = value;
                },
            }
        }
    }
    if (unknownLoadValue) |value| std.debug.print("unknown load value: {d} in area {} {}\n", .{ value, areaXY.areaX, areaXY.areaY });
    if (currenChunk) |chunk| {
        chunks[currentIndex] = chunk;
    }
    return chunks;
}

fn bigBuildingBuildOrderLoad(position: main.Position, citizensSpawn: u8, chunk: *mapZig.MapChunk, halveDone: bool, state: *main.GameState) !void {
    var woodRequired: u8 = if (halveDone) mapZig.Building.BIG_HOUSE_WOOD / 2 else mapZig.Building.BIG_HOUSE_WOOD;
    if (!halveDone) woodRequired -= citizensSpawn;
    const newBuilding: mapZig.Building = .{
        .type = .bigHouse,
        .position = .{ .x = position.x - mapZig.GameMap.TILE_SIZE / 2, .y = position.y - mapZig.GameMap.TILE_SIZE / 2 },
        .woodRequired = woodRequired,
        .citizensSpawned = citizensSpawn,
    };
    for (0..citizensSpawn) |_| {
        var newCitizen = main.Citizen.createCitizen(newBuilding.position, state.allocator);
        newCitizen.position = position;
        newCitizen.foodLevel = @as(f32, @floatCast(@mod(position.x, 2000.0))) / 2000.0 + 0.5; //should not all want to eat at the same time
        try chunk.citizens.append(newCitizen);
    }

    try chunk.bigBuildings.append(newBuilding);
    try chunk.buildOrders.append(.{ .position = position, .materialCount = newBuilding.woodRequired });
}

fn disconnectPathingBetweenChunkAreas(chunk: *mapZig.MapChunk, state: *main.GameState) !void {
    const chunkAreaXPos = @mod(chunk.chunkXY.chunkX, chunkAreaZig.ChunkArea.SIZE);
    const chunkAreaYPos = @mod(chunk.chunkXY.chunkY, chunkAreaZig.ChunkArea.SIZE);
    if (chunkAreaXPos == 0 or chunkAreaXPos == chunkAreaZig.ChunkArea.SIZE - 1 or chunkAreaYPos == 0 or chunkAreaYPos == chunkAreaZig.ChunkArea.SIZE - 1) {
        var checkLeftXY: ?mapZig.ChunkXY = if (chunkAreaXPos == 0) .{ .chunkX = chunk.chunkXY.chunkX - 1, .chunkY = chunk.chunkXY.chunkY } else null;
        var checkRightXY: ?mapZig.ChunkXY = if (chunkAreaXPos == chunkAreaZig.ChunkArea.SIZE - 1) .{ .chunkX = chunk.chunkXY.chunkX + 1, .chunkY = chunk.chunkXY.chunkY } else null;
        var checkTopXY: ?mapZig.ChunkXY = if (chunkAreaYPos == 0) .{ .chunkX = chunk.chunkXY.chunkX, .chunkY = chunk.chunkXY.chunkY - 1 } else null;
        var checkBottomXY: ?mapZig.ChunkXY = if (chunkAreaYPos == chunkAreaZig.ChunkArea.SIZE - 1) .{ .chunkX = chunk.chunkXY.chunkX, .chunkY = chunk.chunkXY.chunkY + 1 } else null;

        var chunkLeft: ?*mapZig.MapChunk = null;
        if (checkLeftXY) |xy| {
            chunkLeft = try mapZig.getChunkByChunkXYWithoutCreateOrLoad(xy, state);
            if (chunkLeft == null) checkLeftXY = null;
        }
        var chunkRight: ?*mapZig.MapChunk = null;
        if (checkRightXY) |xy| {
            chunkRight = try mapZig.getChunkByChunkXYWithoutCreateOrLoad(xy, state);
            if (chunkRight == null) checkRightXY = null;
        }
        var chunkTop: ?*mapZig.MapChunk = null;
        if (checkTopXY) |xy| {
            chunkTop = try mapZig.getChunkByChunkXYWithoutCreateOrLoad(xy, state);
            if (chunkTop == null) checkTopXY = null;
        }
        var chunkBottom: ?*mapZig.MapChunk = null;
        if (checkBottomXY) |xy| {
            chunkBottom = try mapZig.getChunkByChunkXYWithoutCreateOrLoad(xy, state);
            if (chunkBottom == null) checkBottomXY = null;
        }

        for (chunk.pathingData.graphRectangles.items, 0..) |graphRectangle, graphRectangleIndex| {
            for (graphRectangle.connectionIndexes.items) |graphConnection| {
                if (checkLeftXY) |xy| {
                    if (graphConnection.chunkXY.chunkX == xy.chunkX and graphConnection.chunkXY.chunkY == xy.chunkY) {
                        const adjacentGraphRectangle = &chunkLeft.?.pathingData.graphRectangles.items[graphConnection.index];
                        for (adjacentGraphRectangle.connectionIndexes.items, 0..) |adjacentGraphConnection, adjacentGraphConnectionIndex| {
                            if (adjacentGraphConnection.chunkXY.chunkX == chunk.chunkXY.chunkX and adjacentGraphConnection.chunkXY.chunkY == chunk.chunkXY.chunkY and
                                adjacentGraphConnection.index == graphRectangleIndex)
                            {
                                _ = adjacentGraphRectangle.connectionIndexes.swapRemove(adjacentGraphConnectionIndex);
                                try pathfindingZig.graphRectangleConnectionMovedUpdate(chunkLeft.?.pathingData.graphRectangles.items.len, graphConnection.index, chunkLeft.?, 0, state);
                                break;
                            }
                        }
                    }
                }
                if (checkRightXY) |xy| {
                    if (graphConnection.chunkXY.chunkX == xy.chunkX and graphConnection.chunkXY.chunkY == xy.chunkY) {
                        const adjacentGraphRectangle = &chunkRight.?.pathingData.graphRectangles.items[graphConnection.index];
                        for (adjacentGraphRectangle.connectionIndexes.items, 0..) |adjacentGraphConnection, adjacentGraphConnectionIndex| {
                            if (adjacentGraphConnection.chunkXY.chunkX == chunk.chunkXY.chunkX and adjacentGraphConnection.chunkXY.chunkY == chunk.chunkXY.chunkY and
                                adjacentGraphConnection.index == graphRectangleIndex)
                            {
                                _ = adjacentGraphRectangle.connectionIndexes.swapRemove(adjacentGraphConnectionIndex);
                                try pathfindingZig.graphRectangleConnectionMovedUpdate(chunkRight.?.pathingData.graphRectangles.items.len, graphConnection.index, chunkRight.?, 0, state);
                                break;
                            }
                        }
                    }
                }
                if (checkTopXY) |xy| {
                    if (graphConnection.chunkXY.chunkX == xy.chunkX and graphConnection.chunkXY.chunkY == xy.chunkY) {
                        const adjacentGraphRectangle = &chunkTop.?.pathingData.graphRectangles.items[graphConnection.index];
                        for (adjacentGraphRectangle.connectionIndexes.items, 0..) |adjacentGraphConnection, adjacentGraphConnectionIndex| {
                            if (adjacentGraphConnection.chunkXY.chunkX == chunk.chunkXY.chunkX and adjacentGraphConnection.chunkXY.chunkY == chunk.chunkXY.chunkY and
                                adjacentGraphConnection.index == graphRectangleIndex)
                            {
                                _ = adjacentGraphRectangle.connectionIndexes.swapRemove(adjacentGraphConnectionIndex);
                                try pathfindingZig.graphRectangleConnectionMovedUpdate(chunkTop.?.pathingData.graphRectangles.items.len, graphConnection.index, chunkTop.?, 0, state);
                                break;
                            }
                        }
                    }
                }
                if (checkBottomXY) |xy| {
                    if (graphConnection.chunkXY.chunkX == xy.chunkX and graphConnection.chunkXY.chunkY == xy.chunkY) {
                        const adjacentGraphRectangle = &chunkBottom.?.pathingData.graphRectangles.items[graphConnection.index];
                        for (adjacentGraphRectangle.connectionIndexes.items, 0..) |adjacentGraphConnection, adjacentGraphConnectionIndex| {
                            if (adjacentGraphConnection.chunkXY.chunkX == chunk.chunkXY.chunkX and adjacentGraphConnection.chunkXY.chunkY == chunk.chunkXY.chunkY and
                                adjacentGraphConnection.index == graphRectangleIndex)
                            {
                                _ = adjacentGraphRectangle.connectionIndexes.swapRemove(adjacentGraphConnectionIndex);
                                try pathfindingZig.graphRectangleConnectionMovedUpdate(chunkBottom.?.pathingData.graphRectangles.items.len, graphConnection.index, chunkBottom.?, 0, state);
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
}
