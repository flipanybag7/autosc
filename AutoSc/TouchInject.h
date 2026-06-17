#ifndef TOUCH_INJECT_H
#define TOUCH_INJECT_H

#include <stdbool.h>
#include <stdint.h>

bool hid_init(void);
bool hid_ready(void);
void hid_touch_down(float x, float y, int32_t finger_id);
void hid_touch_move(float x, float y, int32_t finger_id);
void hid_touch_up(float x, float y, int32_t finger_id);
void hid_tap(float x, float y);
void hid_swipe(float x1, float y1, float x2, float y2, float duration);
void hid_long_press(float x, float y, float duration);

bool gs_init(void);
bool gs_ready(void);
void gs_touch_down(float x, float y);
void gs_touch_move(float x, float y);
void gs_touch_up(float x, float y);
void gs_tap(float x, float y);
void gs_swipe(float x1, float y1, float x2, float y2, float duration);

int inject_method(void);

#endif
