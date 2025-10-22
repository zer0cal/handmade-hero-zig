const std = @import("std");
const win = std.os.windows;

const zwin = @import("zigwin32");
const et = zwin.everything;
const foundation = zwin.foundation;
const debug = zwin.system.diagnostics.debug;
const wam = zwin.ui.windows_and_messaging;
const gdi = zwin.graphics.gdi;
const mem = zwin.system.memory;

const bytes_per_pixel = 4;

var running: bool = undefined;
var bitmap_info: gdi.BITMAPINFO = undefined;
var bitmap_memory: ?*anyopaque = undefined;
var bitmap_width: u32 = undefined;
var bitmap_height: u32 = undefined;

fn renderGradient(x_offset: u32, y_offset: u32) void {
    const pitch: usize = @intCast(bitmap_width * bytes_per_pixel);
    var row: *u8 = @ptrCast(bitmap_memory);

    for (0..@intCast(bitmap_height)) |y| {
        const y_u32: u32 = @intCast(y);
        var pixel: *u32 = @ptrCast(@alignCast(row));
        for (0..@intCast(bitmap_width)) |x| {
            const x_u32: u32 = @intCast(x);

            const blue = (x_u32 + x_offset) * 255 / bitmap_width;
            const green = (y_u32 + y_offset) * 255 / bitmap_height;
            const red = (y_u32 + x_offset) * 255 / bitmap_width;

            pixel.* = red << 16 | green << 8 | blue;
            pixel = @ptrFromInt(@intFromPtr(pixel) + bytes_per_pixel);
        }
        row = @ptrFromInt(@intFromPtr(row) + pitch);
    }
}

fn resizeDIBSection(width: u32, height: u32) void {
    if (bitmap_memory) |_| {
        _ = mem.VirtualFree(bitmap_memory, 0, et.MEM_RELEASE);
    }

    bitmap_width = width;
    bitmap_height = height;

    bitmap_info.bmiHeader.biSize = @sizeOf(@TypeOf(bitmap_info.bmiHeader));
    bitmap_info.bmiHeader.biWidth = @intCast(bitmap_width);
    bitmap_info.bmiHeader.biHeight = @intCast(bitmap_height);
    bitmap_info.bmiHeader.biPlanes = 1;
    bitmap_info.bmiHeader.biBitCount = 32;
    bitmap_info.bmiHeader.biCompression = gdi.BI_RGB;

    const bitmap_memory_size: usize = @intCast(bitmap_width * bitmap_height * bytes_per_pixel);
    bitmap_memory = mem.VirtualAlloc(
        null,
        bitmap_memory_size,
        mem.MEM_COMMIT,
        mem.PAGE_READWRITE,
    );
}

fn updateWindow(device_context: ?gdi.HDC, client_rect: *et.RECT, x: i32, y: i32, width: i32, height: i32) void {
    _ = x; // autofix
    _ = y; // autofix
    _ = width; // autofix
    _ = height; // autofix

    const window_width = client_rect.right - client_rect.left;
    const window_height = client_rect.bottom - client_rect.top;

    _ = gdi.StretchDIBits(
        device_context,
        0,
        0,
        @intCast(bitmap_width),
        @intCast(bitmap_height),
        0,
        0,
        window_width,
        window_height,
        bitmap_memory,
        &bitmap_info,
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
        wam.WM_SIZE => {
            var client_rect: foundation.RECT = undefined;
            _ = wam.GetClientRect(window, &client_rect);
            const width: u32 = @intCast(client_rect.right - client_rect.left);
            const height: u32 = @intCast(client_rect.bottom - client_rect.top);
            resizeDIBSection(width, height);
        },
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

            const x = paint.rcPaint.left;
            const y = paint.rcPaint.top;
            const width = paint.rcPaint.right - paint.rcPaint.left;
            const height = paint.rcPaint.bottom - paint.rcPaint.top;

            var client_rect: foundation.RECT = undefined;
            _ = wam.GetClientRect(window, &client_rect);
            updateWindow(device_context, &client_rect, x, y, width, height);
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
        .style = .{ .OWNDC = 1, .HREDRAW = 1, .VREDRAW = 1 },
        .hCursor = null,
        .hIcon = null,
        .hInstance = instance,
        .hbrBackground = null,
        .lpfnWndProc = &mainWindowCallback,
        .lpszClassName = "HandmadeHeroWindowClass",
        .lpszMenuName = null,
    };
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
                renderGradient(x_offset, y_offset);

                const device_context = gdi.GetDC(window);
                var client_rect: foundation.RECT = undefined;
                _ = wam.GetClientRect(window, &client_rect);
                const window_width = client_rect.right - client_rect.left;
                const window_height = client_rect.bottom - client_rect.top;
                updateWindow(device_context, &client_rect, 0, 0, window_width, window_height);
                _ = gdi.ReleaseDC(window, device_context);

                x_offset -%= 1;
                y_offset +%= 1;
            }
        }
    }
}
