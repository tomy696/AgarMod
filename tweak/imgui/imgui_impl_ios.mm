// imgui_impl_ios.mm
// Dear ImGui iOS platform backend
// Translates UITouch events into ImGui input and manages display metrics.

#import "imgui_impl_ios.h"
#import "imgui.h"

#import <UIKit/UIKit.h>
#import <mach/mach_time.h>

#pragma mark - Backend Data

struct ImGui_ImplIOS_Data {
    UIView*  view;
    double   lastFrameTime;
    bool     hasTouchDown;
};

static ImGui_ImplIOS_Data* ImGui_ImplIOS_GetBackendData() {
    return ImGui::GetCurrentContext()
        ? (ImGui_ImplIOS_Data*)ImGui::GetIO().BackendPlatformUserData
        : nullptr;
}

#pragma mark - Public API

bool ImGui_ImplIOS_Init(UIView* view) {
    ImGuiIO& io = ImGui::GetIO();
    IM_ASSERT(io.BackendPlatformUserData == nullptr && "Already initialized");

    ImGui_ImplIOS_Data* bd = IM_NEW(ImGui_ImplIOS_Data)();
    bd->view          = view;
    bd->lastFrameTime = CACurrentMediaTime();
    bd->hasTouchDown  = false;

    io.BackendPlatformUserData = (void*)bd;
    io.BackendPlatformName     = "imgui_impl_ios";

    // iOS does not use a hardware keyboard for this mod
    io.ConfigFlags |= ImGuiConfigFlags_IsTouchScreen;

    return true;
}

void ImGui_ImplIOS_Shutdown() {
    ImGui_ImplIOS_Data* bd = ImGui_ImplIOS_GetBackendData();
    IM_ASSERT(bd != nullptr && "iOS backend not initialized");

    ImGuiIO& io = ImGui::GetIO();
    io.BackendPlatformUserData = nullptr;
    io.BackendPlatformName     = nullptr;

    IM_DELETE(bd);
}

void ImGui_ImplIOS_NewFrame() {
    ImGui_ImplIOS_Data* bd = ImGui_ImplIOS_GetBackendData();
    IM_ASSERT(bd != nullptr && "iOS backend not initialized");

    ImGuiIO& io = ImGui::GetIO();

    // Display size and scale
    UIView*   view   = bd->view;
    CGFloat   scale  = view.contentScaleFactor;
    CGSize    size   = view.bounds.size;

    io.DisplaySize             = ImVec2((float)size.width, (float)size.height);
    io.DisplayFramebufferScale = ImVec2((float)scale, (float)scale);

    // Delta time
    double currentTime = CACurrentMediaTime();
    io.DeltaTime = (float)(currentTime - bd->lastFrameTime);
    if (io.DeltaTime <= 0.0f)
        io.DeltaTime = 1.0f / 60.0f;
    bd->lastFrameTime = currentTime;
}

void ImGui_ImplIOS_HandleTouchEvent(NSSet<UITouch*>* touches, UIView* view) {
    ImGui_ImplIOS_Data* bd = ImGui_ImplIOS_GetBackendData();
    if (!bd) return;

    ImGuiIO& io = ImGui::GetIO();

    for (UITouch* touch in touches) {
        CGPoint location = [touch locationInView:view];

        // Map touch phase to ImGui mouse state
        switch (touch.phase) {
            case UITouchPhaseBegan:
                io.AddMousePosEvent((float)location.x, (float)location.y);
                io.AddMouseButtonEvent(0, true);
                bd->hasTouchDown = true;
                break;

            case UITouchPhaseMoved:
                io.AddMousePosEvent((float)location.x, (float)location.y);
                break;

            case UITouchPhaseEnded:
            case UITouchPhaseCancelled:
                io.AddMousePosEvent((float)location.x, (float)location.y);
                io.AddMouseButtonEvent(0, false);
                bd->hasTouchDown = false;
                break;

            default:
                break;
        }

        // Only handle the first touch — ImGui uses a single cursor
        break;
    }
}
