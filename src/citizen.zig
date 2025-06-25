const std = @import("std");
const main = @import("main.zig");
const Position = main.Position;
const mapZig = @import("map.zig");
const imageZig = @import("image.zig");
const soundMixerZig = @import("soundMixer.zig");
const codePerformanceZig = @import("codePerformance.zig");
const chunkAreaZig = @import("chunkArea.zig");
const pathfindingZig = @import("pathfinding.zig");

pub const CitizenThinkAction = enum {
    idle,
    potatoHarvest,
    potatoEat,
    potatoEatFinished,
    potatoPlant,
    potatoPlantFinished,
    treePlant,
    treePlantFinished,
    buildingStart,
    buildingGetWood,
    buildingCutTree,
    buildingBuild,
    buildingFinished,
};

pub const Citizen: type = struct {
    position: Position,
    moveTo: std.ArrayList(main.Position),
    imageIndex: u8 = imageZig.IMAGE_CITIZEN_FRONT,
    moveSpeed: f16,
    directionX: f32 = 1,
    directionY: f32 = 0,
    buildingPosition: ?main.Position = null,
    treePosition: ?main.Position = null,
    farmPosition: ?main.Position = null,
    potatoPosition: ?main.Position = null,
    hasWood: bool = false,
    hasPotato: bool = false,
    homePosition: Position,
    foodLevel: f32 = 1,
    foodLevelLastUpdateTimeMs: u64 = 0,
    nextFoodTickTimeMs: u64 = 0,
    nextThinkingTickTimeMs: u64 = 0,
    nextThinkingAction: CitizenThinkAction = .idle,
    pathfindFailedCounter: u8 = 0,
    nextStuckCheckTime: ?u64 = null,
    pub const MAX_SQUARE_TILE_SEARCH_DISTANCE = 50;
    pub const FAILED_PATH_SEARCH_WAIT_TIME_MS = 3000;
    pub const RECHECK_STUCK_TIME_MS = 15_000;
    pub const MOVE_SPEED_STARVING = 0.5;
    pub const MOVE_SPEED_NORMAL = 2.0;
    pub const MOVE_SPEED_WODD_FACTOR = 0.75;

    pub fn createCitizen(homePosition: main.Position, allocator: std.mem.Allocator) Citizen {
        return Citizen{
            .position = .{ .x = 0, .y = 0 },
            .moveSpeed = Citizen.MOVE_SPEED_NORMAL,
            .moveTo = std.ArrayList(main.Position).init(allocator),
            .homePosition = homePosition,
        };
    }

    pub fn destroyCitizens(chunk: *mapZig.MapChunk) void {
        for (chunk.citizens.items) |*citizen| {
            citizen.moveTo.deinit();
        }
    }

    pub fn citizensTick(chunk: *mapZig.MapChunk, threadIndex: usize, state: *main.GameState) !void {
        const thinkTickInterval = 10;
        if (@mod(state.gameTimeMs, state.tickIntervalMs * thinkTickInterval) != @mod(chunk.chunkXY.chunkX, thinkTickInterval) * state.tickIntervalMs) return;
        for (0..chunk.citizens.items.len) |i| {
            if (chunk.citizens.unusedCapacitySlice().len < 16) try chunk.citizens.ensureUnusedCapacity(32);
            const citizen: *Citizen = &chunk.citizens.items[i];
            try foodTick(citizen, threadIndex, state);
            try thinkTick(citizen, threadIndex, chunk, state);
        }
    }

    pub fn citizensMoveTick(chunk: *mapZig.MapChunk) !void {
        for (0..chunk.citizens.items.len) |i| {
            const citizen: *Citizen = &chunk.citizens.items[i];
            citizenMove(citizen);
        }
    }

    pub fn moveToPosition(self: *Citizen, target: main.Position, threadIndex: usize, state: *main.GameState) !bool {
        if (main.calculateDistance(self.position, target) < 0.01) {
            // no pathfinding or moving required
            return true;
        }
        const goal = mapZig.mapPositionToTileXy(target);
        const foundPath = try main.pathfindingZig.pathfindAStar(goal, self, threadIndex, state);
        if (foundPath) {
            self.moveTo.items[0] = target;
            recalculateCitizenImageIndex(self);
            const direction = main.calculateDirection(self.position, self.moveTo.getLast());
            self.directionX = @cos(direction);
            self.directionY = @sin(direction);
            calculateMoveSpeed(self);
        } else {
            self.nextThinkingTickTimeMs = state.gameTimeMs + Citizen.FAILED_PATH_SEARCH_WAIT_TIME_MS;
        }
        return foundPath;
    }

    fn citizenMove(citizen: *Citizen) void {
        if (citizen.moveTo.items.len > 0) {
            const moveTo = citizen.moveTo.getLast();
            const moveSpeed = citizen.moveSpeed;
            citizen.position.x += citizen.directionX * moveSpeed;
            citizen.position.y += citizen.directionY * moveSpeed;
            const distance = @min(2, moveSpeed * 1.2);
            if (@abs(citizen.position.x - moveTo.x) <= moveSpeed * 1.2 and @abs(citizen.position.y - moveTo.y) <= distance) {
                _ = citizen.moveTo.pop();
                if (citizen.moveTo.items.len > 0) {
                    const direction = main.calculateDirection(citizen.position, citizen.moveTo.getLast());
                    citizen.directionX = @cos(direction);
                    citizen.directionY = @sin(direction);
                }
                recalculateCitizenImageIndex(citizen);
            }
        }
    }

    pub fn findCloseFreeCitizen(targetPosition: main.Position, threadIndex: usize, state: *main.GameState) !?struct { citizen: *Citizen, chunk: *mapZig.MapChunk } {
        var closestCitizen: ?*Citizen = null;
        var closestChunk: *mapZig.MapChunk = undefined;
        var shortestDistance: f32 = 0;

        var topLeftChunk = mapZig.getChunkXyForPosition(targetPosition);
        var iteration: u8 = 0;
        const maxIterations: u8 = @divFloor(Citizen.MAX_SQUARE_TILE_SEARCH_DISTANCE, mapZig.GameMap.CHUNK_LENGTH);
        mainLoop: while (closestCitizen == null and iteration < maxIterations) {
            const loops = iteration * 2 + 1;
            for (0..loops) |x| {
                for (0..loops) |y| {
                    if (x != 0 and x != loops - 1 and y != 0 and y != loops - 1) continue;
                    const chunkXY: mapZig.ChunkXY = .{
                        .chunkX = topLeftChunk.chunkX + @as(i32, @intCast(x)),
                        .chunkY = topLeftChunk.chunkY + @as(i32, @intCast(y)),
                    };
                    const chunk = try mapZig.getChunkByChunkXYWithRequestForLoad(chunkXY, threadIndex, state);
                    if (chunk == null) continue;
                    for (chunk.?.citizens.items) |*citizen| {
                        if (citizen.nextThinkingAction != .idle or citizen.nextStuckCheckTime != null) continue;
                        const tempDistance: f32 = main.calculateDistance(targetPosition, citizen.position);
                        if (closestCitizen == null or shortestDistance > tempDistance) {
                            closestCitizen = citizen;
                            closestChunk = chunk.?;
                            shortestDistance = tempDistance;
                            if (shortestDistance < mapZig.GameMap.CHUNK_SIZE) break :mainLoop;
                        }
                    }
                }
            }
            iteration += 1;
            topLeftChunk.chunkX -= 1;
            topLeftChunk.chunkY -= 1;
        }
        if (closestCitizen) |citizen| {
            return .{ .citizen = citizen, .chunk = closestChunk };
        } else {
            return null;
        }
    }

    pub fn handleRemovingCitizenAction(citizen: *main.Citizen, skipAreaXY: ?chunkAreaZig.ChunkAreaXY, state: *main.GameState) !void {
        // citizens has build order. Place it back
        var buildOrderPosition: ?main.Position = null;
        if (citizen.buildingPosition) |pos| {
            buildOrderPosition = pos;
        } else if (citizen.treePosition) |pos| {
            buildOrderPosition = pos;
        } else if (citizen.farmPosition) |pos| {
            buildOrderPosition = pos;
        }

        if (citizen.treePosition) |pos| {
            const posAreaXY = chunkAreaZig.getChunkAreaXyForPosition(pos);
            if (skipAreaXY == null or !chunkAreaZig.chunkAreaEquals(posAreaXY, skipAreaXY.?)) {
                if (chunkAreaZig.isChunkAreaLoaded(posAreaXY, state)) {
                    if (try mapZig.getChunkByPositionWithoutCreateOrLoad(pos, state)) |treeChunk| {
                        for (treeChunk.trees.items) |*tree| {
                            if (main.calculateDistance(pos, tree.position) < mapZig.GameMap.TILE_SIZE / 2) {
                                tree.beginCuttingTime = null;
                                tree.citizenOnTheWay = false;
                                break;
                            }
                        }
                    }
                }
            }
        }
        if (citizen.potatoPosition) |pos| {
            const posAreaXY = chunkAreaZig.getChunkAreaXyForPosition(pos);
            if (skipAreaXY == null or !chunkAreaZig.chunkAreaEquals(posAreaXY, skipAreaXY.?)) {
                if (chunkAreaZig.isChunkAreaLoaded(posAreaXY, state)) {
                    if (try mapZig.getChunkByPositionWithoutCreateOrLoad(pos, state)) |potatoChunk| {
                        for (potatoChunk.potatoFields.items) |*potatoField| {
                            if (main.calculateDistance(pos, potatoField.position) < mapZig.GameMap.TILE_SIZE / 2) {
                                potatoField.citizenOnTheWay -|= 1;
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (buildOrderPosition) |pos| {
            const posAreaXY = chunkAreaZig.getChunkAreaXyForPosition(pos);
            if (skipAreaXY == null or !chunkAreaZig.chunkAreaEquals(posAreaXY, skipAreaXY.?)) {
                if (try mapZig.getChunkByPositionWithoutCreateOrLoad(pos, state)) |buildOrderChunk| {
                    var isSpecialBigBuildingCase = false;
                    if (citizen.buildingPosition != null) {
                        //big buildings need more specific handling
                        for (buildOrderChunk.bigBuildings.items) |bigBuilding| {
                            if (main.calculateDistance(pos, bigBuilding.position) < mapZig.GameMap.TILE_SIZE / 2) {
                                for (buildOrderChunk.buildOrders.items) |*buildOrder| {
                                    if (main.calculateDistance(pos, buildOrder.position) < mapZig.GameMap.TILE_SIZE / 2) {
                                        buildOrder.materialCount += 1;
                                        isSpecialBigBuildingCase = true;
                                        break;
                                    }
                                }
                                break;
                            }
                        }
                    }
                    if (!isSpecialBigBuildingCase) {
                        try buildOrderChunk.buildOrders.append(.{ .position = pos, .materialCount = 1 });
                    }
                }
            }
        }
        citizen.hasWood = false;
        citizen.potatoPosition = null;
        citizen.buildingPosition = null;
        citizen.treePosition = null;
        citizen.farmPosition = null;
    }
};

fn thinkTick(citizen: *Citizen, threadIndex: usize, chunk: *mapZig.MapChunk, state: *main.GameState) !void {
    if (citizen.nextThinkingTickTimeMs > state.gameTimeMs) return;
    if (citizen.moveTo.items.len > 0) return;

    switch (citizen.nextThinkingAction) {
        .potatoHarvest => {
            try potatoHarvestTick(citizen, threadIndex, state);
        },
        .potatoEat => {
            try potatoEatTick(citizen, threadIndex, state);
        },
        .potatoEatFinished => {
            try potatoEatFinishedTick(citizen, threadIndex, state);
        },
        .potatoPlant => {
            try potatoPlant(citizen, threadIndex, state);
        },
        .potatoPlantFinished => {
            try potatoPlantFinished(citizen, threadIndex, state);
            chunk.workingCitizenCounter -= 1;
        },
        .buildingStart => {
            try buildingStart(citizen, threadIndex, state);
        },
        .buildingGetWood => {
            try buildingGetWood(citizen, threadIndex, state);
        },
        .buildingCutTree => {
            try buildingCutTree(citizen, threadIndex, state);
        },
        .buildingBuild => {
            try buildingBuild(citizen, threadIndex, state);
        },
        .buildingFinished => {
            try buildingFinished(citizen, threadIndex, state);
            chunk.workingCitizenCounter -= 1;
        },
        .treePlant => {
            try treePlant(citizen, threadIndex, state);
        },
        .treePlantFinished => {
            try treePlantFinished(citizen, threadIndex, state);
            chunk.workingCitizenCounter -= 1;
        },
        .idle => {
            try setRandomMoveTo(citizen, threadIndex, state);
            if (citizen.nextStuckCheckTime != null and citizen.nextStuckCheckTime.? < state.gameTimeMs) {
                if (try pathfindingZig.checkIsPositionReachableMovementAreaBiggerThan(citizen.position, threadIndex, 50, state)) {
                    citizen.nextStuckCheckTime = null;
                } else {
                    citizen.nextStuckCheckTime = state.gameTimeMs + Citizen.RECHECK_STUCK_TIME_MS;
                }
            }
        },
    }
}

fn nextThinkingAction(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (try checkHunger(citizen, threadIndex, state)) {
        //nothing
    } else if (citizen.buildingPosition != null) {
        citizen.nextThinkingAction = .buildingStart;
    } else if (citizen.farmPosition != null) {
        citizen.nextThinkingAction = .potatoPlant;
    } else if (citizen.treePosition != null) {
        citizen.nextThinkingAction = .treePlant;
    } else {
        citizen.nextThinkingAction = .idle;
    }
}

/// returns true if citizen goes to eat
fn checkHunger(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !bool {
    if (citizen.foodLevel <= 0.5) {
        if (try findClosestFreePotato(citizen, threadIndex, state)) |potato| {
            potato.citizenOnTheWay += 1;
            citizen.potatoPosition = potato.position;
            citizen.nextThinkingAction = .potatoHarvest;
            citizen.moveTo.clearRetainingCapacity();
            return true;
        }
    }
    return false;
}

fn calculateMoveSpeed(citizen: *Citizen) void {
    if (citizen.moveTo.items.len > 0) {
        var moveSpeed: f16 = if ((citizen.foodLevel > 0 and citizen.nextThinkingAction != .idle) or citizen.nextThinkingAction == .potatoHarvest) Citizen.MOVE_SPEED_NORMAL else Citizen.MOVE_SPEED_STARVING;
        if (citizen.hasWood) moveSpeed *= Citizen.MOVE_SPEED_WODD_FACTOR;
        citizen.moveSpeed = moveSpeed;
    }
}

fn onBeingStuck(citizen: *Citizen, state: *main.GameState) !void {
    try main.Citizen.handleRemovingCitizenAction(citizen, null, state);
    citizen.nextThinkingAction = .idle;
    citizen.pathfindFailedCounter +|= 1;
    if (citizen.pathfindFailedCounter > 2) {
        citizen.nextStuckCheckTime = state.gameTimeMs + Citizen.RECHECK_STUCK_TIME_MS;
    }
}

fn treePlant(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (try mapZig.getTreeOnPosition(citizen.treePosition.?, threadIndex, state)) |treeAndChunk| {
        if (main.calculateDistance(citizen.position, treeAndChunk.tree.position) < mapZig.GameMap.TILE_SIZE / 2) {
            citizen.nextThinkingTickTimeMs = state.gameTimeMs + 1000;
            citizen.nextThinkingAction = .treePlantFinished;
        } else {
            if (!try citizen.moveToPosition(.{ .x = treeAndChunk.tree.position.x, .y = treeAndChunk.tree.position.y - 4 }, threadIndex, state)) {
                try onBeingStuck(citizen, state);
                const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(citizen.homePosition, threadIndex, state);
                chunk.workingCitizenCounter -= 1;
            }
        }
    } else {
        citizen.treePosition = null;
        const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(citizen.homePosition, threadIndex, state);
        chunk.workingCitizenCounter -= 1;
        try nextThinkingAction(citizen, threadIndex, state);
    }
}

fn treePlantFinished(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (try mapZig.getTreeOnPosition(citizen.treePosition.?, threadIndex, state)) |treeAndChunk| {
        treeAndChunk.tree.growStartTimeMs = state.gameTimeMs;
        const queueItem = mapZig.ChunkQueueItem{ .itemData = .{ .tree = treeAndChunk.treeIndex }, .executeTime = state.gameTimeMs + mapZig.GROW_TIME_MS };
        try mapZig.appendToChunkQueue(treeAndChunk.chunk, queueItem, citizen.homePosition, threadIndex, state);
    }
    citizen.treePosition = null;
    try nextThinkingAction(citizen, threadIndex, state);
}

fn buildingStart(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (citizen.hasWood == false) {
        if (citizen.treePosition == null) {
            try findAndSetFastestTree(citizen, citizen.buildingPosition.?, threadIndex, state);
            if (citizen.treePosition == null and try mapZig.getBuildingOnPosition(citizen.buildingPosition.?, threadIndex, state) == null) {
                citizen.treePosition = null;
                citizen.buildingPosition = null;
                const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(citizen.homePosition, threadIndex, state);
                chunk.workingCitizenCounter -= 1;
                if (citizen.nextThinkingAction == .buildingStart) try nextThinkingAction(citizen, threadIndex, state);
            }
        } else {
            citizen.nextThinkingAction = .buildingGetWood;
        }
    } else {
        citizen.nextThinkingAction = .buildingBuild;
    }
}

fn buildingGetWood(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (main.calculateDistance(citizen.treePosition.?, citizen.position) < mapZig.GameMap.TILE_SIZE / 2) {
        if (try mapZig.getTreeOnPosition(citizen.treePosition.?, threadIndex, state)) |treeData| {
            citizen.nextThinkingTickTimeMs = state.gameTimeMs + main.CITIZEN_TREE_CUT_DURATION;
            citizen.nextThinkingAction = .buildingCutTree;
            treeData.tree.beginCuttingTime = state.gameTimeMs;
            const woodCutSoundInterval: u32 = @intFromFloat(std.math.pi * 200);
            var temp: u32 = @divFloor(woodCutSoundInterval, 2);
            if (state.camera.zoom > 0.5) {
                const tooFarAwayFromCameraForSounds = main.calculateDistance(citizen.position, state.camera.position) > 1000;
                if (!tooFarAwayFromCameraForSounds) {
                    while (temp < main.CITIZEN_TREE_CUT_DURATION) {
                        try soundMixerZig.playSoundInFuture(&state.soundMixer, soundMixerZig.getRandomWoodChopIndex(), state.gameTimeMs + temp, citizen.position);
                        temp += woodCutSoundInterval;
                    }
                    try soundMixerZig.playSoundInFuture(&state.soundMixer, soundMixerZig.SOUND_TREE_FALLING, state.gameTimeMs + main.CITIZEN_TREE_CUT_PART1_DURATION, citizen.position);
                }
            }
        } else {
            citizen.treePosition = null;
            citizen.nextThinkingAction = .buildingStart;
        }
    } else {
        const treeXOffset: f32 = if (citizen.position.x < citizen.treePosition.?.x) -7 else 7;
        if (!try citizen.moveToPosition(.{ .x = citizen.treePosition.?.x + treeXOffset, .y = citizen.treePosition.?.y + 3 }, threadIndex, state)) {
            try onBeingStuck(citizen, state);
            const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(citizen.homePosition, threadIndex, state);
            chunk.workingCitizenCounter -= 1;
        }
    }
}

fn buildingCutTree(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (try mapZig.getTreeOnPosition(citizen.treePosition.?, threadIndex, state)) |treeData| {
        citizen.hasWood = true;
        treeData.tree.fullyGrown = false;
        treeData.tree.citizenOnTheWay = false;
        treeData.tree.beginCuttingTime = null;
        citizen.treePosition = null;
        if (!treeData.tree.regrow) {
            mapZig.removeTree(treeData.treeIndex, false, treeData.chunk);
        } else {
            treeData.tree.growStartTimeMs = state.gameTimeMs;
            const queueItem = mapZig.ChunkQueueItem{ .itemData = .{ .tree = treeData.treeIndex }, .executeTime = state.gameTimeMs + mapZig.GROW_TIME_MS };
            try mapZig.appendToChunkQueue(treeData.chunk, queueItem, citizen.homePosition, threadIndex, state);
        }
        if (!try checkHunger(citizen, threadIndex, state)) {
            citizen.nextThinkingAction = .buildingBuild;
        }
    } else {
        citizen.treePosition = null;
        citizen.nextThinkingAction = .buildingStart;
    }
}

fn buildingBuild(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    const optBuilding = try mapZig.getBuildingOnPosition(citizen.buildingPosition.?, threadIndex, state);
    if (optBuilding != null and optBuilding.?.inConstruction) {
        const building = optBuilding.?;
        if (main.calculateDistance(citizen.position, citizen.buildingPosition.?) < mapZig.GameMap.TILE_SIZE / 2) {
            if (try mapZig.canBuildOrWaitForTreeCutdown(citizen.buildingPosition.?, threadIndex, state)) {
                citizen.nextThinkingTickTimeMs = state.gameTimeMs + 3000;
                citizen.nextThinkingAction = .buildingFinished;
                building.constructionStartedTime = state.gameTimeMs;
                if (state.camera.zoom > 0.5) {
                    const tooFarAwayFromCameraForSounds = main.calculateDistance(citizen.position, state.camera.position) > 1000;
                    if (!tooFarAwayFromCameraForSounds) {
                        const hammerSoundInterval: u32 = @intFromFloat(std.math.pi * 200);
                        var temp: u32 = @divFloor(hammerSoundInterval, 2);
                        while (temp < 3000) {
                            try soundMixerZig.playSoundInFuture(&state.soundMixer, soundMixerZig.SOUND_HAMMER_WOOD, state.gameTimeMs + temp, citizen.position);
                            temp += hammerSoundInterval;
                        }
                    }
                }
            } else {
                citizen.nextThinkingTickTimeMs = state.gameTimeMs + 250;
            }
        } else {
            citizen.buildingPosition = building.position; // a case exists where a normal building is swapped to big building build order which otherwise would stuck the citizen
            const buildingXOffset: f32 = if (citizen.position.x < building.position.x) -7 else 7;
            if (!try citizen.moveToPosition(.{ .x = building.position.x + buildingXOffset, .y = building.position.y + 3 }, threadIndex, state)) {
                try onBeingStuck(citizen, state);
                const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(citizen.homePosition, threadIndex, state);
                chunk.workingCitizenCounter -= 1;
            }
        }
    } else {
        citizen.hasWood = false;
        citizen.buildingPosition = null;
        const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(citizen.homePosition, threadIndex, state);
        chunk.workingCitizenCounter -= 1;
        try nextThinkingAction(citizen, threadIndex, state);
    }
}

fn buildingFinished(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (try mapZig.getBuildingOnPosition(citizen.buildingPosition.?, threadIndex, state)) |building| {
        citizen.hasWood = false;
        citizen.buildingPosition = null;
        try mapZig.finishBuilding(building, threadIndex, state);
        try nextThinkingAction(citizen, threadIndex, state);
    } else {
        citizen.hasWood = false;
        citizen.buildingPosition = null;
        try nextThinkingAction(citizen, threadIndex, state);
    }
}

fn potatoPlant(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (try mapZig.getPotatoFieldOnPosition(citizen.farmPosition.?, threadIndex, state)) |farmData| {
        if (main.calculateDistance(farmData.potatoField.position, citizen.position) <= mapZig.GameMap.TILE_SIZE / 2) {
            if (try mapZig.canBuildOrWaitForTreeCutdown(citizen.farmPosition.?, threadIndex, state)) {
                citizen.nextThinkingTickTimeMs = state.gameTimeMs + 1500;
                citizen.nextThinkingAction = .potatoPlantFinished;
            }
        } else {
            if (!try citizen.moveToPosition(.{ .x = farmData.potatoField.position.x, .y = farmData.potatoField.position.y - 5 }, threadIndex, state)) {
                try onBeingStuck(citizen, state);
                const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(citizen.homePosition, threadIndex, state);
                chunk.workingCitizenCounter -= 1;
            }
        }
    } else {
        citizen.farmPosition = null;
        const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(citizen.homePosition, threadIndex, state);
        chunk.workingCitizenCounter -= 1;
        try nextThinkingAction(citizen, threadIndex, state);
    }
}

fn potatoPlantFinished(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (try mapZig.getPotatoFieldOnPosition(citizen.farmPosition.?, threadIndex, state)) |farmData| {
        farmData.potatoField.growStartTimeMs = state.gameTimeMs;
        const queueItem = mapZig.ChunkQueueItem{ .itemData = .{ .potatoField = farmData.potatoIndex }, .executeTime = state.gameTimeMs + mapZig.GROW_TIME_MS };
        try mapZig.appendToChunkQueue(farmData.chunk, queueItem, citizen.homePosition, threadIndex, state);
    }
    citizen.farmPosition = null;
    try nextThinkingAction(citizen, threadIndex, state);
}

fn potatoHarvestTick(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (try mapZig.getPotatoFieldOnPosition(citizen.potatoPosition.?, threadIndex, state)) |farmData| {
        if (main.calculateDistance(farmData.potatoField.position, citizen.position) <= mapZig.GameMap.TILE_SIZE / 2) {
            if (farmData.potatoField.fullyGrown) {
                citizen.nextThinkingTickTimeMs = state.gameTimeMs + 1500;
                citizen.nextThinkingAction = .potatoEat;
            }
        } else {
            if (!try citizen.moveToPosition(.{ .x = farmData.potatoField.position.x, .y = farmData.potatoField.position.y - 8 }, threadIndex, state)) {
                try onBeingStuck(citizen, state);
            }
        }
    } else {
        citizen.potatoPosition = null;
        try nextThinkingAction(citizen, threadIndex, state);
    }
}

fn potatoEatFinishedTick(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    citizen.hasPotato = false;
    eatFood(0.5, citizen, state);
    try nextThinkingAction(citizen, threadIndex, state);
}

fn potatoEatTick(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (try mapZig.getPotatoFieldOnPosition(citizen.potatoPosition.?, threadIndex, state)) |farmData| {
        farmData.potatoField.growStartTimeMs = state.gameTimeMs;
        const queueItem = mapZig.ChunkQueueItem{ .itemData = .{ .potatoField = farmData.potatoIndex }, .executeTime = state.gameTimeMs + mapZig.GROW_TIME_MS };
        try mapZig.appendToChunkQueue(farmData.chunk, queueItem, citizen.homePosition, threadIndex, state);
        farmData.potatoField.fullyGrown = false;
        farmData.potatoField.citizenOnTheWay -|= 1;
        citizen.potatoPosition = null;
        citizen.hasPotato = true;
        citizen.nextThinkingTickTimeMs = state.gameTimeMs + 1500;
        citizen.nextThinkingAction = .potatoEatFinished;
    } else {
        citizen.potatoPosition = null;
        try nextThinkingAction(citizen, threadIndex, state);
    }
}

fn recalculateCitizenImageIndex(citizen: *Citizen) void {
    if (citizen.moveTo.items.len > 0) {
        const xDiff = citizen.moveTo.getLast().x - citizen.position.x;
        const yDiff = citizen.moveTo.getLast().y - citizen.position.y;
        if (@abs(xDiff) > @abs(yDiff)) {
            if (xDiff > 0) {
                citizen.imageIndex = imageZig.IMAGE_CITIZEN_RIGHT;
            } else {
                citizen.imageIndex = imageZig.IMAGE_CITIZEN_LEFT;
            }
        } else {
            if (yDiff < 0) {
                citizen.imageIndex = imageZig.IMAGE_CITIZEN_BACK;
            } else {
                citizen.imageIndex = imageZig.IMAGE_CITIZEN_FRONT;
            }
        }
    } else {
        if (citizen.treePosition) |treePosition| {
            if (treePosition.x < citizen.position.x) {
                citizen.imageIndex = imageZig.IMAGE_CITIZEN_LEFT;
            } else {
                citizen.imageIndex = imageZig.IMAGE_CITIZEN_RIGHT;
            }
        } else if (citizen.buildingPosition) |buildingPosition| {
            if (buildingPosition.x < citizen.position.x) {
                citizen.imageIndex = imageZig.IMAGE_CITIZEN_LEFT;
            } else {
                citizen.imageIndex = imageZig.IMAGE_CITIZEN_RIGHT;
            }
        } else {
            citizen.imageIndex = imageZig.IMAGE_CITIZEN_FRONT;
        }
    }
}

fn eatFood(foodAmount: f32, citizen: *Citizen, state: *main.GameState) void {
    citizen.foodLevel += foodAmount;
    const timePassed: f32 = @floatFromInt(state.gameTimeMs - citizen.foodLevelLastUpdateTimeMs);
    citizen.foodLevel -= 1.0 / 60.0 / 1000.0 * timePassed;
    citizen.foodLevelLastUpdateTimeMs = state.gameTimeMs;
    const footUntilHungry = citizen.foodLevel - 0.5;
    citizen.nextFoodTickTimeMs = state.gameTimeMs;
    if (footUntilHungry > 0) {
        const timeUntilHungry: u32 = @intFromFloat((footUntilHungry + 0.01) * 60.0 * 1000.0);
        citizen.nextFoodTickTimeMs += timeUntilHungry;
    }
}

fn foodTick(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    if (citizen.nextFoodTickTimeMs > state.gameTimeMs) return;
    if (citizen.foodLevelLastUpdateTimeMs == 0) {
        citizen.foodLevelLastUpdateTimeMs = state.gameTimeMs;
        eatFood(0, citizen, state); // used for setting up some data
        return;
    }
    if (state.gameTimeMs - citizen.nextFoodTickTimeMs > 5_000) {
        //assume chunk was idle for some time so reducing foodLevel will be bad as they could not eat in the time
        citizen.foodLevelLastUpdateTimeMs = state.gameTimeMs;
        eatFood(0, citizen, state);
        return;
    }
    const timePassed: f32 = @floatFromInt(state.gameTimeMs - citizen.foodLevelLastUpdateTimeMs);
    citizen.foodLevel -= 1.0 / 60.0 / 1000.0 * timePassed;
    citizen.foodLevelLastUpdateTimeMs = state.gameTimeMs;
    if (citizen.nextThinkingAction == .idle) try nextThinkingAction(citizen, threadIndex, state);
    if (citizen.foodLevel > 0) {
        const timeUntilStarving: u32 = @intFromFloat((citizen.foodLevel + 0.01) * 60.0 * 1000.0);
        citizen.nextFoodTickTimeMs = state.gameTimeMs + timeUntilStarving;
    } else {
        citizen.nextFoodTickTimeMs = state.gameTimeMs + 15_000;
        calculateMoveSpeed(citizen);
        if (citizen.foodLevel < -0.5) {
            citizen.foodLevel = -0.5;
        }
    }
}

fn findClosestFreePotato(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !?*mapZig.PotatoField {
    const homeChunkXY = mapZig.getChunkXyForPosition(citizen.homePosition);
    const optHomeChunk = try mapZig.getChunkByChunkXYWithRequestForLoad(homeChunkXY, threadIndex, state);
    if (optHomeChunk == null) return null;
    const homeChunk = optHomeChunk.?;
    if (homeChunk.noPotatoLeftInChunkProximityGameTime == state.gameTimeMs) return null;
    var shortestDistance: f32 = 0;
    var resultPotatoField: ?*mapZig.PotatoField = null;
    var topLeftChunk = mapZig.getChunkXyForPosition(citizen.position);
    var iteration: u8 = 0;
    const maxChunkDistance = @divFloor(Citizen.MAX_SQUARE_TILE_SEARCH_DISTANCE, mapZig.GameMap.CHUNK_LENGTH);
    const citizenHomeDistance = @max(@abs(homeChunkXY.chunkX - topLeftChunk.chunkX), @abs(homeChunkXY.chunkY - topLeftChunk.chunkY));
    const maxIterations = maxChunkDistance + citizenHomeDistance;
    while (resultPotatoField == null and iteration < maxIterations) {
        const loops = iteration * 2 + 1;
        for (0..loops) |x| {
            for (0..loops) |y| {
                if (x != 0 and x != loops - 1 and y != 0 and y != loops - 1) continue;
                const chunkXY: mapZig.ChunkXY = .{
                    .chunkX = topLeftChunk.chunkX + @as(i32, @intCast(x)),
                    .chunkY = topLeftChunk.chunkY + @as(i32, @intCast(y)),
                };
                const toFarX = @abs(chunkXY.chunkX - homeChunkXY.chunkX) >= maxChunkDistance;
                const toFarY = @abs(chunkXY.chunkY - homeChunkXY.chunkY) >= maxChunkDistance;
                if (toFarX or toFarY) continue;

                const chunk = try mapZig.getChunkByChunkXYWithRequestForLoad(chunkXY, threadIndex, state);
                if (chunk == null) continue;
                for (chunk.?.potatoFields.items) |*potatoField| {
                    if ((!potatoField.fullyGrown and potatoField.growStartTimeMs == null) or potatoField.citizenOnTheWay >= 2) continue;
                    if (potatoField.citizenOnTheWay > 0 and potatoField.growStartTimeMs != null) continue;
                    var tempDistance: f32 = main.calculateDistance(citizen.position, potatoField.position) + @as(f32, @floatFromInt(potatoField.citizenOnTheWay)) * 40.0;
                    if (potatoField.growStartTimeMs) |time| {
                        tempDistance += 40 - @as(f32, @floatFromInt(state.gameTimeMs - time)) / 250;
                    }
                    if (resultPotatoField == null or shortestDistance > tempDistance) {
                        shortestDistance = tempDistance;
                        resultPotatoField = potatoField;
                    }
                }
            }
        }
        iteration += 1;
        topLeftChunk.chunkX -= 1;
        topLeftChunk.chunkY -= 1;
    }
    if (resultPotatoField == null) {
        homeChunk.noPotatoLeftInChunkProximityGameTime = state.gameTimeMs;
    }
    return resultPotatoField;
}

fn findAndSetFastestTree(citizen: *Citizen, targetPosition: Position, threadIndex: usize, state: *main.GameState) !void {
    const homeChunkXY = mapZig.getChunkXyForPosition(citizen.homePosition);
    const optHomeChunk = try mapZig.getChunkByChunkXYWithRequestForLoad(homeChunkXY, threadIndex, state);
    if (optHomeChunk == null) return;
    const homeChunk = optHomeChunk.?;
    if (homeChunk.noTreeLeftInChunkProximityGameTime == state.gameTimeMs) {
        if (!try checkHunger(citizen, threadIndex, state)) {
            try setRandomMoveTo(citizen, threadIndex, state);
        }
        return;
    }
    var closestTree: ?*mapZig.MapTree = null;
    var fastestDistance: f64 = 0;
    var topLeftChunk = mapZig.getChunkXyForPosition(targetPosition);
    var iteration: u8 = 0;
    const maxChunkDistance = @divFloor(Citizen.MAX_SQUARE_TILE_SEARCH_DISTANCE, mapZig.GameMap.CHUNK_LENGTH);
    const citizenHomeDistance = @max(@abs(homeChunkXY.chunkX - topLeftChunk.chunkX), @abs(homeChunkXY.chunkY - topLeftChunk.chunkY));
    const maxIterations = maxChunkDistance + citizenHomeDistance;
    while (closestTree == null and iteration < maxIterations) {
        const loops = iteration * 2 + 1;
        for (0..loops) |x| {
            for (0..loops) |y| {
                if (x != 0 and x != loops - 1 and y != 0 and y != loops - 1) continue;
                const chunkXY: mapZig.ChunkXY = .{
                    .chunkX = topLeftChunk.chunkX + @as(i32, @intCast(x)),
                    .chunkY = topLeftChunk.chunkY + @as(i32, @intCast(y)),
                };
                const toFarX = @abs(chunkXY.chunkX - homeChunkXY.chunkX) >= maxChunkDistance;
                const toFarY = @abs(chunkXY.chunkY - homeChunkXY.chunkY) >= maxChunkDistance;
                if (toFarX or toFarY) continue;

                const chunk = try mapZig.getChunkByChunkXYWithRequestForLoad(chunkXY, threadIndex, state);
                if (chunk == null) continue;
                for (chunk.?.trees.items) |*tree| {
                    if (!tree.fullyGrown or tree.citizenOnTheWay) continue;
                    const tempDistance = main.calculateDistance(citizen.position, tree.position) + main.calculateDistance(tree.position, targetPosition);
                    if (closestTree == null or fastestDistance > tempDistance) {
                        closestTree = tree;
                        fastestDistance = tempDistance;
                    }
                }
            }
        }
        iteration += 1;
        topLeftChunk.chunkX -= 1;
        topLeftChunk.chunkY -= 1;
    }
    if (closestTree != null) {
        citizen.treePosition = closestTree.?.position;
        closestTree.?.citizenOnTheWay = true;
    } else {
        homeChunk.noTreeLeftInChunkProximityGameTime = state.gameTimeMs;
        if (!try checkHunger(citizen, threadIndex, state)) {
            try setRandomMoveTo(citizen, threadIndex, state);
        }
    }
}

fn setRandomMoveTo(citizen: *Citizen, threadIndex: usize, state: *main.GameState) !void {
    const optRandomPos = try main.pathfindingZig.getRandomClosePathingPosition(citizen, threadIndex, state);
    if (optRandomPos) |randomPos| {
        _ = try citizen.moveToPosition(randomPos, threadIndex, state);
    }
}
