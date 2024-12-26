//! Micro-wrapper for SDL2 native functions.
//! Exposes only those functions needed for implementation.

const SDL_H = @cImport({
    @cInclude("SDL2/SDL.h");
});

const SdlError = error{ FailedInit, FailedWindow, FailedRenderer, FailedDraw, FailedOpenAudio, FailedQueueAudio };

pub const RgbColor = struct { red: u8, green: u8, blue: u8 };

/// A struct for audio-specifications for audio in `SDL_H.AUDIO_U8` format (unsigned 8-bit)
pub const RawAudioSpec = struct {
    /// The number of samples per second.
    frequency: usize,
    /// The number of samples in audio buffer.
    samples: u16,
    /// The number of channels in audio.
    channels: u8,
};

/// Manage an audio device provided by SDL2.
pub const AudioContext = struct {
    spec: SDL_H.SDL_AudioSpec,
    device_id: SDL_H.SDL_AudioDeviceID,
    /// Release SDL Audio-related resources.
    pub fn release(self: *const AudioContext) void {
        SDL_H.SDL_CloseAudioDevice(self.device_id);
    }
    /// "Render" some samples from the audio buffer.
    /// The buffer must contain at least `samples * channels` bytes
    pub fn render(self: *const AudioContext, buffer: []const u8) SdlError!void {
        if (SDL_H.SDL_QueueAudio(self.device_id, buffer.ptr, self.spec.samples * self.spec.channels) != 0) {
            return SdlError.FailedQueueAudio;
        }
    }
};

/// Open an audio device which supports specified audio spec.
pub fn getAudioContext(spec: RawAudioSpec) SdlError!AudioContext {
    const desired_spec = SDL_H.SDL_AudioSpec{ .freq = @intCast(spec.frequency), .format = SDL_H.AUDIO_S8, .channels = spec.channels, .samples = spec.samples, .callback = null };
    var obtained_spec = SDL_H.SDL_AudioSpec{}; // Obtained spec may be slightly different.

    // Open an Audio Device for use.
    const device_id = SDL_H.SDL_OpenAudioDevice(null, 0, &desired_spec, &obtained_spec, SDL_H.SDL_AUDIO_ALLOW_ANY_CHANGE);

    // 0 is not a valid device ID, and a placeholder for error.
    if (device_id == 0) return SdlError.FailedOpenAudio;

    SDL_H.SDL_PauseAudioDevice(device_id, 0);

    // Return the context.
    return AudioContext{ .spec = obtained_spec, .device_id = device_id };
}

/// Create a color from 8-bits using 216 colour palette (0..215).
/// Color 216..255 are unused, and set to black.
/// Blue = c (mod 6);
/// Green= c/6 (mod 6);
/// Red  = c/36(mod 6);
pub fn color8b(v: u8) RgbColor {
    if (v >= 216) {
        return RgbColor{ .red = 0, .green = 0, .blue = 0 };
    } else {
        var value = v;
        const blue = (value % 6) * 0x33;
        value /= 6;
        const green = (value % 6) * 0x33;
        value /= 6;
        const red = value * 0x33;
        return RgbColor{ .red = red, .green = green, .blue = blue };
    }
}

/// Intiailize SDL2 for audio, video, timing and events.
pub fn initAll() SdlError!void {
    const ret = SDL_H.SDL_Init( // The emulator requires Audio, Video, Timing, and Keyboard Input.
        SDL_H.SDL_INIT_VIDEO |
        SDL_H.SDL_INIT_AUDIO |
        SDL_H.SDL_INIT_EVENTS |
        SDL_H.SDL_INIT_TIMER);
    if (ret != 0) {
        return SdlError.FailedInit;
    }
}

pub fn createWindow(title: [:0]const u8, width: i32, height: i32) SdlError!*SDL_H.SDL_Window {
    const ret: ?*SDL_H.SDL_Window = SDL_H.SDL_CreateWindow(title, SDL_H.SDL_WINDOWPOS_UNDEFINED, SDL_H.SDL_WINDOWPOS_UNDEFINED, width, height, SDL_H.SDL_WINDOW_SHOWN);
    if (ret) |r| {
        return r;
    } else {
        return SdlError.FailedWindow;
    }
}

pub fn destroyWindow(in: *SDL_H.SDL_Window) void {
    SDL_H.SDL_DestroyWindow(in);
}

pub fn createRenderer(window: *SDL_H.SDL_Window) SdlError!*SDL_H.SDL_Renderer {
    const ret: ?*SDL_H.SDL_Renderer = SDL_H.SDL_CreateRenderer(window, -1, SDL_H.SDL_RENDERER_ACCELERATED);
    if (ret) |r| {
        return r;
    } else {
        return SdlError.FailedRenderer;
    }
}

pub fn destroyRenderer(renderer: *SDL_H.SDL_Renderer) void {
    SDL_H.SDL_DestroyRenderer(renderer);
}

/// Set renderer's draw color for drawing pixels.
pub fn setDrawColor(renderer: *SDL_H.SDL_Renderer, rgb: RgbColor) SdlError!void {
    if (SDL_H.SDL_SetRenderDrawColor(renderer, rgb.red, rgb.green, rgb.blue, SDL_H.SDL_ALPHA_OPAQUE) != 0) return SdlError.FailedDraw;
}

/// Draw a rectangle using the renderer.
pub fn drawFilledRect(renderer: *SDL_H.SDL_Renderer, x: i32, y: i32, w: i32, h: i32, color: RgbColor) SdlError!void {
    try setDrawColor(renderer, color);
    var rect: SDL_H.SDL_Rect = undefined;
    rect.x = x;
    rect.y = y;
    rect.w = w;
    rect.h = h;
    if (SDL_H.SDL_RenderFillRect(renderer, &rect) != 0) return SdlError.FailedDraw;
}

pub fn presentRendered(renderer: *SDL_H.SDL_Renderer) void {
    SDL_H.SDL_RenderPresent(renderer);
}

/// Iterate through events. Return false is quit event was triggered.
/// If any of 0,1,2,3,4,5,6,7,8,9,a,b,c,d,e,f were pressed set their corresponding flags.
pub fn handle_events(flag: *[16]bool) bool {
    var evt: SDL_H.SDL_Event = undefined;
    while (SDL_H.SDL_PollEvent(&evt) == 1) {
        switch (evt.type) {
            SDL_H.SDL_QUIT => {
                return false;
            },
            SDL_H.SDL_KEYDOWN => {
                const key_evt = evt.key;
                switch (key_evt.keysym.sym) {
                    SDL_H.SDLK_0 => {
                        flag[0] = true;
                    },
                    SDL_H.SDLK_1 => {
                        flag[1] = true;
                    },
                    SDL_H.SDLK_2 => {
                        flag[2] = true;
                    },
                    SDL_H.SDLK_3 => {
                        flag[3] = true;
                    },
                    SDL_H.SDLK_4 => {
                        flag[4] = true;
                    },
                    SDL_H.SDLK_5 => {
                        flag[5] = true;
                    },
                    SDL_H.SDLK_6 => {
                        flag[6] = true;
                    },
                    SDL_H.SDLK_7 => {
                        flag[7] = true;
                    },
                    SDL_H.SDLK_8 => {
                        flag[8] = true;
                    },
                    SDL_H.SDLK_9 => {
                        flag[9] = true;
                    },
                    SDL_H.SDLK_a => {
                        flag[10] = true;
                    },
                    SDL_H.SDLK_b => {
                        flag[11] = true;
                    },
                    SDL_H.SDLK_c => {
                        flag[12] = true;
                    },
                    SDL_H.SDLK_d => {
                        flag[13] = true;
                    },
                    SDL_H.SDLK_e => {
                        flag[14] = true;
                    },
                    SDL_H.SDLK_f => {
                        flag[15] = true;
                    },
                    else => {}, // Ignore.
                }
            },
            else => {}, // Do nothing.
        }
    }
    return true;
}

/// Sleep for `millis` milliseconds.
pub fn delay(millis: u32) void {
    SDL_H.SDL_Delay(millis);
}

/// Get the number of milliseconds since `init` was called.
pub fn ticks() u32 {
    return SDL_H.SDL_GetTicks();
}

/// Quit SDL application.
pub fn quit() void {
    SDL_H.SDL_Quit();
}
