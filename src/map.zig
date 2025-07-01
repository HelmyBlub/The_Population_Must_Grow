const std = @import("std");
const main = @import("main.zig");
const windowSdlZig = @import("windowSdl.zig");
const imageZig = @import("image.zig");
const pathfindingZig = @import("pathfinding.zig");
const chunkAreaZig = @import("chunkArea.zig");
const saveZig = @import("save.zig");

pub const GameMap = struct {
    pub const CHUNK_LENGTH: comptime_int = 16;
    pub const TILE_SIZE: comptime_int = 20;
    pub const CHUNK_SIZE: comptime_int = GameMap.CHUNK_LENGTH * GameMap.TILE_SIZE;
    pub const MAX_BUILDING_TILE_RADIUS: comptime_int = 1;
};

pub const GROW_TIME_MS = 10_000;

pub const U64HashMapContext = struct {
    pub fn hash(self: @This(), s: u64) u64 {
        _ = self;
        return s;
    }
    pub fn eql(self: @This(), a: u64, b: u64) bool {
        _ = self;
        return a == b;
    }
};

pub const PathingType = enum {
    fast,
    slow,
    blocking,
};

pub const MapChunk = struct {
    chunkXY: ChunkXY,
    workingCitizenCounter: u32 = 0,
    lastPaintGameTime: u64 = 0,
    noPotatoLeftInChunkProximityGameTime: u64 = 0,
    noTreeLeftInChunkProximityGameTime: u64 = 0,
    trees: std.ArrayList(MapTree),
    buildings: std.ArrayList(Building),
    /// buildings bigger than one tile
    bigBuildings: std.ArrayList(Building),
    potatoFields: std.ArrayList(PotatoField),
    citizens: std.ArrayList(main.Citizen),
    /// used for bigBuildings which use more than one tile
    blockingTiles: std.ArrayList(TileXY),
    buildOrders: std.ArrayList(BuildOrder),
    skipBuildOrdersUntilTimeMs: ?u64 = null,
    pathes: std.ArrayList(main.Position),
    pathingData: main.pathfindingZig.PathfindingChunkData,
    queue: std.ArrayList(ChunkQueueItem),
};

const ChunkQueueType = enum {
    tree,
    potatoField,
};

const ChunkQueueItemData = union(ChunkQueueType) {
    tree: usize,
    potatoField: usize,
};

pub const ChunkQueueItem = struct {
    itemData: ChunkQueueItemData,
    executeTime: u64,
};

pub const BuildOrder = struct {
    position: main.Position,
    materialCount: u8,
};

pub const MapObject = union(enum) {
    building: *Building,
    bigBuilding: *Building,
    potatoField: *PotatoField,
    tree: *MapTree,
    path: *main.Position,
};

pub const MapTree = struct {
    position: main.Position,
    citizenOnTheWay: bool = false,
    fullyGrown: bool = false,
    growStartTimeMs: ?u64 = null,
    beginCuttingTime: ?u64 = null,
    regrow: bool = false,
    imageIndex: u8 = imageZig.IMAGE_TREE,
};

pub const BuildingType = enum {
    house,
    bigHouse,
};

pub const Building = struct {
    type: BuildingType,
    position: main.Position,
    inConstruction: bool = true,
    woodRequired: u8 = 1,
    citizensSpawned: u8 = 0,
    constructionStartedTime: ?u64 = null,
    imageIndex: u8 = imageZig.IMAGE_WHITE_RECTANGLE,
    pub const BIG_HOUSE_WOOD = 16;
};

pub const PotatoField = struct {
    position: main.Position,
    citizenOnTheWay: u8 = 0,
    growStartTimeMs: ?u64 = null,
    fullyGrown: bool = false,
};

pub const ChunkXY = struct {
    chunkX: i32,
    chunkY: i32,
};

pub const TileXY = struct {
    tileX: i32,
    tileY: i32,
};

pub const MapRectangle = struct {
    pos: main.Position,
    width: f32,
    height: f32,
};

pub const MapTileRectangle = struct {
    topLeftTileXY: TileXY,
    columnCount: u32,
    rowCount: u32,
};

pub const VisibleChunksData = struct {
    top: i32,
    left: i32,
    rows: usize,
    columns: usize,
};

pub const BUILD_MODE_SINGLE = 0;
pub const BUILD_MODE_DRAG_RECTANGLE = 1;
pub const BUILD_MODE_DRAW = 2;
pub const BUILD_TYPE_HOUSE = 0;
pub const BUILD_TYPE_TREE_FARM = 1;
pub const BUILD_TYPE_POTATO_FARM = 2;
pub const BUILD_TYPE_DEMOLISH = 3;
pub const BUILD_TYPE_COPY_PASTE = 4;
pub const BUILD_TYPE_BIG_HOUSE = 5;
pub const BUILD_TYPE_PATHES = 6;
pub const TILE_SIZE_BIG_HOUSE = 2;

pub fn visibleAndAdjacentChunkRectangle(state: *main.GameState) !void {
    const camera = state.camera;
    const mapVisibleTopLeft: main.Position = .{
        .x = camera.position.x - windowSdlZig.windowData.widthFloat / 2 / camera.zoom - 10,
        .y = camera.position.y - windowSdlZig.windowData.heightFloat / 2 / camera.zoom - 10,
    };
    const chunkXY = getChunkXyForPosition(mapVisibleTopLeft);
    const increaseBy = 3;
    const newVisible = VisibleChunksData{
        .left = chunkXY.chunkX - increaseBy,
        .top = chunkXY.chunkY - increaseBy,
        .columns = @intFromFloat(windowSdlZig.windowData.widthFloat / camera.zoom / GameMap.CHUNK_SIZE + 2 + increaseBy * 2),
        .rows = @intFromFloat(windowSdlZig.windowData.heightFloat / camera.zoom / GameMap.CHUNK_SIZE + 2 + increaseBy * 2),
    };

    if (state.visibleAndTickRectangle) |rect| try chunkAreaZig.setVisibleFlagOfVisibleAndTickRectangle(rect, false, state);
    state.visibleAndTickRectangle = newVisible;
    try chunkAreaZig.setVisibleFlagOfVisibleAndTickRectangle(newVisible, true, state);
}

pub fn getTopLeftVisibleChunkXY(state: *main.GameState) VisibleChunksData {
    const camera = state.camera;
    const mapVisibleTopLeft: main.Position = .{
        .x = camera.position.x - windowSdlZig.windowData.widthFloat / 2 / camera.zoom - 10,
        .y = camera.position.y - windowSdlZig.windowData.heightFloat / 2 / camera.zoom - 10,
    };
    const chunkXY = getChunkXyForPosition(mapVisibleTopLeft);

    return VisibleChunksData{
        .left = chunkXY.chunkX,
        .top = chunkXY.chunkY,
        .columns = @intFromFloat(windowSdlZig.windowData.widthFloat / camera.zoom / GameMap.CHUNK_SIZE + 2),
        .rows = @intFromFloat(windowSdlZig.windowData.heightFloat / camera.zoom / GameMap.CHUNK_SIZE + 2),
    };
}

pub fn isPositionInsideMapRectangle(position: main.Position, rectangle: MapRectangle) bool {
    return rectangle.pos.x <= position.x and rectangle.pos.x + rectangle.width >= position.x and
        rectangle.pos.y <= position.y and rectangle.pos.y + rectangle.height >= position.y;
}

pub fn getMapScreenVisibilityRectangle(state: *main.GameState) MapRectangle {
    const spacing = 10;
    const camera = state.camera;
    const mapVisibleTopLeft: main.Position = .{
        .x = camera.position.x - windowSdlZig.windowData.widthFloat / 2 / camera.zoom - spacing,
        .y = camera.position.y - windowSdlZig.windowData.heightFloat / 2 / camera.zoom - spacing,
    };
    return MapRectangle{
        .pos = .{ .x = mapVisibleTopLeft.x, .y = mapVisibleTopLeft.y },
        .width = windowSdlZig.windowData.widthFloat / camera.zoom + spacing * 2,
        .height = windowSdlZig.windowData.heightFloat / camera.zoom + spacing * 2,
    };
}

pub fn getChunkAndCreateIfNotExistsForChunkXY(chunkXY: ChunkXY, threadIndex: usize, state: *main.GameState) anyerror!*MapChunk {
    const areaXY = chunkAreaZig.getChunkAreaXyForChunkXy(chunkXY);
    const areaKey = chunkAreaZig.getKeyForAreaXY(areaXY);
    var optChunkArea = state.chunkAreas.getPtr(areaKey);
    if (optChunkArea) |chunkArea| {
        if (chunkArea.chunks == null) {
            chunkArea.chunks = try saveZig.loadChunkAreaFromFile(areaXY, state);
            try chunkAreaZig.setupPathingForLoadedChunkArea(areaXY, state);
            chunkArea.dontUnloadBeforeTime = state.gameTimeMs + chunkAreaZig.MINIMAL_ACTIVE_TIME_BEFORE_UNLOAD;
            chunkArea.idleTypeData = .idle;
            try chunkAreaZig.appendRequestToUnidleChunkAreaKey(&state.threadData[threadIndex], areaKey);
        }
    } else {
        try chunkAreaZig.putChunkArea(areaXY, areaKey, threadIndex, state);
        optChunkArea = state.chunkAreas.getPtr(areaKey);
    }
    const chunkIndex = getChunkIndexForChunkXY(chunkXY);
    return &optChunkArea.?.chunks.?[chunkIndex];
}

pub fn getChunkByChunkXYWithRequestForLoad(chunkXY: ChunkXY, threadIndex: usize, state: *main.GameState) !?*MapChunk {
    const areaXY = chunkAreaZig.getChunkAreaXyForChunkXy(chunkXY);
    const areaKey = chunkAreaZig.getKeyForAreaXY(areaXY);
    const optChunkArea = state.chunkAreas.getPtr(areaKey);
    if (optChunkArea) |chunkArea| {
        if (chunkArea.chunks) |chunks| {
            return &chunks[getChunkIndexForChunkXY(chunkXY)];
        }
    }

    try appendRequestToLoadChunkAreaKey(&state.threadData[threadIndex], areaKey);
    return null;
}

pub fn appendRequestToLoadChunkAreaKey(threadData: *main.ThreadData, areaKey: u64) !void {
    for (threadData.requestToLoadChunkAreaKeys.items) |key| {
        if (key == areaKey) return;
    }
    try threadData.requestToLoadChunkAreaKeys.append(areaKey);
}

pub fn getChunkByChunkXYWithoutCreateOrLoad(chunkXY: ChunkXY, state: *main.GameState) !?*MapChunk {
    const areaXY = chunkAreaZig.getChunkAreaXyForChunkXy(chunkXY);
    const areaKey = chunkAreaZig.getKeyForAreaXY(areaXY);
    const optChunkArea = state.chunkAreas.getPtr(areaKey);
    if (optChunkArea) |chunkArea| {
        if (chunkArea.chunks) |chunks| {
            return &chunks[getChunkIndexForChunkXY(chunkXY)];
        }
    }
    return null;
}

pub fn getChunkAndCreateIfNotExistsForPosition(position: main.Position, threadIndex: usize, state: *main.GameState) !*MapChunk {
    const chunkXY = getChunkXyForPosition(position);
    return try getChunkAndCreateIfNotExistsForChunkXY(chunkXY, threadIndex, state);
}

pub fn getChunkByPositionWithRequestForLoad(position: main.Position, threadIndex: usize, state: *main.GameState) !?*MapChunk {
    const chunkXY = getChunkXyForPosition(position);
    return try getChunkByChunkXYWithRequestForLoad(chunkXY, threadIndex, state);
}

pub fn getChunkByPositionWithoutCreateOrLoad(position: main.Position, state: *main.GameState) !?*MapChunk {
    const chunkXY = getChunkXyForPosition(position);
    return try getChunkByChunkXYWithoutCreateOrLoad(chunkXY, state);
}

pub fn demolishAnythingOnPosition(position: main.Position, optEntireDemolishRectangle: ?MapTileRectangle, state: *main.GameState) !void {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, 0, state);
    for (chunk.trees.items, 0..) |tree, i| {
        if (main.calculateDistance(position, tree.position) < GameMap.TILE_SIZE) {
            removeTree(i, true, chunk);
            break;
        }
    }
    for (chunk.buildings.items, 0..) |*building, i| {
        if (main.calculateDistance(position, building.position) < GameMap.TILE_SIZE) {
            if (state.citizenCounter > 1 and building.citizensSpawned > 0) {
                for (chunk.citizens.items, 0..) |*citizen, j| {
                    if (citizen.homePosition.x == building.position.x and citizen.homePosition.y == building.position.y) {
                        citizen.moveTo.deinit();
                        try main.Citizen.handleRemovingCitizenAction(citizen, null, state);
                        _ = chunk.citizens.swapRemove(j);
                        building.citizensSpawned -= 1;
                        state.citizenCounter -= 1;
                        break;
                    }
                }
            }
            if (building.inConstruction) {
                for (chunk.buildOrders.items, 0..) |*buildOrder, index| {
                    if (buildOrder.position.x == building.position.x and buildOrder.position.y == building.position.y) {
                        _ = chunk.buildOrders.swapRemove(index);
                        break;
                    }
                }
            }
            if (building.citizensSpawned == 0) {
                _ = chunk.buildings.swapRemove(i);
            }
            return;
        }
    }
    if (optEntireDemolishRectangle) |entireDemolishRectangle| {
        for (chunk.bigBuildings.items, 0..) |*building, i| {
            if (main.calculateDistance(position, building.position) < GameMap.TILE_SIZE) {
                const tileXYOfBuilding = mapPositionToTileXy(building.position);
                const buildingTileRectangle: MapTileRectangle = .{
                    .topLeftTileXY = .{ .tileX = tileXYOfBuilding.tileX - 1, .tileY = tileXYOfBuilding.tileY - 1 },
                    .columnCount = 2,
                    .rowCount = 2,
                };
                //deletion rectangle need to be over entire building
                if (entireDemolishRectangle.topLeftTileXY.tileX > buildingTileRectangle.topLeftTileXY.tileX or
                    entireDemolishRectangle.topLeftTileXY.tileX + @as(i32, @intCast(entireDemolishRectangle.columnCount)) < buildingTileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(buildingTileRectangle.columnCount)) or
                    entireDemolishRectangle.topLeftTileXY.tileY > buildingTileRectangle.topLeftTileXY.tileY or
                    entireDemolishRectangle.topLeftTileXY.tileY + @as(i32, @intCast(entireDemolishRectangle.rowCount)) < buildingTileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(buildingTileRectangle.rowCount))) return;
                var index = chunk.citizens.items.len;
                while (index > 0 and state.citizenCounter > building.citizensSpawned) {
                    if (building.citizensSpawned == 0) {
                        break;
                    }
                    index -= 1;
                    const citizen = &chunk.citizens.items[index];
                    if (citizen.homePosition.x == building.position.x and citizen.homePosition.y == building.position.y) {
                        citizen.moveTo.deinit();
                        try main.Citizen.handleRemovingCitizenAction(citizen, null, state);
                        _ = chunk.citizens.swapRemove(index);
                        state.citizenCounter -= 1;
                        building.citizensSpawned -= 1;
                    }
                }

                if (building.inConstruction) {
                    for (chunk.buildOrders.items, 0..) |*buildOrder, buildOrderIndex| {
                        if (buildOrder.position.x == building.position.x and buildOrder.position.y == building.position.y) {
                            _ = chunk.buildOrders.swapRemove(buildOrderIndex);
                            break;
                        }
                    }
                }
                if (building.citizensSpawned == 0) {
                    _ = chunk.bigBuildings.swapRemove(i);
                }
                //check for blocking tiles
                const otherTileXyOfBuilding: [3]TileXY = .{
                    .{ .tileX = tileXYOfBuilding.tileX - 1, .tileY = tileXYOfBuilding.tileY },
                    .{ .tileX = tileXYOfBuilding.tileX, .tileY = tileXYOfBuilding.tileY - 1 },
                    .{ .tileX = tileXYOfBuilding.tileX - 1, .tileY = tileXYOfBuilding.tileY - 1 },
                };
                for (otherTileXyOfBuilding) |otherTileXY| {
                    const otherChunkXY = getChunkXyForTileXy(otherTileXY);
                    if (otherChunkXY.chunkX != chunk.chunkXY.chunkX or otherChunkXY.chunkY != chunk.chunkXY.chunkY) {
                        if (try getChunkByChunkXYWithoutCreateOrLoad(otherChunkXY, state)) |otherChunk| {
                            var currentIndex: usize = 0;
                            while (currentIndex < otherChunk.blockingTiles.items.len) {
                                const currentBlockingTile = otherChunk.blockingTiles.items[currentIndex];
                                if (currentBlockingTile.tileX == otherTileXY.tileX and currentBlockingTile.tileY == otherTileXY.tileY) {
                                    _ = otherChunk.blockingTiles.swapRemove(currentIndex);
                                } else {
                                    currentIndex += 1;
                                }
                            }
                        }
                    }
                }
                return;
            }
        }
    }
    for (chunk.potatoFields.items, 0..) |field, i| {
        if (main.calculateDistance(position, field.position) < GameMap.TILE_SIZE) {
            removePotatoField(i, chunk);
            return;
        }
    }
    for (chunk.pathes.items, 0..) |path, i| {
        if (main.calculateDistance(position, path) < GameMap.TILE_SIZE) {
            _ = chunk.pathes.swapRemove(i);
            return;
        }
    }
}

pub fn getTileRectangleMiddlePosition(tileRectangle: MapTileRectangle) main.Position {
    return .{
        .x = @as(f64, @floatFromInt(tileRectangle.topLeftTileXY.tileX * GameMap.TILE_SIZE + @as(i32, @intCast(@divFloor(tileRectangle.columnCount * GameMap.TILE_SIZE, 2))))),
        .y = @as(f64, @floatFromInt(tileRectangle.topLeftTileXY.tileY * GameMap.TILE_SIZE + @as(i32, @intCast(@divFloor(tileRectangle.rowCount * GameMap.TILE_SIZE, 2))))),
    };
}

pub fn getObjectOnTile(tileXY: TileXY, threadIndex: usize, state: *main.GameState) !?MapObject {
    const position = mapTileXyToTileMiddlePosition(tileXY);
    return try getObjectOnPosition(position, threadIndex, state);
}

pub fn getObjectOnPosition(position: main.Position, threadIndex: usize, state: *main.GameState) !?MapObject {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, threadIndex, state);
    for (chunk.buildings.items) |*building| {
        if (main.calculateDistance(position, building.position) < GameMap.TILE_SIZE) {
            return .{ .building = building };
        }
    }
    for (chunk.bigBuildings.items) |*building| {
        if (main.calculateDistance(position, building.position) < GameMap.TILE_SIZE) {
            return .{ .bigBuilding = building };
        }
    }

    for (chunk.potatoFields.items) |*field| {
        if (main.calculateDistance(position, field.position) < GameMap.TILE_SIZE) {
            return .{ .potatoField = field };
        }
    }
    for (chunk.trees.items) |*tree| {
        if (main.calculateDistance(position, tree.position) < GameMap.TILE_SIZE) {
            return .{ .tree = tree };
        }
    }
    for (chunk.pathes.items) |*pathPos| {
        if (main.calculateDistance(position, pathPos.*) < GameMap.TILE_SIZE) {
            return .{ .path = pathPos };
        }
    }
    return null;
}

pub fn canBuildOrWaitForTreeCutdown(position: main.Position, threadIndex: usize, state: *main.GameState) !bool {
    const chunk = try getChunkByPositionWithRequestForLoad(position, threadIndex, state);
    if (chunk == null) return false;
    for (chunk.?.trees.items, 0..) |tree, i| {
        if (main.calculateDistance(position, tree.position) < GameMap.TILE_SIZE) {
            if (tree.citizenOnTheWay) return false;
            removeTree(i, false, chunk.?);
            return true;
        }
    }
    return true;
}

fn isRectangleBuildable(buildRectangle: MapTileRectangle, state: *main.GameState, setExistingTreeRegrow: bool, ignore1TileBuildings: bool, ignoreNonRegrowTrees: bool) !bool {
    const buildCorners = [_]TileXY{
        .{
            .tileX = buildRectangle.topLeftTileXY.tileX - GameMap.MAX_BUILDING_TILE_RADIUS,
            .tileY = buildRectangle.topLeftTileXY.tileY - GameMap.MAX_BUILDING_TILE_RADIUS,
        },
        .{
            .tileX = buildRectangle.topLeftTileXY.tileX + GameMap.MAX_BUILDING_TILE_RADIUS + @as(i32, @intCast(buildRectangle.columnCount - 1)),
            .tileY = buildRectangle.topLeftTileXY.tileY - GameMap.MAX_BUILDING_TILE_RADIUS,
        },
        .{
            .tileX = buildRectangle.topLeftTileXY.tileX - GameMap.MAX_BUILDING_TILE_RADIUS,
            .tileY = buildRectangle.topLeftTileXY.tileY + @as(i32, @intCast(buildRectangle.rowCount - 1)) + GameMap.MAX_BUILDING_TILE_RADIUS,
        },
        .{
            .tileX = buildRectangle.topLeftTileXY.tileX + GameMap.MAX_BUILDING_TILE_RADIUS + @as(i32, @intCast(buildRectangle.columnCount - 1)),
            .tileY = buildRectangle.topLeftTileXY.tileY + @as(i32, @intCast(buildRectangle.rowCount - 1)) + GameMap.MAX_BUILDING_TILE_RADIUS,
        },
    };
    var chunksMaxIndex: usize = 0;
    var chunkXysToCheck: [4]?ChunkXY = .{ null, null, null, null };
    for (buildCorners) |corner| {
        const chunkXy = getChunkXyForTileXy(corner);
        var exists = false;
        if (chunksMaxIndex > 0) {
            for (0..chunksMaxIndex) |existsIndex| {
                const checkChunkXy = chunkXysToCheck[existsIndex].?;
                if (checkChunkXy.chunkX == chunkXy.chunkX and checkChunkXy.chunkY == chunkXy.chunkY) {
                    exists = true;
                    break;
                }
            }
        }
        if (!exists) {
            chunkXysToCheck[chunksMaxIndex] = chunkXy;
            chunksMaxIndex += 1;
        }
    }
    for (0..chunksMaxIndex) |chunkIndex| {
        const chunk = try getChunkAndCreateIfNotExistsForChunkXY(chunkXysToCheck[chunkIndex].?, 0, state);
        if (!ignore1TileBuildings) {
            for (chunk.buildings.items) |building| {
                if (is1x1ObjectOverlapping(building.position, buildRectangle)) {
                    return false;
                }
            }
        }
        for (chunk.blockingTiles.items) |blockingTile| {
            if (isRectangleOverlapping(MapTileRectangle{ .topLeftTileXY = blockingTile, .columnCount = 1, .rowCount = 1 }, buildRectangle)) {
                return false;
            }
        }
        for (chunk.bigBuildings.items) |building| {
            if (isRectangleOverlapping(getBigBuildingRectangle(building.position), buildRectangle)) {
                return false;
            }
        }
        for (chunk.pathes.items) |pathPos| {
            if (is1x1ObjectOverlapping(pathPos, buildRectangle)) {
                return false;
            }
        }
        for (chunk.trees.items) |*tree| {
            if (is1x1ObjectOverlapping(tree.position, buildRectangle)) {
                if (!tree.regrow) {
                    if (ignoreNonRegrowTrees) break;
                    if (setExistingTreeRegrow) {
                        tree.regrow = true;
                    } else {
                        return true;
                    }
                }
                return false;
            }
        }
        for (chunk.potatoFields.items) |field| {
            if (is1x1ObjectOverlapping(field.position, buildRectangle)) {
                return false;
            }
        }
    }
    return true;
}

pub fn getBigBuildingRectangle(bigBuildingPosition: main.Position) MapTileRectangle {
    return .{
        .topLeftTileXY = mapPositionToTileXy(.{
            .x = bigBuildingPosition.x - GameMap.TILE_SIZE / 2,
            .y = bigBuildingPosition.y - GameMap.TILE_SIZE / 2,
        }),
        .columnCount = 2,
        .rowCount = 2,
    };
}

pub fn get1x1RectangleFromPosition(position: main.Position) MapTileRectangle {
    return .{
        .topLeftTileXY = mapPositionToTileXy(position),
        .columnCount = 1,
        .rowCount = 1,
    };
}

fn is1x1ObjectOverlapping(position: main.Position, buildRectangle: MapTileRectangle) bool {
    return isRectangleOverlapping(get1x1RectangleFromPosition(position), buildRectangle);
}

pub fn isRectangleOverlapping(rect1: MapTileRectangle, rect2: MapTileRectangle) bool {
    if (rect1.topLeftTileXY.tileX <= rect2.topLeftTileXY.tileX + @as(i32, @intCast(rect2.columnCount - 1)) and rect2.topLeftTileXY.tileX <= rect1.topLeftTileXY.tileX + @as(i32, @intCast(rect1.columnCount - 1)) //
    and rect1.topLeftTileXY.tileY <= rect2.topLeftTileXY.tileY + @as(i32, @intCast(rect2.rowCount - 1)) and rect2.topLeftTileXY.tileY <= rect1.topLeftTileXY.tileY + @as(i32, @intCast(rect1.rowCount - 1))) {
        return true;
    }
    return false;
}

pub fn getChunkXyForTileXy(tileXy: TileXY) ChunkXY {
    return .{
        .chunkX = @divFloor(tileXy.tileX, GameMap.CHUNK_LENGTH),
        .chunkY = @divFloor(tileXy.tileY, GameMap.CHUNK_LENGTH),
    };
}

pub fn mapPositionToTilePosition(pos: main.Position) main.Position {
    return main.Position{
        .x = @round(pos.x / GameMap.TILE_SIZE) * GameMap.TILE_SIZE,
        .y = @round(pos.y / GameMap.TILE_SIZE) * GameMap.TILE_SIZE,
    };
}

pub fn mapPositionToTileMiddlePosition(pos: main.Position) main.Position {
    return main.Position{
        .x = @round((pos.x - GameMap.TILE_SIZE / 2) / GameMap.TILE_SIZE) * GameMap.TILE_SIZE + GameMap.TILE_SIZE / 2,
        .y = @round((pos.y - GameMap.TILE_SIZE / 2) / GameMap.TILE_SIZE) * GameMap.TILE_SIZE + GameMap.TILE_SIZE / 2,
    };
}

pub fn mapTileXyToTileMiddlePosition(tileXY: TileXY) main.Position {
    return main.Position{
        .x = @floatFromInt(tileXY.tileX * GameMap.TILE_SIZE + GameMap.TILE_SIZE / 2),
        .y = @floatFromInt(tileXY.tileY * GameMap.TILE_SIZE + GameMap.TILE_SIZE / 2),
    };
}

pub fn mapTileXyToTilePosition(tileXY: TileXY) main.Position {
    return main.Position{
        .x = @floatFromInt(tileXY.tileX * GameMap.TILE_SIZE),
        .y = @floatFromInt(tileXY.tileY * GameMap.TILE_SIZE),
    };
}

pub fn mapTileXyToVulkanSurfacePosition(tileXY: TileXY, camera: main.Camera) main.Position {
    const mapPosition = mapTileXyToTilePosition(tileXY);
    return mapPositionToVulkanSurfacePoisition(mapPosition.x, mapPosition.y, camera);
}

pub fn mapTileXyMiddleToVulkanSurfacePosition(tileXY: TileXY, camera: main.Camera) main.Position {
    const mapPosition = mapTileXyToTileMiddlePosition(tileXY);
    return mapPositionToVulkanSurfacePoisition(mapPosition.x, mapPosition.y, camera);
}

pub fn mapPositionToTileXy(position: main.Position) TileXY {
    return TileXY{
        .tileX = @intFromFloat(@floor(position.x / GameMap.TILE_SIZE)),
        .tileY = @intFromFloat(@floor(position.y / GameMap.TILE_SIZE)),
    };
}

pub fn mapPositionToTileXyBottomRight(position: main.Position) TileXY {
    return TileXY{
        .tileX = @intFromFloat(@ceil(position.x / GameMap.TILE_SIZE)),
        .tileY = @intFromFloat(@ceil(position.y / GameMap.TILE_SIZE)),
    };
}

pub fn mapPositionToVulkanSurfacePoisition(x: f64, y: f64, camera: main.Camera) main.Position {
    var width: u32 = 0;
    var height: u32 = 0;
    windowSdlZig.getWindowSize(&width, &height);
    const widthFloat = @as(f32, @floatFromInt(width));
    const heightFloat = @as(f32, @floatFromInt(height));

    return main.Position{
        .x = ((x - camera.position.x) * camera.zoom + widthFloat / 2) / widthFloat * 2 - 1,
        .y = ((y - camera.position.y) * camera.zoom + heightFloat / 2) / heightFloat * 2 - 1,
    };
}

pub fn placeTree(tree: MapTree, state: *main.GameState) !bool {
    if (!try isRectangleBuildable(get1x1RectangleFromPosition(tree.position), state, true, false, false)) return false;
    const chunk = try getChunkAndCreateIfNotExistsForPosition(tree.position, 0, state);
    try chunk.trees.append(tree);
    try chunk.buildOrders.append(.{ .position = tree.position, .materialCount = 1 });
    if (tree.regrow) {
        try chunkAreaZig.checkIfAreaIsActive(chunk.chunkXY, 0, state);
    }
    return true;
}

pub fn placeCitizen(citizen: main.Citizen, threadIndex: usize, state: *main.GameState) !void {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(citizen.position, threadIndex, state);
    state.threadData[threadIndex].citizensAddedThisTick += 1;
    try chunk.citizens.append(citizen);
    try chunkAreaZig.checkIfAreaIsActive(chunk.chunkXY, threadIndex, state);
}

pub fn placePotatoField(potatoField: PotatoField, state: *main.GameState) !bool {
    if (!try isRectangleBuildable(get1x1RectangleFromPosition(potatoField.position), state, false, false, true)) return false;
    const chunk = try getChunkAndCreateIfNotExistsForPosition(potatoField.position, 0, state);
    try chunk.potatoFields.append(potatoField);
    try chunk.buildOrders.append(.{ .position = potatoField.position, .materialCount = 1 });
    try chunkAreaZig.checkIfAreaIsActive(chunk.chunkXY, 0, state);
    return true;
}

pub fn placePath(pathPos: main.Position, state: *main.GameState) !bool {
    if (!try isRectangleBuildable(get1x1RectangleFromPosition(pathPos), state, false, false, true)) return false;
    const chunk = try getChunkAndCreateIfNotExistsForPosition(pathPos, 0, state);
    try chunk.pathes.append(pathPos);
    return true;
}

pub fn placeHouse(position: main.Position, state: *main.GameState, checkPath: bool, displayHelpText: bool, threadIndex: usize) !bool {
    const newBuilding: Building = .{
        .position = position,
        .type = .house,
    };
    return try placeBuilding(newBuilding, state, checkPath, displayHelpText, threadIndex);
}

pub fn placeBigHouse(position: main.Position, state: *main.GameState, checkPath: bool, displayHelpText: bool, threadIndex: usize) !bool {
    const newBuilding: Building = .{
        .position = position,
        .type = .bigHouse,
        .woodRequired = Building.BIG_HOUSE_WOOD,
    };
    return try placeBuilding(newBuilding, state, checkPath, displayHelpText, threadIndex);
}

pub fn placeBuilding(building: Building, state: *main.GameState, checkPath: bool, displayHelpText: bool, threadIndex: usize) !bool {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(building.position, 0, state);
    if (building.type == .bigHouse) {
        const buildRectangle = getBigBuildingRectangle(building.position);
        if (!try isRectangleBuildable(buildRectangle, state, false, true, true)) return false;
        if (checkPath and !try isRectangleAdjacentToPath(buildRectangle, state)) return false;
        var tempBuilding = building;
        try replace1TileBuildingsFor2x2Building(&tempBuilding, state);
        try main.pathfindingZig.changePathingDataRectangle(buildRectangle, PathingType.slow, threadIndex, state);
        try chunk.bigBuildings.append(tempBuilding);
        try chunk.buildOrders.append(.{ .position = tempBuilding.position, .materialCount = tempBuilding.woodRequired });
    } else {
        const buildRectangle = get1x1RectangleFromPosition(building.position);
        if (!try isRectangleBuildable(buildRectangle, state, false, false, true)) return false;
        if (checkPath and !try isRectangleAdjacentToPath(buildRectangle, state)) {
            if (displayHelpText) state.vkState.citizenPopulationCounterUx.houseBuildPathMessageDisplayTime = std.time.milliTimestamp();
            return false;
        }
        try chunk.buildings.append(building);
        try chunk.buildOrders.append(.{ .position = building.position, .materialCount = 1 });
    }
    try chunkAreaZig.checkIfAreaIsActive(chunk.chunkXY, 0, state);
    return true;
}

pub fn finishBuilding(building: *Building, threadIndex: usize, state: *main.GameState) !void {
    building.constructionStartedTime = null;
    building.woodRequired -|= 1;
    if (!building.inConstruction) return;
    if (building.type == .house) {
        building.inConstruction = false;
        building.imageIndex = imageZig.IMAGE_HOUSE;
        const buildRectangle = get1x1RectangleFromPosition(building.position);
        try main.pathfindingZig.changePathingDataRectangle(buildRectangle, PathingType.blocking, threadIndex, state);
        var newCitizen = main.Citizen.createCitizen(building.position, state.allocator);
        newCitizen.position = building.position;
        try placeCitizen(newCitizen, threadIndex, state);
        building.citizensSpawned += 1;
    } else if (building.type == .bigHouse) {
        if (building.woodRequired == 0) {
            building.inConstruction = false;
            building.imageIndex = imageZig.IMAGE_BIG_HOUSE;
            const buildRectangle = getBigBuildingRectangle(building.position);
            try main.pathfindingZig.changePathingDataRectangle(buildRectangle, PathingType.blocking, threadIndex, state);
            while (building.citizensSpawned < 8) {
                var newCitizen = main.Citizen.createCitizen(building.position, state.allocator);
                newCitizen.position = building.position;
                try placeCitizen(newCitizen, threadIndex, state);
                building.citizensSpawned += 1;
            }
            const bigBuildingTileXY = mapPositionToTileXy(building.position);
            const chunkXY = getChunkXyForTileXy(bigBuildingTileXY);
            const bigBuildingOtherTiles: [3]TileXY = .{
                .{ .tileX = bigBuildingTileXY.tileX - 1, .tileY = bigBuildingTileXY.tileY },
                .{ .tileX = bigBuildingTileXY.tileX, .tileY = bigBuildingTileXY.tileY - 1 },
                .{ .tileX = bigBuildingTileXY.tileX - 1, .tileY = bigBuildingTileXY.tileY - 1 },
            };
            for (bigBuildingOtherTiles) |otherTile| {
                const otherTileChunkXY = getChunkXyForTileXy(otherTile);
                if (otherTileChunkXY.chunkX != chunkXY.chunkX or otherTileChunkXY.chunkY != chunkXY.chunkY) {
                    const otherChunk = try getChunkAndCreateIfNotExistsForChunkXY(otherTileChunkXY, 0, state);
                    try otherChunk.blockingTiles.append(otherTile);
                }
            }
        } else if (building.woodRequired < 4) {
            building.imageIndex = imageZig.IMAGE_BIG_HOUSE;
        }
    }
}

fn isRectangleAdjacentToPath(buildRectangle: MapTileRectangle, state: *main.GameState) !bool {
    var checkCorners = [_]TileXY{
        .{
            .tileX = buildRectangle.topLeftTileXY.tileX - 1,
            .tileY = buildRectangle.topLeftTileXY.tileY - 1,
        },
        .{
            .tileX = buildRectangle.topLeftTileXY.tileX + @as(i32, @intCast(buildRectangle.columnCount)),
            .tileY = buildRectangle.topLeftTileXY.tileY - 1,
        },
        .{
            .tileX = buildRectangle.topLeftTileXY.tileX - 1,
            .tileY = buildRectangle.topLeftTileXY.tileY + @as(i32, @intCast(buildRectangle.rowCount)),
        },
        .{
            .tileX = buildRectangle.topLeftTileXY.tileX + @as(i32, @intCast(buildRectangle.columnCount)),
            .tileY = buildRectangle.topLeftTileXY.tileY + @as(i32, @intCast(buildRectangle.rowCount)),
        },
    };
    var chunksMaxIndex: usize = 0;
    var chunkXysToCheck: [4]?ChunkXY = .{ null, null, null, null };
    {
        const xMod = @mod(buildRectangle.topLeftTileXY.tileX, GameMap.CHUNK_LENGTH);
        const yMod = @mod(buildRectangle.topLeftTileXY.tileY, GameMap.CHUNK_LENGTH);
        if (xMod == 0) {
            if (yMod == 0) {
                checkCorners[0].tileX += 1;
            } else if (yMod == GameMap.CHUNK_LENGTH - 1) {
                checkCorners[2].tileX += 1;
            }
        } else if (xMod == GameMap.CHUNK_LENGTH - 1) {
            if (yMod == 0) {
                checkCorners[1].tileX -= 1;
            } else if (yMod == GameMap.CHUNK_LENGTH - 1) {
                checkCorners[3].tileX -= 1;
            }
        }
    }
    for (checkCorners) |corner| {
        const chunkXy = getChunkXyForTileXy(corner);
        var exists = false;
        if (chunksMaxIndex > 0) {
            for (0..chunksMaxIndex) |existsIndex| {
                const checkChunkXy = chunkXysToCheck[existsIndex].?;
                if (checkChunkXy.chunkX == chunkXy.chunkX and checkChunkXy.chunkY == chunkXy.chunkY) {
                    exists = true;
                    break;
                }
            }
        }
        if (!exists) {
            chunkXysToCheck[chunksMaxIndex] = chunkXy;
            chunksMaxIndex += 1;
        }
    }
    const rectMapTopLeft = mapTileXyToTilePosition(buildRectangle.topLeftTileXY);
    const rectMapBottomRight: main.Position = .{
        .x = rectMapTopLeft.x + @as(f64, @floatFromInt(buildRectangle.columnCount * GameMap.TILE_SIZE)),
        .y = rectMapTopLeft.y + @as(f64, @floatFromInt(buildRectangle.rowCount * GameMap.TILE_SIZE)),
    };
    for (0..chunksMaxIndex) |chunkIndex| {
        const chunk = try getChunkAndCreateIfNotExistsForChunkXY(chunkXysToCheck[chunkIndex].?, 0, state);
        for (chunk.pathes.items) |pathPos| {
            if (rectMapTopLeft.x - GameMap.TILE_SIZE < pathPos.x and pathPos.x < rectMapBottomRight.x + GameMap.TILE_SIZE and
                rectMapTopLeft.y - GameMap.TILE_SIZE < pathPos.y and pathPos.y < rectMapBottomRight.y + GameMap.TILE_SIZE)
            {
                if (rectMapTopLeft.x < pathPos.x and pathPos.x < rectMapBottomRight.x or
                    rectMapTopLeft.y < pathPos.y and pathPos.y < rectMapBottomRight.y)
                {
                    return true;
                }
            }
        }
    }
    return false;
}

fn replace1TileBuildingsFor2x2Building(building: *Building, state: *main.GameState) !void {
    const corners = [_]main.Position{
        .{ .x = building.position.x - GameMap.TILE_SIZE / 2, .y = building.position.y - GameMap.TILE_SIZE / 2 },
        .{ .x = building.position.x - GameMap.TILE_SIZE / 2, .y = building.position.y + GameMap.TILE_SIZE / 2 },
        .{ .x = building.position.x + GameMap.TILE_SIZE / 2, .y = building.position.y - GameMap.TILE_SIZE / 2 },
        .{ .x = building.position.x + GameMap.TILE_SIZE / 2, .y = building.position.y + GameMap.TILE_SIZE / 2 },
    };

    for (corners) |corner| {
        if (try getBuildingOnPosition(.{ .x = corner.x, .y = corner.y }, 0, state)) |cornerBuilding| {
            if (!cornerBuilding.inConstruction) {
                if (building.woodRequired > 1) building.woodRequired -= 1;
                const chunk = try getChunkAndCreateIfNotExistsForPosition(cornerBuilding.position, 0, state);
                for (chunk.citizens.items, 0..) |*citizen, i| {
                    if (citizen.homePosition.x == cornerBuilding.position.x and citizen.homePosition.y == cornerBuilding.position.y) {
                        citizen.homePosition = building.position;
                        building.citizensSpawned += 1;
                        cornerBuilding.citizensSpawned -= 1;
                        const newBuildingChunk = try getChunkAndCreateIfNotExistsForPosition(building.position, 0, state);
                        if (newBuildingChunk != chunk) {
                            var moveCitizen = chunk.citizens.swapRemove(i);
                            try newBuildingChunk.citizens.append(moveCitizen);
                            if (chunk.chunkXY.chunkX != newBuildingChunk.chunkXY.chunkX or chunk.chunkXY.chunkY != newBuildingChunk.chunkXY.chunkY) {
                                if (main.Citizen.isCitizenWorking(&moveCitizen)) {
                                    chunk.workingCitizenCounter -= 1;
                                    newBuildingChunk.workingCitizenCounter += 1;
                                }
                            }
                        }
                        break;
                    }
                }
            }
            try demolishAnythingOnPosition(cornerBuilding.position, null, state);
        }
    }
}

pub fn getPotatoFieldOnPosition(position: main.Position, threadIndex: usize, state: *main.GameState) !?struct { potatoField: *PotatoField, chunk: *MapChunk, potatoIndex: usize } {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, threadIndex, state);
    for (chunk.potatoFields.items, 0..) |*field, i| {
        if (main.calculateDistance(position, field.position) < GameMap.TILE_SIZE) {
            return .{ .potatoField = field, .chunk = chunk, .potatoIndex = i };
        }
    }
    return null;
}

pub fn appendToChunkQueue(chunk: *MapChunk, chunkQueueItem: ChunkQueueItem, citizenHome: main.Position, threadIndex: usize, state: *main.GameState) !void {
    const chunkAreaXY = chunkAreaZig.getChunkAreaXyForChunkXy(chunk.chunkXY);
    const citizenHomeChunkXY = getChunkXyForPosition(citizenHome);
    const chunkAreaXYCitizenHome = chunkAreaZig.getChunkAreaXyForChunkXy(citizenHomeChunkXY);
    if (chunkAreaXY.areaX != chunkAreaXYCitizenHome.areaX or chunkAreaXY.areaY != chunkAreaXYCitizenHome.areaY) {
        const areaKey = chunkAreaZig.getKeyForAreaXY(chunkAreaXY);
        if (state.chunkAreas.getPtr(areaKey)) |idleArea| {
            if (idleArea.idleTypeData != .active) {
                try chunkAreaZig.appendRequestToUnidleChunkAreaKey(&state.threadData[threadIndex], areaKey);
            }
        }
    }
    try chunk.queue.append(chunkQueueItem);
}

pub fn getTreeOnPosition(position: main.Position, threadIndex: usize, state: *main.GameState) !?struct { tree: *MapTree, chunk: *MapChunk, treeIndex: usize } {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, threadIndex, state);
    for (chunk.trees.items, 0..) |*tree, index| {
        if (main.calculateDistance(position, tree.position) < GameMap.TILE_SIZE) {
            return .{ .tree = tree, .chunk = chunk, .treeIndex = index };
        }
    }
    return null;
}

pub fn removeTree(treeIndex: usize, removeBuildOrderOnPosition: bool, chunk: *MapChunk) void {
    const movedIndex = chunk.trees.items.len - 1;
    const removedTree = chunk.trees.swapRemove(treeIndex);
    var queueIndex: usize = 0;
    while (chunk.queue.items.len > queueIndex) {
        const queueItem = &chunk.queue.items[queueIndex];
        if (@as(ChunkQueueType, queueItem.itemData) == ChunkQueueType.tree) {
            if (queueItem.itemData.tree == treeIndex) {
                _ = chunk.queue.orderedRemove(queueIndex);
                continue;
            } else if (queueItem.itemData.tree == movedIndex) {
                queueItem.itemData.tree = treeIndex;
            }
            queueIndex += 1;
        } else {
            queueIndex += 1;
        }
    }
    if (removeBuildOrderOnPosition and removedTree.fullyGrown == false and removedTree.growStartTimeMs == null) {
        for (chunk.buildOrders.items, 0..) |*buildOrder, buildOrderIndex| {
            if (buildOrder.position.x == removedTree.position.x and buildOrder.position.y == removedTree.position.y) {
                _ = chunk.buildOrders.swapRemove(buildOrderIndex);
                break;
            }
        }
    }
}

pub fn removePotatoField(potatoIndex: usize, chunk: *MapChunk) void {
    const movedIndex = chunk.potatoFields.items.len - 1;
    const removedField = chunk.potatoFields.swapRemove(potatoIndex);
    var queueIndex: usize = 0;
    while (chunk.queue.items.len > queueIndex) {
        const queueItem = &chunk.queue.items[queueIndex];
        if (@as(ChunkQueueType, queueItem.itemData) == ChunkQueueType.potatoField) {
            if (queueItem.itemData.potatoField == potatoIndex) {
                _ = chunk.queue.orderedRemove(queueIndex);
                continue;
            } else if (queueItem.itemData.potatoField == movedIndex) {
                queueItem.itemData.potatoField = potatoIndex;
            }
            queueIndex += 1;
        } else {
            queueIndex += 1;
        }
    }
    if (removedField.fullyGrown == false and removedField.growStartTimeMs == null) {
        for (chunk.buildOrders.items, 0..) |*buildOrder, buildOrderIndex| {
            if (buildOrder.position.x == removedField.position.x and buildOrder.position.y == removedField.position.y) {
                _ = chunk.buildOrders.swapRemove(buildOrderIndex);
                break;
            }
        }
    }
}

pub fn getBuildingOnPosition(position: main.Position, threadIndex: usize, state: *main.GameState) !?*Building {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, threadIndex, state);
    for (chunk.buildings.items) |*building| {
        if (main.calculateDistance(position, building.position) < GameMap.TILE_SIZE) {
            return building;
        }
    }
    for (chunk.bigBuildings.items) |*building| {
        if (main.calculateDistance(position, building.position) < GameMap.TILE_SIZE) {
            return building;
        }
    }
    return null;
}

pub fn unidleAffectedChunkAreas(mapTileRectangle: MapTileRectangle, state: *main.GameState) !void {
    const areaRectangleFromTileRectangle: MapTileRectangle = .{
        .topLeftTileXY = .{
            .tileX = @divFloor(@divFloor(mapTileRectangle.topLeftTileXY.tileX, GameMap.CHUNK_LENGTH), chunkAreaZig.ChunkArea.SIZE),
            .tileY = @divFloor(@divFloor(mapTileRectangle.topLeftTileXY.tileY, GameMap.CHUNK_LENGTH), chunkAreaZig.ChunkArea.SIZE),
        },
        .columnCount = @divFloor(@divFloor(mapTileRectangle.columnCount, GameMap.CHUNK_LENGTH), chunkAreaZig.ChunkArea.SIZE) + 1,
        .rowCount = @divFloor(@divFloor(mapTileRectangle.rowCount, GameMap.CHUNK_LENGTH), chunkAreaZig.ChunkArea.SIZE) + 1,
    };
    for (0..areaRectangleFromTileRectangle.columnCount) |x| {
        for (0..areaRectangleFromTileRectangle.rowCount) |y| {
            const areaKey = chunkAreaZig.getKeyForAreaXY(.{
                .areaX = @as(i32, @intCast(x)) + areaRectangleFromTileRectangle.topLeftTileXY.tileX,
                .areaY = @as(i32, @intCast(y)) + areaRectangleFromTileRectangle.topLeftTileXY.tileY,
            });
            if (state.chunkAreas.getPtr(areaKey)) |idleArea| {
                try chunkAreaZig.assignChunkAreaBackToThread(idleArea, areaKey, state);
            }
        }
    }
}

pub fn copyFromTo(fromTopLeftTileXY: TileXY, toTopLeftTileXY: TileXY, tileCountColumns: u32, tileCountRows: u32, state: *main.GameState) !void {
    const fromTopLeftTileMiddle = mapTileXyToTileMiddlePosition(fromTopLeftTileXY);
    const targetTopLeftTileMiddle = mapTileXyToTileMiddlePosition(toTopLeftTileXY);
    for (0..tileCountColumns) |x| {
        nextTile: for (0..tileCountRows) |y| {
            const sourcePosition: main.Position = .{
                .x = fromTopLeftTileMiddle.x + @as(f64, @floatFromInt(x * GameMap.TILE_SIZE)),
                .y = fromTopLeftTileMiddle.y + @as(f64, @floatFromInt(y * GameMap.TILE_SIZE)),
            };
            const chunk = try getChunkAndCreateIfNotExistsForPosition(sourcePosition, 0, state);
            const targetPosition: main.Position = .{
                .x = targetTopLeftTileMiddle.x + @as(f64, @floatFromInt(x * GameMap.TILE_SIZE)),
                .y = targetTopLeftTileMiddle.y + @as(f64, @floatFromInt(y * GameMap.TILE_SIZE)),
            };
            for (chunk.buildings.items) |building| {
                if (main.calculateDistance(sourcePosition, building.position) < GameMap.TILE_SIZE) {
                    _ = try placeHouse(targetPosition, state, false, false, 0);
                    continue :nextTile;
                }
            }
            for (chunk.bigBuildings.items) |building| {
                if (main.calculateDistance(sourcePosition, building.position) < GameMap.TILE_SIZE) {
                    const position: main.Position = .{
                        .x = building.position.x + targetTopLeftTileMiddle.x - fromTopLeftTileMiddle.x,
                        .y = building.position.y + targetTopLeftTileMiddle.y - fromTopLeftTileMiddle.y,
                    };
                    _ = try placeBigHouse(position, state, false, false, 0);
                    continue :nextTile;
                }
            }
            for (chunk.trees.items) |tree| {
                if (main.calculateDistance(sourcePosition, tree.position) < GameMap.TILE_SIZE and tree.regrow) {
                    const newTree: MapTree = .{
                        .position = targetPosition,
                        .regrow = true,
                        .imageIndex = imageZig.IMAGE_GREEN_RECTANGLE,
                    };
                    _ = try placeTree(newTree, state);
                    continue :nextTile;
                }
            }
            for (chunk.potatoFields.items) |potatoField| {
                if (main.calculateDistance(sourcePosition, potatoField.position) < GameMap.TILE_SIZE) {
                    const newPotatoField: PotatoField = .{
                        .position = targetPosition,
                    };
                    _ = try placePotatoField(newPotatoField, state);
                    continue :nextTile;
                }
            }
            for (chunk.pathes.items) |pathPos| {
                if (main.calculateDistance(sourcePosition, pathPos) < GameMap.TILE_SIZE) {
                    _ = try placePath(targetPosition, state);
                    continue :nextTile;
                }
            }
        }
    }
    const tileRectangle: MapTileRectangle = .{
        .topLeftTileXY = toTopLeftTileXY,
        .columnCount = tileCountColumns,
        .rowCount = tileCountRows,
    };
    try unidleAffectedChunkAreas(tileRectangle, state);
}

pub fn getChunkIndexForChunkXY(chunkXY: ChunkXY) usize {
    return chunkAreaZig.chunkKeyOrder[@intCast(@mod(chunkXY.chunkX, chunkAreaZig.ChunkArea.SIZE))][@intCast(@mod(chunkXY.chunkY, chunkAreaZig.ChunkArea.SIZE))];
}

pub fn getChunkXyForPosition(position: main.Position) ChunkXY {
    return .{
        .chunkX = @intFromFloat(@floor(position.x / GameMap.CHUNK_SIZE)),
        .chunkY = @intFromFloat(@floor(position.y / GameMap.CHUNK_SIZE)),
    };
}

pub fn createEmptyChunk(chunkXY: ChunkXY, allocator: std.mem.Allocator) !MapChunk {
    const chunk: MapChunk = .{
        .chunkXY = chunkXY,
        .buildings = std.ArrayList(Building).init(allocator),
        .bigBuildings = std.ArrayList(Building).init(allocator),
        .trees = std.ArrayList(MapTree).init(allocator),
        .potatoFields = std.ArrayList(PotatoField).init(allocator),
        .citizens = std.ArrayList(main.Citizen).init(allocator),
        .buildOrders = std.ArrayList(BuildOrder).init(allocator),
        .pathes = std.ArrayList(main.Position).init(allocator),
        .blockingTiles = std.ArrayList(TileXY).init(allocator),
        .pathingData = .{
            .pathingData = undefined,
            .graphRectangles = std.ArrayList(pathfindingZig.ChunkGraphRectangle).init(allocator),
        },
        .queue = std.ArrayList(ChunkQueueItem).init(allocator),
    };
    return chunk;
}

pub fn destroyChunk(chunk: *MapChunk) void {
    chunk.trees.deinit();
    chunk.buildings.deinit();
    chunk.bigBuildings.deinit();
    chunk.potatoFields.deinit();
    main.Citizen.destroyCitizens(chunk);
    chunk.citizens.deinit();
    chunk.buildOrders.deinit();
    chunk.blockingTiles.deinit();
    chunk.pathes.deinit();
    chunk.queue.deinit();
    pathfindingZig.destoryChunkData(&chunk.pathingData);
}

pub fn createChunk(chunkXY: ChunkXY, state: *main.GameState) !MapChunk {
    var mapChunk: MapChunk = try createEmptyChunk(chunkXY, state.allocator);
    for (0..GameMap.CHUNK_LENGTH) |x| {
        for (0..GameMap.CHUNK_LENGTH) |y| {
            const random = fixedRandom(
                @as(f64, @floatFromInt(x)) + @as(f64, @floatFromInt(chunkXY.chunkX * GameMap.CHUNK_LENGTH)),
                @as(f64, @floatFromInt(y)) + @as(f64, @floatFromInt(chunkXY.chunkY * GameMap.CHUNK_LENGTH)),
                0.0,
            );
            if (random < 0.1) {
                const tree = MapTree{
                    .position = .{
                        .x = @floatFromInt((chunkXY.chunkX * GameMap.CHUNK_LENGTH + @as(i32, @intCast(x))) * GameMap.TILE_SIZE + GameMap.TILE_SIZE / 2),
                        .y = @floatFromInt((chunkXY.chunkY * GameMap.CHUNK_LENGTH + @as(i32, @intCast(y))) * GameMap.TILE_SIZE + GameMap.TILE_SIZE / 2),
                    },
                    .fullyGrown = true,
                };
                try mapChunk.trees.append(tree);
            }
        }
    }
    return mapChunk;
}

pub fn createSpawnArea(state: *main.GameState) !void {
    const areaXY: chunkAreaZig.ChunkAreaXY = .{ .areaX = 0, .areaY = 0 };
    const areaKey = chunkAreaZig.getKeyForAreaXY(areaXY);
    try state.chunkAreas.put(areaKey, .{
        .areaXY = areaXY,
        .currentChunkIndex = 0,
        .chunks = null,
        .dontUnloadBeforeTime = state.gameTimeMs,
    });
    const chunkArea = state.chunkAreas.getPtr(areaKey).?;
    chunkArea.chunks = try state.allocator.alloc(MapChunk, chunkAreaZig.ChunkArea.SIZE * chunkAreaZig.ChunkArea.SIZE);
    const spawnChunkXY: ChunkXY = .{ .chunkX = 0, .chunkY = 0 };
    for (0..chunkAreaZig.ChunkArea.SIZE) |chunkX| {
        for (0..chunkAreaZig.ChunkArea.SIZE) |chunkY| {
            if (chunkX == spawnChunkXY.chunkX and chunkY == spawnChunkXY.chunkY) {
                chunkArea.chunks.?[chunkAreaZig.chunkKeyOrder[chunkX][chunkY]] = try createEmptyChunk(spawnChunkXY, state.allocator);
            } else {
                chunkArea.chunks.?[chunkAreaZig.chunkKeyOrder[chunkX][chunkY]] = try createChunk(.{
                    .chunkX = @as(i32, @intCast(chunkX)) + areaXY.areaX * chunkAreaZig.ChunkArea.SIZE,
                    .chunkY = @as(i32, @intCast(chunkY)) + areaXY.areaY * chunkAreaZig.ChunkArea.SIZE,
                }, state);
            }
        }
    }
    try chunkAreaZig.setupPathingForLoadedChunkArea(areaXY, state);

    var spawnChunk: *MapChunk = &chunkArea.chunks.?[chunkAreaZig.chunkKeyOrder[spawnChunkXY.chunkX][spawnChunkXY.chunkY]];
    const halveTileSize = GameMap.TILE_SIZE / 2;
    _ = try placePath(.{ .x = halveTileSize, .y = GameMap.TILE_SIZE + halveTileSize }, state);
    _ = try placePath(.{ .x = GameMap.TILE_SIZE + halveTileSize, .y = GameMap.TILE_SIZE + halveTileSize }, state);
    try spawnChunk.potatoFields.append(PotatoField{ .position = .{
        .x = GameMap.TILE_SIZE + halveTileSize,
        .y = halveTileSize,
    }, .fullyGrown = true });
    try spawnChunk.trees.append(.{ .position = .{ .x = GameMap.TILE_SIZE + halveTileSize, .y = GameMap.TILE_SIZE * 2 + halveTileSize }, .fullyGrown = true });

    const startHomePosition: main.Position = .{ .x = halveTileSize, .y = halveTileSize };
    const startBuilding: Building = .{ .position = startHomePosition, .type = .house };
    try spawnChunk.buildings.append(startBuilding);
    if (try getBuildingOnPosition(startHomePosition, 0, state)) |building| {
        try finishBuilding(building, 0, state);
    }

    state.citizenCounterLastTick = 1;
    try chunkAreaZig.checkIfAreaIsActive(spawnChunk.chunkXY, 0, state);
}

fn fixedRandom(x: f64, y: f64, seed: f64) f64 {
    return @mod((@sin((x * 112.01716 + y * 718.233 + seed * 1234.1234) * 437057.545323) * 1000000.0), 256) / 256.0;
}
