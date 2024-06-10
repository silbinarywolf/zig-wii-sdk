const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");
const wasm3 = @import("wasm3");
const png = @import("png.zig");

const assert = std.debug.assert;

comptime {
    // add additional functionality so standard Zig functions work
    _ = @import("zigwii").runtime;
}

pub const os = struct {
    // NOTE(jae): 2024-06-10
    // Not currently supported by Zig.
    // PR here: https://github.com/ziglang/zig/pull/20241
    // pub const c = @import("zigwii").c;

    // NOTE(jae): 2024-06-10
    // Force allocator to use c allocator for wii
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    try sdl.Wii_SDL_Init();

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        sdl.SDL_Log("Unable to initialize SDL: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow(
        "Map Editor",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        640,
        480,
        sdl.SDL_WINDOW_FULLSCREEN,
    ) orelse {
        sdl.SDL_Log("unable to create window: %s", sdl.SDL_GetError());
        return error.SDLWindowInitializationFailed;
    };
    defer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(window, -1, 0) orelse {
        sdl.SDL_Log("unable to create renderer: %s", sdl.SDL_GetError());
        return error.SDLRendererInitializationFailed;
    };
    defer sdl.SDL_DestroyRenderer(renderer);

    const zig_bmp = @embedFile("zig.bmp");
    const rw = sdl.SDL_RWFromConstMem(zig_bmp, zig_bmp.len) orelse {
        sdl.SDL_Log("Unable to get RWFromConstMem: %s", sdl.SDL_GetError());
        return error.SDLRWFromConstMemFailed;
    };
    defer assert(sdl.SDL_RWclose(rw) == 0);

    const zig_surface = sdl.SDL_LoadBMP_RW(rw, 0) orelse {
        sdl.SDL_Log("Unable to load bmp: %s", sdl.SDL_GetError());
        return error.SDLLoadBmpFailed;
    };
    defer sdl.SDL_FreeSurface(zig_surface);

    // Load BMP
    const zig_texture_bmp = sdl.SDL_CreateTextureFromSurface(renderer, zig_surface) orelse {
        sdl.SDL_Log("Unable to create texture from surface: %s", sdl.SDL_GetError());
        return error.SDL_CreateTextureFromSurfaceFailed;
    };
    defer sdl.SDL_DestroyTexture(zig_texture_bmp);

    // Load PNG
    const zig_texture_png = try png.load_from_buffer(renderer, allocator, @embedFile("zig.png"));
    defer sdl.SDL_DestroyTexture(zig_texture_png);

    // Print before we start the loop
    std.debug.print("Start before infinite loop", .{});
    while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    return;
                },
                sdl.SDL_WINDOWEVENT => {
                    // if (event.window.event == sdl.SDL_WINDOWEVENT_RESIZED) {
                    //     // std.debug.print("MESSAGE: Resizing window...\n", .{});
                    //     // resizeWindow(m_event.window.data1, m_event.window.data2);
                    // }
                },
                else => {},
            }
        }

        _ = sdl.SDL_SetRenderDrawColor(renderer, 255, 0, 0, 0);
        _ = sdl.SDL_RenderClear(renderer);

        // render .bmp
        {
            const zig_texture_rect = sdl.SDL_FRect{
                .x = 128,
                .y = 128,
                .w = @as(f32, @floatFromInt(400)),
                .h = @as(f32, @floatFromInt(140)),
            };
            _ = sdl.SDL_RenderCopyF(renderer, zig_texture_bmp, null, &zig_texture_rect);
        }

        // render .png
        {
            const zig_texture_rect = sdl.SDL_FRect{
                .x = 128,
                .y = 280,
                .w = @as(f32, @floatFromInt(400)),
                .h = @as(f32, @floatFromInt(140)),
            };
            _ = sdl.SDL_RenderCopyF(renderer, zig_texture_png, null, &zig_texture_rect);
        }
        sdl.SDL_RenderPresent(renderer);
    }
}
