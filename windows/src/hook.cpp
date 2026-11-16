#include "protocol.h"

extern "C" __declspec(dllexport) LRESULT CALLBACK CaptureHook(int code, WPARAM wp, LPARAM lp) {
    if (code >= 0 && lp) {
        const auto* event = reinterpret_cast<const CWPSTRUCT*>(lp);
        if (event->message == RegisterWindowMessageW(kMessage)) {
            wchar_t name[128];
            MappingName(name, _countof(name), DWORD(event->wParam), DWORD(event->lParam));
            HANDLE mapping = OpenFileMappingW(FILE_MAP_READ | FILE_MAP_WRITE, FALSE, name);
            if (mapping) {
                auto* r = static_cast<Request*>(MapViewOfFile(mapping, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, sizeof(Request)));
                if (r) {
                    FILETIME created{}, exited{}, kernel{}, user{};
                    bool own = GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user) != FALSE;
                    if (r->version == 1 && r->targetPid == GetCurrentProcessId() &&
                        r->targetTid == GetCurrentThreadId() &&
                        r->targetWindow == uint64_t(reinterpret_cast<uintptr_t>(event->hwnd)) &&
                        own && r->creationTime == FileTimeValue(created) && ValidAffinity(r->desired)) {
                        r->error = 0;
                        SetLastError(0);
                        if (!GetWindowDisplayAffinity(event->hwnd, &r->before)) {
                            r->error = GetLastError();
                            if (!r->error) r->error = ERROR_NOT_SUPPORTED;
                        } else if (r->before == r->desired) {
                            r->reserved = 1;
                            r->after = r->before;
                            r->success = 1;
                        } else {
                            r->reserved = 1;
                            SetLastError(0);
                            if (!SetWindowDisplayAffinity(event->hwnd, r->desired)) {
                                r->error = GetLastError();
                                if (!r->error) r->error = ERROR_GEN_FAILURE;
                            } else if ((r->reserved |= 2), !GetWindowDisplayAffinity(event->hwnd, &r->after)) {
                                r->error = GetLastError();
                                if (!r->error) r->error = ERROR_NOT_SUPPORTED;
                            } else {
                                r->success = r->after == r->desired;
                                if (!r->success) r->error = ERROR_RETRY;
                            }
                        }
                        // Publish the result only after all fields have been filled.
                        InterlockedExchange(reinterpret_cast<volatile LONG*>(&r->acknowledged), 1);
                    }
                    UnmapViewOfFile(r);
                }
                CloseHandle(mapping);
            }
        }
    }
    return CallNextHookEx(nullptr, code, wp, lp);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    return TRUE;
}
