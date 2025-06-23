const std = @import("std");
const main = @import("main.zig");

const ISteamUserStats = opaque {};
pub extern fn SteamAPI_InitFlat(err: ?*[1024]u8) callconv(.C) u32;
pub extern fn SteamAPI_Shutdown() callconv(.C) void;
pub extern fn SteamAPI_SteamUserStats_v013() callconv(.C) ?*ISteamUserStats;
pub extern fn SteamAPI_ISteamUserStats_StoreStats(ptr: ?*ISteamUserStats) callconv(.C) bool;
pub extern fn SteamAPI_ISteamUserStats_ClearAchievement(ptr: ?*ISteamUserStats, pchName: [*c]const u8) callconv(.C) bool;
pub extern fn SteamAPI_ISteamUserStats_SetAchievement(ptr: ?*ISteamUserStats, pchName: [*c]const u8) callconv(.C) bool;
pub extern fn SteamAPI_ISteamUserStats_GetAchievement(ptr: ?*ISteamUserStats, pchName: [*c]const u8, pbAchieved: *bool) callconv(.C) bool;

pub fn setAchievement(achievementName: [*:0]const u8) bool {
    return SteamAPI_ISteamUserStats_ClearAchievement(SteamAPI_SteamUserStats_v013(), achievementName);
}

pub fn steamInit(state: *main.GameState) void {
    if (SteamAPI_InitFlat(null) == 0) {
        state.steamEnabled = true;
        std.debug.print("steam connected\n", .{});
    } else {
        std.debug.print("steam init failed\n", .{});
    }
}
