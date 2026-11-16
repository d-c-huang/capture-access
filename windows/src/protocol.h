#pragma once
#include <windows.h>
#include <stdint.h>
#include <stdio.h>

// Fixed-width fields make the request identical in x86 and x64 processes.
struct Request {
    DWORD version;
    DWORD targetPid;
    DWORD targetTid;
    DWORD desired;
    uint64_t targetWindow;
    uint64_t creationTime;
    DWORD before;
    DWORD after;
    DWORD error;
    DWORD acknowledged;
    DWORD success;
    DWORD reserved;
};
static_assert(sizeof(Request) == 56, "Protocol layout changed");
static const wchar_t* kMessage = L"CaptureAccess.Apply.7A31FC75-520F-4336-B7F3-8505EEB518B9.v1";
inline void MappingName(wchar_t* out, size_t count, DWORD sender, DWORD nonce) {
    swprintf_s(out, count, L"Local\\CaptureAccess.v1.%lu.%08lX", sender, nonce);
}
inline uint64_t FileTimeValue(const FILETIME& t) {
    return (uint64_t(t.dwHighDateTime) << 32) | t.dwLowDateTime;
}
inline bool ValidAffinity(DWORD a) { return a == 0 || a == 1 || a == 0x11; }
