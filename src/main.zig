const std = @import("std");
const zwin = @import("zigwin32").everything;
const win = std.os.windows;

const BYTES_PER_PIXEL = 4;

const OffscreenBuffer = struct {
    info: zwin.BITMAPINFO = undefined,
    memory: ?*anyopaque = undefined,
    width: u32 = undefined,
    height: u32 = undefined,
    pitch: u32 = undefined,
};

const WindowDimension = struct {
    width: u32,
    height: u32,
};

var running: bool = undefined;
var global_backbuffer: OffscreenBuffer = .{};
var global_x_offset: u16 = 0;
var global_y_offset: u16 = 0;

fn initDSound(window: zwin.HWND, samples_per_second: u32, buffer_size: u32) void {
    var wave_format: zwin.WAVEFORMATEX = undefined;
    wave_format.wFormatTag = zwin.WAVE_FORMAT_PCM;
    wave_format.nChannels = 2;
    wave_format.nSamplesPerSec = samples_per_second;
    wave_format.wBitsPerSample = 16;
    wave_format.nBlockAlign = (wave_format.nChannels * wave_format.wBitsPerSample) / 8;
    wave_format.nAvgBytesPerSec = wave_format.nSamplesPerSec * wave_format.nBlockAlign;
    wave_format.cbSize = 0;

    var direct_sound: ?*zwin.IDirectSound = undefined;
    const direct_sound_result = zwin.DirectSoundCreate(null, &direct_sound, null);

    if (zwin.SUCCEEDED(direct_sound_result)) {
        if (zwin.SUCCEEDED(direct_sound.?.SetCooperativeLevel(window, zwin.DSSCL_PRIORITY))) {
            var buffer_desctiption: zwin.DSBUFFERDESC = undefined;
            buffer_desctiption.dwSize = @sizeOf(zwin.DSBUFFERDESC);
            buffer_desctiption.dwFlags = zwin.DSBCAPS_PRIMARYBUFFER;

            var primary_buffer: ?*zwin.IDirectSoundBuffer = undefined;
            const primary_buffer_result = direct_sound.?.CreateSoundBuffer(&buffer_desctiption, &primary_buffer, null);

            if (zwin.SUCCEEDED(primary_buffer_result)) {
                if (zwin.SUCCEEDED(primary_buffer.?.SetFormat(&wave_format))) {
                    zwin.OutputDebugStringA("DS: Primary buffer OK\n");
                }
            }
        }

        var buffer_desctiption: zwin.DSBUFFERDESC = undefined;
        buffer_desctiption.dwSize = @sizeOf(zwin.DSBUFFERDESC);
        buffer_desctiption.dwFlags = 0;
        buffer_desctiption.dwBufferBytes = buffer_size;
        buffer_desctiption.lpwfxFormat = &wave_format;

        var secondary_buffer: ?*zwin.IDirectSoundBuffer = undefined;
        const secondary_buffer_result = direct_sound.?.CreateSoundBuffer(&buffer_desctiption, &secondary_buffer, null);

        if (zwin.SUCCEEDED(secondary_buffer_result)) {
            zwin.OutputDebugStringA("DS: Secondary buffer OK\n");
        }
    }
}

fn getWindowDimension(window: ?zwin.HWND) WindowDimension {
    var client_rect: zwin.RECT = undefined;
    _ = zwin.GetClientRect(window, &client_rect);
    const width: u32 = @intCast(client_rect.right - client_rect.left);
    const height: u32 = @intCast(client_rect.bottom - client_rect.top);
    return .{
        .width = width,
        .height = height,
    };
}

fn renderGradient(buffer: *const OffscreenBuffer, x_offset: u32, y_offset: u32) void {
    var row: *u8 = @ptrCast(buffer.memory);

    for (0..@intCast(buffer.height)) |y| {
        const y_u32: u32 = @intCast(y);
        var pixel: *u32 = @ptrCast(@alignCast(row));
        for (0..@intCast(buffer.width)) |x| {
            const x_u32: u32 = @intCast(x);

            const red = (y_u32 + x_offset) * 255 / buffer.width;
            const green = y_u32 + y_offset;
            const blue = x_u32 + x_offset;

            pixel.* = red << 16 | green << 8 | blue;
            pixel = @ptrFromInt(@intFromPtr(pixel) + BYTES_PER_PIXEL);
        }
        row = @ptrFromInt(@intFromPtr(row) + buffer.pitch);
    }
}

fn resizeDIBSection(buffer: *OffscreenBuffer, width: u32, height: u32) !void {
    if (buffer.memory) |_| {
        _ = win.VirtualFree(buffer.memory, 0, win.MEM_RELEASE);
    }

    buffer.width = width;
    buffer.height = height;

    buffer.info.bmiHeader.biSize = @sizeOf(@TypeOf(buffer.info.bmiHeader));
    buffer.info.bmiHeader.biWidth = @intCast(buffer.width);
    buffer.info.bmiHeader.biHeight = @intCast(buffer.height);
    buffer.info.bmiHeader.biPlanes = 1;
    buffer.info.bmiHeader.biBitCount = 32;
    buffer.info.bmiHeader.biCompression = zwin.BI_RGB;

    const buffer_memory_size: usize = @intCast(buffer.width * buffer.height * BYTES_PER_PIXEL);
    buffer.memory = try win.VirtualAlloc(
        null,
        buffer_memory_size,
        win.MEM_COMMIT,
        win.PAGE_READWRITE,
    );
    buffer.pitch = @intCast(buffer.width * BYTES_PER_PIXEL);
}

fn displayBufferInWindow(
    buffer: *OffscreenBuffer,
    device_context: ?zwin.HDC,
    window_width: u32,
    window_height: u32,
) void {
    _ = zwin.StretchDIBits(
        device_context,
        0,
        0,
        @intCast(window_width),
        @intCast(window_height),
        0,
        0,
        @intCast(buffer.width),
        @intCast(buffer.height),
        buffer.memory,
        &buffer.info,
        zwin.DIB_RGB_COLORS,
        zwin.SRCCOPY,
    );
}

pub fn mainWindowCallback(
    window: zwin.HWND,
    message: u32,
    w_param: usize,
    l_param: isize,
) callconv(.winapi) isize {
    var result: win.LRESULT = 0;
    switch (message) {
        zwin.WM_SIZE => {},
        zwin.WM_DESTROY => {
            zwin.OutputDebugStringA("Callback: WM_DESTROY\n");
            running = false;
        },
        zwin.WM_CLOSE => {
            zwin.OutputDebugStringA("Callback: WM_CLOSE\n");
            running = false;
        },
        zwin.WM_ACTIVATE => {
            zwin.OutputDebugStringA("Callback: WM_ACTIVATE\n");
        },
        zwin.WM_PAINT => {
            var paint: zwin.PAINTSTRUCT = undefined;
            const device_context = zwin.BeginPaint(window, &paint);
            defer _ = zwin.EndPaint(window, &paint);

            const dimension = getWindowDimension(window);

            displayBufferInWindow(
                &global_backbuffer,
                device_context,
                dimension.width,
                dimension.height,
            );
        },
        zwin.WM_SYSKEYUP, zwin.WM_SYSKEYDOWN, zwin.WM_KEYUP, zwin.WM_KEYDOWN => {
            // const was_down = (l_param & (1 << 30)) != 0;
            // const is_down = (l_param & (1 << 31)) == 0;
            // if (was_down == is_down) {
            //     break :blk;
            // }
            switch (@as(zwin.VIRTUAL_KEY, @enumFromInt(w_param))) {
                .W => {
                    global_y_offset -%= 5;
                },
                .S => {
                    global_y_offset +%= 5;
                },
                .D => {
                    global_x_offset -%= 5;
                },
                .A => {
                    global_x_offset +%= 5;
                },
                .Q => {},
                .E => {},
                .UP => {},
                .DOWN => {},
                .LEFT => {},
                .RIGHT => {},
                .SPACE => {},
                .ESCAPE => {},
                else => {},
            }
        },
        else => {
            result = zwin.DefWindowProcA(window, message, w_param, l_param);
        },
    }
    return result;
}

pub export fn main(
    instance: ?win.HINSTANCE,
    prevInstance: ?win.HINSTANCE,
    pCmdLine: win.LPWSTR,
    nCmdShow: c_int,
) callconv(.winapi) void {
    _ = prevInstance;
    _ = pCmdLine;
    _ = nCmdShow;

    const window_class = zwin.WNDCLASSA{
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .style = .{ .HREDRAW = 1, .VREDRAW = 1 },
        .hCursor = null,
        .hIcon = null,
        .hInstance = instance,
        .hbrBackground = null,
        .lpfnWndProc = &mainWindowCallback,
        .lpszClassName = "HandmadeHeroWindowClass",
        .lpszMenuName = null,
    };

    resizeDIBSection(&global_backbuffer, 1280, 720) catch {
        return;
    };

    const window_style: zwin.WINDOW_STYLE = .{
        .TABSTOP = 1,
        .GROUP = 1,
        .THICKFRAME = 1,
        .SYSMENU = 1,
        .DLGFRAME = 1,
        .BORDER = 1,
        .VISIBLE = 1,
    };
    if (zwin.RegisterClassA(&window_class) != 0) {
        const window = zwin.CreateWindowExA(
            .{},
            window_class.lpszClassName,
            "Handmade Hero",
            window_style,
            zwin.CW_USEDEFAULT,
            zwin.CW_USEDEFAULT,
            zwin.CW_USEDEFAULT,
            zwin.CW_USEDEFAULT,
            null,
            null,
            instance,
            null,
        );
        if (window) |window_ok| {
            initDSound(window_ok, 48000, 48000 * @sizeOf(i16) * 2);

            running = true;
            while (running) {
                var message: zwin.MSG = undefined;
                while (zwin.PeekMessageA(&message, null, 0, 0, zwin.PM_REMOVE) != 0) {
                    if (message.message == zwin.WM_QUIT) {
                        running = false;
                    }
                    _ = zwin.TranslateMessage(&message);
                    _ = zwin.DispatchMessageA(&message);
                }

                for (1..zwin.XUSER_MAX_COUNT) |controller_index| {
                    var controller_state: zwin.XINPUT_STATE = undefined;

                    const get_state_result = zwin.XInputGetState(@intCast(controller_index), &controller_state);
                    if (get_state_result == zwin.BTH_ERROR_SUCCESS) {
                        const gamepad: *zwin.XINPUT_GAMEPAD = &controller_state.Gamepad;

                        // const up = gamepad.wButtons & zwin.XINPUT_GAMEPAD_DPAD_UP;
                        // const down = gamepad.wButtons & zwin.XINPUT_GAMEPAD_DPAD_DOWN;
                        // const left = gamepad.wButtons & zwin.XINPUT_GAMEPAD_DPAD_LEFT;
                        // const right = gamepad.wButtons & zwin.XINPUT_GAMEPAD_DPAD_RIGHT;
                        // const start = gamepad.wButtons & zwin.XINPUT_GAMEPAD_START;
                        // const back = gamepad.wButtons & zwin.XINPUT_GAMEPAD_BACK;
                        // const left_thumb = gamepad.wButtons & zwin.XINPUT_GAMEPAD_LEFT_THUMB;
                        // const right_thumb = gamepad.wButtons & zwin.XINPUT_GAMEPAD_RIGHT_THUMB;
                        // const left_shoulder = gamepad.wButtons & zwin.XINPUT_GAMEPAD_LEFT_SHOULDER;
                        // const right_shoulder = gamepad.wButtons & zwin.XINPUT_GAMEPAD_RIGHT_SHOULDER;
                        // const a_button = gamepad.wButtons & zwin.XINPUT_GAMEPAD_A;
                        // const b_button = gamepad.wButtons & zwin.XINPUT_GAMEPAD_B;
                        // const x_button = gamepad.wButtons & zwin.XINPUT_GAMEPAD_X;
                        // const y_button = gamepad.wButtons & zwin.XINPUT_GAMEPAD_Y;

                        // const stick_rx: u16 = @intCast(gamepad.sThumbRX);
                        // const stick_ry: u16 = @intCast(gamepad.sThumbRY);
                        const stick_lx: u16 = @intCast(gamepad.sThumbLX);
                        const stick_ly: u16 = @intCast(gamepad.sThumbLY);

                        global_x_offset +%= stick_lx >> 12;
                        global_y_offset +%= stick_ly >> 12;
                    }
                }

                renderGradient(&global_backbuffer, global_x_offset, global_y_offset);

                const device_context = zwin.GetDC(window);
                const dimension = getWindowDimension(window);
                displayBufferInWindow(&global_backbuffer, device_context, dimension.width, dimension.height);
                _ = zwin.ReleaseDC(window, device_context);

                // x_offset -%= 1;
                // y_offset +%= 1;
            }
        }
    }
}
