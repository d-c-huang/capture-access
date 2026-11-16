#include <windows.h>
#include <stdio.h>
#include <string.h>

static bool repeatProtection = false;
static LRESULT CALLBACK WindowProc(HWND h, UINT message, WPARAM wp, LPARAM lp) {
    if (message == WM_CREATE) {
        SetWindowDisplayAffinity(h, 0x11);
        if (repeatProtection) SetTimer(h, 1, 700, nullptr);
        return 0;
    }
    if (message == WM_TIMER) { SetWindowDisplayAffinity(h, 0x11); return 0; }
    if (message == WM_KEYDOWN && wp == 'P') { SetWindowDisplayAffinity(h, 0x11); InvalidateRect(h, nullptr, TRUE); return 0; }
    if (message == WM_PAINT) {
        PAINTSTRUCT ps{};
        HDC dc = BeginPaint(h, &ps);
        RECT rect; GetClientRect(h, &rect);
        HBRUSH brush = CreateSolidBrush(RGB(24, 66, 100));
        FillRect(dc, &rect, brush); DeleteObject(brush);
        SetTextColor(dc, RGB(255, 255, 255)); SetBkMode(dc, TRANSPARENT);
        rect.left += 30; rect.top += 35;
        DrawTextW(dc, L"Capture Access test window\n\nScreenshot protection starts ON.\nSelect this window in the tool, then disable protection.\n\nPress P to enable protection again.", -1, &rect, DT_LEFT | DT_WORDBREAK);
        EndPaint(h, &ps); return 0;
    }
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, message, wp, lp);
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, wchar_t* command, int show) {
    repeatProtection = wcsstr(command, L"--repeat") != nullptr;
    WNDCLASSW wc{}; wc.hInstance = instance; wc.lpfnWndProc = WindowProc;
    wc.lpszClassName = L"CaptureAccessDemo"; wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassW(&wc);
#ifdef _WIN64
    const wchar_t* title = L"CaptureAccess test x64";
#else
    const wchar_t* title = L"CaptureAccess test x86";
#endif
    HWND window = CreateWindowExW(0, wc.lpszClassName, title, WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 640, 340, nullptr, nullptr, instance, nullptr);
    if (!window) return 1;
    ShowWindow(window, show); UpdateWindow(window);
    MSG message;
    while (GetMessageW(&message, nullptr, 0, 0) > 0) { TranslateMessage(&message); DispatchMessageW(&message); }
    return 0;
}
