#ifndef TOUCH_INJECT_H
#define TOUCH_INJECT_H

#include <stdbool.h>
#include <stdint.h>

bool helper_init(const char *path);
bool helper_ready(void);
bool helper_is_root(void);
void helper_touch_down(float x, float y, int32_t finger_id);
void helper_touch_move(float x, float y, int32_t finger_id);
void helper_touch_up(float x, float y, int32_t finger_id);

bool hid_init(void);
bool hid_ready(void);
void hid_touch_down(float x, float y, int32_t finger_id);
void hid_touch_move(float x, float y, int32_t finger_id);
void hid_touch_up(float x, float y, int32_t finger_id);

bool gs_init(void);
bool gs_ready(void);
void gs_touch_down(float x, float y);
void gs_touch_move(float x, float y);
void gs_touch_up(float x, float y);

int inject_method(void);

#endif
