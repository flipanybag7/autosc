#include "TouchInject.h"
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

#pragma mark - IOKit HID via dlsym

typedef void* IOHIDSystemClientRef;
typedef void* IOHIDEventRef;

static IOHIDSystemClientRef _hid_client = NULL;
static bool _hid_ok = false;
static char _hid_error[256] = "";

/* function pointers loaded via dlsym */
static IOHIDSystemClientRef (*_IOHIDEventSystemClientCreate)(CFAllocatorRef);
static IOHIDEventRef (*_IOHIDEventCreateDigitizerEvent)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t,
    int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, uint32_t);
static IOHIDEventRef (*_IOHIDEventCreateDigitizerFingerEvent)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
    int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, uint32_t);
static void (*_IOHIDEventAppendEvent)(IOHIDEventRef, IOHIDEventRef);
static void (*_IOHIDEventSystemClientDispatchEvent)(IOHIDSystemClientRef, IOHIDEventRef);

#define FIX(p) ((int32_t)((p) * 65536.0f))

bool hid_init(void) {
    if (_hid_client) return _hid_ok;

    /* try IOKit first, then IOKit via full path */
    const char* paths[] = {
        "/System/Library/Frameworks/IOKit.framework/IOKit",
        NULL
    };

    void* handle = NULL;
    for (int i = 0; paths[i]; i++) {
        handle = dlopen(paths[i], RTLD_NOW);
        if (handle) {
            snprintf(_hid_error, sizeof(_hid_error), "loaded %s", paths[i]);
            break;
        }
    }

    if (!handle) {
        /* try system path */
        handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) {
            snprintf(_hid_error, sizeof(_hid_error), "dlopen IOKit failed: %s", dlerror());
            return false;
        }
        snprintf(_hid_error, sizeof(_hid_error), "loaded IOKit (lazy)");
    }

    _IOHIDEventSystemClientCreate = dlsym(handle, "IOHIDEventSystemClientCreate");
    _IOHIDEventCreateDigitizerEvent = dlsym(handle, "IOHIDEventCreateDigitizerEvent");
    _IOHIDEventCreateDigitizerFingerEvent = dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
    _IOHIDEventAppendEvent = dlsym(handle, "IOHIDEventAppendEvent");
    _IOHIDEventSystemClientDispatchEvent = dlsym(handle, "IOHIDEventSystemClientDispatchEvent");

    if (!_IOHIDEventSystemClientCreate) {
        snprintf(_hid_error, sizeof(_hid_error), "dlsym IOHIDEventSystemClientCreate failed");
        dlclose(handle);
        return false;
    }

    _hid_client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!_hid_client) {
        snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventSystemClientCreate returned NULL - check entitlements");
        dlclose(handle);
        return false;
    }

    _hid_ok = true;
    return true;
}

bool hid_ready(void) {
    return _hid_ok;
}

const char* hid_error(void) {
    return _hid_error;
}

static void _hid_send(float x, float y, int32_t finger_id, int touch_type) {
    if (!_hid_client) return;

    uint64_t ts = mach_absolute_time();
    int32_t fx = FIX(x);
    int32_t fy = FIX(y);

    uint32_t finger_event_mask;
    int32_t tip_pressure;
    int32_t range_val;

    switch (touch_type) {
        case 0:
        case 1:
            finger_event_mask = 7;
            tip_pressure = FIX(1);
            range_val = 1;
            break;
        case 2:
            finger_event_mask = 1;
            tip_pressure = 0;
            range_val = 0;
            break;
        default:
            return;
    }

    if (!_IOHIDEventCreateDigitizerEvent || !_IOHIDEventCreateDigitizerFingerEvent ||
        !_IOHIDEventAppendEvent || !_IOHIDEventSystemClientDispatchEvent) return;

    IOHIDEventRef parent = _IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, ts, 3, 0, (uint32_t)finger_id + 2, 1,
        0, 0, 0, 0, 0, 0, 1, 0);

    IOHIDEventRef finger = _IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, ts, (uint32_t)finger_id, (uint32_t)finger_id + 2,
        finger_event_mask, fx, fy, 0, tip_pressure, 0, 0, range_val, 0);

    if (parent && finger) {
        _IOHIDEventAppendEvent(parent, finger);
        _IOHIDEventSystemClientDispatchEvent(_hid_client, parent);
    }

    if (finger) CFRelease(finger);
    if (parent) CFRelease(parent);
}

void hid_touch_down(float x, float y, int32_t finger_id) {
    _hid_send(x, y, finger_id, 0);
}

void hid_touch_move(float x, float y, int32_t finger_id) {
    _hid_send(x, y, finger_id, 1);
}

void hid_touch_up(float x, float y, int32_t finger_id) {
    _hid_send(x, y, finger_id, 2);
}

void hid_tap(float x, float y) {
    hid_touch_down(x, y, 0);
    usleep(60000);
    hid_touch_up(x, y, 0);
}

void hid_swipe(float x1, float y1, float x2, float y2, float duration) {
    int steps = (int)(duration * 120);
    if (steps < 10) steps = 10;
    useconds_t delay = (useconds_t)(duration / (float)steps * 1000000.0f);

    hid_touch_down(x1, y1, 0);
    for (int i = 1; i <= steps; i++) {
        usleep(delay);
        float t = (float)i / (float)steps;
        float cx = x1 + (x2 - x1) * t;
        float cy = y1 + (y2 - y1) * t;
        hid_touch_move(cx, cy, 0);
    }
    usleep(40000);
    hid_touch_up(x2, y2, 0);
}

void hid_long_press(float x, float y, float duration) {
    hid_touch_down(x, y, 0);
    usleep((useconds_t)(duration * 1000000.0f));
    hid_touch_up(x, y, 0);
}

#pragma mark - GraphicsServices GSEvent (fallback)

static void* _gs_handle = NULL;
static bool _gs_ok = false;
static char _gs_error[256] = "";
static const char* _gs_path_failed = "";

static void* (*_GSCreateEvent)(const void* record);
static void (*_GSSendEvent)(void* event, int32_t port);

bool gs_init(void) {
    if (_gs_handle) return _gs_ok;

    const char* paths[] = {
        "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",
        "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",
        NULL
    };

    for (int i = 0; paths[i]; i++) {
        _gs_handle = dlopen(paths[i], RTLD_NOW);
        if (_gs_handle) {
            _gs_path_failed = paths[i];
            break;
        }
    }

    if (!_gs_handle) {
        snprintf(_gs_error, sizeof(_gs_error), "dlopen GraphicsServices failed: %s", dlerror());
        return false;
    }

    _GSCreateEvent = dlsym(_gs_handle, "GSCreateEvent");
    if (!_GSCreateEvent) {
        snprintf(_gs_error, sizeof(_gs_error), "dlsym GSCreateEvent failed");
        dlclose(_gs_handle);
        _gs_handle = NULL;
        return false;
    }

    _GSSendEvent = dlsym(_gs_handle, "GSSendEvent");
    if (!_GSSendEvent) {
        /* try GSSendSystemEvent as alternative */
        void* alt = dlsym(_gs_handle, "GSSendSystemEvent");
        if (alt) {
            _GSSendEvent = alt;
        } else {
            snprintf(_gs_error, sizeof(_gs_error), "dlsym GSSendEvent/GSSendSystemEvent failed");
            dlclose(_gs_handle);
            _gs_handle = NULL;
            return false;
        }
    }

    _gs_ok = true;
    return true;
}

bool gs_ready(void) {
    return _gs_ok;
}

const char* gs_error(void) {
    return _gs_error;
}

static void _gs_build_and_send(int32_t phase, float x, float y) {
    if (!_GSCreateEvent || !_GSSendEvent) return;

    uint8_t record[256];
    memset(record, 0, sizeof(record));

    int off = 0;
    #define W32(v) do { int32_t _v = (int32_t)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    #define W64(v) do { int64_t _v = (int64_t)(v); memcpy(record + off, &_v, 8); off += 8; } while(0)
    #define WF(v) do { float _v = (float)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    #define WU32(v) do { uint32_t _v = (uint32_t)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)

    /* GSEventHand (3001) record structure for iOS 14-16 */
    W32(3001);       /* type: kGSEventHand */
    W32(0);           /* flags */
    WF(x); WF(y);     /* location */
    W64((int64_t)mach_absolute_time());  /* timestamp */
    W32(1);           /* windowIndex */
    W32(phase);       /* phase: 0=down, 1=moved, 2=up */
    W32(0);           /* fingerId */
    WF(0); WF(0);     /* normalizedLocation */
    WU32(0);          /* pathIndex */
    WU32(phase == 2 ? 0 : 1);  /* pathIdentity */
    WU32(0);          /* pathProximity */
    WU32(0);          /* jitterRadius */
    WU32(0);          /* angle */
    WU32(0);          /* majorRadius */

    #undef W32
    #undef W64
    #undef WF
    #undef WU32

    void* evt = _GSCreateEvent(record);
    if (evt) {
        _GSSendEvent(evt, 0);
        CFRelease(evt);
    }
}

void gs_touch_down(float x, float y) {
    _gs_build_and_send(0, x, y);
}

void gs_touch_move(float x, float y) {
    _gs_build_and_send(1, x, y);
}

void gs_touch_up(float x, float y) {
    _gs_build_and_send(2, x, y);
}

void gs_tap(float x, float y) {
    gs_touch_down(x, y);
    usleep(60000);
    gs_touch_up(x, y);
}

void gs_swipe(float x1, float y1, float x2, float y2, float duration) {
    int steps = (int)(duration * 60);
    if (steps < 10) steps = 10;
    useconds_t delay = (useconds_t)(duration / (float)steps * 1000000.0f);

    gs_touch_down(x1, y1);
    for (int i = 1; i <= steps; i++) {
        usleep(delay);
        float t = (float)i / (float)steps;
        gs_touch_move(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
    }
    usleep(40000);
    gs_touch_up(x2, y2);
}

#pragma mark - Method selection

int inject_method(void) {
    if (_hid_ok) return 0;
    if (_gs_ok) return 1;
    return -1;
}

const char* inject_method_name(void) {
    if (_hid_ok) return "IOKit HID";
    if (_gs_ok) return "GraphicsServices";
    return "none";
}

const char* inject_error(void) {
    if (_hid_error[0]) return _hid_error;
    if (_gs_error[0]) return _gs_error;
    return "";
}
