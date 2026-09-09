// ModMenuRenderer.mm
// Creates a transparent MTKView overlay, sets up Metal + ImGui,
// and drives the per-frame render loop.

#import "ModMenuRenderer.h"
#import "ModMenu.h"
#import "imgui.h"
#import "imgui_impl_metal.h"
#import "imgui_impl_ios.h"

// ============================================================================
// PassthroughView — a UIView that forwards non-ImGui touches to the game
// ============================================================================

@interface PassthroughView : MTKView
@end

@implementation PassthroughView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // If ImGui wants to capture the mouse, consume the touch
    if (ImGui::GetCurrentContext()) {
        ImGuiIO& io = ImGui::GetIO();
        if (io.WantCaptureMouse) {
            return YES;
        }
    }
    // Otherwise let the touch fall through to the game
    return NO;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    ImGui_ImplIOS_HandleTouchEvent(touches, self);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    ImGui_ImplIOS_HandleTouchEvent(touches, self);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    ImGui_ImplIOS_HandleTouchEvent(touches, self);
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    ImGui_ImplIOS_HandleTouchEvent(touches, self);
}

@end

// ============================================================================
// ModMenuRenderer
// ============================================================================

@implementation ModMenuRenderer {
    BOOL _imguiInitialized;
}

#pragma mark - Singleton

+ (instancetype)shared {
    static ModMenuRenderer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ModMenuRenderer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _menuVisible       = YES;
        _imguiInitialized  = NO;
    }
    return self;
}

#pragma mark - Setup

- (void)setupWithWindow:(UIWindow *)window {
    if (_imguiInitialized)
        return;

    // Create Metal device
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) {
        NSLog(@"[ModMenu] Metal not available on this device");
        return;
    }
    _commandQueue = [_device newCommandQueue];

    // Create the transparent MTKView overlay
    CGRect frame = window.bounds;
    _overlayView = [[PassthroughView alloc] initWithFrame:frame device:_device];
    _overlayView.delegate             = self;
    _overlayView.autoresizingMask     = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _overlayView.backgroundColor      = [UIColor clearColor];
    _overlayView.opaque               = NO;
    _overlayView.layer.opaque         = NO;
    _overlayView.multipleTouchEnabled = YES;
    _overlayView.preferredFramesPerSecond = 60;
    _overlayView.colorPixelFormat     = MTLPixelFormatBGRA8Unorm;
    _overlayView.clearColor           = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _overlayView.framebufferOnly      = NO;
    _overlayView.userInteractionEnabled = YES;

    // Add on top of everything
    [window addSubview:_overlayView];
    [window bringSubviewToFront:_overlayView];

    // Initialize Dear ImGui
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();

    ImGuiIO& io = ImGui::GetIO();
    io.IniFilename = nullptr;  // No .ini persistence on iOS

    // Initialize backends
    ImGui_ImplMetal_Init(_device);
    ImGui_ImplIOS_Init(_overlayView);

    // Build fonts
    [self setupFonts];

    // Create Metal font texture
    ImGui_ImplMetal_CreateFontsTexture(_device);

    // Apply custom dark style
    ModMenu::ApplyCustomStyle();

    // Load saved settings
    agmod_reloadSettings();

    _imguiInitialized = YES;

    // Add a floating toggle button so the user can show/hide the menu
    UIButton *toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    toggleBtn.frame = CGRectMake(10, 80, 44, 44);
    toggleBtn.backgroundColor = [UIColor colorWithRed:0.4f green:0.2f blue:0.8f alpha:0.85f];
    toggleBtn.layer.cornerRadius = 22;
    toggleBtn.layer.borderWidth = 2;
    toggleBtn.layer.borderColor = [UIColor colorWithRed:0.6f green:0.4f blue:1.0f alpha:1.0f].CGColor;
    [toggleBtn setTitle:@"XRD" forState:UIControlStateNormal];
    toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    toggleBtn.tag = 8880099;
    [toggleBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];

    // Make it draggable
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleToggleDrag:)];
    [toggleBtn addGestureRecognizer:pan];

    [window addSubview:toggleBtn];
    [window bringSubviewToFront:toggleBtn];

    NSLog(@"[ModMenu] ImGui overlay initialized successfully");
}

#pragma mark - Fonts

- (void)setupFonts {
    ImGuiIO& io = ImGui::GetIO();
    CGFloat scale = [UIScreen mainScreen].scale;

    // Add default font (ProggyClean is built into Dear ImGui)
    ImFontConfig fontConfig;
    fontConfig.SizePixels  = 14.0f * scale;
    fontConfig.OversampleH = 2;
    fontConfig.OversampleV = 1;
    fontConfig.PixelSnapH  = true;
    io.Fonts->AddFontDefault(&fontConfig);

    // Merge Font Awesome 5 icons if the .ttf is bundled
    NSString *faPath = [[NSBundle mainBundle] pathForResource:@"fa-solid-900" ofType:@"ttf"];
    if (faPath) {
        static const ImWchar iconRanges[] = { 0xF000, 0xF8FF, 0 };
        ImFontConfig iconConfig;
        iconConfig.MergeMode        = true;
        iconConfig.PixelSnapH       = true;
        iconConfig.SizePixels       = 14.0f * scale;
        iconConfig.GlyphMinAdvanceX = 14.0f * scale;
        io.Fonts->AddFontFromFileTTF([faPath UTF8String], 14.0f * scale, &iconConfig, iconRanges);
    } else {
        NSLog(@"[ModMenu] Font Awesome not found in bundle, icons will display as ??");
    }

    io.Fonts->Build();
    io.FontGlobalScale = 1.0f / scale;
}

#pragma mark - Teardown

- (void)teardown {
    if (!_imguiInitialized)
        return;

    agmod_saveAllSettings();

    ImGui_ImplMetal_Shutdown();
    ImGui_ImplIOS_Shutdown();
    ImGui::DestroyContext();

    [_overlayView removeFromSuperview];
    _overlayView  = nil;
    _commandQueue = nil;
    _device       = nil;

    _imguiInitialized = NO;
    NSLog(@"[ModMenu] ImGui overlay torn down");
}

#pragma mark - Toggle

- (void)toggleMenu {
    _menuVisible = !_menuVisible;
    _overlayView.userInteractionEnabled = _menuVisible;
}

- (void)handleToggleDrag:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    UIView *superview = btn.superview;
    if (!btn || !superview) return;

    CGPoint translation = [pan translationInView:superview];
    btn.center = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:superview];

    // Keep button on screen
    if (pan.state == UIGestureRecognizerStateEnded) {
        CGRect bounds = superview.bounds;
        CGFloat x = btn.center.x;
        CGFloat y = btn.center.y;
        x = MAX(btn.frame.size.width/2, MIN(x, bounds.size.width - btn.frame.size.width/2));
        y = MAX(btn.frame.size.height/2, MIN(y, bounds.size.height - btn.frame.size.height/2));
        [UIView animateWithDuration:0.2 animations:^{ btn.center = CGPointMake(x, y); }];
    }
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // Display size is updated in ImGui_ImplIOS_NewFrame
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_imguiInitialized)
        return;

    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    if (!renderPassDescriptor)
        return;

    // Make sure the clear color is fully transparent
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    // Begin ImGui frame
    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
    ImGui_ImplIOS_NewFrame();
    ImGui::NewFrame();

    // Draw mod menu content
    [self renderModMenu];

    // Finalize ImGui frame
    ImGui::Render();

    // Encode Metal commands
    id<MTLRenderCommandEncoder> commandEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, commandEncoder);

    [commandEncoder endEncoding];

    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (drawable) {
        [commandBuffer presentDrawable:drawable];
    }
    [commandBuffer commit];
}

#pragma mark - Mod Menu Rendering

- (void)renderModMenu {
    if (_menuVisible) {
        ModMenu::Draw();
    }
}

@end
