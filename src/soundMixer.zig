const std = @import("std");
const main = @import("main.zig");
const mapZig = @import("map.zig");
const minimp3 = @cImport({
    @cInclude("minimp3_ex.h");
});
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
});

pub const SoundMixer = struct {
    mutex: std.Thread.Mutex = .{},
    volume: f32 = 1,
    addedSoundDataUntilTimeMs: i64 = 0,
    soundsFutureQueue: std.ArrayList(FutureSoundToPlay),
    soundsToPlay: std.ArrayList(SoundToPlay),
    soundData: SoundData = undefined,
    countTreeFalling: u8 = 0,
    countWoodCut: u8 = 0,
    countHammer: u8 = 0,
    pub const LIMIT_TREE_FALLING: u8 = 24;
    pub const LIMIT_WOOD_CUT: u8 = 24;
    pub const LIMIT_HAMMER: u8 = 24;
    pub const MAX_SOUNDS_AT_ONCE: u32 = 24 * 3;
};

const SoundToPlay = struct {
    soundIndex: usize,
    dataIndex: usize = 0,
    mapPosition: main.Position,
};

const FutureSoundToPlay = struct {
    soundIndex: usize,
    startGameTimeMs: u32,
    mapPosition: main.Position,
};

const SoundFile = struct {
    data: [*]u8,
    len: u32,
    mp3: ?[]i16,
};

pub const SoundData = struct {
    stream: ?*sdl.SDL_AudioStream,
    sounds: []SoundFile,
};

pub fn createSoundMixer(state: *main.ChatSimState, allocator: std.mem.Allocator) !void {
    state.soundMixer = .{
        .soundsToPlay = std.ArrayList(SoundToPlay).init(allocator),
        .soundsFutureQueue = std.ArrayList(FutureSoundToPlay).init(allocator),
    };
    state.soundMixer.soundData = try initSounds(state, allocator);
    try state.soundMixer.soundsToPlay.ensureTotalCapacity(SoundMixer.MAX_SOUNDS_AT_ONCE);
}

pub fn destroySoundMixer(state: *main.ChatSimState) void {
    state.soundMixer.mutex.lock();
    defer state.soundMixer.mutex.unlock();
    state.soundMixer.soundsToPlay.deinit();
    state.soundMixer.soundsFutureQueue.deinit();
    sdl.SDL_DestroyAudioStream(state.soundMixer.soundData.stream);
    for (state.soundMixer.soundData.sounds) |sound| {
        if (sound.mp3) |dealocate| {
            state.allocator.free(dealocate);
        } else {
            sdl.SDL_free(sound.data);
        }
    }
    state.allocator.free(state.soundMixer.soundData.sounds);
}

pub fn tickSoundMixer(state: *main.ChatSimState) !void {
    var index: usize = 0;
    while (index < state.soundMixer.soundsFutureQueue.items.len) {
        const item = state.soundMixer.soundsFutureQueue.items[index];
        if (item.startGameTimeMs <= state.gameTimeMs) {
            const removed = state.soundMixer.soundsFutureQueue.swapRemove(index);
            const offset = (state.gameTimeMs - removed.startGameTimeMs) * 48 * 2;
            try playSound(&state.soundMixer, removed.soundIndex, offset, removed.mapPosition);
        } else {
            index += 1;
        }
    }

    var i: usize = 0;
    while (i < state.soundMixer.soundsToPlay.items.len) {
        if (state.soundMixer.soundsToPlay.items[i].dataIndex >= state.soundMixer.soundData.sounds[state.soundMixer.soundsToPlay.items[i].soundIndex].len) {
            const removed = state.soundMixer.soundsToPlay.swapRemove(i);
            switch (removed.soundIndex) {
                SOUND_HAMMER_WOOD => {
                    state.soundMixer.countHammer -= 1;
                },
                SOUND_TREE_FALLING => {
                    state.soundMixer.countTreeFalling -= 1;
                },
                SOUND_WOOD_CHOP_1, SOUND_WOOD_CHOP_2, SOUND_WOOD_CHOP_3, SOUND_WOOD_CHOP_4, SOUND_WOOD_CHOP_5 => {
                    state.soundMixer.countWoodCut -= 1;
                },
                else => {
                    unreachable;
                },
            }
        } else {
            i += 1;
        }
    }
}

fn audioCallback(userdata: ?*anyopaque, stream: ?*sdl.SDL_AudioStream, additional_amount: c_int, len: c_int) callconv(.C) void {
    _ = len;
    const Sample = i16;
    const state: *main.ChatSimState = @ptrCast(@alignCast(userdata.?));
    state.soundMixer.mutex.lock();
    defer state.soundMixer.mutex.unlock();
    if (state.gameEnd) return;

    const sampleCount = @divExact(additional_amount, @sizeOf(Sample));
    var buffer = state.allocator.alloc(Sample, @intCast(sampleCount)) catch return;
    defer state.allocator.free(buffer);
    @memset(buffer, 0);

    const cameraZoomDistanceBonus: f32 = 500 / state.camera.zoom;
    var soundCounter: u16 = 0;
    const screenRectangle = mapZig.getMapScreenVisibilityRectangle(state);
    for (state.soundMixer.soundsToPlay.items) |*sound| {
        if (mapZig.isPositionInsideMapRectangle(sound.mapPosition, screenRectangle)) {
            soundCounter += 1;
            var i: usize = 0;
            while (i < sampleCount and sound.dataIndex < state.soundMixer.soundData.sounds[sound.soundIndex].len) {
                const data: [*]Sample = @ptrCast(@alignCast(state.soundMixer.soundData.sounds[sound.soundIndex].data));
                const distance: f64 = main.calculateDistance(sound.mapPosition, state.camera.position) + cameraZoomDistanceBonus;
                const volume: f64 = @max(1 - (distance / 1000.0), 0);
                buffer[i] +|= @intFromFloat(@as(f64, @floatFromInt(data[@divFloor(sound.dataIndex, 2)])) * volume);
                i += 1;
                sound.dataIndex += 2;
            }
        } else {
            sound.dataIndex += @intCast(2 * sampleCount);
        }
    }
    if (soundCounter > 0) {
        const powY = @sqrt(@as(f32, @floatFromInt(soundCounter - 1)));
        const soundCountVolumeFactor: f32 = std.math.pow(f32, 0.8, powY);
        for (0..buffer.len) |index| {
            buffer[index] = @intFromFloat(@as(f32, @floatFromInt(buffer[index])) * soundCountVolumeFactor);
        }
    }

    _ = sdl.SDL_PutAudioStreamData(stream, buffer.ptr, additional_amount);
}

pub fn playSoundInFuture(soundMixer: *SoundMixer, soundIndex: usize, startGameTimeMs: u32, mapPosition: main.Position) !void {
    try soundMixer.soundsFutureQueue.append(FutureSoundToPlay{
        .soundIndex = soundIndex,
        .startGameTimeMs = startGameTimeMs,
        .mapPosition = mapPosition,
    });
}

pub fn playSound(soundMixer: *SoundMixer, soundIndex: usize, offset: usize, mapPosition: main.Position) !void {
    if (soundMixer.soundsToPlay.items.len < SoundMixer.MAX_SOUNDS_AT_ONCE) {
        switch (soundIndex) {
            SOUND_HAMMER_WOOD => {
                if (soundMixer.countHammer >= SoundMixer.LIMIT_HAMMER) return;
                try soundMixer.soundsToPlay.append(.{
                    .soundIndex = soundIndex,
                    .dataIndex = offset,
                    .mapPosition = mapPosition,
                });
                soundMixer.countHammer += 1;
            },
            SOUND_TREE_FALLING => {
                if (soundMixer.countTreeFalling >= SoundMixer.LIMIT_TREE_FALLING) return;
                try soundMixer.soundsToPlay.append(.{
                    .soundIndex = soundIndex,
                    .dataIndex = offset,
                    .mapPosition = mapPosition,
                });
                soundMixer.countTreeFalling += 1;
            },
            SOUND_WOOD_CHOP_1, SOUND_WOOD_CHOP_2, SOUND_WOOD_CHOP_3, SOUND_WOOD_CHOP_4, SOUND_WOOD_CHOP_5 => {
                if (soundMixer.countWoodCut >= SoundMixer.LIMIT_WOOD_CUT) return;
                try soundMixer.soundsToPlay.append(.{
                    .soundIndex = soundIndex,
                    .dataIndex = offset,
                    .mapPosition = mapPosition,
                });
                soundMixer.countWoodCut += 1;
            },
            else => {
                unreachable;
            },
        }
    }
}

pub fn getRandomWoodChopIndex() usize {
    const rand = std.crypto.random;
    return @as(usize, @intFromFloat(rand.float(f32) * 5.0)) + 1;
}

pub const SOUND_TREE_FALLING = 0;
pub const SOUND_WOOD_CHOP_1 = 1;
pub const SOUND_WOOD_CHOP_2 = 2;
pub const SOUND_WOOD_CHOP_3 = 3;
pub const SOUND_WOOD_CHOP_4 = 4;
pub const SOUND_WOOD_CHOP_5 = 5;
pub const SOUND_HAMMER_WOOD = 6;
fn initSounds(state: *main.ChatSimState, allocator: std.mem.Allocator) !SoundData {
    var desired_spec = sdl.SDL_AudioSpec{
        .format = sdl.SDL_AUDIO_S16,
        .freq = 48000,
        .channels = 1,
    };

    const stream = sdl.SDL_OpenAudioDeviceStream(sdl.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &desired_spec, audioCallback, state);
    if (stream == null) {
        return error.createAudioStream;
    }
    const device = sdl.SDL_GetAudioStreamDevice(stream);
    if (device == 0) {
        return error.openAudioDevice;
    }
    if (!sdl.SDL_ResumeAudioDevice(device)) {
        return error.resumeAudioDevice;
    }
    const sounds = try allocator.alloc(SoundFile, 7);
    sounds[SOUND_TREE_FALLING] = try loadSoundFile("sounds/441617__danielajq__38-arbol-cayendo.wav", allocator);
    sounds[SOUND_WOOD_CHOP_1] = try loadSoundFile("sounds/553254__t-man95__axe-cutting-wood_chop_1.mp3", allocator);
    sounds[SOUND_WOOD_CHOP_2] = try loadSoundFile("sounds/553254__t-man95__axe-cutting-wood_chop_2.mp3", allocator);
    sounds[SOUND_WOOD_CHOP_3] = try loadSoundFile("sounds/553254__t-man95__axe-cutting-wood_chop_3.mp3", allocator);
    sounds[SOUND_WOOD_CHOP_4] = try loadSoundFile("sounds/553254__t-man95__axe-cutting-wood_chop_4.mp3", allocator);
    sounds[SOUND_WOOD_CHOP_5] = try loadSoundFile("sounds/553254__t-man95__axe-cutting-wood_chop_5.mp3", allocator);
    sounds[SOUND_HAMMER_WOOD] = try loadSoundFile("sounds/496262__16gpanskatoman_kristian__hammer-wood_shortened.mp3", allocator);
    return .{
        .stream = stream,
        .sounds = sounds,
    };
}

///support wav and mp3
fn loadSoundFile(path: []const u8, allocator: std.mem.Allocator) !SoundFile {
    var audio_buf: [*]u8 = undefined;
    var audio_len: u32 = 0;
    if (std.mem.endsWith(u8, path, ".wav")) {
        var spec: sdl.SDL_AudioSpec = undefined;
        if (!sdl.SDL_LoadWAV(@ptrCast(path), &spec, @ptrCast(&audio_buf), &audio_len)) {
            return error.loadWav;
        }

        return .{ .data = audio_buf, .len = audio_len, .mp3 = null };
        // defer sdl.SDL_free(audio_buf);
    } else if (std.mem.endsWith(u8, path, ".mp3")) {
        var mp3 = minimp3.mp3dec_ex_t{};
        if (minimp3.mp3dec_ex_open(&mp3, path.ptr, minimp3.MP3D_SEEK_TO_SAMPLE) != 0) {
            return error.openMp3;
        }
        defer minimp3.mp3dec_ex_close(&mp3);
        // Allocate your own buffer for the decoded samples
        const total_samples = mp3.samples; // number of samples (not bytes)
        const sample_count: usize = @intCast(total_samples);
        const decoded = try allocator.alloc(i16, sample_count);

        // Read all samples
        const samples_read = minimp3.mp3dec_ex_read(&mp3, decoded.ptr, sample_count);
        audio_buf = @ptrCast(decoded.ptr);
        audio_len = @intCast(samples_read * @sizeOf(i16));
        return .{ .data = audio_buf, .len = audio_len, .mp3 = decoded };
    } else {
        return error.unknwonSoundFileType;
    }
}
