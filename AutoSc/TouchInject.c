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

/* GSEvent record creation - try multiple API names */
static void* _gs_createFunc = NULL;
static bool _gs_createFromData = false; /* flag: create from CFData */

/* Send a GSEvent by creating a CFData wrapping the record and passing to GSSendEvent */
static bool _gs_try_create = false;

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

    /* Use GSSendSystemEvent if we have it (it sends to the system port) */
    if (_GSSendSystemEvent && !_GSSendEvent) {
        _GSSendEvent = (void*)_GSSendSystemEvent;
    }

    /* Try multiple GSEvent creation function names */
    const char* createNames[] = {
        "GSCreateEvent",
        "GSEventCreateWithData",
        "GSEventCreateFromRecord",
        "GSEventCFCreate",
        "GSEventCreate",
        NULL
    };

    for (int i = 0; createNames[i]; i++) {
        _gs_createFunc = dlsym(_gs_handle, createNames[i]);
        if (_gs_createFunc) {
            snprintf(_gs_error, sizeof(_gs_error), "found %s", createNames[i]);
            _gs_ok = true;
            return true;
        }
    }

    /* All creation functions failed - but GSSendEvent exists.
       Try sending raw CFData as GSEvent (works on some iOS versions).
       The GSEventRef is just a CFType wrapping the event buffer.
       A CFData with the correct record might be accepted. */
    snprintf(_gs_error, sizeof(_gs_error), "no create func found, will try CFData direct send");
    _gs_createFromData = true;
    _gs_ok = true;
    return true;
}

bool gs_ready(void) { return _gs_ok; }
const char* gs_error(void) { return _gs_error; }

/* GSEvent record format for iOS 14-16 (adjusted based on common reverse engineering) */
static void* _gs_make_event(float x, float y, int32_t phase) {
    uint8_t record[128];
    memset(record, 0, sizeof(record));
    int off = 0;

    #define W16(v) do { uint16_t _v = (uint16_t)(v); memcpy(record + off, &_v, 2); off += 2; } while(0)
    #define W32(v) do { int32_t _v = (int32_t)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    #define W64(v) do { int64_t _v = (int64_t)(v); memcpy(record + off, &_v, 8); off += 8; } while(0)
    #define WF(v) do { float _v = (float)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)

    uint64_t ts = mach_absolute_time();

    /* iOS 14-15 GSEventHand record structure */
    W32(3001);          /* kGSEventHand */
    W32(0);              /* flags */
    WF(x); WF(y);        /* location */
    W64(ts);             /* timestamp */
    W32(1);              /* windowIndex / contextId */
    W32(0);              /* modifierFlags */
    W32(phase);          /* phase: 0=down, 1=moved, 2=up */
    W32(0);              /* fingerCount */
    WF(x); WF(y);        /* normalizedLocation */
    W32(0);              /* pathIndex */
    W32(phase == 2 ? 0 : 1); /* pathIdentity (0=up, 1=down) */
    W32(0);              /* pathProximity */
    W32(0);              /* jitterRadius */
    W32(0);              /* angle */
    W32(0);              /* majorRadius */
    W16(0);              /* pressure */
    W16(0);              /* twist */

    #undef W16
    #undef W32
    #undef W64
    #undef WF

    if (_gs_createFunc) {
        /* Use the found creation function */
        void* (*createFn)(const void*) = (void* (*)(const void*))_gs_createFunc;
        return createFn(record);
    } else if (_gs_createFromData) {
        /* Wrap as CFData and pass directly */
        CFDataRef data = CFDataCreate(kCFAllocatorDefault, record, off);
        if (data) {
            /* GSSendEvent might accept CFData */
            return (void*)data;
        }
    }
    return NULL;
}

static void _gs_send(float x, float y, int32_t phase) {
    if (!_GSSendEvent) return;

    void* event = _gs_make_event(x, y, phase);
    if (!event) return;

    if (_gs_createFromData) {
        /* Send CFData directly */
        _GSSendEvent(event, 0);
        CFRelease((CFTypeRef)event);
    } else if (_gs_createFunc) {
        /* Send event created by the create function */
        _GSSendEvent(event, 0);
        CFRelease((CFTypeRef)event);
    }
}

void gs_touch_down(float x, float y) { _gs_send(x, y, 0); }
void gs_touch_move(float x, float y) { _gs_send(x, y, 1); }
void gs_touch_up(float x, float y)   { _gs_send(x, y, 2); }

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
        float cx = x1 + (x2 - x1) * t;
        float cy = y1 + (y2 - y1) * t;
        gs_touch_move(cx, cy);
    }
    usleep(40000);
    gs_touch_up(x2, y2);
}

#pragma mark - CGEvent (CoreGraphics mouse events → touch on iOS)

typedef struct CGEvent* CGEventRef;
typedef struct CGEventSource* CGEventSourceRef;
typedef double CGEventTimestamp;

static bool _cgevent_ok = false;
static char _cgevent_error[512] = "";

static CGEventRef (*_CGEventCreateMouseEvent)(CGEventSourceRef, int32_t, CGPoint, int32_t);
static void (*_CGEventPost)(int32_t, CGEventRef);
static void (*_CGEventSetIntegerValueField)(CGEventRef, int32_t, int64_t);

bool cgevent_init(void) {
    if (_cgevent_ok) return true;

    void* handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY | RTLD_LOCAL);
    }
    if (!handle) {
        snprintf(_cgevent_error, sizeof(_cgevent_error), "dlopen CoreGraphics failed");
        return false;
    }

    _CGEventCreateMouseEvent = dlsym(handle, "CGEventCreateMouseEvent");
    _CGEventPost = dlsym(handle, "CGEventPost");

    if (!_CGEventCreateMouseEvent || !_CGEventPost) {
        snprintf(_cgevent_error, sizeof(_cgevent_error), "dlsym CGEventCreateMouseEvent/Post failed");
        return false;
    }

    _cgevent_ok = true;
    return true;
}

bool cgevent_ready(void) { return _cgevent_ok; }
const char* cgevent_error(void) { return _cgevent_error; }

void cgevent_tap(float x, float y) {
    if (!_CGEventCreateMouseEvent || !_CGEventPost) return;
    CGPoint pt = { (CGFloat)x, (CGFloat)y };
    CGEventRef down = _CGEventCreateMouseEvent(NULL, 1, pt, 0);  /* kCGEventLeftMouseDown */
    CGEventRef up = _CGEventCreateMouseEvent(NULL, 2, pt, 0);    /* kCGEventLeftMouseUp */
    if (down) { _CGEventPost(0, down); CFRelease(down); }
    usleep(60000);
    if (up) { _CGEventPost(0, up); CFRelease(up); }
}

void cgevent_touch_down(float x, float y) {
    if (!_CGEventCreateMouseEvent || !_CGEventPost) return;
    CGPoint pt = { (CGFloat)x, (CGFloat)y };
    CGEventRef ev = _CGEventCreateMouseEvent(NULL, 1, pt, 0);
    if (ev) { _CGEventPost(0, ev); CFRelease(ev); }
}

void cgevent_touch_up(float x, float y) {
    if (!_CGEventCreateMouseEvent || !_CGEventPost) return;
    CGPoint pt = { (CGFloat)x, (CGFloat)y };
    CGEventRef ev = _CGEventCreateMouseEvent(NULL, 2, pt, 0);
    if (ev) { _CGEventPost(0, ev); CFRelease(ev); }
}

void cgevent_swipe(float x1, float y1, float x2, float y2, float duration) {
    int steps = (int)(duration * 60);
    if (steps < 10) steps = 10;
    useconds_t delay = (useconds_t)(duration / (float)steps * 1000000.0f);

    cgevent_touch_down(x1, y1);
    for (int i = 1; i <= steps; i++) {
        usleep(delay);
        float t = (float)i / (float)steps;
        float cx = x1 + (x2 - x1) * t;
        float cy = y1 + (y2 - y1) * t;
        CGPoint pt = { (CGFloat)cx, (CGFloat)cy };
        CGEventRef ev = _CGEventCreateMouseEvent(NULL, 3, pt, 0);  /* kCGEventLeftMouseDragged */
        if (ev) { _CGEventPost(0, ev); CFRelease(ev); }
    }
    usleep(40000);
    cgevent_touch_up(x2, y2);
}

#pragma mark - Method selection

int inject_method(void) {
    /* GS first - HID dispatch silently fails on iOS 15 */
    if (_gs_ok) return 1;
    if (_hid_ok) return 0;
    if (_userdev_ok) return 2;
    if (_cgevent_ok) return 3;
    return -1;
}

const char* inject_method_name(void) {
    if (_gs_ok) return "GraphicsServices";
    if (_hid_ok) return "IOKit HID";
    if (_userdev_ok) return "IOKit UserDevice";
    if (_cgevent_ok) return "CGEvent";
    return "none";
}

const char* inject_error(void) {
    if (!_gs_ok && _gs_error[0]) return _gs_error;
    if (!_hid_ok && _hid_error[0]) return _hid_error;
    if (!_userdev_ok && _userdev_error[0]) return _userdev_error;
    if (!_cgevent_ok && _cgevent_error[0]) return _cgevent_error;
    return "";
}
