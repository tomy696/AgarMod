// imgui_impl_metal.h
// Dear ImGui Metal backend for iOS
// Renders ImGui draw data using Apple Metal APIs.

#pragma once
#include "imgui.h"

#import <Metal/Metal.h>

// Backend API
bool    ImGui_ImplMetal_Init(id<MTLDevice> device);
void    ImGui_ImplMetal_Shutdown();
void    ImGui_ImplMetal_NewFrame(MTLRenderPassDescriptor* renderPassDescriptor);
void    ImGui_ImplMetal_RenderDrawData(ImDrawData* drawData,
                                       id<MTLCommandBuffer> commandBuffer,
                                       id<MTLRenderCommandEncoder> commandEncoder);

// Resource management
bool    ImGui_ImplMetal_CreateFontsTexture(id<MTLDevice> device);
void    ImGui_ImplMetal_DestroyFontsTexture();
bool    ImGui_ImplMetal_CreateDeviceObjects(id<MTLDevice> device);
void    ImGui_ImplMetal_DestroyDeviceObjects();
