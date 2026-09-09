// ModMenuRenderer.h
// Main overlay renderer — creates a transparent MTKView on top of the game
// and drives the ImGui frame loop with Metal rendering.

#pragma once

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@interface ModMenuRenderer : NSObject <MTKViewDelegate>

@property (nonatomic, strong) MTKView *overlayView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, assign) BOOL menuVisible;

+ (instancetype)shared;
- (void)setupWithWindow:(UIWindow *)window;
- (void)teardown;
- (void)toggleMenu;
- (void)renderModMenu;

@end
