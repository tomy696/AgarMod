#import "NativeMenu.h"
#import "ModAPI.h"

static const CGFloat kPanelWidth  = 320.0f;
static const CGFloat kBtnSize     = 46.0f;

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

    // Floating toggle button
    _toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _toggleBtn.frame = CGRectMake(8, 90, kBtnSize, kBtnSize);
    _toggleBtn.backgroundColor = [UIColor colorWithRed:0.40f green:0.20f blue:0.80f alpha:0.90f];
    _toggleBtn.layer.cornerRadius = kBtnSize / 2.0f;
    _toggleBtn.layer.borderWidth  = 2.0f;
    _toggleBtn.layer.borderColor  = [UIColor colorWithRed:0.60f green:0.40f blue:1.0f alpha:1.0f].CGColor;
    _toggleBtn.layer.shadowColor  = [UIColor colorWithRed:0.50f green:0.25f blue:1.0f alpha:1.0f].CGColor;
    _toggleBtn.layer.shadowOffset = CGSizeMake(0, 2);
    _toggleBtn.layer.shadowRadius = 6;
    _toggleBtn.layer.shadowOpacity = 0.6f;
    [_toggleBtn setTitle:@"XRD" forState:UIControlStateNormal];
    _toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [_toggleBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [_toggleBtn addGestureRecognizer:pan];

    [window addSubview:_toggleBtn];

    NSLog(@"[XRD] Native menu button added");
}

#pragma mark - Toggle

- (void)toggleMenu {
    if (_menuOpen) {
        [self hideMenu];
    } else {
        [self showMenu];
    }
}

- (void)showMenu {
    if (_menuOpen || !_hostWindow) return;
    _menuOpen = YES;

    CGRect screenBounds = _hostWindow.bounds;

    // Dim background
    _dimView = [[UIView alloc] initWithFrame:screenBounds];
    _dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0f];
    _dimView.alpha = 0;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideMenu)];
    [_dimView addGestureRecognizer:tap];
    [_hostWindow insertSubview:_dimView belowSubview:_toggleBtn];

    // Panel
    CGFloat panelW = MIN(kPanelWidth, screenBounds.size.width - 40);
    _panelView = [[UIView alloc] initWithFrame:CGRectMake(-panelW, 0, panelW, screenBounds.size.height)];
    _panelView.backgroundColor = [UIColor colorWithRed:0.06f green:0.04f blue:0.10f alpha:0.96f];
    _panelView.layer.shadowColor   = [UIColor blackColor].CGColor;
    _panelView.layer.shadowOffset  = CGSizeMake(4, 0);
    _panelView.layer.shadowRadius  = 12;
    _panelView.layer.shadowOpacity = 0.5f;
    [_hostWindow insertSubview:_panelView belowSubview:_toggleBtn];

    // ScrollView inside panel
    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, panelW, screenBounds.size.height)];
    _scrollView.showsVerticalScrollIndicator = YES;
    _scrollView.alwaysBounceVertical = YES;
    [_panelView addSubview:_scrollView];

    [self buildMenuContent];

    // Animate in
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{
        self->_dimView.alpha = 1.0f;
        self->_dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4f];
        self->_panelView.frame = CGRectMake(0, 0, panelW, screenBounds.size.height);
    } completion:nil];
}

- (void)hideMenu {
    if (!_menuOpen) return;

    CGFloat panelW = _panelView.frame.size.width;

    [UIView animateWithDuration:0.25 animations:^{
        self->_dimView.alpha = 0;
        self->_panelView.frame = CGRectMake(-panelW, 0, panelW, self->_panelView.frame.size.height);
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
    CGFloat pad = 16;
    CGFloat rowH = 48;

    // Safe area top
    if (@available(iOS 11.0, *)) {
        y += _hostWindow.safeAreaInsets.top;
    }

    // Header
    y += 10;
    UILabel *title = [self labelAt:CGRectMake(pad, y, w - pad*2, 36) text:@"X R D" size:22 bold:YES];
    title.textColor = [UIColor colorWithRed:0.55f green:0.30f blue:1.0f alpha:1.0f];
    [_scrollView addSubview:title];

    UILabel *ver = [self labelAt:CGRectMake(pad + 80, y + 4, 60, 30) text:@"v2.0" size:13 bold:NO];
    ver.textColor = [UIColor colorWithRed:0.45f green:0.38f blue:0.58f alpha:1.0f];
    [_scrollView addSubview:ver];
    y += 40;

    // Separator
    [_scrollView addSubview:[self separatorAt:y width:w]];
    y += 12;

    // === PLAYER ===
    y = [self addSectionHeader:@"PLAYER" atY:y width:w];

    y = [self addToggle:@"Zoom Hack" atY:y width:w on:agmod_isZoomEnabled() action:^(BOOL on){ agmod_setZoomEnabled(on); }];
    y = [self addToggle:@"Auto-Respawn" atY:y width:w on:agmod_isAutoContinue() action:^(BOOL on){ agmod_setAutoContinue(on); }];
    y = [self addToggle:@"Unlock All Skins" atY:y width:w on:agmod_isUnlockAllSkins() action:^(BOOL on){ agmod_setUnlockAllSkins(on); }];
    y = [self addToggle:@"120 FPS" atY:y width:w on:agmod_isUnlockFPS() action:^(BOOL on){ agmod_setUnlockFPS(on); }];

    // Zoom intensity slider
    y += 4;
    UILabel *zoomLbl = [self labelAt:CGRectMake(pad, y, 100, 30) text:@"Zoom Level" size:13 bold:NO];
    zoomLbl.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
    [_scrollView addSubview:zoomLbl];

    UISlider *zoomSlider = [[UISlider alloc] initWithFrame:CGRectMake(pad + 105, y, w - pad*2 - 105, 30)];
    zoomSlider.minimumValue = 0.05f;
    zoomSlider.maximumValue = 1.0f;
    zoomSlider.value = agmod_getFlexZoom();
    zoomSlider.minimumTrackTintColor = [UIColor colorWithRed:0.55f green:0.30f blue:1.0f alpha:1.0f];
    zoomSlider.tag = 100;
    [zoomSlider addTarget:self action:@selector(zoomSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:zoomSlider];
    y += 40;

    // Zoom mode
    UILabel *modeLbl = [self labelAt:CGRectMake(pad, y, 100, 30) text:@"Zoom Mode" size:13 bold:NO];
    modeLbl.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
    [_scrollView addSubview:modeLbl];

    UISegmentedControl *zoomSeg = [[UISegmentedControl alloc] initWithItems:@[@"Dynamic", @"Stable", @"Speed"]];
    zoomSeg.frame = CGRectMake(pad + 105, y, w - pad*2 - 105, 30);
    zoomSeg.selectedSegmentIndex = agmod_getZoomMode();
    zoomSeg.selectedSegmentTintColor = [UIColor colorWithRed:0.55f green:0.30f blue:1.0f alpha:1.0f];
    [zoomSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateSelected];
    [zoomSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.6f alpha:1.0f]} forState:UIControlStateNormal];
    [zoomSeg addTarget:self action:@selector(zoomModeChanged:) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:zoomSeg];
    y += 44;

    [_scrollView addSubview:[self separatorAt:y width:w]];
    y += 12;

    // === VISUALS ===
    y = [self addSectionHeader:@"VISUALS" atY:y width:w];

    y = [self addToggle:@"Dark Mode" atY:y width:w on:agmod_isDarkMode() action:^(BOOL on){ agmod_setDarkMode(on); }];
    y = [self addToggle:@"Performance Mode" atY:y width:w on:agmod_isFastMode() action:^(BOOL on){ agmod_setFastMode(on); }];
    y = [self addToggle:@"Enemy Mass ESP" atY:y width:w on:agmod_isShowEnemyMass() action:^(BOOL on){ agmod_setShowEnemyMass(on); }];
    y = [self addToggle:@"Hide Grid" atY:y width:w on:agmod_isHideGrid() action:^(BOOL on){ agmod_setHideGrid(on); }];
    y = [self addToggle:@"Hide Borders" atY:y width:w on:agmod_isHideBorders() action:^(BOOL on){ agmod_setHideBorders(on); }];
    y = [self addToggle:@"Hide Friend Tracker" atY:y width:w on:agmod_isHideFriendTracker() action:^(BOOL on){ agmod_setHideFriendTracker(on); }];
    y = [self addToggle:@"Hide Token Counter" atY:y width:w on:agmod_isHideTokenCounter() action:^(BOOL on){ agmod_setHideTokenCounter(on); }];

    [_scrollView addSubview:[self separatorAt:y width:w]];
    y += 12;

    // === BOTS ===
    y = [self addSectionHeader:@"BOTS" atY:y width:w];

    y = [self addTextField:@"Server URL" atY:y width:w text:[agmod_getBotServerURL() UTF8String] ?: "" tag:200];
    y = [self addTextField:@"Secret Key" atY:y width:w text:[agmod_getBotSecretKey() UTF8String] ?: "" tag:201];
    y = [self addTextField:@"Bot Name" atY:y width:w text:[agmod_getBotName() UTF8String] ?: "" tag:202];

    // Bot mode
    UILabel *botModeLbl = [self labelAt:CGRectMake(pad, y, 100, 30) text:@"Bot Mode" size:13 bold:NO];
    botModeLbl.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
    [_scrollView addSubview:botModeLbl];

    UISegmentedControl *botSeg = [[UISegmentedControl alloc] initWithItems:@[@"Move", @"Feed", @"Farm"]];
    botSeg.frame = CGRectMake(pad + 105, y, w - pad*2 - 105, 30);
    botSeg.selectedSegmentIndex = MIN(agmod_getBotMode(), 2);
    botSeg.selectedSegmentTintColor = [UIColor colorWithRed:0.55f green:0.30f blue:1.0f alpha:1.0f];
    [botSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateSelected];
    [botSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.6f alpha:1.0f]} forState:UIControlStateNormal];
    [botSeg addTarget:self action:@selector(botModeChanged:) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:botSeg];
    y += 44;

    // Launch/Stop button
    y += 8;
    BOOL running = agmod_isBotsRunning();
    UIButton *botBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    botBtn.frame = CGRectMake(pad, y, w - pad*2, 44);
    botBtn.layer.cornerRadius = 10;
    if (running) {
        botBtn.backgroundColor = [UIColor colorWithRed:0.70f green:0.12f blue:0.12f alpha:1.0f];
        [botBtn setTitle:@"STOP BOTS" forState:UIControlStateNormal];
        [botBtn addTarget:self action:@selector(stopBotsTapped) forControlEvents:UIControlEventTouchUpInside];
    } else {
        botBtn.backgroundColor = [UIColor colorWithRed:0.55f green:0.30f blue:1.0f alpha:1.0f];
        [botBtn setTitle:@"LAUNCH BOTS" forState:UIControlStateNormal];
        [botBtn addTarget:self action:@selector(launchBotsTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    [botBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    botBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [_scrollView addSubview:botBtn];
    y += 56;

    // Status
    NSString *serverIP = agmod_getCurrentServerIP();
    if (serverIP && serverIP.length > 0) {
        UILabel *ipLbl = [self labelAt:CGRectMake(pad, y, w - pad*2, 20) text:[NSString stringWithFormat:@"Server: %@", serverIP] size:11 bold:NO];
        ipLbl.textColor = [UIColor colorWithWhite:0.5f alpha:1.0f];
        [_scrollView addSubview:ipLbl];
        y += 22;
    }

    [_scrollView addSubview:[self separatorAt:y width:w]];
    y += 12;

    // === MACROS ===
    y = [self addSectionHeader:@"MACROS" atY:y width:w];

    y = [self addToggle:@"Auto-Feed" atY:y width:w on:agmod_isFeedMacroActive() action:^(BOOL on){ agmod_setFeedMacroActive(on); }];
    y = [self addToggle:@"Auto-Split" atY:y width:w on:agmod_isSplitMacroActive() action:^(BOOL on){ agmod_setSplitMacroActive(on); }];

    [_scrollView addSubview:[self separatorAt:y width:w]];
    y += 12;

    // === CONFIG ===
    y = [self addSectionHeader:@"CONFIG" atY:y width:w];

    y = [self addToggle:@"Custom Server" atY:y width:w on:agmod_isServerLoaderEnabled() action:^(BOOL on){ agmod_setServerLoaderEnabled(on); }];
    y = [self addTextField:@"Target IP" atY:y width:w text:[agmod_getTargetServerIP() UTF8String] ?: "" tag:203];

    // Save / Reset buttons
    y += 8;
    CGFloat halfW = (w - pad*3) / 2.0f;

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(pad, y, halfW, 40);
    saveBtn.backgroundColor = [UIColor colorWithRed:0.55f green:0.30f blue:1.0f alpha:1.0f];
    saveBtn.layer.cornerRadius = 8;
    [saveBtn setTitle:@"Save" forState:UIControlStateNormal];
    [saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [saveBtn addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:saveBtn];

    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(pad*2 + halfW, y, halfW, 40);
    resetBtn.backgroundColor = [UIColor colorWithRed:0.50f green:0.12f blue:0.12f alpha:1.0f];
    resetBtn.layer.cornerRadius = 8;
    [resetBtn setTitle:@"Reset" forState:UIControlStateNormal];
    [resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [resetBtn addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:resetBtn];
    y += 52;

    // Credits
    y += 8;
    UILabel *credits = [self labelAt:CGRectMake(pad, y, w - pad*2, 20) text:@"XRD v2.0 — Native UI" size:11 bold:NO];
    credits.textColor = [UIColor colorWithWhite:0.35f alpha:1.0f];
    credits.textAlignment = NSTextAlignmentCenter;
    [_scrollView addSubview:credits];

    NSString *sid = agmod_getSessionId();
    if (sid.length > 0) {
        UILabel *sidLbl = [self labelAt:CGRectMake(pad, y + 18, w - pad*2, 16) text:[NSString stringWithFormat:@"ID: %.8s", [sid UTF8String]] size:10 bold:NO];
        sidLbl.textColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
        sidLbl.textAlignment = NSTextAlignmentCenter;
        [_scrollView addSubview:sidLbl];
    }
    y += 50;

    // Safe area bottom
    if (@available(iOS 11.0, *)) {
        y += _hostWindow.safeAreaInsets.bottom;
    }

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
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(16, y, w - 32, 1)];
    sep.backgroundColor = [UIColor colorWithRed:0.25f green:0.18f blue:0.40f alpha:0.5f];
    return sep;
}

- (CGFloat)addSectionHeader:(NSString *)text atY:(CGFloat)y width:(CGFloat)w {
    UILabel *lbl = [self labelAt:CGRectMake(16, y, w - 32, 24) text:text size:12 bold:YES];
    lbl.textColor = [UIColor colorWithRed:0.55f green:0.30f blue:1.0f alpha:1.0f];
    [_scrollView addSubview:lbl];
    return y + 28;
}

typedef void(^ToggleBlock)(BOOL on);

- (CGFloat)addToggle:(NSString *)label atY:(CGFloat)y width:(CGFloat)w on:(BOOL)isOn action:(ToggleBlock)action {
    UILabel *lbl = [self labelAt:CGRectMake(16, y + 6, w - 80, 30) text:label size:15 bold:NO];
    lbl.textColor = [UIColor colorWithWhite:0.88f alpha:1.0f];
    [_scrollView addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(w - 67, y + 6, 51, 31)];
    sw.on = isOn;
    sw.onTintColor = [UIColor colorWithRed:0.55f green:0.30f blue:1.0f alpha:1.0f];
    __weak typeof(self) weakSelf = self;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) {
        UISwitch *s = (UISwitch *)a.sender;
        if (action) action(s.isOn);
    }] forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:sw];

    return y + 44;
}

- (CGFloat)addTextField:(NSString *)label atY:(CGFloat)y width:(CGFloat)w text:(const char *)text tag:(NSInteger)tag {
    UILabel *lbl = [self labelAt:CGRectMake(16, y, w - 32, 20) text:label size:12 bold:NO];
    lbl.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
    [_scrollView addSubview:lbl];
    y += 22;

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(16, y, w - 32, 36)];
    tf.text = text ? [NSString stringWithUTF8String:text] : @"";
    tf.textColor = [UIColor whiteColor];
    tf.font = [UIFont systemFontOfSize:13];
    tf.backgroundColor = [UIColor colorWithRed:0.10f green:0.08f blue:0.18f alpha:1.0f];
    tf.layer.cornerRadius = 8;
    tf.layer.borderWidth = 1;
    tf.layer.borderColor = [UIColor colorWithRed:0.25f green:0.18f blue:0.40f alpha:0.5f].CGColor;
    tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 36)];
    tf.leftViewMode = UITextFieldViewModeAlways;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.returnKeyType = UIReturnKeyDone;
    tf.tag = tag;
    tf.delegate = (id<UITextFieldDelegate>)self;
    [_scrollView addSubview:tf];

    return y + 42;
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
}

- (void)resetTapped {
    agmod_reloadSettings();
    [self buildMenuContent];
}

- (void)applyTextFields {
    UITextField *urlField = [_scrollView viewWithTag:200];
    if ([urlField isKindOfClass:[UITextField class]] && urlField.text.length > 0) {
        agmod_setBotServerURL(urlField.text);
    }
    UITextField *keyField = [_scrollView viewWithTag:201];
    if ([keyField isKindOfClass:[UITextField class]] && keyField.text.length > 0) {
        agmod_setBotSecretKey(keyField.text);
    }
    UITextField *nameField = [_scrollView viewWithTag:202];
    if ([nameField isKindOfClass:[UITextField class]] && nameField.text.length > 0) {
        agmod_setBotName(nameField.text);
    }
    UITextField *ipField = [_scrollView viewWithTag:203];
    if ([ipField isKindOfClass:[UITextField class]] && ipField.text.length > 0) {
        agmod_setTargetServerIP(ipField.text);
    }
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
