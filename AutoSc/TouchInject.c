#include "TouchInject.h"
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/access.h>

#pragma mark - C Helper Binary (primary, proven working with sudo)

static char _helper_path[512] = {0};
static bool _helper_ready = false;
static bool _helper_is_root = false;

bool helper_init(const char *path) {
    if (!path) return false;
    strncpy(_helper_path, path, sizeof(_helper_path) - 1);
    _helper_ready = (access(_helper_path, X_OK) == 0);
    return _helper_ready;
}

bool helper_ready(void) {
    return _helper_ready;
}

bool helper_is_root(void) {
    return _helper_is_root;
}

static int _spawn_helper(const char *type, float x, float y, int32_t fid) {
    if (!_helper_ready) return -1;

    char xs[32], ys[32], fids[16];
    snprintf(xs, sizeof(xs), "%.2f", x);
    snprintf(ys, sizeof(ys), "%.2f", y);
    snprintf(fids, sizeof(fids), "%d", fid);

    const char *sudo_path = "/var/jb/usr/bin/sudo";
    bool use_sudo = (access(sudo_path, X_OK) == 0);

    pid_t pid = 0;
    int status;

    if (use_sudo && !_helper_is_root) {
        const char *args[] = { sudo_path, _helper_path, type, xs, ys, fids, NULL };
        posix_spawn(&pid, sudo_path, NULL, NULL, (char* const*)args, NULL);
        _helper_is_root = true;
    } else if (_helper_is_root) {
        const char *args[] = { sudo_path, _helper_path, type, xs, ys, fids, NULL };
        posix_spawn(&pid, sudo_path, NULL, NULL, (char* const*)args, NULL);
    } else {
        const char *args[] = { _helper_path, type, xs, ys, fids, NULL };
        posix_spawn(&pid, _helper_path, NULL, NULL, (char* const*)args, NULL);
    }

    if (pid > 0) {
        waitpid(pid, &status, 0);
        return WEXITSTATUS(status);
    }
    return -1;
}

void helper_touch_down(float x, float y, int32_t fid) {
    _spawn_helper("0", x, y, fid);
}

void helper_touch_move(float x, float y, int32_t fid) {
    _spawn_helper("1", x, y, fid);
}

void helper_touch_up(float x, float y, int32_t fid) {
    _spawn_helper("2", x, y, fid);
}

#pragma mark - IOKit HID (fallback, direct in-process)

typedef void* IOHIDSystemClientRef;
typedef void* IOHIDEventRef;

static IOHIDSystemClientRef _hid_client = NULL;
static bool _hid_ok = false;

extern IOHIDSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern IOHIDEventRef IOHIDEventCreateDigitizerEvent(
    CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t transducerType, uint32_t index, uint32_t identity,
    uint32_t eventMask,
    int32_t x, int32_t y, int32_t z,
    int32_t tipPressure, int32_t auxPressure,
    int32_t twist, int32_t range,
    uint32_t options);
extern IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(
    CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t index, uint32_t identity, uint32_t eventMask,
    int32_t x, int32_t y, int32_t z,
    int32_t tipPressure, int32_t auxPressure,
    int32_t twist, int32_t range,
    uint32_t options);
extern void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDSystemClientRef client, IOHIDEventRef event);

#define FIX(p) ((int32_t)((p) * 65536.0f))

bool hid_init(void) {
    if (_hid_client) return _hid_ok;
    _hid_client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    _hid_ok = (_hid_client != NULL);
    return _hid_ok;
}

bool hid_ready(void) { return _hid_ok; }

static void _hid_send(float x, float y, int32_t finger_id, int touch_type) {
    if (!_hid_client) return;
    uint64_t ts = mach_absolute_time();
    int32_t fx = FIX(x), fy = FIX(y);
    uint32_t fmask; int32_t tip, rng;
    if (touch_type == 2) { fmask = 1; tip = 0; rng = 0; }
    else { fmask = 7; tip = FIX(1); rng = 1; }
    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, ts, 3, 0, (uint32_t)(finger_id+2), 1, 0, 0, 0, 0, 0, 0, rng, 0);
    IOHIDEventRef finger = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, ts, (uint32_t)finger_id, (uint32_t)(finger_id+2), fmask, fx, fy, 0, tip, 0, 0, rng, 0);
    if (parent && finger) { IOHIDEventAppendEvent(parent, finger); IOHIDEventSystemClientDispatchEvent(_hid_client, parent); }
    if (finger) CFRelease(finger);
    if (parent) CFRelease(parent);
}

void hid_touch_down(float x, float y, int32_t fid) { _hid_send(x, y, fid, 0); }
void hid_touch_move(float x, float y, int32_t fid) { _hid_send(x, y, fid, 1); }
void hid_touch_up(float x, float y, int32_t fid) { _hid_send(x, y, fid, 2); }

#pragma mark - GSEvent (fallback #2)

static void* _gs_handle = NULL;
static bool _gs_ok = false;
static void* (*_GSCreateEvent)(const void*);
static void (*_GSSendEvent)(void*, int32_t);
static int32_t (*_GSSendSystemEvent)(void*, int32_t);

bool gs_init(void) {
    if (_gs_handle) return _gs_ok;
    _gs_handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW);
    if (!_gs_handle) return false;
    _GSCreateEvent = dlsym(_gs_handle, "GSCreateEvent");
    _GSSendEvent = dlsym(_gs_handle, "GSSendEvent");
    _GSSendSystemEvent = dlsym(_gs_handle, "GSSendSystemEvent");
    _gs_ok = (_GSCreateEvent != NULL && (_GSSendEvent != NULL || _GSSendSystemEvent != NULL));
    return _gs_ok;
}

bool gs_ready(void) { return _gs_ok; }

static void _gs_build_and_send(int32_t phase, float x, float y) {
    if (!_GSCreateEvent) return;
    uint8_t record[200]; memset(record, 0, sizeof(record));
    int off = 0;
    #define W32(v) do { int32_t _v=(int32_t)(v); memcpy(record+off,&_v,4); off+=4; } while(0)
    #define W64(v) do { int64_t _v=(int64_t)(v); memcpy(record+off,&_v,8); off+=8; } while(0)
    #define WF(v) do { float _v=(float)(v); memcpy(record+off,&_v,4); off+=4; } while(0)
    #define WU32(v) do { uint32_t _v=(uint32_t)(v); memcpy(record+off,&_v,4); off+=4; } while(0)
    W32(3001); W32(0); WF(0); WF(0); WF(0); WF(0);
    W64((int64_t)mach_absolute_time()); W64(0); WU32(44); WU32(0);
    W32(phase); W32(0); WF(x); WF(y); WF(0); WF(0); WF(0); WF(0);
    WU32(1); WU32(2); WU32(phase==2?0:1); WF(0);
    #undef W32; #undef W64; #undef WF; #undef WU32
    void* evt = _GSCreateEvent(record);
    if (evt) { if (_GSSendSystemEvent) _GSSendSystemEvent(evt, 0); else if (_GSSendEvent) _GSSendEvent(evt, 0); }
}

void gs_touch_down(float x, float y) { _gs_build_and_send(0, x, y); }
void gs_touch_move(float x, float y) { _gs_build_and_send(1, x, y); }
void gs_touch_up(float x, float y) { _gs_build_and_send(2, x, y); }

#pragma mark - Method selection (helper > IOKit > GSEvent)

int inject_method(void) {
    if (_helper_ready) return 0;
    if (_hid_ok) return 1;
    if (_gs_ok) return 2;
    return -1;
}
