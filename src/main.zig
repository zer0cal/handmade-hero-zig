const std = @import("std");
const win = std.os.windows;

const zwin = @import("zigwin32");
const et = zwin.everything;
const foundation = zwin.foundation;
const debug = zwin.system.diagnostics.debug;
const wam = zwin.ui.windows_and_messaging;
const gdi = zwin.graphics.gdi;
const mem = zwin.system.memory;

const OffscreenBuffer = struct {
    info: gdi.BITMAPINFO = undefined,
    memory: ?*anyopaque = undefined,
    width: u32 = undefined,
    height: u32 = undefined,
    pitch: u32 = undefined,
    bytes_per_pixel: u32 = undefined,
};

const WindowDimension = struct {
    width: u32,
    height: u32,
};

var running: bool = undefined;
var globalBackbuffer: OffscreenBuffer = .{};

fn getWindowDimension(window: ?foundation.HWND) WindowDimension {
    var client_rect: foundation.RECT = undefined;
    _ = wam.GetClientRect(window, &client_rect);
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

            const blue = (x_u32 + x_offset) * 255 / buffer.width;
            const green = (y_u32 + y_offset) * 255 / buffer.height;
            const red = (y_u32 + x_offset) * 255 / buffer.width;

            pixel.* = red << 16 | green << 8 | blue;
            pixel = @ptrFromInt(@intFromPtr(pixel) + buffer.bytes_per_pixel);
        }
        row = @ptrFromInt(@intFromPtr(row) + buffer.pitch);
    }
}

fn resizeDIBSection(buffer: *OffscreenBuffer, width: u32, height: u32) void {
    if (buffer.memory) |_| {
        _ = mem.VirtualFree(buffer.memory, 0, et.MEM_RELEASE);
    }

    buffer.width = width;
    buffer.height = height;
    buffer.bytes_per_pixel = 4;

    buffer.info.bmiHeader.biSize = @sizeOf(@TypeOf(buffer.info.bmiHeader));
    buffer.info.bmiHeader.biWidth = @intCast(buffer.width);
    buffer.info.bmiHeader.biHeight = @intCast(buffer.height);
    buffer.info.bmiHeader.biPlanes = 1;
    buffer.info.bmiHeader.biBitCount = 32;
    buffer.info.bmiHeader.biCompression = gdi.BI_RGB;

    const buffer_memory_size: usize = @intCast(buffer.width * buffer.height * buffer.bytes_per_pixel);
    buffer.memory = mem.VirtualAlloc(
        null,
        buffer_memory_size,
        mem.MEM_COMMIT,
        mem.PAGE_READWRITE,
    );
    buffer.pitch = @intCast(buffer.width * buffer.bytes_per_pixel);
}

fn displayBufferInWindow(
    buffer: *OffscreenBuffer,
    device_context: ?gdi.HDC,
    window_width: u32,
    window_height: u32,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) void {
    _ = x; // autofix
    _ = y; // autofix
    _ = width; // autofix
    _ = height; // autofix

    _ = gdi.StretchDIBits(
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
        gdi.DIB_RGB_COLORS,
        gdi.SRCCOPY,
    );
}

pub fn mainWindowCallback(
    window: foundation.HWND,
    message: u32,
    wPapram: usize,
    lParam: isize,
) callconv(.winapi) isize {
    var result: win.LRESULT = 0;
    switch (message) {
        wam.WM_SIZE => {},
        wam.WM_DESTROY => {
            running = false;
        },
        wam.WM_CLOSE => {
            running = false;
        },
        wam.WM_ACTIVATE => {
            debug.OutputDebugStringA("WM_ACTIVATE\n");
        },
        wam.WM_PAINT => {
            var paint: gdi.PAINTSTRUCT = undefined;
            const device_context = gdi.BeginPaint(window, &paint);
            defer _ = gdi.EndPaint(window, &paint);

            const x: u32 = @intCast(paint.rcPaint.left);
            const y: u32 = @intCast(paint.rcPaint.top);
            const width: u32 = @intCast(paint.rcPaint.right - paint.rcPaint.left);
            const height: u32 = @intCast(paint.rcPaint.bottom - paint.rcPaint.top);

            const dimension = getWindowDimension(window);

            displayBufferInWindow(
                &globalBackbuffer,
                device_context,
                dimension.width,
                dimension.height,
                x,
                y,
                width,
                height,
            );
        },
        else => {
            result = wam.DefWindowProcA(window, message, wPapram, lParam);
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

    const window_class = wam.WNDCLASSA{
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

    resizeDIBSection(&globalBackbuffer, 1280, 720);

    const window_style: wam.WINDOW_STYLE = .{
        .TABSTOP = 1,
        .GROUP = 1,
        .THICKFRAME = 1,
        .SYSMENU = 1,
        .DLGFRAME = 1,
        .BORDER = 1,
        .VISIBLE = 1,
    };
    if (wam.RegisterClassA(&window_class) != 0) {
        const window = wam.CreateWindowExA(
            .{},
            window_class.lpszClassName,
            "Handmade Hero",
            window_style,
            wam.CW_USEDEFAULT,
            wam.CW_USEDEFAULT,
            wam.CW_USEDEFAULT,
            wam.CW_USEDEFAULT,
            null,
            null,
            instance,
            null,
        );
        if (window) |_| {
            var x_offset: u16 = 0;
            var y_offset: u16 = 0;
            running = true;
            while (running) {
                var message: wam.MSG = undefined;
                while (wam.PeekMessageA(&message, null, 0, 0, wam.PM_REMOVE) != 0) {
                    if (message.message == wam.WM_QUIT) {
                        running = false;
                    }
                    _ = wam.TranslateMessage(&message);
                    _ = wam.DispatchMessageA(&message);
                }
                renderGradient(&globalBackbuffer, x_offset, y_offset);

                const device_context = gdi.GetDC(window);
                const dimension = getWindowDimension(window);
                displayBufferInWindow(&globalBackbuffer, device_context, dimension.width, dimension.height, 0, 0, dimension.width, dimension.height);
                _ = gdi.ReleaseDC(window, device_context);

                x_offset -%= 1;
                y_offset +%= 1;
            }
        }
    }
}
