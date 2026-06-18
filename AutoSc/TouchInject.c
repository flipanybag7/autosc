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
static int _hid_send_failures = 0;
static int _hid_dispatch_err = 0;

static IOHIDSystemClientRef (*_IOHIDEventSystemClientCreate)(CFAllocatorRef);
static void (*_IOHIDEventSystemClientScheduleWithRunLoop)(IOHIDSystemClientRef, CFRunLoopRef, CFStringRef);
static IOHIDEventRef (*_IOHIDEventCreate)(CFAllocatorRef, uint32_t, uint64_t, uint64_t);
static void (*_IOHIDEventSetFloatValue)(IOHIDEventRef, uint32_t, double);
static void (*_IOHIDEventSetIntegerValue)(IOHIDEventRef, uint32_t, int64_t);
static IOHIDEventRef (*_IOHIDEventCreateChild)(IOHIDEventRef, uint32_t, uint64_t, uint64_t);
static void (*_IOHIDEventAppendEvent)(IOHIDEventRef, IOHIDEventRef);
static int (*_IOHIDEventSystemClientDispatchEvent)(IOHIDSystemClientRef, IOHIDEventRef);
static void (*_IOHIDEventSystemClientUnscheduleFromRunLoop)(IOHIDSystemClientRef, CFRunLoopRef, CFStringRef);

#define FIX(p) ((int32_t)((p) * 65536.0f))

bool hid_init(void) {
    if (_hid_client) return _hid_ok;

    void* handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    }
    if (!handle) {
        snprintf(_hid_error, sizeof(_hid_error), "dlopen failed: %s", dlerror());
        return false;
    }

    _IOHIDEventSystemClientCreate = dlsym(handle, "IOHIDEventSystemClientCreate");
    _IOHIDEventSystemClientScheduleWithRunLoop = dlsym(handle, "IOHIDEventSystemClientScheduleWithRunLoop");
    _IOHIDEventSystemClientUnscheduleFromRunLoop = dlsym(handle, "IOHIDEventSystemClientUnscheduleFromRunLoop");
    _IOHIDEventCreate = dlsym(handle, "IOHIDEventCreate");
    _IOHIDEventSetFloatValue = dlsym(handle, "IOHIDEventSetFloatValue");
    _IOHIDEventSetIntegerValue = dlsym(handle, "IOHIDEventSetIntegerValue");
    _IOHIDEventCreateChild = dlsym(handle, "IOHIDEventCreateChild");
    _IOHIDEventAppendEvent = dlsym(handle, "IOHIDEventAppendEvent");
    _IOHIDEventSystemClientDispatchEvent = dlsym(handle, "IOHIDEventSystemClientDispatchEvent");

    if (!_IOHIDEventSystemClientCreate)     { snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventSystemClientCreate = NULL"); return false; }
    if (!_IOHIDEventSystemClientScheduleWithRunLoop) { snprintf(_hid_error, sizeof(_hid_error), "ScheduleWithRunLoop = NULL"); return false; }
    if (!_IOHIDEventCreate)                { snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventCreate = NULL"); return false; }
    if (!_IOHIDEventSetFloatValue)         { snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventSetFloatValue = NULL"); return false; }
    if (!_IOHIDEventSetIntegerValue)       { snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventSetIntegerValue = NULL"); return false; }
    if (!_IOHIDEventAppendEvent)           { snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventAppendEvent = NULL"); return false; }
    if (!_IOHIDEventSystemClientDispatchEvent) { snprintf(_hid_error, sizeof(_hid_error), "IOHIDEventSystemClientDispatchEvent = NULL"); return false; }

    _hid_client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!_hid_client) {
        snprintf(_hid_error, sizeof(_hid_error), "ClientCreate returned NULL");
        return false;
    }

    /* Schedule client on main run loop — required for dispatch to work */
    _IOHIDEventSystemClientScheduleWithRunLoop(_hid_client, CFRunLoopGetMain(), kCFRunLoopDefaultMode);

    _hid_ok = true;
    _hid_send_failures = 0;
    _hid_dispatch_err = 0;
    return true;
}

bool hid_ready(void) { return _hid_ok; }
const char* hid_error(void) { return _hid_error; }
int hid_send_failures(void) { return _hid_send_failures; }
int hid_dispatch_err(void) { return _hid_dispatch_err; }

/* IOHIDEventField constants for digitizer events */
#define kIOHIDEventTypeDigitizer      3
#define kIOHIDEventTypeDigitizerFinger 11

#define kIOHIDEventFieldDigitizerX          0x00030003
#define kIOHIDEventFieldDigitizerY          0x00030004
#define kIOHIDEventFieldDigitizerZ          0x00030005
#define kIOHIDEventFieldDigitizerTipPressure 0x00030002
#define kIOHIDEventFieldDigitizerAuxPressure 0x00030006
#define kIOHIDEventFieldDigitizerRange      0x00030001
#define kIOHIDEventFieldDigitizerTouch      0x00030008
#define kIOHIDEventFieldDigitizerIdentity   0x0003000c
#define kIOHIDEventFieldDigitizerIndex      0x0003000d
#define kIOHIDEventFieldDigitizerTwist      0x0003000e
#define kIOHIDEventFieldDigitizerQuality    0x0003000f
#define kIOHIDEventFieldDigitizerDensity    0x00030010
#define kIOHIDEventFieldDigitizerIrregularity 0x00030011
#define kIOHIDEventFieldDigitizerMajorRadius 0x00030012
#define kIOHIDEventFieldDigitizerMinorRadius 0x00030013

static void _hid_send(float x, float y, int32_t finger_id, int touch_type) {
    if (!_hid_client) { _hid_send_failures++; return; }

    uint64_t ts = mach_absolute_time();
    bool isDown = (touch_type != 2);

    /* Create parent digitizer event */
    IOHIDEventRef parent = _IOHIDEventCreate(kCFAllocatorDefault, kIOHIDEventTypeDigitizer, ts, 0);
    if (!parent) { _hid_send_failures++; return; }

    /* Set digitizer-level fields */
    _IOHIDEventSetIntegerValue(parent, kIOHIDEventFieldDigitizerRange, isDown ? 1 : 0);
    _IOHIDEventSetFloatValue(parent, kIOHIDEventFieldDigitizerX, x);
    _IOHIDEventSetFloatValue(parent, kIOHIDEventFieldDigitizerY, y);

    /* Create finger child event */
    IOHIDEventRef finger = NULL;
    if (_IOHIDEventCreateChild) {
        finger = _IOHIDEventCreateChild(parent, kIOHIDEventTypeDigitizerFinger, ts, 0);
    } else {
        /* Manually create child */
        finger = _IOHIDEventCreate(kCFAllocatorDefault, kIOHIDEventTypeDigitizerFinger, ts, 0);
    }
    if (!finger) { _hid_send_failures++; CFRelease(parent); return; }

    /* Set finger-level fields */
    _IOHIDEventSetIntegerValue(finger, kIOHIDEventFieldDigitizerRange, isDown ? 1 : 0);
    _IOHIDEventSetIntegerValue(finger, kIOHIDEventFieldDigitizerTouch, isDown ? 1 : 0);
    _IOHIDEventSetIntegerValue(finger, kIOHIDEventFieldDigitizerIdentity, finger_id + 2);
    _IOHIDEventSetIntegerValue(finger, kIOHIDEventFieldDigitizerIndex, (uint32_t)finger_id);
    _IOHIDEventSetFloatValue(finger, kIOHIDEventFieldDigitizerX, x);
    _IOHIDEventSetFloatValue(finger, kIOHIDEventFieldDigitizerY, y);
    _IOHIDEventSetFloatValue(finger, kIOHIDEventFieldDigitizerTipPressure, isDown ? 1.0f : 0.0f);

    /* Append finger to parent and dispatch */
    _IOHIDEventAppendEvent(parent, finger);
    int dispatch_ret = _IOHIDEventSystemClientDispatchEvent(_hid_client, parent);
    if (dispatch_ret != 0) {
        _hid_dispatch_err = dispatch_ret;
        _hid_send_failures++;
    }

    CFRelease(finger);
    CFRelease(parent);
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

#pragma mark - GraphicsServices GSEvent (try multiple create APIs)

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

    _GSSendEvent = dlsym(_gs_handle, "GSSendEvent");
    _GSSendSystemEvent = dlsym(_gs_handle, "GSSendSystemEvent");

    if (!_GSSendEvent && !_GSSendSystemEvent) {
        snprintf(_gs_error, sizeof(_gs_error), "GSSendEvent and GSSendSystemEvent both NULL");
        dlclose(_gs_handle); _gs_handle = NULL;
        return false;
    }

    if (_GSSendSystemEvent && !_GSSendEvent) _GSSendEvent = (void*)_GSSendSystemEvent;

    /* Try multiple GSEvent creation function names */
    const char* names[] = {"GSCreateEvent","GSEventCreateWithData","GSEventCreateFromRecord","GSEventCFCreate","GSEventCreate",NULL};
    for (int i = 0; names[i]; i++) {
        _GSCreateEvent = dlsym(_gs_handle, names[i]);
        if (_GSCreateEvent) {
            snprintf(_gs_error, sizeof(_gs_error), "using %s", names[i]);
            _gs_ok = true;
            return true;
        }
    }

    snprintf(_gs_error, sizeof(_gs_error), "no create function found (GSSendEvent exists but no GSCreateEvent/alternatives)");
    return false;
}

bool gs_ready(void) { return _gs_ok; }
const char* gs_error(void) { return _gs_error; }

void gs_touch_down(float x, float y) {
    if (!_GSCreateEvent || !_GSSendEvent) return;
    uint8_t record[128]; memset(record, 0, sizeof(record)); int off = 0;
    #define W32(v) do { int32_t _v = (int32_t)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    #define W64(v) do { int64_t _v = (int64_t)(v); memcpy(record + off, &_v, 8); off += 8; } while(0)
    #define WF(v) do { float _v = (float)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    W32(3001); W32(0); WF(x); WF(y); W64(mach_absolute_time());
    W32(1); W32(0); W32(0); W32(1); WF(x); WF(y); W32(0); W32(1); W32(0); W32(0); W32(0); W32(0);
    #undef W32 #undef W64 #undef WF
    void* evt = _GSCreateEvent(record);
    if (evt) { _GSSendEvent(evt, 0); CFRelease(evt); }
}
void gs_touch_move(float x, float y) { gs_touch_down(x, y); }
void gs_touch_up(float x, float y) {
    if (!_GSCreateEvent || !_GSSendEvent) return;
    uint8_t record[128]; memset(record, 0, sizeof(record)); int off = 0;
    #define W32(v) do { int32_t _v = (int32_t)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    #define W64(v) do { int64_t _v = (int64_t)(v); memcpy(record + off, &_v, 8); off += 8; } while(0)
    #define WF(v) do { float _v = (float)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    W32(3001); W32(0); WF(x); WF(y); W64(mach_absolute_time());
    W32(1); W32(0); W32(2); W32(0); WF(x); WF(y); W32(0); W32(0); W32(0); W32(0); W32(0); W32(0);
    #undef W32 #undef W64 #undef WF
    void* evt = _GSCreateEvent(record);
    if (evt) { _GSSendEvent(evt, 0); CFRelease(evt); }
}
void gs_tap(float x, float y) { gs_touch_down(x, y); usleep(60000); gs_touch_up(x, y); }
void gs_swipe(float x1, float y1, float x2, float y2, float duration) {
    int steps = (int)(duration * 60); if (steps < 10) steps = 10;
    useconds_t delay = (useconds_t)(duration / (float)steps * 1000000.0f);
    gs_touch_down(x1, y1);
    for (int i = 1; i <= steps; i++) {
        usleep(delay); float t = (float)i / (float)steps;
        gs_touch_move(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
    }
    usleep(40000); gs_touch_up(x2, y2);
}

#pragma mark - IOHIDUserDevice (virtual HID device, iOS 12+)

typedef void* IOHIDUserDeviceRef;

static IOHIDUserDeviceRef _user_device = NULL;
static bool _userdev_ok = false;
static char _userdev_error[512] = "";

static IOHIDUserDeviceRef (*_IOHIDUserDeviceCreate)(CFAllocatorRef, CFDictionaryRef);
static int (*_IOHIDUserDeviceHandleReport)(IOHIDUserDeviceRef, uint8_t*, CFIndex);
static void (*_IOHIDUserDeviceScheduleWithRunLoop)(IOHIDUserDeviceRef, CFRunLoopRef, CFStringRef);

static float _userdev_screen_w = 393.0f;
static float _userdev_screen_h = 852.0f;

void userdev_set_screen_size(float w, float h) { _userdev_screen_w = w; _userdev_screen_h = h; }

bool userdev_init(void) {
    if (_user_device) return _userdev_ok;

    void* handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    }
    if (!handle) { snprintf(_userdev_error, sizeof(_userdev_error), "dlopen failed"); return false; }

    _IOHIDUserDeviceCreate = dlsym(handle, "IOHIDUserDeviceCreate");
    _IOHIDUserDeviceHandleReport = dlsym(handle, "IOHIDUserDeviceHandleReport");
    _IOHIDUserDeviceScheduleWithRunLoop = dlsym(handle, "IOHIDUserDeviceScheduleWithRunLoop");

    if (!_IOHIDUserDeviceCreate) { snprintf(_userdev_error, sizeof(_userdev_error), "IOHIDUserDeviceCreate not found"); return false; }
    if (!_IOHIDUserDeviceHandleReport) { snprintf(_userdev_error, sizeof(_userdev_error), "IOHIDUserDeviceHandleReport not found"); return false; }

    CFMutableDictionaryRef props = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    uint32_t up = 0x0D, u = 0x04;
    CFNumberRef pn = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &up);
    CFNumberRef un = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &u);
    static const uint8_t desc[] = {
        0x05,0x0D,0x09,0x04,0xA1,0x01,0x09,0x22,0xA1,0x02,0x09,0x42,0x15,0x00,0x25,0x01,
        0x75,0x01,0x95,0x01,0x81,0x02,0x09,0x32,0x81,0x02,0x09,0x30,0x09,0x31,0x15,0x00,
        0x26,0xFF,0x7F,0x75,0x10,0x95,0x02,0x81,0x02,0x09,0x51,0x75,0x10,0x95,0x01,0x81,0x02,0xC0,0xC0
    };
    CFDataRef dd = CFDataCreate(kCFAllocatorDefault, desc, sizeof(desc));
    if (props && pn && un && dd) {
        CFDictionarySetValue(props, CFSTR("PrimaryUsagePage"), pn);
        CFDictionarySetValue(props, CFSTR("PrimaryUsage"), un);
        CFDictionarySetValue(props, CFSTR("ReportDescriptor"), dd);
        _user_device = _IOHIDUserDeviceCreate(kCFAllocatorDefault, props);
    }
    if (props) CFRelease(props); if (pn) CFRelease(pn); if (un) CFRelease(un); if (dd) CFRelease(dd);

    if (!_user_device) { snprintf(_userdev_error, sizeof(_userdev_error), "IOHIDUserDeviceCreate failed"); return false; }
    if (_IOHIDUserDeviceScheduleWithRunLoop)
        _IOHIDUserDeviceScheduleWithRunLoop(_user_device, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    _userdev_ok = true;
    return true;
}

bool userdev_ready(void) { return _userdev_ok; }
const char* userdev_error(void) { return _userdev_error; }

void userdev_touch(float x, float y, int32_t finger_id, int touch_type) {
    if (!_user_device || !_IOHIDUserDeviceHandleReport) return;
    int32_t ix = (int32_t)(x / _userdev_screen_w * 32767.0f);
    int32_t iy = (int32_t)(y / _userdev_screen_h * 32767.0f);
    uint8_t report[8]; memset(report, 0, 8);
    report[0] = (touch_type == 2) ? 0 : 3;
    report[2] = ix & 0xFF; report[3] = (ix >> 8) & 0xFF;
    report[4] = iy & 0xFF; report[5] = (iy >> 8) & 0xFF;
    report[6] = finger_id & 0xFF; report[7] = (finger_id >> 8) & 0xFF;
    _IOHIDUserDeviceHandleReport(_user_device, report, 8);
}

void userdev_tap(float x, float y) { userdev_touch(x, y, 0, 0); usleep(60000); userdev_touch(x, y, 0, 2); }

void userdev_swipe(float x1, float y1, float x2, float y2, float duration) {
    int steps = (int)(duration * 120); if (steps < 10) steps = 10;
    useconds_t delay = (useconds_t)(duration / (float)steps * 1000000.0f);
    userdev_touch(x1, y1, 0, 0);
    for (int i = 1; i <= steps; i++) {
        usleep(delay); float t = (float)i / (float)steps;
        userdev_touch(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, 0, 1);
    }
    usleep(40000); userdev_touch(x2, y2, 0, 2);
}

#pragma mark - CGEvent (CoreGraphics mouse events, fallback)

static bool _cgevent_ok = false;
static char _cgevent_error[512] = "";

static void* (*_CGEventCreate)(CFAllocatorRef);
static void (*_CGEventSetType)(void*, uint32_t);
static void (*_CGEventSetLocation)(void*, double, double);
static void (*_CGEventPost)(int32_t, void*);

bool cgevent_init(void) {
    if (_cgevent_ok) return true;
    void* handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW | RTLD_LOCAL);
    if (!handle) { handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY | RTLD_LOCAL); }
    if (!handle) { snprintf(_cgevent_error, sizeof(_cgevent_error), "dlopen CoreGraphics failed"); return false; }

    _CGEventCreate = dlsym(handle, "CGEventCreate");
    _CGEventSetType = dlsym(handle, "CGEventSetType");
    _CGEventSetLocation = dlsym(handle, "CGEventSetLocation");
    _CGEventPost = dlsym(handle, "CGEventPost");

    if (!_CGEventCreate) { snprintf(_cgevent_error, sizeof(_cgevent_error), "CGEventCreate = NULL"); return false; }
    if (!_CGEventPost)   { snprintf(_cgevent_error, sizeof(_cgevent_error), "CGEventPost = NULL"); return false; }

    _cgevent_ok = true;
    return true;
}

bool cgevent_ready(void) { return _cgevent_ok; }
const char* cgevent_error(void) { return _cgevent_error; }

static void _cgevent_send(int32_t type, float x, float y) {
    if (!_CGEventCreate || !_CGEventPost) return;
    void* evt = _CGEventCreate(kCFAllocatorDefault);
    if (!evt) return;
    if (_CGEventSetType) _CGEventSetType(evt, type);
    if (_CGEventSetLocation) _CGEventSetLocation(evt, (double)x, (double)y);
    _CGEventPost(0, evt);
    CFRelease(evt);
}

void cgevent_tap(float x, float y) {
    _cgevent_send(1, x, y);  /* kCGEventLeftMouseDown */
    usleep(60000);
    _cgevent_send(2, x, y);  /* kCGEventLeftMouseUp */
}

void cgevent_touch_down(float x, float y) { _cgevent_send(1, x, y); }
void cgevent_touch_up(float x, float y)   { _cgevent_send(2, x, y); }

void cgevent_swipe(float x1, float y1, float x2, float y2, float duration) {
    int steps = (int)(duration * 60); if (steps < 10) steps = 10;
    useconds_t delay = (useconds_t)(duration / (float)steps * 1000000.0f);
    cgevent_touch_down(x1, y1);
    for (int i = 1; i <= steps; i++) {
        usleep(delay); float t = (float)i / (float)steps;
        float cx = x1 + (x2 - x1) * t, cy = y1 + (y2 - y1) * t;
        _cgevent_send(3, cx, cy);  /* kCGEventLeftMouseDragged */
    }
    usleep(40000); cgevent_touch_up(x2, y2);
}

#pragma mark - Direct IOKit user client (kernal-level HID events)

typedef mach_port_t io_object_t;
typedef io_object_t io_service_t;
typedef io_object_t io_connect_t;

static io_connect_t _kernel_connect = 0;
static bool _kernel_ok = false;
static char _kernel_error[512] = "";

static io_service_t (*_IOServiceGetMatchingService)(mach_port_t, CFDictionaryRef);
static CFDictionaryRef (*_IOServiceMatching)(const char*);
static kern_return_t (*_IOServiceOpen)(io_service_t, task_port_t, uint32_t, io_connect_t*);
static kern_return_t (*_IOObjectRelease)(io_object_t);
static kern_return_t (*_IOConnectCallStructMethod)(io_connect_t, uint32_t, const void*, size_t, void*, size_t*);

/* HID event structure for IOHIDSystem user client */
typedef struct {
    uint64_t _pad1[2];
    uint32_t type;       /* 1 = touch, 2 = pointer */
    uint32_t _pad2;
    uint64_t timestamp;
    float x, y;
    uint32_t finger;
    uint32_t phase;      /* 0 = down, 1 = move, 2 = up */
    uint32_t _pad3[4];
} __attribute__((packed)) KernelTouchEvent;

bool kernel_init(void) {
    if (_kernel_connect) return _kernel_ok;

    void* handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
    if (!handle) handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) { snprintf(_kernel_error, sizeof(_kernel_error), "dlopen IOKit failed"); return false; }

    _IOServiceGetMatchingService = dlsym(handle, "IOServiceGetMatchingService");
    _IOServiceMatching = dlsym(handle, "IOServiceMatching");
    _IOServiceOpen = dlsym(handle, "IOServiceOpen");
    _IOObjectRelease = dlsym(handle, "IOObjectRelease");
    _IOConnectCallStructMethod = dlsym(handle, "IOConnectCallStructMethod");

    if (!_IOServiceGetMatchingService || !_IOServiceMatching || !_IOServiceOpen || !_IOConnectCallStructMethod) {
        snprintf(_kernel_error, sizeof(_kernel_error), "dlsym one or more IOKit functions failed");
        return false;
    }

    io_service_t service = _IOServiceGetMatchingService(kIOMasterPortDefault, _IOServiceMatching("IOHIDSystem"));
    if (!service) { snprintf(_kernel_error, sizeof(_kernel_error), "IOHIDSystem service not found"); return false; }

    kern_return_t kr = _IOServiceOpen(service, mach_task_self(), 1, &_kernel_connect);
    _IOObjectRelease(service);

    if (kr != KERN_SUCCESS) {
        snprintf(_kernel_error, sizeof(_kernel_error), "IOServiceOpen returned 0x%x", kr);
        return false;
    }

    _kernel_ok = true;
    return true;
}

bool kernel_ready(void) { return _kernel_ok; }
const char* kernel_error(void) { return _kernel_error; }

static int _kernel_failures = 0;
int kernel_failures(void) { return _kernel_failures; }

static void kernel_send_touch(float x, float y, int phase) {
    if (!_kernel_connect) { _kernel_failures++; return; }

    KernelTouchEvent evt;
    memset(&evt, 0, sizeof(evt));
    evt.type = 1;
    evt.timestamp = mach_absolute_time();
    evt.x = x;
    evt.y = y;
    evt.finger = 0;
    evt.phase = phase;

    size_t outSz = 0;
    kern_return_t kr = _IOConnectCallStructMethod(_kernel_connect, 1, &evt, sizeof(evt), NULL, &outSz);
    if (kr != KERN_SUCCESS) _kernel_failures++;
}

void kernel_touch_down(float x, float y) { kernel_send_touch(x, y, 0); }
void kernel_touch_move(float x, float y) { kernel_send_touch(x, y, 1); }
void kernel_touch_up(float x, float y)   { kernel_send_touch(x, y, 2); }

void kernel_tap(float x, float y) {
    kernel_touch_down(x, y);
    usleep(60000);
    kernel_touch_up(x, y);
}

void kernel_swipe(float x1, float y1, float x2, float y2, float duration) {
    int steps = (int)(duration * 60);
    if (steps < 10) steps = 10;
    useconds_t delay = (useconds_t)(duration / (float)steps * 1000000.0f);
    kernel_touch_down(x1, y1);
    for (int i = 1; i <= steps; i++) {
        usleep(delay);
        float t = (float)i / (float)steps;
        kernel_touch_move(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
    }
    usleep(40000);
    kernel_touch_up(x2, y2);
}

#pragma mark - Method selection

int inject_method(void) {
    if (_kernel_ok) return 4;
    if (_hid_ok) return 0;
    if (_gs_ok) return 1;
    if (_userdev_ok) return 2;
    if (_cgevent_ok) return 3;
    return -1;
}

const char* inject_method_name(void) {
    if (_kernel_ok) return "IOKit Kernel Direct";
    if (_hid_ok) return "IOKit HID";
    if (_gs_ok) return "GraphicsServices";
    if (_userdev_ok) return "IOKit UserDevice";
    if (_cgevent_ok) return "CGEvent";
    return "none";
}

const char* inject_error(void) {
    if (!_kernel_ok && _kernel_error[0]) return _kernel_error;
    if (!_hid_ok && _hid_error[0]) return _hid_error;
    if (!_gs_ok && _gs_error[0]) return _gs_error;
    if (!_userdev_ok && _userdev_error[0]) return _userdev_error;
    if (!_cgevent_ok && _cgevent_error[0]) return _cgevent_error;
    return "";
}
