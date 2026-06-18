#ifndef TOUCH_INJECT_H
#define TOUCH_INJECT_H

#include <stdbool.h>
#include <stdint.h>

bool hid_init(void);
bool hid_ready(void);
const char* hid_error(void);
int hid_attempts(void);
int hid_send_failures(void);
int hid_dispatch_err(void);
void hid_touch_down(float x, float y, int32_t finger_id);
void hid_touch_move(float x, float y, int32_t finger_id);
void hid_touch_up(float x, float y, int32_t finger_id);
void hid_tap(float x, float y);
void hid_swipe(float x1, float y1, float x2, float y2, float duration);
void hid_long_press(float x, float y, float duration);

bool userdev_init(void);
bool userdev_ready(void);
const char* userdev_error(void);
void userdev_set_screen_size(float w, float h);
void userdev_touch(float x, float y, int32_t finger_id, int touch_type);
void userdev_tap(float x, float y);
void userdev_swipe(float x1, float y1, float x2, float y2, float duration);

bool gs_init(void);
bool gs_ready(void);
const char* gs_error(void);
void gs_touch_down(float x, float y);
void gs_touch_move(float x, float y);
void gs_touch_up(float x, float y);
void gs_tap(float x, float y);
void gs_swipe(float x1, float y1, float x2, float y2, float duration);

bool cgevent_init(void);
bool cgevent_ready(void);
const char* cgevent_error(void);
void cgevent_tap(float x, float y);
void cgevent_touch_down(float x, float y);
void cgevent_touch_up(float x, float y);
void cgevent_swipe(float x1, float y1, float x2, float y2, float duration);

bool kernel_init(void);
bool kernel_ready(void);
const char* kernel_error(void);
int kernel_failures(void);
void kernel_touch_down(float x, float y);
void kernel_touch_move(float x, float y);
void kernel_touch_up(float x, float y);
void kernel_tap(float x, float y);
void kernel_swipe(float x1, float y1, float x2, float y2, float duration);

int inject_method(void);
const char* inject_method_name(void);
const char* inject_error(void);

#endif
