#include "TouchInject.h"
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

#pragma mark - IOKit HID (primary)

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

bool hid_ready(void) {
    return _hid_ok;
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
            finger_event_mask = 7;
            tip_pressure = FIX(1);
            range_val = 1;
            break;
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

    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, ts,
        3, 0, (uint32_t)finger_id + 2,
        1,
        0, 0, 0,
        0, 0,
        0, 1,
        0);

    IOHIDEventRef finger = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, ts,
        (uint32_t)finger_id,
        (uint32_t)finger_id + 2,
        finger_event_mask,
        fx, fy, 0,
        tip_pressure, 0,
        0, range_val,
        0);

    if (parent && finger) {
        IOHIDEventAppendEvent(parent, finger);
        IOHIDEventSystemClientDispatchEvent(_hid_client, parent);
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

static void* (*_GSCreateEvent)(const void* record);
static void (*_GSSendEvent)(void* event, int32_t port);
static int32_t (*_GSSendSystemEvent)(void* event, int32_t port);

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

bool gs_ready(void) {
    return _gs_ok;
}

static void _gs_build_and_send(int32_t phase, float x, float y) {
    if (!_GSCreateEvent) return;

    uint8_t record[200];
    memset(record, 0, sizeof(record));

    int off = 0;
    #define W32(v) do { int32_t _v = (int32_t)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    #define W64(v) do { int64_t _v = (int64_t)(v); memcpy(record + off, &_v, 8); off += 8; } while(0)
    #define WF(v) do { float _v = (float)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    #define WU32(v) do { uint32_t _v = (uint32_t)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)

    W32(3001);
    W32(0);
    WF(0); WF(0);
    WF(0); WF(0);
    W64((int64_t)mach_absolute_time());
    W64(0);
    WU32(44);
    WU32(0);
    W32(phase);
    W32(0);
    WF(x); WF(y); WF(0);
    WF(0); WF(0); WF(0);
    WU32(1);
    WU32(2);
    WU32(phase == 2 ? 0 : 1);
    WF(0);

    #undef W32
    #undef W64
    #undef WF
    #undef WU32

    void* evt = _GSCreateEvent(record);
    if (evt) {
        if (_GSSendSystemEvent) {
            _GSSendSystemEvent(evt, 0);
        } else if (_GSSendEvent) {
            _GSSendEvent(evt, 0);
        }
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
