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
static char _hid_error[512] = "";
static int _hid_attempt_count = 0;
static int _hid_send_failures = 0;

static IOHIDSystemClientRef (*_IOHIDEventSystemClientCreate)(CFAllocatorRef);
static IOHIDEventRef (*_IOHIDEventCreateDigitizerEvent)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t,
    int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, uint32_t);
static IOHIDEventRef (*_IOHIDEventCreateDigitizerFingerEvent)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
    int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, uint32_t);
static void (*_IOHIDEventAppendEvent)(IOHIDEventRef, IOHIDEventRef);
static int (*_IOHIDEventSystemClientDispatchEvent)(IOHIDSystemClientRef, IOHIDEventRef);

#define FIX(p) ((int32_t)((p) * 65536.0f))

bool hid_init(void) {
    if (_hid_client) return _hid_ok;
    _hid_attempt_count++;

    void* handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    }
    if (!handle) {
        snprintf(_hid_error, sizeof(_hid_error), "dlopen IOKit failed: %s", dlerror());
        return false;
    }

    _IOHIDEventSystemClientCreate = dlsym(handle, "IOHIDEventSystemClientCreate");
    _IOHIDEventCreateDigitizerEvent = dlsym(handle, "IOHIDEventCreateDigitizerEvent");
    _IOHIDEventCreateDigitizerFingerEvent = dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
    _IOHIDEventAppendEvent = dlsym(handle, "IOHIDEventAppendEvent");
    _IOHIDEventSystemClientDispatchEvent = dlsym(handle, "IOHIDEventSystemClientDispatchEvent");

    if (!_IOHIDEventSystemClientCreate)       { snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventSystemClientCreate = NULL"); return false; }
    if (!_IOHIDEventCreateDigitizerEvent)      { snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventCreateDigitizerEvent = NULL"); return false; }
    if (!_IOHIDEventCreateDigitizerFingerEvent){ snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventCreateDigitizerFingerEvent = NULL"); return false; }
    if (!_IOHIDEventAppendEvent)               { snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventAppendEvent = NULL"); return false; }
    if (!_IOHIDEventSystemClientDispatchEvent) { snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventSystemClientDispatchEvent = NULL"); return false; }

    _hid_client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!_hid_client) {
        snprintf(_hid_error, sizeof(_hid_error), "ClientCreate returned NULL (attempt %d)", _hid_attempt_count);
        return false;
    }

    _hid_ok = true;
    _hid_send_failures = 0;
    return true;
}

bool hid_ready(void) {
    return _hid_ok;
}

const char* hid_error(void) {
    return _hid_error;
}

int hid_attempts(void) {
    return _hid_attempt_count;
}

int hid_send_failures(void) {
    return _hid_send_failures;
}

static void _hid_send(float x, float y, int32_t finger_id, int touch_type) {
    if (!_hid_client) { _hid_send_failures++; return; }

    uint64_t ts = mach_absolute_time();
    int32_t fx = FIX(x);
    int32_t fy = FIX(y);

    uint32_t finger_mask;
    int32_t tip, range;
    if (touch_type == 2) {
        finger_mask = 1;   /* kIOHIDDigitizerEventRange */
        tip = 0;
        range = 0;
    } else {
        finger_mask = 7;   /* range | touch | position */
        tip = FIX(1);
        range = 1;
    }

    IOHIDEventRef parent = _IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, ts,
        3,                     /* transducerType: finger */
        0,                     /* index */
        (uint32_t)finger_id + 2, /* identity */
        touch_type == 2 ? 0 : 3, /* eventMask: range+touch */
        fx, fy, 0,             /* x,y,z fixed */
        tip, 0,                /* tipPressure, auxPressure */
        0,                     /* twist */
        range,                 /* range */
        0);                    /* options */

    IOHIDEventRef finger = _IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, ts,
        (uint32_t)finger_id,               /* index */
        (uint32_t)finger_id + 2,           /* identity */
        finger_mask,
        fx, fy, 0,
        tip, 0,
        0, range,
        0);

    if (!parent) { _hid_send_failures++; }
    if (!finger) { _hid_send_failures++; }

    if (parent && finger) {
        _IOHIDEventAppendEvent(parent, finger);
        _IOHIDEventSystemClientDispatchEvent(_hid_client, parent);
    }

    if (finger) CFRelease(finger);
    if (parent) CFRelease(parent);
}

void hid_touch_down(float x, float y, int32_t finger_id) { _hid_send(x, y, finger_id, 0); }
void hid_touch_move(float x, float y, int32_t finger_id) { _hid_send(x, y, finger_id, 1); }
void hid_touch_up(float x, float y, int32_t finger_id)   { _hid_send(x, y, finger_id, 2); }

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

#pragma mark - GraphicsServices GSEvent

static void* _gs_handle = NULL;
static bool _gs_ok = false;
static char _gs_error[512] = "";

static void* (*_GSCreateEvent)(const void* record);
static void (*_GSSendEvent)(void* event, int32_t port);
static int32_t (*_GSSendSystemEvent)(void* event, int32_t port);

bool gs_init(void) {
    if (_gs_handle) return _gs_ok;

    _gs_handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW | RTLD_LOCAL);
    if (!_gs_handle) {
        _gs_handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY | RTLD_LOCAL);
    }
    if (!_gs_handle) {
        snprintf(_gs_error, sizeof(_gs_error), "dlopen failed: %s", dlerror());
        return false;
    }

    _GSCreateEvent = dlsym(_gs_handle, "GSCreateEvent");
    _GSSendEvent = dlsym(_gs_handle, "GSSendEvent");
    _GSSendSystemEvent = dlsym(_gs_handle, "GSSendSystemEvent");

    if (!_GSSendEvent && !_GSSendSystemEvent) {
        snprintf(_gs_error, sizeof(_gs_error), "GSSendEvent and GSSendSystemEvent both NULL");
        dlclose(_gs_handle);
        _gs_handle = NULL;
        return false;
    }

    if (!_GSCreateEvent) {
        snprintf(_gs_error, sizeof(_gs_error), "GSCreateEvent not found (remove in later iOS)");
    }

    if (_GSCreateEvent) {
        _gs_ok = true;
        return true;
    }

    return false;
}

bool gs_ready(void) {
    return _gs_ok;
}

const char* gs_error(void) {
    return _gs_error;
}

void gs_touch_down(float x, float y) {}
void gs_touch_move(float x, float y) {}
void gs_touch_up(float x, float y) {}
void gs_tap(float x, float y) {}
void gs_swipe(float x1, float y1, float x2, float y2, float duration) {}

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
    if (!_hid_ok && _hid_error[0]) return _hid_error;
    if (!_gs_ok && _gs_error[0]) return _gs_error;
    return "";
}
