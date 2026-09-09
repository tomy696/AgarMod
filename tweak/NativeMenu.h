#pragma once
#import <UIKit/UIKit.h>

@interface XRDMenuController : NSObject <UITextFieldDelegate>

+ (instancetype)shared;
- (void)setupWithWindow:(UIWindow *)window;
- (void)toggleMenu;

@end
