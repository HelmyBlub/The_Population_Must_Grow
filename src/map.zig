const std = @import("std");
const main = @import("main.zig");

pub const GameMap = struct {
    chunks: std.StringHashMap(MapChunk),
    activeChunkKeys: std.ArrayList([]const u8),
    pub const CHUNK_LENGTH: u8 = 8;
    pub const TILE_SIZE: u16 = 20;
    pub const CHUNK_SIZE: u16 = GameMap.CHUNK_LENGTH * GameMap.TILE_SIZE;
};

pub const MapChunk = struct {
    chunkX: i32,
    chunkY: i32,
    trees: std.ArrayList(MapTree),
    buildings: std.ArrayList(Building),
    potatoFields: std.ArrayList(PotatoField),
};

pub const MapTree = struct {
    position: main.Position,
    citizenOnTheWay: bool = false,
    ///  values from 0 to 1
    grow: f32 = 0,
};

pub const Building = struct {
    type: u8,
    position: main.Position,
    inConstruction: bool = true,
};

pub const PotatoField = struct {
    position: main.Position,
    citizenOnTheWay: u8 = 0,
    planted: bool = false,
    ///  values from 0 to 1
    grow: f32 = 0,
};

pub const BUILDING_MODE_SINGLE = 0;
pub const BUILDING_MODE_DRAG_RECTANGLE = 1;
pub const BUILDING_TYPE_HOUSE = 0;
pub const BUILDING_TYPE_TREE_FARM = 1;
pub const BUILDING_TYPE_POTATO_FARM = 2;

pub fn createMap(allocator: std.mem.Allocator) !GameMap {
    var map: GameMap = .{
        .chunks = std.StringHashMap(MapChunk).init(allocator),
        .activeChunkKeys = std.ArrayList([]const u8).init(allocator),
    };
    var mapChunk: MapChunk = .{
        .chunkX = 0,
        .chunkY = 0,
        .buildings = std.ArrayList(Building).init(allocator),
        .trees = std.ArrayList(MapTree).init(allocator),
        .potatoFields = std.ArrayList(PotatoField).init(allocator),
    };
    try mapChunk.buildings.append(.{ .position = .{ .x = 0, .y = 0 }, .inConstruction = false, .type = BUILDING_TYPE_HOUSE });
    try mapChunk.trees.append(.{ .position = .{ .x = GameMap.TILE_SIZE, .y = 0 }, .grow = 1 });
    try mapChunk.trees.append(.{ .position = .{ .x = GameMap.TILE_SIZE, .y = GameMap.TILE_SIZE }, .grow = 1 });

    const key = try getKeyForChunkXY(mapChunk.chunkX, mapChunk.chunkY);
    try map.chunks.put(key, mapChunk);
    return map;
}

pub fn getTopLeftVisibleChunkXY(state: *main.ChatSimState) void {
    //find top left chunk x and y
    //find chunk width counter
    //find chunk height counter
    _ = state; //TODO
}

pub fn mapIsTilePositionFree(pos: main.Position, state: *main.ChatSimState) !bool {
    const key = try getKeyForPosition(pos);
    const chunk = state.map.chunks.get(key).?;
    for (chunk.buildings.items) |building| {
        if (main.calculateDistance(pos, building.position) < GameMap.TILE_SIZE) {
            return false;
        }
    }
    for (chunk.trees.items) |tree| {
        if (main.calculateDistance(pos, tree.position) < GameMap.TILE_SIZE) {
            return false;
        }
    }
    for (chunk.potatoFields.items) |field| {
        if (main.calculateDistance(pos, field.position) < GameMap.TILE_SIZE) {
            return false;
        }
    }
    return true;
}

pub fn getKeyForPosition(position: main.Position) ![]const u8 {
    const chunkX: i32 = @intFromFloat(position.x / GameMap.CHUNK_SIZE);
    const chunkY: i32 = @intFromFloat(position.y / GameMap.CHUNK_SIZE);
    return try getKeyForChunkXY(chunkX, chunkY);
}

pub fn getKeyForChunkXY(chunkX: i32, chunkY: i32) ![]const u8 {
    const max_len = 20;
    var buf: [max_len]u8 = undefined;
    const key = try std.fmt.bufPrint(&buf, "{}_{}", .{ chunkX, chunkY });
    return key;
}

fn createChunk(chunkX: u32, chunkY: u32, allocator: std.mem.Allocator) MapChunk {
    const mapChunk: MapChunk = .{
        .chunkX = chunkX,
        .chunkY = chunkY,
        .buildings = std.ArrayList(Building).init(allocator),
        .trees = std.ArrayList(MapTree).init(allocator),
        .potatoFields = std.ArrayList(PotatoField).init(allocator),
    };

    mapChunk.trees.append(.{
        .position = .{
            .x = chunkX * GameMap.CHUNK_LENGTH * GameMap.TILE_SIZE,
            .y = chunkY * GameMap.CHUNK_LENGTH * GameMap.TILE_SIZE,
        },
        .grow = 1.0,
    });

    return mapChunk;
}
