// SPDX-License-Identifier: AGPL-3.0-only
// API-call sequence reference: Riley Testut's AltServer-Windows,
// AltServer/AnisetteDataManager.cpp (AGPL-3.0):
// https://github.com/rileytestut/AltServer-Windows
// License: https://www.gnu.org/licenses/agpl-3.0.html
// This standalone implementation omits upstream's debug output, optional binary
// patches, provisioning resets, and ADI-file management.
//
// Build only with x86 MSVC. The parent must capture stdout in a private pipe;
// never run this executable through a terminal/transcript or redirect to a file.
// Success JSON contains fresh device authentication data, not diagnostic output.
// Failure JSON has the same three keys with null values; the exit code identifies
// the static failure category. This program does not accept account credentials.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <bcrypt.h>
#include <shlobj.h>
#include <io.h>
#include <array>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#if !defined(_M_IX86)
#error The installed Apple AOSKit library requires an x86 helper.
#endif

namespace {
enum ExitCode : int {
    Success = 0,
    StdoutNotPipe = 2,
    OutputIsolationFailed = 3,
    AppleDirectoryUnavailable = 4,
    DllSearchSetupFailed = 5,
    AppleLibraryUnavailable = 6,
    RuntimeExportUnavailable = 7,
    AppleClassUnavailable = 8,
    AppleMethodUnavailable = 9,
    GeneratedHeadersUnavailable = 10,
    GeneratedHeaderFormatInvalid = 11,
    PipeWriteFailed = 12,
    UnexpectedFailure = 13,
    InvalidArguments = 14,
    UnsupportedIdentityLibrary = 15,
    NativeIdentityUnavailable = 16,
};

constexpr size_t MaxFieldBytes = 8192;
constexpr char FailureJson[] =
    "{\"success\":false,\"machine_id\":null,\"one_time_password\":null}\n";

struct SensitiveBuffers {
    std::array<char, MaxFieldBytes + 1> machine{};
    std::array<char, MaxFieldBytes + 1> otp{};
    std::array<char, 1025> clientInfo{};
    std::array<char, 129> deviceId{};
    std::array<char, 257> localUserId{};
    std::array<char, 20 * 1024> json{};
    ~SensitiveBuffers() { SecureZeroMemory(this, sizeof(*this)); }
};

using Obj = void*;
using Sel = void*;
using GetClass = Obj(__cdecl*)(const char*);
using RegisterSelector = Sel(__cdecl*)(const char*);
using GetClassMethod = void*(__cdecl*)(Obj, Sel);
using SendNoArg = Obj(__cdecl*)(Obj, Sel);
using SendObject = Obj(__cdecl*)(Obj, Sel, Obj);
using SendCString = Obj(__cdecl*)(Obj, Sel, const char*);
using SendUtf8 = const char*(__cdecl*)(Obj, Sel);
using PoolPush = void*(__cdecl*)();
using PoolPop = void(__cdecl*)(void*);
using GetNativeObject = Obj(__cdecl*)();
using GetNativeClientInfo = Obj(__cdecl*)(Obj);

struct FileHandle {
    HANDLE value = INVALID_HANDLE_VALUE;
    ~FileHandle() { if (value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};

struct AutoreleasePool {
    void* value;
    PoolPop pop;
    ~AutoreleasePool() { pop(value); }
};

bool WritePipe(HANDLE pipe, const char* bytes, size_t length) {
    while (length != 0) {
        DWORD written = 0;
        if (!WriteFile(pipe, bytes, static_cast<DWORD>(length), &written, nullptr) || written == 0) {
            return false;
        }
        bytes += written;
        length -= written;
    }
    return true;
}

int Fail(HANDLE pipe, ExitCode code) {
    if (!WritePipe(pipe, FailureJson, sizeof(FailureJson) - 1)) {
        return PipeWriteFailed;
    }
    return code;
}

bool CopyBase64(const char* value, std::array<char, MaxFieldBytes + 1>& output, size_t& length) {
    if (!value) return false;
    length = strnlen_s(value, MaxFieldBytes + 1);
    if (length == 0 || length > MaxFieldBytes) return false;
    for (size_t i = 0; i < length; ++i) {
        const unsigned char c = static_cast<unsigned char>(value[i]);
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
              (c >= '0' && c <= '9') || c == '+' || c == '/' || c == '=')) {
            return false;
        }
    }
    std::memcpy(output.data(), value, length);
    return true;
}

template<size_t Capacity>
bool CopyJsonSafeText(const char* value, std::array<char, Capacity>& output, size_t& length) {
    if (!value) return false;
    length = strnlen_s(value, Capacity);
    if (length == 0 || length >= Capacity) return false;
    for (size_t i = 0; i < length; ++i) {
        const unsigned char c = static_cast<unsigned char>(value[i]);
        if (c < 32 || c > 126 || c == '"' || c == '\\') return false;
    }
    std::memcpy(output.data(), value, length);
    return true;
}

bool IdentityLibraryHashMatches(HANDLE file) {
    // Installed iCloud_main.dll 261.7.0.67, x86. Reject every other binary before
    // using the private getter offsets from official AltServer commit e91915d.
    constexpr BYTE expected[32] = {
        0xcc,0x42,0x0c,0x7b,0xd3,0xdd,0xdc,0x2b,0xe7,0xb1,0xf0,0x7d,0xce,0x18,0x49,0x99,
        0x37,0x45,0x1e,0xde,0x79,0x3a,0xce,0x86,0xc8,0x7b,0x84,0x50,0x96,0x61,0x88,0x1c
    };
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) return false;
    DWORD objectLength = 0;
    DWORD written = 0;
    bool valid = false;
    if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
        reinterpret_cast<PUCHAR>(&objectLength), sizeof(objectLength), &written, 0) >= 0 &&
        objectLength != 0 && objectLength <= 64 * 1024) {
        std::vector<BYTE> hashObject(objectLength);
        if (BCryptCreateHash(algorithm, &hash, hashObject.data(), objectLength, nullptr, 0, 0) >= 0) {
            std::array<BYTE, 64 * 1024> chunk{};
            DWORD count = 0;
            bool readOk = true;
            while (true) {
                if (!ReadFile(file, chunk.data(), static_cast<DWORD>(chunk.size()), &count, nullptr)) { readOk = false; break; }
                if (count == 0) break;
                if (BCryptHashData(hash, chunk.data(), count, 0) < 0) { readOk = false; break; }
            }
            BYTE digest[32]{};
            valid = readOk && BCryptFinishHash(hash, digest, sizeof(digest), 0) >= 0 &&
                std::memcmp(digest, expected, sizeof(expected)) == 0;
            BCryptDestroyHash(hash);
        }
    }
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return valid;
}

int Generate(HANDLE output, bool nativeIdentity) {
    PWSTR commonPath = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_ProgramFilesCommonX86, 0, nullptr, &commonPath))) {
        return Fail(output, AppleDirectoryUnavailable);
    }
    const std::wstring apple = std::wstring(commonPath) + L"\\Apple";
    CoTaskMemFree(commonPath);
    const std::wstring support = apple + L"\\Apple Application Support";
    const std::wstring internet = apple + L"\\Internet Services";

    // Limit dependency lookup to installed Apple directories and Windows system
    // libraries; the executable's working directory is never searched.
    if (!SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32 | LOAD_LIBRARY_SEARCH_USER_DIRS) ||
        !AddDllDirectory(support.c_str()) || !AddDllDirectory(internet.c_str())) {
        return Fail(output, DllSearchSetupFailed);
    }
    constexpr DWORD loadFlags = LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS;
    const HMODULE objc = LoadLibraryExW((support + L"\\objc.dll").c_str(), nullptr, loadFlags);
    const HMODULE foundation = LoadLibraryExW((support + L"\\Foundation.dll").c_str(), nullptr, loadFlags);
    const HMODULE aos = LoadLibraryExW((internet + L"\\AOSKit.dll").c_str(), nullptr, loadFlags);
    if (!objc || !foundation || !aos) return Fail(output, AppleLibraryUnavailable);

    const auto getClass = reinterpret_cast<GetClass>(GetProcAddress(objc, "objc_getClass"));
    const auto selector = reinterpret_cast<RegisterSelector>(GetProcAddress(objc, "sel_registerName"));
    const auto classMethod = reinterpret_cast<GetClassMethod>(GetProcAddress(objc, "class_getClassMethod"));
    const auto send = GetProcAddress(objc, "objc_msgSend");
    const auto pushPool = reinterpret_cast<PoolPush>(GetProcAddress(objc, "objc_autoreleasePoolPush"));
    const auto popPool = reinterpret_cast<PoolPop>(GetProcAddress(objc, "objc_autoreleasePoolPop"));
    if (!getClass || !selector || !classMethod || !send || !pushPool || !popPool) {
        return Fail(output, RuntimeExportUnavailable);
    }
    AutoreleasePool pool{pushPool(), popPool};
    const Obj stringClass = getClass("NSString");
    const Obj utilities = getClass("AOSUtilities");
    if (!stringClass || !utilities) return Fail(output, AppleClassUnavailable);
    const Sel makeString = selector("stringWithUTF8String:");
    const Sel retrieve = selector("retrieveOTPHeadersForDSID:");
    const Sel objectForKey = selector("objectForKey:");
    const Sel utf8 = selector("UTF8String");
    if (!makeString || !retrieve || !objectForKey || !utf8 ||
        !classMethod(stringClass, makeString) || !classMethod(utilities, retrieve)) {
        return Fail(output, AppleMethodUnavailable);
    }
    const auto string = reinterpret_cast<SendCString>(send);
    const auto object = reinterpret_cast<SendObject>(send);
    const auto utf8String = reinterpret_cast<SendUtf8>(send);

    SensitiveBuffers buffers;
    FileHandle identityFile;
    size_t clientInfoLength = 0;
    size_t deviceIdLength = 0;
    size_t localUserIdLength = 0;
    if (nativeIdentity) {
        const std::wstring identityPath = internet + L"\\iCloud_main.dll";
        // Keep the validated file open without write/delete sharing until exit.
        identityFile.value = CreateFileW(identityPath.c_str(), GENERIC_READ, FILE_SHARE_READ,
            nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
        if (identityFile.value == INVALID_HANDLE_VALUE || !IdentityLibraryHashMatches(identityFile.value)) {
            return Fail(output, UnsupportedIdentityLibrary);
        }
        const HMODULE identity = LoadLibraryExW(identityPath.c_str(), nullptr, loadFlags);
        if (!identity) return Fail(output, AppleLibraryUnavailable);
        const auto base = reinterpret_cast<const BYTE*>(identity);
        const auto anchor = reinterpret_cast<const BYTE*>(GetProcAddress(identity, "PL_FreeArenaPool"));
        if (anchor != base + 0x1AAEA0) return Fail(output, UnsupportedIdentityLibrary);
        // Official source calculates these relative to PL_FreeArenaPool. The
        // installed binary has the same deltas, statically checked against the
        // UDID/Local UUID/client-description routines, and the hash above pins it.
        const BYTE* clientAddress = anchor + (0x23E730 - 0x1AA2A0);
        const BYTE* deviceAddress = anchor + (0x23D8B0 - 0x1AA2A0);
        const BYTE* localAddress = anchor + (0x23DB30 - 0x1AA2A0);
        constexpr BYTE prologue[] = {0x55, 0x8b, 0xec};
        if (std::memcmp(clientAddress, prologue, sizeof(prologue)) != 0 ||
            std::memcmp(deviceAddress, prologue, sizeof(prologue)) != 0 ||
            std::memcmp(localAddress, prologue, sizeof(prologue)) != 0) {
            return Fail(output, UnsupportedIdentityLibrary);
        }
        const auto getClient = reinterpret_cast<GetNativeClientInfo>(const_cast<BYTE*>(clientAddress));
        const auto getDevice = reinterpret_cast<GetNativeObject>(const_cast<BYTE*>(deviceAddress));
        const auto getLocal = reinterpret_cast<GetNativeObject>(const_cast<BYTE*>(localAddress));
        const Obj nativeClient = getClient(nullptr);
        const Obj nativeDevice = getDevice();
        const Obj nativeLocal = getLocal();
        if (!nativeClient || !nativeDevice || !nativeLocal) return Fail(output, NativeIdentityUnavailable);
        // Upstream obtains NSString via -description before reading UTF8String.
        const Sel description = selector("description");
        const auto describe = reinterpret_cast<SendNoArg>(send);
        const Obj clientText = describe(nativeClient, description);
        const Obj deviceText = describe(nativeDevice, description);
        const Obj localText = describe(nativeLocal, description);
        if (!clientText || !deviceText || !localText ||
            !CopyJsonSafeText(utf8String(clientText, utf8), buffers.clientInfo, clientInfoLength) ||
            !CopyJsonSafeText(utf8String(deviceText, utf8), buffers.deviceId, deviceIdLength) ||
            !CopyJsonSafeText(utf8String(localText, utf8), buffers.localUserId, localUserIdLength)) {
            return Fail(output, NativeIdentityUnavailable);
        }
    }

    // Generate fresh OTP only after all identity validation has finished.
    const Obj dsid = string(stringClass, makeString, "-2");
    const Obj machineKey = string(stringClass, makeString, "X-Apple-MD-M");
    const Obj otpKey = string(stringClass, makeString, "X-Apple-MD");
    if (!dsid || !machineKey || !otpKey) return Fail(output, AppleClassUnavailable);
    const Obj headers = object(utilities, retrieve, dsid);
    if (!headers) return Fail(output, GeneratedHeadersUnavailable);
    const Obj machine = object(headers, objectForKey, machineKey);
    const Obj otp = object(headers, objectForKey, otpKey);
    if (!machine || !otp) return Fail(output, GeneratedHeadersUnavailable);

    size_t machineLength = 0;
    size_t otpLength = 0;
    if (!CopyBase64(utf8String(machine, utf8), buffers.machine, machineLength) ||
        !CopyBase64(utf8String(otp, utf8), buffers.otp, otpLength)) {
        return Fail(output, GeneratedHeaderFormatInvalid);
    }
    // Values are bounded base64, so none can introduce JSON punctuation or escapes.
    size_t used = 0;
    const auto append = [&](const char* bytes, size_t count) {
        std::memcpy(buffers.json.data() + used, bytes, count);
        used += count;
    };
    constexpr char prefix[] = "{\"success\":true,\"machine_id\":\"";
    constexpr char middle[] = "\",\"one_time_password\":\"";
    append(prefix, sizeof(prefix) - 1);
    append(buffers.machine.data(), machineLength);
    append(middle, sizeof(middle) - 1);
    append(buffers.otp.data(), otpLength);
    if (nativeIdentity) {
        constexpr char clientKey[] = "\",\"client_info\":\"";
        constexpr char deviceKey[] = "\",\"device_id\":\"";
        constexpr char localKey[] = "\",\"local_user_id\":\"";
        constexpr char routing[] = "\",\"routing_info\":\"84215040";
        append(clientKey, sizeof(clientKey) - 1);
        append(buffers.clientInfo.data(), clientInfoLength);
        append(deviceKey, sizeof(deviceKey) - 1);
        append(buffers.deviceId.data(), deviceIdLength);
        append(localKey, sizeof(localKey) - 1);
        append(buffers.localUserId.data(), localUserIdLength);
        append(routing, sizeof(routing) - 1);
    }
    constexpr char suffix[] = "\"}\n";
    append(suffix, sizeof(suffix) - 1);
    return WritePipe(output, buffers.json.data(), used) ? Success : PipeWriteFailed;
}
} // namespace

int main(int argc, char* argv[]) {
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
    const HANDLE inherited = GetStdHandle(STD_OUTPUT_HANDLE);
    if (!inherited || inherited == INVALID_HANDLE_VALUE || GetFileType(inherited) != FILE_TYPE_PIPE) {
        return StdoutNotPipe;
    }
    HANDLE output = nullptr;
    if (!DuplicateHandle(GetCurrentProcess(), inherited, GetCurrentProcess(), &output, 0, FALSE, DUPLICATE_SAME_ACCESS)) {
        return OutputIsolationFailed;
    }
    // Preserve only our explicit pipe handle. Libraries loaded later see NUL for
    // ordinary stdout/stderr; our code emits no trace or debug messages.
    FILE* ignored = nullptr;
    if (_wfreopen_s(&ignored, L"NUL", L"w", stdout) != 0 ||
        _wfreopen_s(&ignored, L"NUL", L"w", stderr) != 0) {
        const int result = Fail(output, OutputIsolationFailed);
        CloseHandle(output);
        return result;
    }
    if (!SetStdHandle(STD_OUTPUT_HANDLE, reinterpret_cast<HANDLE>(_get_osfhandle(_fileno(stdout)))) ||
        !SetStdHandle(STD_ERROR_HANDLE, reinterpret_cast<HANDLE>(_get_osfhandle(_fileno(stderr))))) {
        const int result = Fail(output, OutputIsolationFailed);
        CloseHandle(output);
        return result;
    }
    int result = UnexpectedFailure;
    try {
        if (argc > 2 || (argc == 2 && std::strcmp(argv[1], "--native-identity") != 0)) {
            result = Fail(output, InvalidArguments);
        } else {
            result = Generate(output, argc == 2);
        }
    }
    catch (...) { result = Fail(output, UnexpectedFailure); }
    CloseHandle(output);
    return result;
}
