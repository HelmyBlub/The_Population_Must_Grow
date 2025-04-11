const std = @import("std");
const main = @import("main.zig");
const windowSdlZig = @import("windowSdl.zig");

pub const GameMap = struct {
    chunks: std.HashMap(u64, MapChunk, U64HashMapContext, 30),
    activeChunkKeys: std.ArrayList(u64),
    pub const CHUNK_LENGTH: comptime_int = 16;
    pub const TILE_SIZE: comptime_int = 20;
    pub const CHUNK_SIZE: comptime_int = GameMap.CHUNK_LENGTH * GameMap.TILE_SIZE;
    pub const MAX_CHUNKS_ROWS_COLUMNS: comptime_int = 10_000;
    pub const MAX_BUILDING_TILE_RADIUS: comptime_int = 1;
};

const U64HashMapContext = struct {
    pub fn hash(self: @This(), s: u64) u64 {
        _ = self;
        return s;
    }
    pub fn eql(self: @This(), a: u64, b: u64) bool {
        _ = self;
        return a == b;
    }
};

pub const MapChunk = struct {
    chunkX: i32,
    chunkY: i32,
    trees: std.ArrayList(MapTree),
    buildings: std.ArrayList(Building),
    /// buildings bigger than one tile
    bigBuildings: std.ArrayList(Building),
    potatoFields: std.ArrayList(PotatoField),
    citizens: std.ArrayList(main.Citizen),
    buildOrders: std.ArrayList(BuildOrder),
    pathes: std.ArrayList(main.Position),
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
    ///  values from 0 to 1
    grow: f32 = 0,
    planted: bool = true,
    regrow: bool = false,
};

pub const Building = struct {
    type: u8,
    position: main.Position,
    inConstruction: bool = true,
    woodRequired: u8 = 1,
    citizensSpawned: u8 = 0,
};

pub const PotatoField = struct {
    position: main.Position,
    citizenOnTheWay: u8 = 0,
    planted: bool = true,
    ///  values from 0 to 1
    grow: f32 = 0,
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

const VisibleChunksData = struct {
    top: i32,
    left: i32,
    rows: usize,
    columns: usize,
};

pub const BUILD_MODE_SINGLE = 0;
pub const BUILD_MODE_DRAG_RECTANGLE = 1;
pub const BUILD_MODE_DRAW = 2;
pub const BUILDING_TYPE_HOUSE = 0;
pub const BUILDING_TYPE_BIG_HOUSE = 1;
pub const BUILD_TYPE_HOUSE = 0;
pub const BUILD_TYPE_TREE_FARM = 1;
pub const BUILD_TYPE_POTATO_FARM = 2;
pub const BUILD_TYPE_DEMOLISH = 3;
pub const BUILD_TYPE_COPY_PASTE = 4;
pub const BUILD_TYPE_BIG_HOUSE = 5;
pub const BUILD_TYPE_PATHES = 6;
pub const TILE_SIZE_BIG_HOUSE = 2;

pub fn createMap(allocator: std.mem.Allocator) !GameMap {
    var map: GameMap = .{
        .chunks = std.HashMap(u64, MapChunk, U64HashMapContext, 30).init(allocator),
        .activeChunkKeys = std.ArrayList(u64).init(allocator),
    };
    const spawnChunk = try createSpawnChunk(allocator);
    const key = getKeyForChunkXY(spawnChunk.chunkX, spawnChunk.chunkY);
    try map.chunks.put(key, spawnChunk);
    return map;
}

pub fn getTopLeftVisibleChunkXY(state: *main.ChatSimState) VisibleChunksData {
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

pub fn getChunkAndCreateIfNotExistsForChunkXY(chunkX: i32, chunkY: i32, state: *main.ChatSimState) !*MapChunk {
    const key = getKeyForChunkXY(chunkX, chunkY);
    if (!state.map.chunks.contains(key)) {
        try createAndPushChunkForChunkXY(chunkX, chunkY, state);
    }
    return state.map.chunks.getPtr(key).?;
}

pub fn getChunkAndCreateIfNotExistsForPosition(position: main.Position, state: *main.ChatSimState) !*MapChunk {
    const chunkXY = getChunkXyForPosition(position);
    return getChunkAndCreateIfNotExistsForChunkXY(chunkXY.chunkX, chunkXY.chunkY, state);
}

pub fn demolishAnythingOnPosition(position: main.Position, state: *main.ChatSimState) !void {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, state);
    for (chunk.buildings.items, 0..) |*building, i| {
        if (main.calculateDistance(position, building.position) < GameMap.TILE_SIZE) {
            if (state.citizenCounter > 1 and building.citizensSpawned > 0) {
                for (chunk.citizens.items, 0..) |citizen, j| {
                    if (citizen.homePosition != null and citizen.homePosition.?.x == building.position.x and citizen.homePosition.?.y == building.position.y) {
                        _ = chunk.citizens.swapRemove(j);
                        building.citizensSpawned -= 1;
                        state.citizenCounter -= 1;
                        break;
                    }
                }
            }

            if (building.citizensSpawned == 0) _ = chunk.buildings.swapRemove(i);
            return;
        }
    }
    for (chunk.bigBuildings.items, 0..) |*building, i| {
        if (main.calculateDistance(position, building.position) < GameMap.TILE_SIZE) {
            var index = chunk.citizens.items.len;
            while (index > 0 and state.citizenCounter > building.citizensSpawned) {
                if (building.citizensSpawned == 0) {
                    break;
                }
                index -= 1;
                const citizen = chunk.citizens.items[index];
                if (citizen.homePosition != null and citizen.homePosition.?.x == building.position.x and citizen.homePosition.?.y == building.position.y) {
                    _ = chunk.citizens.swapRemove(index);
                    state.citizenCounter -= 1;
                    building.citizensSpawned -= 1;
                }
            }

            if (building.citizensSpawned == 0) _ = chunk.bigBuildings.swapRemove(i);
            return;
        }
    }
    for (chunk.trees.items, 0..) |tree, i| {
        if (main.calculateDistance(position, tree.position) < GameMap.TILE_SIZE) {
            _ = chunk.trees.swapRemove(i);
            return;
        }
    }
    for (chunk.potatoFields.items, 0..) |field, i| {
        if (main.calculateDistance(position, field.position) < GameMap.TILE_SIZE) {
            _ = chunk.potatoFields.swapRemove(i);
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

pub fn getObjectOnPosition(position: main.Position, state: *main.ChatSimState) !?MapObject {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, state);
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
    for (chunk.trees.items) |*tree| {
        if (main.calculateDistance(position, tree.position) < GameMap.TILE_SIZE) {
            return .{ .tree = tree };
        }
    }
    for (chunk.potatoFields.items) |*field| {
        if (main.calculateDistance(position, field.position) < GameMap.TILE_SIZE) {
            return .{ .potatoField = field };
        }
    }
    for (chunk.pathes.items) |*pathPos| {
        if (main.calculateDistance(position, pathPos.*) < GameMap.TILE_SIZE) {
            return .{ .path = pathPos };
        }
    }
    return null;
}

pub fn canBuildOrWaitForTreeCutdown(position: main.Position, state: *main.ChatSimState) !bool {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, state);
    for (chunk.trees.items, 0..) |tree, i| {
        if (main.calculateDistance(position, tree.position) < GameMap.TILE_SIZE) {
            if (tree.citizenOnTheWay) return false;
            _ = chunk.trees.swapRemove(i);
            return true;
        }
    }
    return true;
}

pub fn isRectangleBuildable(buildRectangle: MapTileRectangle, state: *main.ChatSimState, setExistingTreeRegrow: bool, ignore1TileBuildings: bool) !bool {
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
        const chunk = try getChunkAndCreateIfNotExistsForChunkXY(chunkXysToCheck[chunkIndex].?.chunkX, chunkXysToCheck[chunkIndex].?.chunkY, state);
        if (!ignore1TileBuildings) {
            for (chunk.buildings.items) |building| {
                if (is1x1ObjectOverlapping(building.position, buildRectangle)) {
                    return false;
                }
            }
        }
        for (chunk.bigBuildings.items) |building| {
            if (isRectangleOverlapping(getBigBuildingRectangle(building.position), buildRectangle)) {
                return false;
            }
        }
        for (chunk.trees.items) |*tree| {
            if (is1x1ObjectOverlapping(tree.position, buildRectangle)) {
                if (!tree.regrow) {
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
        for (chunk.pathes.items) |pathPos| {
            if (is1x1ObjectOverlapping(pathPos, buildRectangle)) {
                return false;
            }
        }
    }
    return true;
}

fn getBigBuildingRectangle(bigBuildingPosition: main.Position) MapTileRectangle {
    return .{
        .topLeftTileXY = mapPositionToTileXy(.{
            .x = bigBuildingPosition.x - GameMap.TILE_SIZE / 2,
            .y = bigBuildingPosition.y - GameMap.TILE_SIZE / 2,
        }),
        .columnCount = 2,
        .rowCount = 2,
    };
}

fn get1x1RectangleFromPosition(position: main.Position) MapTileRectangle {
    return .{
        .topLeftTileXY = mapPositionToTileXy(position),
        .columnCount = 1,
        .rowCount = 1,
    };
}

fn is1x1ObjectOverlapping(position: main.Position, buildRectangle: MapTileRectangle) bool {
    return isRectangleOverlapping(get1x1RectangleFromPosition(position), buildRectangle);
}

fn isRectangleOverlapping(rect1: MapTileRectangle, rect2: MapTileRectangle) bool {
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

pub fn mapPositionToVulkanSurfacePoisition(x: f32, y: f32, camera: main.Camera) main.Position {
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

pub fn placeTree(tree: MapTree, state: *main.ChatSimState) !bool {
    if (!try isRectangleBuildable(get1x1RectangleFromPosition(tree.position), state, true, false)) return false;
    const chunk = try getChunkAndCreateIfNotExistsForPosition(tree.position, state);
    try chunk.trees.append(tree);
    try chunk.buildOrders.append(.{ .position = tree.position, .materialCount = 1 });
    if (tree.regrow) {
        try addTickPosition(chunk.chunkX, chunk.chunkY, state);
    }
    return true;
}

pub fn placeCitizen(citizen: main.Citizen, state: *main.ChatSimState) !void {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(citizen.position, state);
    state.citizenCounter += 1;
    try chunk.citizens.append(citizen);
    try addTickPosition(chunk.chunkX, chunk.chunkY, state);
}

pub fn placePotatoField(potatoField: PotatoField, state: *main.ChatSimState) !bool {
    if (!try isRectangleBuildable(get1x1RectangleFromPosition(potatoField.position), state, false, false)) return false;
    const chunk = try getChunkAndCreateIfNotExistsForPosition(potatoField.position, state);
    try chunk.potatoFields.append(potatoField);
    try chunk.buildOrders.append(.{ .position = potatoField.position, .materialCount = 1 });
    try addTickPosition(chunk.chunkX, chunk.chunkY, state);
    return true;
}

pub fn placePath(pathPos: main.Position, state: *main.ChatSimState) !bool {
    if (!try isRectangleBuildable(get1x1RectangleFromPosition(pathPos), state, false, false)) return false;
    const chunk = try getChunkAndCreateIfNotExistsForPosition(pathPos, state);
    try chunk.pathes.append(pathPos);
    return true;
}

pub fn placeBuilding(building: Building, state: *main.ChatSimState) !bool {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(building.position, state);
    if (building.type == BUILDING_TYPE_BIG_HOUSE) {
        if (!try isRectangleBuildable(getBigBuildingRectangle(building.position), state, false, true)) return false;
        var tempBuilding = building;
        try replace1TileBuildingsFor2x2Building(&tempBuilding, state);
        try chunk.bigBuildings.append(tempBuilding);
        try chunk.buildOrders.append(.{ .position = tempBuilding.position, .materialCount = tempBuilding.woodRequired });
    } else {
        if (!try isRectangleBuildable(get1x1RectangleFromPosition(building.position), state, false, false)) return false;
        try chunk.buildings.append(building);
        try chunk.buildOrders.append(.{ .position = building.position, .materialCount = 1 });
    }
    try addTickPosition(chunk.chunkX, chunk.chunkY, state);
    return true;
}

fn replace1TileBuildingsFor2x2Building(building: *Building, state: *main.ChatSimState) !void {
    const corners = [_]main.Position{
        .{ .x = building.position.x - GameMap.TILE_SIZE / 2, .y = building.position.y - GameMap.TILE_SIZE / 2 },
        .{ .x = building.position.x - GameMap.TILE_SIZE / 2, .y = building.position.y + GameMap.TILE_SIZE / 2 },
        .{ .x = building.position.x + GameMap.TILE_SIZE / 2, .y = building.position.y - GameMap.TILE_SIZE / 2 },
        .{ .x = building.position.x + GameMap.TILE_SIZE / 2, .y = building.position.y + GameMap.TILE_SIZE / 2 },
    };

    for (corners) |corner| {
        const optBuilding = try getBuildingOnPosition(.{ .x = corner.x, .y = corner.y }, state);
        if (optBuilding) |cornerBuilding| {
            building.woodRequired -= 1;
            const chunk = try getChunkAndCreateIfNotExistsForPosition(cornerBuilding.position, state);
            for (chunk.citizens.items, 0..) |*citizen, i| {
                if (citizen.homePosition != null and citizen.homePosition.?.x == cornerBuilding.position.x and citizen.homePosition.?.y == cornerBuilding.position.y) {
                    citizen.homePosition = building.position;
                    building.citizensSpawned += 1;
                    cornerBuilding.citizensSpawned -= 1;
                    const newBuildingChunk = try getChunkAndCreateIfNotExistsForPosition(building.position, state);
                    if (newBuildingChunk != chunk) {
                        const moveCitizen = chunk.citizens.swapRemove(i);
                        try newBuildingChunk.citizens.append(moveCitizen);
                    }
                    break;
                }
            }
            try demolishAnythingOnPosition(cornerBuilding.position, state);
        }
    }
}

pub fn addTickPosition(chunkX: i32, chunkY: i32, state: *main.ChatSimState) !void {
    const newKey = getKeyForChunkXY(chunkX, chunkY);
    for (state.map.activeChunkKeys.items) |key| {
        if (newKey == key) return;
    }
    try state.map.activeChunkKeys.append(newKey);
}

pub fn getPotatoFieldOnPosition(position: main.Position, state: *main.ChatSimState) !?*PotatoField {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, state);
    for (chunk.potatoFields.items) |*field| {
        if (main.calculateDistance(position, field.position) < GameMap.TILE_SIZE) {
            return field;
        }
    }
    return null;
}

pub fn getTreeOnPosition(position: main.Position, state: *main.ChatSimState) !?*MapTree {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, state);
    for (chunk.trees.items) |*tree| {
        if (main.calculateDistance(position, tree.position) < GameMap.TILE_SIZE) {
            return tree;
        }
    }
    return null;
}

pub fn getBuildingOnPosition(position: main.Position, state: *main.ChatSimState) !?*Building {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, state);
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

pub fn copyFromTo(fromTopLeftTileXY: TileXY, toTopLeftTileXY: TileXY, tileCountColumns: u32, tileCountRows: u32, state: *main.ChatSimState) !void {
    const fromTopLeftTileMiddle = mapTileXyToTileMiddlePosition(fromTopLeftTileXY);
    const targetTopLeftTileMiddle = mapTileXyToTileMiddlePosition(toTopLeftTileXY);
    for (0..tileCountColumns) |x| {
        nextTile: for (0..tileCountRows) |y| {
            const sourcePosition: main.Position = .{
                .x = fromTopLeftTileMiddle.x + @as(f32, @floatFromInt(x * GameMap.TILE_SIZE)),
                .y = fromTopLeftTileMiddle.y + @as(f32, @floatFromInt(y * GameMap.TILE_SIZE)),
            };
            const chunk = try getChunkAndCreateIfNotExistsForPosition(sourcePosition, state);
            const targetPosition: main.Position = .{
                .x = targetTopLeftTileMiddle.x + @as(f32, @floatFromInt(x * GameMap.TILE_SIZE)),
                .y = targetTopLeftTileMiddle.y + @as(f32, @floatFromInt(y * GameMap.TILE_SIZE)),
            };
            for (chunk.buildings.items) |building| {
                if (main.calculateDistance(sourcePosition, building.position) < GameMap.TILE_SIZE) {
                    const newBuilding: Building = .{
                        .position = targetPosition,
                        .inConstruction = true,
                        .type = building.type,
                    };
                    _ = try placeBuilding(newBuilding, state);
                    continue :nextTile;
                }
            }
            for (chunk.bigBuildings.items) |building| {
                if (main.calculateDistance(sourcePosition, building.position) < GameMap.TILE_SIZE) {
                    const newBuilding: Building = .{
                        .position = .{
                            .x = building.position.x + targetTopLeftTileMiddle.x - fromTopLeftTileMiddle.x,
                            .y = building.position.y + targetTopLeftTileMiddle.y - fromTopLeftTileMiddle.y,
                        },
                        .inConstruction = true,
                        .type = building.type,
                    };
                    _ = try placeBuilding(newBuilding, state);
                    continue :nextTile;
                }
            }
            for (chunk.trees.items) |tree| {
                if (main.calculateDistance(sourcePosition, tree.position) < GameMap.TILE_SIZE and tree.regrow) {
                    const newTree: MapTree = .{
                        .position = targetPosition,
                        .regrow = true,
                        .planted = false,
                    };
                    _ = try placeTree(newTree, state);
                    continue :nextTile;
                }
            }
            for (chunk.potatoFields.items) |potatoField| {
                if (main.calculateDistance(sourcePosition, potatoField.position) < GameMap.TILE_SIZE) {
                    const newPotatoField: PotatoField = .{
                        .position = targetPosition,
                        .planted = false,
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
}

pub fn getKeyForPosition(position: main.Position) !u64 {
    const chunkXY = getChunkXyForPosition(position);
    return getKeyForChunkXY(chunkXY.chunkX, chunkXY.chunkY);
}

pub fn getKeyForChunkXY(chunkX: i32, chunkY: i32) u64 {
    return @intCast(chunkX * GameMap.MAX_CHUNKS_ROWS_COLUMNS + chunkY + GameMap.MAX_CHUNKS_ROWS_COLUMNS * GameMap.MAX_CHUNKS_ROWS_COLUMNS);
}

pub fn getChunkXyForPosition(position: main.Position) ChunkXY {
    return .{
        .chunkX = @intFromFloat(@floor(position.x / GameMap.CHUNK_SIZE)),
        .chunkY = @intFromFloat(@floor(position.y / GameMap.CHUNK_SIZE)),
    };
}

fn createAndPushChunkForChunkXY(chunkX: i32, chunkY: i32, state: *main.ChatSimState) !void {
    const newChunk = try createChunk(chunkX, chunkY, state.allocator);
    const key = getKeyForChunkXY(chunkX, chunkY);
    try state.map.chunks.put(key, newChunk);
}

fn createAndPushChunkForPosition(position: main.Position, state: *main.ChatSimState) !void {
    const chunkXY = getChunkXyForPosition(position);
    try createAndPushChunkForChunkXY(chunkXY.chunkX, chunkXY.chunkY, state);
}

fn createChunk(chunkX: i32, chunkY: i32, allocator: std.mem.Allocator) !MapChunk {
    var mapChunk: MapChunk = .{
        .chunkX = chunkX,
        .chunkY = chunkY,
        .buildings = std.ArrayList(Building).init(allocator),
        .bigBuildings = std.ArrayList(Building).init(allocator),
        .trees = std.ArrayList(MapTree).init(allocator),
        .potatoFields = std.ArrayList(PotatoField).init(allocator),
        .citizens = std.ArrayList(main.Citizen).init(allocator),
        .buildOrders = std.ArrayList(BuildOrder).init(allocator),
        .pathes = std.ArrayList(main.Position).init(allocator),
    };

    for (0..GameMap.CHUNK_LENGTH) |x| {
        for (0..GameMap.CHUNK_LENGTH) |y| {
            const random = fixedRandom(
                @as(f32, @floatFromInt(x)) + @as(f32, @floatFromInt(chunkX * GameMap.CHUNK_LENGTH)),
                @as(f32, @floatFromInt(y)) + @as(f32, @floatFromInt(chunkY * GameMap.CHUNK_LENGTH)),
                0.0,
            );
            if (random < 0.1) {
                const tree = MapTree{
                    .position = .{
                        .x = @floatFromInt((chunkX * GameMap.CHUNK_LENGTH + @as(i32, @intCast(x))) * GameMap.TILE_SIZE + GameMap.TILE_SIZE / 2),
                        .y = @floatFromInt((chunkY * GameMap.CHUNK_LENGTH + @as(i32, @intCast(y))) * GameMap.TILE_SIZE + GameMap.TILE_SIZE / 2),
                    },
                    .grow = 1.0,
                };
                try mapChunk.trees.append(tree);
            }
        }
    }
    return mapChunk;
}

fn createSpawnChunk(allocator: std.mem.Allocator) !MapChunk {
    var spawnChunk: MapChunk = .{
        .chunkX = 0,
        .chunkY = 0,
        .buildings = std.ArrayList(Building).init(allocator),
        .bigBuildings = std.ArrayList(Building).init(allocator),
        .trees = std.ArrayList(MapTree).init(allocator),
        .potatoFields = std.ArrayList(PotatoField).init(allocator),
        .citizens = std.ArrayList(main.Citizen).init(allocator),
        .buildOrders = std.ArrayList(BuildOrder).init(allocator),
        .pathes = std.ArrayList(main.Position).init(allocator),
    };
    const halveTileSize = GameMap.TILE_SIZE / 2;
    try spawnChunk.buildings.append(.{ .position = .{ .x = halveTileSize, .y = halveTileSize }, .inConstruction = false, .type = BUILDING_TYPE_HOUSE, .citizensSpawned = 1 });
    try spawnChunk.trees.append(.{ .position = .{ .x = GameMap.TILE_SIZE + halveTileSize, .y = halveTileSize }, .grow = 1 });
    try spawnChunk.trees.append(.{ .position = .{ .x = GameMap.TILE_SIZE + halveTileSize, .y = GameMap.TILE_SIZE + halveTileSize }, .grow = 1 });
    var citizen = main.Citizen.createCitizen();
    citizen.homePosition = .{ .x = halveTileSize, .y = halveTileSize };
    try spawnChunk.citizens.append(citizen);
    return spawnChunk;
}

fn fixedRandom(x: f32, y: f32, seed: f32) f32 {
    return @mod((@sin((x * 112.01716 + y * 718.233 + seed * 1234.1234) * 437057.545323) * 1000000.0), 256) / 256.0;
}
