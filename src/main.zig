const std = @import("std");

const c = @cImport({
    @cInclude("windows.h");
    @cInclude("winuser.h");
    @cInclude("wingdi.h");
});

// pub export fn wWinMain(hInstance: win.HINSTANCE, hPrevInstance: ?win.HINSTANCE, lpCmdLine: win.LPWSTR, nShowCmd: c_int) callconv(.winapi) c_int {
//     _ = hInstance;
//     _ = hPrevInstance;
//     _ = lpCmdLine;
//     _ = nShowCmd;

//     _ = c.MessageBoxA(0, "This is Handmade Hero.", "Handmade Hero", c.MB_OK | c.MB_ICONINFORMATION);
//     return 0;
// }

pub fn mainWindowCallback(
    window: c.HWND,
    message: c.UINT,
    wPapram: c.WPARAM,
    lParam: c.LPARAM,
) callconv(.winapi) c.LRESULT {
    var result: c.LRESULT = 0;
    switch (message) {
        c.WM_SIZE => {
            c.OutputDebugStringA("WM_SIZE\n");
        },
        c.WM_DESTROY => {
            c.OutputDebugStringA("WM_DESTROY \n");
        },
        c.WM_CLOSE => {
            c.OutputDebugStringA("WM_CLOSE\n");
        },
        c.WM_ACTIVATE => {
            c.OutputDebugStringA("WM_ACTIVATE\n");
        },
        c.WM_PAINT => {
            var paint: c.PAINTSTRUCT = .{};
            const deviceContext = c.BeginPaint(window, &paint);
            defer _ = c.EndPaint(window, &paint);

            const x = paint.rcPaint.left;
            const y = paint.rcPaint.top;
            const width = paint.rcPaint.right - paint.rcPaint.left;
            const height = paint.rcPaint.bottom - paint.rcPaint.top;
            _ = c.PatBlt(deviceContext, x, y, width, height, c.WHITENESS);
        },
        else => {
            // c.OutputDebugStringA("WM_SIZE\n");
            result = c.DefWindowProcA(window, message, wPapram, lParam);
        },
    }
    return result;
}

pub fn main() !void {
    const windowClass = c.WNDCLASS{
        .style = c.CS_OWNDC | c.CS_HREDRAW | c.CS_VREDRAW,
        .lpfnWndProc = &mainWindowCallback,
        .hInstance = c.GetModuleHandleA(0),
        .lpszClassName = "HandmadeHeroWindowClass",
    };
    const regResult = c.RegisterClassA(&windowClass);
    if (regResult != 0) {
        const windowHandle = c.CreateWindowExA(0, windowClass.lpszClassName, "Handmade Hero", c.WS_OVERLAPPEDWINDOW | c.WS_VISIBLE, c.CW_USEDEFAULT, c.CW_USEDEFAULT, c.CW_USEDEFAULT, c.CW_USEDEFAULT, 0, 0, c.GetModuleHandleA((0)), null);
        if (windowHandle != 0) {
            while (true) {
                var message: c.MSG = undefined;
                const messageResult: c.WINBOOL = c.GetMessageA(&message, 0, 0, 0);
                if (messageResult > 0) {
                    _ = c.TranslateMessage(&message);
                    _ = c.DispatchMessageA(&message);
                } else {
                    break;
                }
            }
        }
    }
}
