/* AutoScTweak - Injected into SpringBoard via Substitute/Substrate
   Listens for touch commands from the AutoSc app via CFMessagePort */

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

#pragma mark - IOKit HID functions (loaded via dlsym from SpringBoard's context)

typedef void* IOHIDSystemClientRef;
typedef void* IOHIDEventRef;

static IOHIDSystemClientRef _hid_client = NULL;

static IOHIDSystemClientRef (*_IOHIDEventSystemClientCreate)(CFAllocatorRef);
static void (*_IOHIDEventSystemClientScheduleWithRunLoop)(IOHIDSystemClientRef, CFRunLoopRef, CFStringRef);
static IOHIDEventRef (*_IOHIDEventCreate)(CFAllocatorRef, uint32_t, uint64_t, uint64_t);
static void (*_IOHIDEventSetFloatValue)(IOHIDEventRef, uint32_t, double);
static void (*_IOHIDEventSetIntegerValue)(IOHIDEventRef, uint32_t, int64_t);
static IOHIDEventRef (*_IOHIDEventCreateChild)(IOHIDEventRef, uint32_t, uint64_t, uint64_t);
static void (*_IOHIDEventAppendEvent)(IOHIDEventRef, IOHIDEventRef);
static int (*_IOHIDEventSystemClientDispatchEvent)(IOHIDSystemClientRef, IOHIDEventRef);

/* Field constants */
#define kIOHIDEventTypeDigitizer       3
#define kIOHIDEventTypeDigitizerFinger 11
#define kIOHIDEventFieldDigitizerX          0x00030003
#define kIOHIDEventFieldDigitizerY          0x00030004
#define kIOHIDEventFieldDigitizerTipPressure 0x00030002
#define kIOHIDEventFieldDigitizerRange      0x00030001
#define kIOHIDEventFieldDigitizerTouch      0x00030008
#define kIOHIDEventFieldDigitizerIdentity   0x0003000c
#define kIOHIDEventFieldDigitizerIndex      0x0003000d

static bool init_hid(void) {
    if (_hid_client) return true;

    void* handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
    if (!handle) handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) return false;

    _IOHIDEventSystemClientCreate = dlsym(handle, "IOHIDEventSystemClientCreate");
    _IOHIDEventSystemClientScheduleWithRunLoop = dlsym(handle, "IOHIDEventSystemClientScheduleWithRunLoop");
    _IOHIDEventCreate = dlsym(handle, "IOHIDEventCreate");
    _IOHIDEventSetFloatValue = dlsym(handle, "IOHIDEventSetFloatValue");
    _IOHIDEventSetIntegerValue = dlsym(handle, "IOHIDEventSetIntegerValue");
    _IOHIDEventCreateChild = dlsym(handle, "IOHIDEventCreateChild");
    _IOHIDEventAppendEvent = dlsym(handle, "IOHIDEventAppendEvent");
    _IOHIDEventSystemClientDispatchEvent = dlsym(handle, "IOHIDEventSystemClientDispatchEvent");

    if (!_IOHIDEventSystemClientCreate || !_IOHIDEventCreate || !_IOHIDEventSetFloatValue ||
        !_IOHIDEventSetIntegerValue || !_IOHIDEventAppendEvent || !_IOHIDEventSystemClientDispatchEvent)
        return false;

    _hid_client = _IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!_hid_client) return false;

    if (_IOHIDEventSystemClientScheduleWithRunLoop)
        _IOHIDEventSystemClientScheduleWithRunLoop(_hid_client, CFRunLoopGetMain(), kCFRunLoopDefaultMode);

    return true;
}

static void send_hid(float x, float y, int touch_type) {
    if (!_hid_client) return;

    uint64_t ts = mach_absolute_time();
    bool isDown = (touch_type != 2);

    IOHIDEventRef parent = _IOHIDEventCreate(kCFAllocatorDefault, kIOHIDEventTypeDigitizer, ts, 0);
    if (!parent) return;

    _IOHIDEventSetIntegerValue(parent, kIOHIDEventFieldDigitizerRange, isDown ? 1 : 0);
    _IOHIDEventSetFloatValue(parent, kIOHIDEventFieldDigitizerX, x);
    _IOHIDEventSetFloatValue(parent, kIOHIDEventFieldDigitizerY, y);

    IOHIDEventRef finger = NULL;
    if (_IOHIDEventCreateChild)
        finger = _IOHIDEventCreateChild(parent, kIOHIDEventTypeDigitizerFinger, ts, 0);
    else
        finger = _IOHIDEventCreate(kCFAllocatorDefault, kIOHIDEventTypeDigitizerFinger, ts, 0);

    if (!finger) { CFRelease(parent); return; }

    _IOHIDEventSetIntegerValue(finger, kIOHIDEventFieldDigitizerRange, isDown ? 1 : 0);
    _IOHIDEventSetIntegerValue(finger, kIOHIDEventFieldDigitizerTouch, isDown ? 1 : 0);
    _IOHIDEventSetIntegerValue(finger, kIOHIDEventFieldDigitizerIdentity, 2);
    _IOHIDEventSetIntegerValue(finger, kIOHIDEventFieldDigitizerIndex, 0);
    _IOHIDEventSetFloatValue(finger, kIOHIDEventFieldDigitizerX, x);
    _IOHIDEventSetFloatValue(finger, kIOHIDEventFieldDigitizerY, y);
    _IOHIDEventSetFloatValue(finger, kIOHIDEventFieldDigitizerTipPressure, isDown ? 1.0f : 0.0f);

    _IOHIDEventAppendEvent(parent, finger);
    _IOHIDEventSystemClientDispatchEvent(_hid_client, parent);

    CFRelease(finger);
    CFRelease(parent);
}

#pragma mark - GSEvent (alternative from SpringBoard context)

static void* _gs_handle = NULL;
static void* (*_GSCreateEvent)(const void* record);
static void (*_GSSendEvent)(void* event, int32_t port);

static bool init_gs(void) {
    if (_gs_handle) return _GSCreateEvent && _GSSendEvent;

    _gs_handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW | RTLD_LOCAL);
    if (!_gs_handle) {
        _gs_handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY | RTLD_LOCAL);
    }
    if (!_gs_handle) return false;

    /* Try multiple creation function names (iOS version dependent) */
    const char* names[] = {"GSCreateEvent","GSEventCreateWithData","GSEventCreateFromRecord","GSEventCFCreate","GSEventCreate",NULL};
    for (int i = 0; names[i]; i++) {
        _GSCreateEvent = dlsym(_gs_handle, names[i]);
        if (_GSCreateEvent) break;
    }
    _GSSendEvent = dlsym(_gs_handle, "GSSendEvent");
    if (!_GSSendEvent) {
        void* alt = dlsym(_gs_handle, "GSSendSystemEvent");
        if (alt) _GSSendEvent = alt;
    }

    return _GSCreateEvent && _GSSendEvent;
}

static void send_gs(float x, float y, int phase) {
    if (!_GSCreateEvent || !_GSSendEvent) return;

    uint8_t record[128]; memset(record, 0, sizeof(record)); int off = 0;
    #define W32(v) do { int32_t _v = (int32_t)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    #define W64(v) do { int64_t _v = (int64_t)(v); memcpy(record + off, &_v, 8); off += 8; } while(0)
    #define WF(v) do { float _v = (float)(v); memcpy(record + off, &_v, 4); off += 4; } while(0)
    W32(3001); W32(0); WF(x); WF(y); W64(mach_absolute_time());
    W32(1); W32(0); W32(phase); W32(phase == 2 ? 0 : 1); WF(x); WF(y);
    W32(0); W32(phase == 2 ? 0 : 1); W32(0); W32(0); W32(0); W32(0);
    #undef W32
    #undef W64
    #undef WF

    void* evt = _GSCreateEvent(record);
    if (evt) { _GSSendEvent(evt, 0); CFRelease(evt); }
}

#pragma mark - CFMessagePort communication

#define AUTOSC_PORT_NAME "com.autosc.tweak"

/* Message format */
typedef struct {
    uint32_t magic;    /* 0x41544F53 = "ATOS" */
    uint32_t type;     /* 0=tap, 1=fingerDown, 2=fingerMove, 3=fingerUp, 4=swipe */
    float x, y;
    float x2, y2;      /* for swipe */
    float duration;    /* for swipe */
} TouchMessage;

/* Lazy init: called on first touch command */
static bool _tweak_initialized = false;

static void ensure_init(void) {
    if (_tweak_initialized) return;
    _tweak_initialized = true;
    bool hid_ok = init_hid();
    bool gs_ok = init_gs();
    fprintf(stderr, "[AutoScTweak] Initialized. HID=%s GS=%s\n",
            hid_ok ? "OK" : "FAIL", gs_ok ? "OK" : "FAIL");
}

static CFDataRef port_callback(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void* info) {
    ensure_init();
    if (!data) return NULL;
    CFIndex len = CFDataGetLength(data);
    if (len < sizeof(TouchMessage)) return NULL;
    TouchMessage msg;
    CFDataGetBytes(data, CFRangeMake(0, sizeof(msg)), (UInt8*)&msg);
    if (msg.magic != 0x41544F53) return NULL;
    switch (msg.type) {
        case 0: send_hid(msg.x, msg.y, 0); usleep(60000); send_hid(msg.x, msg.y, 2); break;
        case 1: send_hid(msg.x, msg.y, 0); break;
        case 2: send_hid(msg.x, msg.y, 1); break;
        case 3: send_hid(msg.x, msg.y, 2);
            break;
        case 4:
        {
            int steps = (int)(msg.duration * 60);
            if (steps < 5) steps = 5;
            useconds_t delay = (useconds_t)(msg.duration / (float)steps * 1000000.0f);
            send_hid(msg.x, msg.y, 0);
            for (int i = 1; i <= steps; i++) {
                usleep(delay);
                float t = (float)i / (float)steps;
                float cx = msg.x + (msg.x2 - msg.x) * t;
                float cy = msg.y + (msg.y2 - msg.y) * t;
                send_hid(cx, cy, 1);
            }
            usleep(40000);
            send_hid(msg.x2, msg.y2, 2);
            break;
        }
    }

    return NULL;
}

static void setup_port(void* _unused) {
    CFMessagePortRef port = CFMessagePortCreateLocal(
        kCFAllocatorDefault, CFSTR(AUTOSC_PORT_NAME), port_callback, NULL, NULL);
    if (!port) { fprintf(stderr, "[AutoScTweak] Port create failed\n"); return; }
    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, port, 0);
    if (source) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        CFRelease(source);
    }
    fprintf(stderr, "[AutoScTweak] Listening on " AUTOSC_PORT_NAME "\n");
}

__attribute__((constructor))
static void tweak_init() {
    /* Defer port setup to the first run loop cycle to ensure run loop is ready */
    dispatch_async_f(dispatch_get_main_queue(), NULL, (void(*)(void*))setup_port);
}
