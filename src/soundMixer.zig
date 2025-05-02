const std = @import("std");
const main = @import("main.zig");
const minimp3 = @cImport({
    @cInclude("minimp3_ex.h");
});
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
});

pub const SoundMixer = struct {
    volume: f32 = 1,
    addedSoundDataUntilTimeMs: i64 = 0,
    soundsFutureQueue: std.ArrayList(FutureSoundToPlay),
    soundsToPlay: std.ArrayList(SoundToPlay),
    soundData: SoundData,
    pub const MAX_SOUNDS_AT_ONCE: u32 = 20;
};

const SoundToPlay = struct {
    soundIndex: usize,
    position: usize = 0,
};

const FutureSoundToPlay = struct {
    soundIndex: usize,
    startGameTimeMs: u32,
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

pub fn createSoundMixer(state: *main.ChatSimState, allocator: std.mem.Allocator) !SoundMixer {
    const soundMixer: SoundMixer = .{
        .soundsToPlay = std.ArrayList(SoundToPlay).init(allocator),
        .soundsFutureQueue = std.ArrayList(FutureSoundToPlay).init(allocator),
        .soundData = try initSounds(state, allocator),
    };
    return soundMixer;
}

pub fn destroySoundMixer(state: *main.ChatSimState) void {
    state.soundMixer.soundsToPlay.deinit();
    state.soundMixer.soundsFutureQueue.deinit();
    destorySounds(state.soundMixer, state.allocator);
}

pub fn tickSoundMixer(state: *main.ChatSimState) !void {
    var index: usize = 0;
    while (index < state.soundMixer.soundsFutureQueue.items.len) {
        std.debug.print("1", .{});
        const item = state.soundMixer.soundsFutureQueue.items[index];
        if (item.startGameTimeMs <= state.gameTimeMs) {
            const removed = state.soundMixer.soundsFutureQueue.swapRemove(index);
            try playSound(&state.soundMixer, removed.soundIndex);
        } else {
            index += 1;
        }
    }
}

fn audioCallback(userdata: ?*anyopaque, stream: ?*sdl.SDL_AudioStream, additional_amount: c_int, len: c_int) callconv(.C) void {
    _ = len;
    const Sample = i16;
    const state: *main.ChatSimState = @ptrCast(@alignCast(userdata.?));

    const sampleCount = @divExact(additional_amount, @sizeOf(Sample));
    var buffer = state.allocator.alloc(Sample, @intCast(sampleCount)) catch return;
    defer state.allocator.free(buffer);
    @memset(buffer, 0);

    for (state.soundMixer.soundsToPlay.items) |*sound| { //TODO thread safety issue
        var i: usize = 0;
        while (i < sampleCount and sound.position < state.soundMixer.soundData.sounds[sound.soundIndex].len) {
            const data: [*]Sample = @ptrCast(@alignCast(state.soundMixer.soundData.sounds[sound.soundIndex].data));
            buffer[i] +|= data[@divFloor(sound.position, 2)];
            i += 1;
            sound.position += 2;
        }
    }
    _ = sdl.SDL_PutAudioStreamData(stream, buffer.ptr, additional_amount);
    var i: usize = 0;
    while (i < state.soundMixer.soundsToPlay.items.len) {
        if (state.soundMixer.soundsToPlay.items[i].position >= state.soundMixer.soundData.sounds[state.soundMixer.soundsToPlay.items[i].soundIndex].len) {
            _ = state.soundMixer.soundsToPlay.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

pub fn playSoundInFuture(soundMixer: *SoundMixer, soundIndex: usize, startGameTimeMs: u32) !void {
    try soundMixer.soundsFutureQueue.append(.{
        .soundIndex = soundIndex,
        .startGameTimeMs = startGameTimeMs,
    });
}

pub fn playSound(soundMixer: *SoundMixer, soundIndex: usize) !void {
    if (soundMixer.soundsToPlay.items.len < SoundMixer.MAX_SOUNDS_AT_ONCE) {
        try soundMixer.soundsToPlay.append(.{
            .soundIndex = soundIndex,
        });
    }
}

pub const SOUND_TREE_FALLING = 0;
pub const SOUND_WOOD_CHOP = 1;
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
    const sounds = try allocator.alloc(SoundFile, 2);
    sounds[SOUND_TREE_FALLING] = try loadSoundFile("sounds/441617__danielajq__38-arbol-cayendo.wav", allocator);
    sounds[SOUND_WOOD_CHOP] = try loadSoundFile("sounds/553254__t-man95__axe-cutting-wood_chop_1.mp3", allocator);
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

fn destorySounds(soundMixer: SoundMixer, allocator: std.mem.Allocator) void {
    sdl.SDL_DestroyAudioStream(soundMixer.soundData.stream);
    for (soundMixer.soundData.sounds) |sound| {
        if (sound.mp3) |dealocate| {
            allocator.free(dealocate);
        } else {
            sdl.SDL_free(sound.data);
        }
    }
    allocator.free(soundMixer.soundData.sounds);
}
