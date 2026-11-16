#include "protocol.h"
#include <bcrypt.h>
#include <stdlib.h>
#include <errno.h>
#include <string>

static int Report(const char* status, DWORD error, const Request* r = nullptr) {
    printf("{\"status\":\"%s\",\"error\":%lu,\"before\":%lu,\"after\":%lu,\"ack\":%lu,\"success\":%lu,\"known\":%lu,\"changed\":%lu}\n",
        status, error, r ? r->before : 0, r ? r->after : 0,
        r ? r->acknowledged : 0, r ? r->success : 0, r && (r->reserved & 1) ? 1UL : 0UL, r && (r->reserved & 2) ? 1UL : 0UL);
    return error || (r && !r->success) ? 1 : 0;
}
static bool Number(const wchar_t* s, uint64_t& n) {
    if (!s || !*s || *s == L'-') return false;
    wchar_t* end = nullptr;
    errno = 0;
    n = _wcstoui64(s, &end, 10);
    return errno == 0 && end && !*end;
}

int wmain(int argc, wchar_t** argv) {
    // No arbitrary module path or arbitrary remote execution is exposed.
    if (argc != 6 || wcscmp(argv[1], L"--set")) return Report("arguments", ERROR_BAD_ARGUMENTS);
    uint64_t h, p, created, desired;
    if (!Number(argv[2], h) || !Number(argv[3], p) || !Number(argv[4], created) || !Number(argv[5], desired) ||
        h > UINTPTR_MAX || p > MAXDWORD || desired > MAXDWORD || !ValidAffinity(DWORD(desired)))
        return Report("arguments", ERROR_BAD_ARGUMENTS);
    HWND window = reinterpret_cast<HWND>(uintptr_t(h));
    DWORD pid = 0;
    DWORD tid = GetWindowThreadProcessId(window, &pid);
    if (!IsWindow(window) || !tid || pid != DWORD(p) || GetAncestor(window, GA_ROOT) != window)
        return Report("window_changed", ERROR_INVALID_WINDOW_HANDLE);
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return Report("open_process", GetLastError());
    FILETIME ct{}, et{}, kt{}, ut{};
    BOOL gotTime = GetProcessTimes(process, &ct, &et, &kt, &ut);
    DWORD timeError = GetLastError();
    BOOL wow = FALSE;
    BOOL gotWow = IsWow64Process(process, &wow);
    DWORD wowError = GetLastError();
    CloseHandle(process);
    if (!gotTime) return Report("process_time", timeError);
    if (FileTimeValue(ct) != created) return Report("process_changed", ERROR_INVALID_PARAMETER);
    if (!gotWow) return Report("architecture", wowError);
    SYSTEM_INFO sys{};
    GetNativeSystemInfo(&sys);
    if (sys.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_ARM64)
        return Report("arm64_unsupported", ERROR_NOT_SUPPORTED);
#ifdef _WIN64
    if (wow) return Report("architecture", ERROR_BAD_EXE_FORMAT);
#else
    if (sys.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_AMD64 && !wow)
        return Report("architecture", ERROR_BAD_EXE_FORMAT);
#endif
    wchar_t exe[MAX_PATH];
    DWORD length = GetModuleFileNameW(nullptr, exe, _countof(exe));
    if (!length || length >= _countof(exe)) return Report("module_path", ERROR_FILENAME_EXCED_RANGE);
    std::wstring path(exe);
    path.resize(path.find_last_of(L"\\/") + 1);
#ifdef _WIN64
    path += L"CaptureHook64.dll";
#else
    path += L"CaptureHook32.dll";
#endif
    // Resolve only our colocated, architecture-specific library; no PATH search.
    HMODULE module = LoadLibraryExW(path.c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module) return Report("load_library", GetLastError());
    auto callback = reinterpret_cast<HOOKPROC>(GetProcAddress(module, "CaptureHook"));
    if (!callback) { DWORD e = GetLastError(); FreeLibrary(module); return Report("export", e); }
    DWORD nonce = 0;
    if (BCryptGenRandom(nullptr, reinterpret_cast<PUCHAR>(&nonce), sizeof nonce, BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0) {
        FreeLibrary(module); return Report("random", ERROR_GEN_FAILURE);
    }
    wchar_t name[128];
    MappingName(name, _countof(name), GetCurrentProcessId(), nonce);
    HANDLE mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, sizeof(Request), name);
    DWORD mapError = GetLastError();
    if (!mapping || mapError == ERROR_ALREADY_EXISTS) {
        if (mapping) CloseHandle(mapping);
        FreeLibrary(module); return Report("mapping", mapError);
    }
    auto* request = static_cast<Request*>(MapViewOfFile(mapping, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, sizeof(Request)));
    if (!request) {
        DWORD e = GetLastError(); CloseHandle(mapping); FreeLibrary(module); return Report("mapping_view", e);
    }
    *request = {};
    request->version = 1; request->targetPid = pid; request->targetTid = tid;
    request->targetWindow = h; request->creationTime = created; request->desired = DWORD(desired);
    UINT message = RegisterWindowMessageW(kMessage);
    HHOOK hook = message ? SetWindowsHookExW(WH_CALLWNDPROC, callback, module, tid) : nullptr;
    DWORD error = hook ? 0 : GetLastError();
    const char* status = "hook";
    if (hook) {
        DWORD_PTR result = 0;
        SetLastError(0);
        LRESULT sent = SendMessageTimeoutW(window, message, GetCurrentProcessId(), LPARAM(nonce),
            SMTO_ABORTIFHUNG | SMTO_BLOCK | SMTO_ERRORONEXIT, 1500, &result);
        if (!sent) { error = GetLastError(); if (!error) error = ERROR_TIMEOUT; status = "send_timeout"; }
        else if (!request->acknowledged) { error = ERROR_NOT_SUPPORTED; status = "no_ack"; }
        else { error = request->error; status = request->success ? "ok" : "apply"; }
        UnhookWindowsHookEx(hook);
    }
    Request copy = *request;
    UnmapViewOfFile(request);
    CloseHandle(mapping);
    FreeLibrary(module);
    return Report(status, error, &copy);
}
