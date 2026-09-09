// imgui_impl_ios.h
// Dear ImGui iOS platform backend
// Handles touch input translation and display metrics for ImGui on iOS.

#pragma once
#include "imgui.h"

#import <UIKit/UIKit.h>

bool    ImGui_ImplIOS_Init(UIView* view);
void    ImGui_ImplIOS_Shutdown();
void    ImGui_ImplIOS_NewFrame();
void    ImGui_ImplIOS_HandleTouchEvent(NSSet<UITouch*>* touches, UIView* view);
