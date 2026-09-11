#pragma once
#import <UIKit/UIKit.h>

@interface XRDMenuController : NSObject <UITextFieldDelegate, UIGestureRecognizerDelegate>

+ (instancetype)shared;
- (void)setupWithWindow:(UIWindow *)window;
- (void)toggleMenu;
- (void)handlePinchZoom:(UIPinchGestureRecognizer *)pinch;

@end
