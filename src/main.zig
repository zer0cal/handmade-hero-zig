const std = @import("std");
const win = std.os.windows;
const zwin = @import("zigwin32");
const util = zwin.everything;

pub fn mainWindowCallback(
    window: zwin.foundation.HWND,
    message: u32,
    wPapram: usize,
    lParam: isize,
) callconv(.winapi) isize {
    var result: win.LRESULT = 0;
    switch (message) {
        util.WM_SIZE => {
            util.OutputDebugStringA("WM_SIZE\n");
        },
        util.WM_DESTROY => {
            util.OutputDebugStringA("WM_DESTROY \n");
        },
        util.WM_CLOSE => {
            util.OutputDebugStringA("WM_CLOSE\n");
        },
        util.WM_ACTIVATE => {
            util.OutputDebugStringA("WM_ACTIVATE\n");
        },
        util.WM_PAINT => {
            var paint: util.PAINTSTRUCT = undefined;
            const deviceContext = util.BeginPaint(window, &paint);
            defer _ = util.EndPaint(window, &paint);

            const x = paint.rcPaint.left;
            const y = paint.rcPaint.top;
            const width = paint.rcPaint.right - paint.rcPaint.left;
            const height = paint.rcPaint.bottom - paint.rcPaint.top;
            _ = util.PatBlt(deviceContext, x, y, width, height, util.WHITENESS);
        },
        else => {
            // c.OutputDebugStringA("WM_SIZE\n");
            result = util.DefWindowProcA(window, message, wPapram, lParam);
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

    const window = util.WNDCLASSA{
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
    const window_style: zwin.ui.windows_and_messaging.WINDOW_STYLE = .{
        .TABSTOP = 1,
        .GROUP = 1,
        .THICKFRAME = 1,
        .SYSMENU = 1,
        .DLGFRAME = 1,
        .BORDER = 1,
        .VISIBLE = 1,
    };
    if (util.RegisterClassA(&window) != 0) {
        const handle = util.CreateWindowExA(
            .{},
            window.lpszClassName,
            "Handmade Hero",
            window_style,
            util.CW_USEDEFAULT,
            util.CW_USEDEFAULT,
            util.CW_USEDEFAULT,
            util.CW_USEDEFAULT,
            null,
            null,
            instance,
            null,
        );
        if (handle) |_| {
            var message: util.MSG = undefined;
            sw: switch (util.GetMessageA(&message, null, 0, 0)) {
                0 => break :sw,
                else => {
                    _ = util.TranslateMessage(&message);
                    _ = util.DispatchMessageA(&message);
                    continue :sw util.GetMessageA(&message, null, 0, 0);
                },
            }
        }
    }
}
