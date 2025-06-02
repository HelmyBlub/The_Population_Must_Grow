const std = @import("std");
const main = @import("main.zig");
const mapZig = @import("map.zig");
const imageZig = @import("image.zig");

const SAVE_EMPTY = 0;
const SAVE_PATH = 1;
const SAVE_TREE = 2;
const SAVE_POTATO = 3;
const SAVE_BUILDING = 4;
const SAVE_BIG_BUILDING = 5;

fn getSavePath(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    const game_name = "NumberGoUp";
    const save_folder = "saves";

    const base_dir = try std.fs.getAppDataDir(allocator, game_name);
    defer allocator.free(base_dir);

    const directory_path = try std.fs.path.join(allocator, &.{ base_dir, save_folder });
    defer allocator.free(directory_path);
    try std.fs.cwd().makePath(directory_path);

    const full_path = try std.fs.path.join(allocator, &.{ directory_path, filename });
    return full_path;
}

fn getFileNameForAreaXy(areaXY: main.ChunkAreaXY, allocator: std.mem.Allocator) ![]const u8 {
    // Format the filename: region_x_y.dat
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const writer = buf.writer();
    try writer.print("region_{d}_{d}.dat", .{ areaXY.areaX, areaXY.areaY });

    return getSavePath(allocator, buf.items);
}

pub fn saveChunkAreaToFile(chunkArea: *main.ChunkArea, state: *main.ChatSimState) !void {
    const path = try getFileNameForAreaXy(chunkArea.areaXY, state.allocator);
    defer state.allocator.free(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const writer = file.writer();
    var writeValues: [main.ChunkArea.SIZE * main.ChunkArea.SIZE * mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH]u8 = undefined;

    var count: u32 = 0;
    for (0..main.ChunkArea.SIZE) |chunkX| {
        for (0..main.ChunkArea.SIZE) |chunkY| {
            const chunkTileOffsetX = (@as(i32, @intCast(chunkX)) + chunkArea.areaXY.areaX * main.ChunkArea.SIZE) * mapZig.GameMap.CHUNK_LENGTH;
            const chunkTileOffsetY = (@as(i32, @intCast(chunkY)) + chunkArea.areaXY.areaY * main.ChunkArea.SIZE) * mapZig.GameMap.CHUNK_LENGTH;
            for (0..mapZig.GameMap.CHUNK_LENGTH) |tileX| {
                for (0..mapZig.GameMap.CHUNK_LENGTH) |tileY| {
                    const optObject = try mapZig.getObjectOnTile(.{
                        .tileX = @as(i32, @intCast(tileX)) + chunkTileOffsetX,
                        .tileY = @as(i32, @intCast(tileY)) + chunkTileOffsetY,
                    }, state);
                    var writeValue: u8 = 0;
                    if (optObject) |object| {
                        switch (object) {
                            .path => {
                                writeValue = SAVE_PATH;
                            },
                            .tree => {
                                writeValue = SAVE_TREE;
                            },
                            .building => {
                                writeValue = SAVE_BUILDING;
                            },
                            .bigBuilding => {
                                writeValue = SAVE_BIG_BUILDING;
                            },
                            .potatoField => {
                                writeValue = SAVE_POTATO;
                            },
                        }
                    } else {
                        writeValue = SAVE_EMPTY;
                    }
                    writeValues[count] = writeValue;
                    count += 1;
                }
            }
        }
    }
    try writer.writeAll(&writeValues);
}

pub fn loadChunkAreaFromFile(areaXY: main.ChunkAreaXY, state: *main.ChatSimState) !void {
    const path = try getFileNameForAreaXy(areaXY, state.allocator);
    defer state.allocator.free(path);

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const reader = file.reader();
    var readValues: [main.ChunkArea.SIZE * main.ChunkArea.SIZE * mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH]u8 = undefined;
    _ = try reader.readAll(&readValues);

    // var chunkArea: main.ChunkArea = .{.{
    //     .areaXY = areaXY,
    //     .activeChunkKeys = std.ArrayList(main.ChunkAreaActiveKey).init(state.allocator),
    //     .currentChunkKeyIndex = 0,
    // }};
    var currentChunkXY: mapZig.ChunkXY = .{ .chunkX = 0, .chunkY = 0 };
    var currentKey: u64 = 0;
    var currenChunk: ?mapZig.MapChunk = null;
    for (readValues, 0..) |value, index| {
        const tileXYIndex = @mod(index, mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH);
        if (tileXYIndex == 0) {
            const chunkInAreaIndex = @divFloor(index, mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH);
            if (currenChunk) |chunk| {
                if (state.map.chunks.contains(currentKey)) {
                    const oldChunk = state.map.chunks.getPtr(currentKey).?;
                    mapZig.destroyChunk(oldChunk);
                }
                try state.map.chunks.put(currentKey, chunk);
            }
            currentChunkXY = .{
                .chunkX = areaXY.areaX * main.ChunkArea.SIZE + @as(i32, @intCast(@divFloor(chunkInAreaIndex, main.ChunkArea.SIZE))),
                .chunkY = areaXY.areaY * main.ChunkArea.SIZE + @as(i32, @intCast(@mod(chunkInAreaIndex, main.ChunkArea.SIZE))),
            };
            currentKey = mapZig.getKeyForChunkXY(currentChunkXY);
            currenChunk = try mapZig.createEmptyChunk(currentChunkXY, state);
        }

        const position: main.Position = mapZig.mapTileXyToTileMiddlePosition(.{
            .tileX = @as(i32, @intCast(@divFloor(tileXYIndex, mapZig.GameMap.CHUNK_LENGTH))) + currentChunkXY.chunkX * mapZig.GameMap.CHUNK_LENGTH,
            .tileY = @as(i32, @intCast(@mod(tileXYIndex, mapZig.GameMap.CHUNK_LENGTH))) + currentChunkXY.chunkY * mapZig.GameMap.CHUNK_LENGTH,
        });

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
                else => {
                    //missing implementation or nothing to do
                },
            }
        }
    }
}
