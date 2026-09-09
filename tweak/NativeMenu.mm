#import "NativeMenu.h"
#import "ModAPI.h"

static const CGFloat kPanelWidth  = 290.0f;
static const CGFloat kBtnSize     = 42.0f;

#pragma mark - XRDMenuController

@interface XRDMenuController ()
@property (nonatomic, strong) UIView   *panelView;
@property (nonatomic, strong) UIView   *dimView;
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, assign) BOOL menuOpen;
@property (nonatomic, weak)   UIWindow *hostWindow;
@end

@implementation XRDMenuController

+ (instancetype)shared {
    static XRDMenuController *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[XRDMenuController alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) { _menuOpen = NO; }
    return self;
}

#pragma mark - Setup

- (void)setupWithWindow:(UIWindow *)window {
    if (_toggleBtn) return;
    _hostWindow = window;

    CGFloat screenW = window.bounds.size.width;
    CGFloat safeTop = 50;
    if (@available(iOS 11.0, *)) {
        safeTop = window.safeAreaInsets.top + 8;
    }

    _toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _toggleBtn.frame = CGRectMake(screenW - kBtnSize - 12, safeTop, kBtnSize, kBtnSize);
    _toggleBtn.backgroundColor = [UIColor colorWithRed:0.40f green:0.20f blue:0.80f alpha:0.85f];
    _toggleBtn.layer.cornerRadius = kBtnSize / 2.0f;
    _toggleBtn.layer.borderWidth  = 1.5f;
    _toggleBtn.layer.borderColor  = [UIColor colorWithRed:0.60f green:0.40f blue:1.0f alpha:0.8f].CGColor;
    _toggleBtn.layer.shadowColor  = [UIColor blackColor].CGColor;
    _toggleBtn.layer.shadowOffset = CGSizeMake(0, 2);
    _toggleBtn.layer.shadowRadius = 4;
    _toggleBtn.layer.shadowOpacity = 0.5f;
    [_toggleBtn setTitle:@"X" forState:UIControlStateNormal];
    _toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [_toggleBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [_toggleBtn addGestureRecognizer:pan];

    [window addSubview:_toggleBtn];
    NSLog(@"[XRD] Native menu button added (top-right)");
}

#pragma mark - Toggle

- (void)toggleMenu {
    if (_menuOpen) [self hideMenu];
    else [self showMenu];
}

- (void)showMenu {
    if (_menuOpen || !_hostWindow) return;
    _menuOpen = YES;

    CGRect sb = _hostWindow.bounds;
    CGFloat panelW = MIN(kPanelWidth, sb.size.width - 20);

    _dimView = [[UIView alloc] initWithFrame:sb];
    _dimView.backgroundColor = [UIColor clearColor];
    _dimView.alpha = 0;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideMenu)];
    [_dimView addGestureRecognizer:tap];
    [_hostWindow insertSubview:_dimView belowSubview:_toggleBtn];

    _panelView = [[UIView alloc] initWithFrame:CGRectMake(sb.size.width, 0, panelW, sb.size.height)];
    _panelView.backgroundColor = [UIColor colorWithRed:0.08f green:0.06f blue:0.14f alpha:0.97f];
    _panelView.layer.cornerRadius = 16;
    _panelView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    _panelView.layer.shadowColor   = [UIColor blackColor].CGColor;
    _panelView.layer.shadowOffset  = CGSizeMake(-4, 0);
    _panelView.layer.shadowRadius  = 16;
    _panelView.layer.shadowOpacity = 0.6f;
    [_hostWindow insertSubview:_panelView belowSubview:_toggleBtn];

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, panelW, sb.size.height)];
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = YES;
    [_panelView addSubview:_scrollView];

    [self buildMenuContent];

    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0 options:0 animations:^{
        self->_dimView.alpha = 1.0f;
        self->_dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35f];
        self->_panelView.frame = CGRectMake(sb.size.width - panelW, 0, panelW, sb.size.height);
    } completion:nil];
}

- (void)hideMenu {
    if (!_menuOpen) return;
    CGFloat screenW = _hostWindow.bounds.size.width;
    CGFloat panelW = _panelView.frame.size.width;

    [UIView animateWithDuration:0.22 animations:^{
        self->_dimView.alpha = 0;
        self->_panelView.frame = CGRectMake(screenW, 0, panelW, self->_panelView.frame.size.height);
    } completion:^(BOOL finished) {
        [self->_dimView removeFromSuperview];
        [self->_panelView removeFromSuperview];
        self->_dimView = nil;
        self->_panelView = nil;
        self->_scrollView = nil;
        self->_menuOpen = NO;
    }];
}

#pragma mark - Build Content

- (void)buildMenuContent {
    for (UIView *v in _scrollView.subviews) [v removeFromSuperview];

    CGFloat w = _scrollView.frame.size.width;
    CGFloat y = 0;
    CGFloat pad = 14;

    if (@available(iOS 11.0, *)) {
        y += _hostWindow.safeAreaInsets.top;
    }

    // Header
    y += 8;
    UILabel *title = [self labelAt:CGRectMake(pad, y, 60, 28) text:@"XRD" size:20 bold:YES];
    title.textColor = [UIColor colorWithRed:0.55f green:0.30f blue:1.0f alpha:1.0f];
    [_scrollView addSubview:title];

    UILabel *ver = [self labelAt:CGRectMake(pad + 52, y + 5, 40, 20) text:@"v2.0" size:11 bold:NO];
    ver.textColor = [UIColor colorWithWhite:0.4f alpha:1.0f];
    [_scrollView addSubview:ver];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w - pad - 30, y, 30, 28);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.5f alpha:1.0f] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [closeBtn addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:closeBtn];
    y += 34;

    [_scrollView addSubview:[self separatorAt:y width:w]];
    y += 8;

    // === PLAYER ===
    y = [self addSectionHeader:@"PLAYER" atY:y width:w];
    y = [self addToggle:@"Zoom Hack" atY:y width:w on:agmod_isZoomEnabled() action:^(BOOL on){ agmod_setZoomEnabled(on); }];

    UISlider *zoomSlider = [[UISlider alloc] initWithFrame:CGRectMake(pad, y, w - pad*2, 28)];
    zoomSlider.minimumValue = 0.05f;
    zoomSlider.maximumValue = 1.0f;
    zoomSlider.value = agmod_getFlexZoom();
    zoomSlider.minimumTrackTintColor = [UIColor colorWithRed:0.55f green:0.30f blue:1.0f alpha:1.0f];
    zoomSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.2f alpha:1.0f];
    [zoomSlider addTarget:self action:@selector(zoomSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:zoomSlider];
    y += 32;

    UISegmentedControl *zoomSeg = [[UISegmentedControl alloc] initWithItems:@[@"Dynamic", @"Stable", @"Speed"]];
    zoomSeg.frame = CGRectMake(pad, y, w - pad*2, 28);
    zoomSeg.selectedSegmentIndex = agmod_getZoomMode();
    zoomSeg.selectedSegmentTintColor = [UIColor colorWithRed:0.45f green:0.22f blue:0.85f alpha:1.0f];
    [zoomSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateSelected];
    [zoomSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.5f alpha:1.0f], NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
    [zoomSeg addTarget:self action:@selector(zoomModeChanged:) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:zoomSeg];
    y += 36;

    y = [self addToggle:@"Auto-Respawn" atY:y width:w on:agmod_isAutoContinue() action:^(BOOL on){ agmod_setAutoContinue(on); }];
    y = [self addToggle:@"All Skins" atY:y width:w on:agmod_isUnlockAllSkins() action:^(BOOL on){ agmod_setUnlockAllSkins(on); }];
    y = [self addToggle:@"120 FPS" atY:y width:w on:agmod_isUnlockFPS() action:^(BOOL on){ agmod_setUnlockFPS(on); }];

    [_scrollView addSubview:[self separatorAt:y width:w]];
    y += 8;

    // === VISUALS ===
    y = [self addSectionHeader:@"VISUALS" atY:y width:w];
    y = [self addToggle:@"Dark Mode" atY:y width:w on:agmod_isDarkMode() action:^(BOOL on){ agmod_setDarkMode(on); }];
    y = [self addToggle:@"Perf Mode" atY:y width:w on:agmod_isFastMode() action:^(BOOL on){ agmod_setFastMode(on); }];
    y = [self addToggle:@"Enemy Mass" atY:y width:w on:agmod_isShowEnemyMass() action:^(BOOL on){ agmod_setShowEnemyMass(on); }];
    y = [self addToggle:@"Hide Grid" atY:y width:w on:agmod_isHideGrid() action:^(BOOL on){ agmod_setHideGrid(on); }];
    y = [self addToggle:@"Hide Borders" atY:y width:w on:agmod_isHideBorders() action:^(BOOL on){ agmod_setHideBorders(on); }];

    [_scrollView addSubview:[self separatorAt:y width:w]];
    y += 8;

    // === MACROS ===
    y = [self addSectionHeader:@"MACROS" atY:y width:w];
    y = [self addToggle:@"Auto-Feed" atY:y width:w on:agmod_isFeedMacroActive() action:^(BOOL on){ agmod_setFeedMacroActive(on); }];
    y = [self addToggle:@"Auto-Split" atY:y width:w on:agmod_isSplitMacroActive() action:^(BOOL on){ agmod_setSplitMacroActive(on); }];

    [_scrollView addSubview:[self separatorAt:y width:w]];
    y += 8;

    // === BOTS ===
    y = [self addSectionHeader:@"BOTS" atY:y width:w];
    y = [self addTextField:@"Server URL" atY:y width:w text:[agmod_getBotServerURL() UTF8String] ?: "" tag:200];
    y = [self addTextField:@"Key" atY:y width:w text:[agmod_getBotSecretKey() UTF8String] ?: "" tag:201];
    y = [self addTextField:@"Bot Name" atY:y width:w text:[agmod_getBotName() UTF8String] ?: "" tag:202];

    UISegmentedControl *botSeg = [[UISegmentedControl alloc] initWithItems:@[@"Move", @"Feed", @"Farm"]];
    botSeg.frame = CGRectMake(pad, y, w - pad*2, 28);
    botSeg.selectedSegmentIndex = MIN(agmod_getBotMode(), 2);
    botSeg.selectedSegmentTintColor = [UIColor colorWithRed:0.45f green:0.22f blue:0.85f alpha:1.0f];
    [botSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateSelected];
    [botSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.5f alpha:1.0f], NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
    [botSeg addTarget:self action:@selector(botModeChanged:) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:botSeg];
    y += 36;

    BOOL running = agmod_isBotsRunning();
    UIButton *botBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    botBtn.frame = CGRectMake(pad, y, w - pad*2, 40);
    botBtn.layer.cornerRadius = 10;
    if (running) {
        botBtn.backgroundColor = [UIColor colorWithRed:0.65f green:0.10f blue:0.10f alpha:1.0f];
        [botBtn setTitle:@"STOP BOTS" forState:UIControlStateNormal];
        [botBtn addTarget:self action:@selector(stopBotsTapped) forControlEvents:UIControlEventTouchUpInside];
    } else {
        botBtn.backgroundColor = [UIColor colorWithRed:0.45f green:0.22f blue:0.85f alpha:1.0f];
        [botBtn setTitle:@"LAUNCH BOTS" forState:UIControlStateNormal];
        [botBtn addTarget:self action:@selector(launchBotsTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    [botBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    botBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [_scrollView addSubview:botBtn];
    y += 48;

    NSString *serverIP = agmod_getCurrentServerIP();
    if (serverIP && serverIP.length > 0) {
        UILabel *ipLbl = [self labelAt:CGRectMake(pad, y, w - pad*2, 16) text:[NSString stringWithFormat:@"Server: %@", serverIP] size:10 bold:NO];
        ipLbl.textColor = [UIColor colorWithWhite:0.4f alpha:1.0f];
        [_scrollView addSubview:ipLbl];
        y += 18;
    }

    [_scrollView addSubview:[self separatorAt:y width:w]];
    y += 8;

    // === BOTTOM ACTIONS ===
    CGFloat thirdW = (w - pad*4) / 3.0f;

    UIButton *saveBtn = [self actionBtn:@"Save" color:[UIColor colorWithRed:0.45f green:0.22f blue:0.85f alpha:1.0f]
                                  frame:CGRectMake(pad, y, thirdW, 36) action:@selector(saveTapped)];
    [_scrollView addSubview:saveBtn];

    UIButton *resetBtn = [self actionBtn:@"Reset" color:[UIColor colorWithRed:0.55f green:0.10f blue:0.10f alpha:1.0f]
                                   frame:CGRectMake(pad*2 + thirdW, y, thirdW, 36) action:@selector(resetTapped)];
    [_scrollView addSubview:resetBtn];

    UIButton *configBtn = [self actionBtn:@"Server" color:[UIColor colorWithWhite:0.18f alpha:1.0f]
                                    frame:CGRectMake(pad*3 + thirdW*2, y, thirdW, 36) action:@selector(configTapped)];
    [_scrollView addSubview:configBtn];
    y += 44;

    if (@available(iOS 11.0, *)) {
        y += _hostWindow.safeAreaInsets.bottom;
    }
    y += 10;

    _scrollView.contentSize = CGSizeMake(w, y);
}

#pragma mark - UI Helpers

- (UILabel *)labelAt:(CGRect)frame text:(NSString *)text size:(CGFloat)size bold:(BOOL)bold {
    UILabel *lbl = [[UILabel alloc] initWithFrame:frame];
    lbl.text = text;
    lbl.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    lbl.textColor = [UIColor whiteColor];
    return lbl;
}

- (UIView *)separatorAt:(CGFloat)y width:(CGFloat)w {
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(14, y, w - 28, 0.5f)];
    sep.backgroundColor = [UIColor colorWithWhite:0.25f alpha:0.4f];
    return sep;
}

- (CGFloat)addSectionHeader:(NSString *)text atY:(CGFloat)y width:(CGFloat)w {
    UILabel *lbl = [self labelAt:CGRectMake(14, y, w - 28, 20) text:text size:10 bold:YES];
    lbl.textColor = [UIColor colorWithRed:0.50f green:0.30f blue:0.90f alpha:0.8f];
    [_scrollView addSubview:lbl];
    return y + 22;
}

- (UIButton *)actionBtn:(NSString *)title color:(UIColor *)color frame:(CGRect)frame action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 8;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

typedef void(^ToggleBlock)(BOOL on);

- (CGFloat)addToggle:(NSString *)label atY:(CGFloat)y width:(CGFloat)w on:(BOOL)isOn action:(ToggleBlock)action {
    UILabel *lbl = [self labelAt:CGRectMake(14, y + 2, w - 72, 28) text:label size:14 bold:NO];
    lbl.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
    [_scrollView addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.transform = CGAffineTransformMakeScale(0.75f, 0.75f);
    CGSize swSize = sw.frame.size;
    sw.frame = CGRectMake(w - swSize.width - 10, y + 2, swSize.width, swSize.height);
    sw.on = isOn;
    sw.onTintColor = [UIColor colorWithRed:0.50f green:0.25f blue:0.90f alpha:1.0f];
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) {
        UISwitch *s = (UISwitch *)a.sender;
        if (action) action(s.isOn);
    }] forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:sw];

    return y + 34;
}

- (CGFloat)addTextField:(NSString *)label atY:(CGFloat)y width:(CGFloat)w text:(const char *)text tag:(NSInteger)tag {
    UILabel *lbl = [self labelAt:CGRectMake(14, y, 70, 18) text:label size:10 bold:NO];
    lbl.textColor = [UIColor colorWithWhite:0.5f alpha:1.0f];
    [_scrollView addSubview:lbl];

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(14, y + 18, w - 28, 32)];
    tf.text = text ? [NSString stringWithUTF8String:text] : @"";
    tf.textColor = [UIColor whiteColor];
    tf.font = [UIFont systemFontOfSize:12];
    tf.backgroundColor = [UIColor colorWithWhite:0.12f alpha:1.0f];
    tf.layer.cornerRadius = 6;
    tf.layer.borderWidth = 0.5f;
    tf.layer.borderColor = [UIColor colorWithWhite:0.25f alpha:0.5f].CGColor;
    tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 32)];
    tf.leftViewMode = UITextFieldViewModeAlways;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.returnKeyType = UIReturnKeyDone;
    tf.tag = tag;
    tf.delegate = (id<UITextFieldDelegate>)self;
    [_scrollView addSubview:tf];

    return y + 54;
}

#pragma mark - Actions

- (void)zoomSliderChanged:(UISlider *)slider {
    agmod_setFlexZoom(slider.value);
}

- (void)zoomModeChanged:(UISegmentedControl *)seg {
    agmod_setZoomMode((int)seg.selectedSegmentIndex);
}

- (void)botModeChanged:(UISegmentedControl *)seg {
    agmod_setBotMode((int)seg.selectedSegmentIndex);
}

- (void)launchBotsTapped {
    [self applyTextFields];
    agmod_startBots();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self buildMenuContent];
    });
}

- (void)stopBotsTapped {
    agmod_stopBots();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self buildMenuContent];
    });
}

- (void)saveTapped {
    [self applyTextFields];
    agmod_saveAllSettings();
    [self flashButton:(UIButton *)[_scrollView viewWithTag:0] message:@"Saved!"];
}

- (void)resetTapped {
    agmod_reloadSettings();
    [self buildMenuContent];
}

- (void)configTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Server"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"IP address";
        tf.text = agmod_getTargetServerIP();
        tf.keyboardType = UIKeyboardTypeURL;
    }];
    UIAlertAction *toggle = [UIAlertAction actionWithTitle:
        agmod_isServerLoaderEnabled() ? @"Disable" : @"Enable"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSString *ip = alert.textFields.firstObject.text;
            if (ip.length > 0) agmod_setTargetServerIP(ip);
            agmod_setServerLoaderEnabled(!agmod_isServerLoaderEnabled());
        }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:toggle];
    [alert addAction:cancel];

    UIViewController *vc = _hostWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:alert animated:YES completion:nil];
}

- (void)flashButton:(UIButton *)btn message:(NSString *)msg {
    // brief visual feedback not critical
}

- (void)applyTextFields {
    UITextField *urlField = [_scrollView viewWithTag:200];
    if ([urlField isKindOfClass:[UITextField class]] && urlField.text.length > 0)
        agmod_setBotServerURL(urlField.text);
    UITextField *keyField = [_scrollView viewWithTag:201];
    if ([keyField isKindOfClass:[UITextField class]] && keyField.text.length > 0)
        agmod_setBotSecretKey(keyField.text);
    UITextField *nameField = [_scrollView viewWithTag:202];
    if ([nameField isKindOfClass:[UITextField class]] && nameField.text.length > 0)
        agmod_setBotName(nameField.text);
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self applyTextFields];
    return YES;
}

#pragma mark - Drag

- (void)handleDrag:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    UIView *sv  = btn.superview;
    if (!btn || !sv) return;

    CGPoint t = [pan translationInView:sv];
    btn.center = CGPointMake(btn.center.x + t.x, btn.center.y + t.y);
    [pan setTranslation:CGPointZero inView:sv];

    if (pan.state == UIGestureRecognizerStateEnded) {
        CGRect b = sv.bounds;
        CGFloat x = MAX(kBtnSize/2, MIN(btn.center.x, b.size.width - kBtnSize/2));
        CGFloat y = MAX(kBtnSize/2, MIN(btn.center.y, b.size.height - kBtnSize/2));
        [UIView animateWithDuration:0.2 animations:^{ btn.center = CGPointMake(x, y); }];
    }
}

@end
