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
static int _hid_dispatch_err = 0;

static IOHIDSystemClientRef (*_IOHIDEventSystemClientCreate)(CFAllocatorRef);
static IOHIDEventRef (*_IOHIDEventCreateDigitizerEvent)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t,
    int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, uint32_t);
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
    _hid_dispatch_err = 0;
    return true;
}

bool hid_ready(void) { return _hid_ok; }
const char* hid_error(void) { return _hid_error; }
int hid_attempts(void) { return _hid_attempt_count; }
int hid_send_failures(void) { return _hid_send_failures; }
int hid_dispatch_err(void) { return _hid_dispatch_err; }

static void _hid_send(float x, float y, int32_t finger_id, int touch_type) {
    if (!_hid_client) { _hid_send_failures++; return; }

    uint64_t ts = mach_absolute_time();
    int32_t fx = FIX(x);
    int32_t fy = FIX(y);

    uint32_t finger_mask;
    int32_t tip, range;
    if (touch_type == 2) {
        finger_mask = 1;   /* range only */
        tip = 0;
        range = 0;
    } else {
        finger_mask = 7;   /* range | touch | position */
        tip = FIX(1);
        range = 1;
    }

    IOHIDEventRef parent = _IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, ts,
        3,                     /* kIOHIDDigitizerTransducerTypeFinger */
        0,                     /* index */
        (uint32_t)finger_id + 2, /* identity */
        touch_type == 2 ? 0 : 3, /* eventMask */
        0,                     /* buttonMask */
        fx, fy, 0,
        tip, 0,
        0,                     /* twist */
        0,                     /* tangentialPressure */
        range,
        0);

    IOHIDEventRef finger = _IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, ts,
        (uint32_t)finger_id,
        (uint32_t)finger_id + 2,
        finger_mask,
        fx, fy, 0,
        tip, 0,
        0, range,
        0);

    if (!parent) { _hid_send_failures++; return; }
    if (!finger) { _hid_send_failures++; CFRelease(parent); return; }

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

#pragma mark - IOHIDUserDevice (virtual HID device)

typedef void* IOHIDUserDeviceRef;

static IOHIDUserDeviceRef _user_device = NULL;
static bool _userdev_ok = false;
static char _userdev_error[512] = "";

static IOHIDUserDeviceRef (*_IOHIDUserDeviceCreate)(CFAllocatorRef, CFDictionaryRef);
static int (*_IOHIDUserDeviceHandleReport)(IOHIDUserDeviceRef, uint8_t*, CFIndex);
static void (*_IOHIDUserDeviceRegisterGetReportCallback)(IOHIDUserDeviceRef, void*, void*);
static void (*_IOHIDUserDeviceUnscheduleWithRunLoop)(IOHIDUserDeviceRef, CFRunLoopRef, CFStringRef);
static void (*_IOHIDUserDeviceScheduleWithRunLoop)(IOHIDUserDeviceRef, CFRunLoopRef, CFStringRef);

/* HID report descriptor for a simple touch digitizer */
static const uint8_t _touch_descriptor[] = {
    0x05, 0x0D,        /* Usage Page (Digitizers) */
    0x09, 0x04,        /* Usage (Touch Screen) */
    0xA1, 0x01,        /* Collection (Application) */
    0x09, 0x22,        /*   Usage (Finger) */
    0xA1, 0x02,        /*   Collection (Logical) */
    0x09, 0x42,        /*     Usage (Tip Switch) */
    0x15, 0x00,        /*     Logical Minimum (0) */
    0x25, 0x01,        /*     Logical Maximum (1) */
    0x75, 0x01,        /*     Report Size (1) */
    0x95, 0x01,        /*     Report Count (1) */
    0x81, 0x02,        /*     Input (Data,Var,Abs) */
    0x09, 0x32,        /*     Usage (In Range) */
    0x81, 0x02,        /*     Input (Data,Var,Abs) */
    0x09, 0x30,        /*     Usage (Tip X) */
    0x09, 0x31,        /*     Usage (Tip Y) */
    0x15, 0x00,        /*     Logical Minimum (0) */
    0x26, 0xFF, 0x7F,  /*     Logical Maximum (32767) */
    0x75, 0x10,        /*     Report Size (16) */
    0x95, 0x02,        /*     Report Count (2) */
    0x81, 0x02,        /*     Input (Data,Var,Abs) */
    0x09, 0x51,        /*     Usage (Contact Identifier) */
    0x75, 0x10,        /*     Report Size (16) */
    0x95, 0x01,        /*     Report Count (1) */
    0x81, 0x02,        /*     Input (Data,Var,Abs) */
    0xC0,              /*   End Collection */
    0xC0               /* End Collection */
};

bool userdev_init(void) {
    if (_user_device) return _userdev_ok;

    void* handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    }
    if (!handle) {
        snprintf(_userdev_error, sizeof(_userdev_error), "dlopen failed");
        return false;
    }

    _IOHIDUserDeviceCreate = dlsym(handle, "IOHIDUserDeviceCreate");
    _IOHIDUserDeviceHandleReport = dlsym(handle, "IOHIDUserDeviceHandleReport");
    _IOHIDUserDeviceRegisterGetReportCallback = dlsym(handle, "IOHIDUserDeviceRegisterGetReportCallback");
    _IOHIDUserDeviceScheduleWithRunLoop = dlsym(handle, "IOHIDUserDeviceScheduleWithRunLoop");
    _IOHIDUserDeviceUnscheduleWithRunLoop = dlsym(handle, "IOHIDUserDeviceUnscheduleWithRunLoop");

    if (!_IOHIDUserDeviceCreate) {
        snprintf(_userdev_error, sizeof(_userdev_error), "IOHIDUserDeviceCreate not found");
        return false;
    }
    if (!_IOHIDUserDeviceHandleReport) {
        snprintf(_userdev_error, sizeof(_userdev_error), "IOHIDUserDeviceHandleReport not found");
        return false;
    }

    CFMutableDictionaryRef props = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFStringRef primaryUsagePageKey = CFSTR("PrimaryUsagePage");
    CFStringRef primaryUsageKey = CFSTR("PrimaryUsage");
    CFStringRef reportDescKey = CFSTR("ReportDescriptor");

    uint32_t usagePage = 0x0D;
    uint32_t usage = 0x04;

    CFNumberRef pageNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &usagePage);
    CFNumberRef usageNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &usage);

    CFDataRef descData = CFDataCreate(kCFAllocatorDefault, _touch_descriptor, sizeof(_touch_descriptor));

    if (props && pageNum && usageNum && descData) {
        CFDictionarySetValue(props, primaryUsagePageKey, pageNum);
        CFDictionarySetValue(props, primaryUsageKey, usageNum);
        CFDictionarySetValue(props, reportDescKey, descData);

        _user_device = _IOHIDUserDeviceCreate(kCFAllocatorDefault, props);
    }

    if (props) CFRelease(props);
    if (pageNum) CFRelease(pageNum);
    if (usageNum) CFRelease(usageNum);
    if (descData) CFRelease(descData);

    if (!_user_device) {
        snprintf(_userdev_error, sizeof(_userdev_error), "IOHIDUserDeviceCreate failed");
        return false;
    }

    /* Schedule on main run loop */
    if (_IOHIDUserDeviceScheduleWithRunLoop) {
        _IOHIDUserDeviceScheduleWithRunLoop(_user_device, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    }

    _userdev_ok = true;
    return true;
}

bool userdev_ready(void) { return _userdev_ok; }
const char* userdev_error(void) { return _userdev_error; }

static float _userdev_screen_w = 393.0f;
static float _userdev_screen_h = 852.0f;

void userdev_set_screen_size(float w, float h) {
    _userdev_screen_w = w;
    _userdev_screen_h = h;
}

void userdev_touch(float x, float y, int32_t finger_id, int touch_type) {
    if (!_user_device || !_IOHIDUserDeviceHandleReport) return;

    int32_t ix = (int32_t)(x / _userdev_screen_w * 32767.0f);
    int32_t iy = (int32_t)(y / _userdev_screen_h * 32767.0f);

    uint8_t report[8];
    memset(report, 0, sizeof(report));

    /* HID report: [touch_switch:1] [in_range:1] [reserved:6] [x:16] [y:16] [contact:16] */
    if (touch_type == 2) {
        report[0] = 0;  /* tip switch = 0, in_range = 0 */
    } else {
        report[0] = 3;  /* tip switch = 1, in_range = 1 */
    }
    report[2] = (uint8_t)(ix & 0xFF);
    report[3] = (uint8_t)((ix >> 8) & 0xFF);
    report[4] = (uint8_t)(iy & 0xFF);
    report[5] = (uint8_t)((iy >> 8) & 0xFF);
    report[6] = (uint8_t)(finger_id & 0xFF);
    report[7] = (uint8_t)((finger_id >> 8) & 0xFF);

    _IOHIDUserDeviceHandleReport(_user_device, report, sizeof(report));
}

void userdev_tap(float x, float y) {
    userdev_touch(x, y, 0, 0);
    usleep(60000);
    userdev_touch(x, y, 0, 2);
}

void userdev_swipe(float x1, float y1, float x2, float y2, float duration) {
    int steps = (int)(duration * 120);
    if (steps < 10) steps = 10;
    useconds_t delay = (useconds_t)(duration / (float)steps * 1000000.0f);

    userdev_touch(x1, y1, 0, 0);
    for (int i = 1; i <= steps; i++) {
        usleep(delay);
        float t = (float)i / (float)steps;
        float cx = x1 + (x2 - x1) * t;
        float cy = y1 + (y2 - y1) * t;
        userdev_touch(cx, cy, 0, 1);
    }
    usleep(40000);
    userdev_touch(x2, y2, 0, 2);
}

#pragma mark - GraphicsServices GSEvent (for older iOS)

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
        dlclose(_gs_handle); _gs_handle = NULL;
        return false;
    }

    if (!_GSCreateEvent) {
        snprintf(_gs_error, sizeof(_gs_error), "GSCreateEvent not found (removed in later iOS)");
    }

    if (_GSCreateEvent) {
        _gs_ok = true;
        return true;
    }

    return false;
}

bool gs_ready(void) { return _gs_ok; }
const char* gs_error(void) { return _gs_error; }

void gs_touch_down(float x, float y) {}
void gs_touch_move(float x, float y) {}
void gs_touch_up(float x, float y) {}
void gs_tap(float x, float y) {}
void gs_swipe(float x1, float y1, float x2, float y2, float duration) {}

#pragma mark - Method selection

int inject_method(void) {
    if (_hid_ok) return 0;
    if (_userdev_ok) return 2;
    if (_gs_ok) return 1;
    return -1;
}

const char* inject_method_name(void) {
    if (_hid_ok) return "IOKit HID";
    if (_userdev_ok) return "IOKit UserDevice";
    if (_gs_ok) return "GraphicsServices";
    return "none";
}

const char* inject_error(void) {
    if (!_hid_ok && _hid_error[0]) return _hid_error;
    if (!_userdev_ok && _userdev_error[0]) return _userdev_error;
    if (!_gs_ok && _gs_error[0]) return _gs_error;
    return "";
}
