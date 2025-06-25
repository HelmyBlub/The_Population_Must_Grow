const std = @import("std");
const main = @import("main.zig");
const countryPopulationDataZig = @import("countryPopulationData.zig");

const ISteamUserStats = opaque {};
pub extern fn SteamAPI_InitFlat(err: ?*[1024]u8) callconv(.C) u32;
pub extern fn SteamAPI_Shutdown() callconv(.C) void;
pub extern fn SteamAPI_SteamUserStats_v013() callconv(.C) ?*ISteamUserStats;
pub extern fn SteamAPI_ISteamUserStats_StoreStats(ptr: ?*ISteamUserStats) callconv(.C) bool;
pub extern fn SteamAPI_ISteamUserStats_ClearAchievement(ptr: ?*ISteamUserStats, pchName: [*c]const u8) callconv(.C) bool;
pub extern fn SteamAPI_ISteamUserStats_SetAchievement(ptr: ?*ISteamUserStats, pchName: [*c]const u8) callconv(.C) bool;
pub extern fn SteamAPI_ISteamUserStats_GetAchievement(ptr: ?*ISteamUserStats, pchName: [*c]const u8, pbAchieved: *bool) callconv(.C) bool;

pub const SteamData = struct {
    earliestNextStoreStats: i64,
};
const MIN_STORE_INTERVAL = 60;

pub fn setAchievement(popIndex: usize, state: *main.GameState) !void {
    if (state.steam != null and state.testData == null) {
        std.debug.print("pleas no steam in test\n", .{});
        if (countryPopulationDataZig.WORLD_POPULATION[popIndex].hasAchievement) {
            var buf: [5]u8 = [_]u8{ 0, 0, 0, 0, 0 };
            _ = try std.fmt.bufPrint(&buf, "{d}", .{(popIndex + 1)});
            var achieved: bool = false;
            const success = SteamAPI_ISteamUserStats_GetAchievement(SteamAPI_SteamUserStats_v013(), &buf, &achieved);
            if (!achieved and success) {
                _ = SteamAPI_ISteamUserStats_SetAchievement(SteamAPI_SteamUserStats_v013(), &buf);
                const timestamp = std.time.timestamp();
                if (state.steam.?.earliestNextStoreStats < timestamp) {
                    _ = SteamAPI_ISteamUserStats_StoreStats(SteamAPI_SteamUserStats_v013());
                    state.steam.?.earliestNextStoreStats = timestamp + MIN_STORE_INTERVAL;
                }
            }
        }
    }
}

pub fn steamInit(state: *main.GameState) void {
    if (state.testData != null) return;
    if (SteamAPI_InitFlat(null) == 0) {
        state.steam = .{ .earliestNextStoreStats = std.time.timestamp() };
        std.debug.print("steam connected\n", .{});
    } else {
        std.debug.print("steam init failed\n", .{});
    }
}
