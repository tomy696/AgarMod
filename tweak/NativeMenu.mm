#import "NativeMenu.h"
#import "ModAPI.h"

static const CGFloat kPanelWidth  = 300.0f;
static const CGFloat kBtnSize     = 44.0f;

// Colors
#define CRGBA(r,g,b,a) [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:a]
#define kAccent     CRGBA(130, 87, 255, 1.0)
#define kAccentDim  CRGBA(130, 87, 255, 0.15)
#define kGreen      CRGBA(52, 211, 153, 1.0)
#define kGreenDim   CRGBA(52, 211, 153, 0.15)
#define kRed        CRGBA(248, 113, 113, 1.0)
#define kRedDim     CRGBA(248, 113, 113, 0.15)
#define kOrange     CRGBA(251, 191, 36, 1.0)
#define kBlue       CRGBA(96, 165, 250, 1.0)
#define kBg         CRGBA(13, 13, 20, 0.98)
#define kCard       CRGBA(22, 22, 35, 1.0)
#define kCardBorder CRGBA(40, 40, 60, 0.6)
#define kTextPri    CRGBA(235, 235, 245, 1.0)
#define kTextSec    CRGBA(140, 140, 165, 1.0)
#define kTextDim    CRGBA(90, 90, 110, 1.0)

#pragma mark - XRDMenuController

@interface XRDMenuController ()
@property (nonatomic, strong) UIView   *panelView;
@property (nonatomic, strong) UIView   *dimView;
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, assign) BOOL menuOpen;
@property (nonatomic, weak)   UIWindow *hostWindow;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchGesture;
@property (nonatomic, strong) UILabel *zoomHUD;
@property (nonatomic, assign) float pinchBaseZoom;
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

    // Floating toggle button
    _toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _toggleBtn.frame = CGRectMake(screenW - kBtnSize - 12, safeTop, kBtnSize, kBtnSize);
    _toggleBtn.layer.cornerRadius = kBtnSize / 2.0f;
    _toggleBtn.clipsToBounds = NO;

    // Gradient-like button
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = _toggleBtn.bounds;
    grad.cornerRadius = kBtnSize / 2.0f;
    grad.colors = @[(id)CRGBA(130, 87, 255, 0.95).CGColor, (id)CRGBA(90, 50, 200, 0.95).CGColor];
    grad.startPoint = CGPointMake(0, 0);
    grad.endPoint = CGPointMake(1, 1);
    [_toggleBtn.layer insertSublayer:grad atIndex:0];

    _toggleBtn.layer.shadowColor = CRGBA(130, 87, 255, 1.0).CGColor;
    _toggleBtn.layer.shadowOffset = CGSizeMake(0, 2);
    _toggleBtn.layer.shadowRadius = 8;
    _toggleBtn.layer.shadowOpacity = 0.4f;

    [_toggleBtn setTitle:@"X" forState:UIControlStateNormal];
    _toggleBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBlack];
    [_toggleBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [_toggleBtn addGestureRecognizer:pan];

    [window addSubview:_toggleBtn];

    // Pinch-to-zoom gesture
    _pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchZoom:)];
    _pinchGesture.delegate = self;
    [window addGestureRecognizer:_pinchGesture];

    // Zoom HUD indicator
    _zoomHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 120, 36)];
    _zoomHUD.center = CGPointMake(screenW / 2.0f, safeTop + 30);
    _zoomHUD.textAlignment = NSTextAlignmentCenter;
    _zoomHUD.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightBold];
    _zoomHUD.textColor = [UIColor whiteColor];
    _zoomHUD.backgroundColor = CRGBA(0, 0, 0, 0.6);
    _zoomHUD.layer.cornerRadius = 10;
    _zoomHUD.clipsToBounds = YES;
    _zoomHUD.alpha = 0;
    [window addSubview:_zoomHUD];

    NSLog(@"[XRD] Menu + pinch zoom initialized");
}

#pragma mark - Pinch Zoom

- (void)handlePinchZoom:(UIPinchGestureRecognizer *)pinch {
    if (!agmod_isModEnabled() || !agmod_isZoomEnabled()) return;
    if (_menuOpen) return;

    switch (pinch.state) {
        case UIGestureRecognizerStateBegan:
            _pinchBaseZoom = agmod_getFlexZoom();
            _zoomHUD.alpha = 1.0f;
            break;

        case UIGestureRecognizerStateChanged: {
            float scale = pinch.scale;
            // Pinch out (scale > 1) = zoom out (lower flexZoom = more zoomed out)
            // Pinch in (scale < 1) = zoom in (higher flexZoom)
            float newZoom = _pinchBaseZoom / scale;
            if (newZoom < 0.05f) newZoom = 0.05f;
            if (newZoom > 1.0f) newZoom = 1.0f;
            agmod_setFlexZoom(newZoom);
            _zoomHUD.text = [NSString stringWithFormat:@"%.0f%%", (1.0f - newZoom) * 100 + 50];
            break;
        }

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            [UIView animateWithDuration:0.6 delay:0.4 options:0 animations:^{
                self->_zoomHUD.alpha = 0;
            } completion:nil];
            break;

        default:
            break;
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
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
    CGFloat panelW = MIN(kPanelWidth, sb.size.width - 16);

    _dimView = [[UIView alloc] initWithFrame:sb];
    _dimView.backgroundColor = [UIColor clearColor];
    _dimView.alpha = 0;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideMenu)];
    [_dimView addGestureRecognizer:tap];
    [_hostWindow insertSubview:_dimView belowSubview:_toggleBtn];

    _panelView = [[UIView alloc] initWithFrame:CGRectMake(sb.size.width, 0, panelW, sb.size.height)];
    _panelView.backgroundColor = kBg;
    _panelView.layer.cornerRadius = 20;
    _panelView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    _panelView.layer.shadowColor = [UIColor blackColor].CGColor;
    _panelView.layer.shadowOffset = CGSizeMake(-6, 0);
    _panelView.layer.shadowRadius = 24;
    _panelView.layer.shadowOpacity = 0.7f;
    [_hostWindow insertSubview:_panelView belowSubview:_toggleBtn];

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, panelW, sb.size.height)];
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = YES;
    [_panelView addSubview:_scrollView];

    [self buildMenuContent];

    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{
        self->_dimView.alpha = 1.0f;
        self->_dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4f];
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
    CGFloat pad = 16;
    CGFloat cardPad = 12;

    if (@available(iOS 11.0, *)) {
        y += _hostWindow.safeAreaInsets.top;
    }

    // ── Header ──
    y += 12;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, 80, 30)];
    title.text = @"XRD";
    title.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBlack];
    title.textColor = kAccent;
    [_scrollView addSubview:title];

    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(pad + 55, y + 8, 50, 18)];
    ver.text = @"v2.0";
    ver.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    ver.textColor = kTextDim;
    [_scrollView addSubview:ver];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w - pad - 32, y, 32, 30);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:kTextSec forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightLight];
    [closeBtn addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:closeBtn];
    y += 38;

    // Status bar
    NSString *consoleId = agmod_getConsoleId();
    NSString *serverIP = agmod_getCurrentServerIP();
    if (consoleId.length > 0 || serverIP.length > 0) {
        UIView *statusCard = [self cardAt:y width:w pad:pad height:44];
        statusCard.backgroundColor = CRGBA(18, 18, 28, 1.0);

        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(cardPad, 18, 8, 8)];
        dot.backgroundColor = serverIP.length > 0 ? kGreen : kOrange;
        dot.layer.cornerRadius = 4;
        [statusCard addSubview:dot];

        NSString *statusText = serverIP.length > 0
            ? [NSString stringWithFormat:@"Connected — %@", [serverIP componentsSeparatedByString:@"/"].lastObject]
            : @"Waiting for game...";
        UILabel *statusLbl = [[UILabel alloc] initWithFrame:CGRectMake(cardPad + 14, 10, statusCard.frame.size.width - cardPad*2 - 14, 24)];
        statusLbl.text = statusText;
        statusLbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        statusLbl.textColor = kTextSec;
        [statusCard addSubview:statusLbl];

        [_scrollView addSubview:statusCard];
        y += 52;
    }

    // ── ZOOM ──
    y = [self addSection:@"ZOOM" icon:@"\U0001F50D" atY:y width:w pad:pad];

    UIView *zoomCard = [self cardAt:y width:w pad:pad height:0];
    CGFloat zy = cardPad;

    zy = [self addToggleInCard:zoomCard atY:zy label:@"Zoom Hack" on:agmod_isZoomEnabled()
        action:^(BOOL on){ agmod_setZoomEnabled(on); }];

    // Zoom mode segmented control
    UISegmentedControl *zoomSeg = [[UISegmentedControl alloc] initWithItems:@[@"Dynamic", @"Stable", @"Speed"]];
    zoomSeg.frame = CGRectMake(cardPad, zy, zoomCard.frame.size.width - cardPad*2, 30);
    zoomSeg.selectedSegmentIndex = agmod_getZoomMode();
    zoomSeg.selectedSegmentTintColor = kAccent;
    [zoomSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]} forState:UIControlStateSelected];
    [zoomSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: kTextSec, NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
    [zoomSeg addTarget:self action:@selector(zoomModeChanged:) forControlEvents:UIControlEventValueChanged];
    [zoomCard addSubview:zoomSeg];
    zy += 38;

    // Zoom level slider
    UILabel *zoomLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, zy, 100, 16)];
    zoomLabel.text = @"Zoom Level";
    zoomLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    zoomLabel.textColor = kTextSec;
    [zoomCard addSubview:zoomLabel];

    UILabel *zoomVal = [[UILabel alloc] initWithFrame:CGRectMake(zoomCard.frame.size.width - cardPad - 50, zy, 50, 16)];
    zoomVal.text = [NSString stringWithFormat:@"%.0f%%", agmod_getFlexZoom() * 100];
    zoomVal.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightBold];
    zoomVal.textColor = kAccent;
    zoomVal.textAlignment = NSTextAlignmentRight;
    zoomVal.tag = 500;
    [zoomCard addSubview:zoomVal];
    zy += 20;

    UISlider *zoomSlider = [[UISlider alloc] initWithFrame:CGRectMake(cardPad, zy, zoomCard.frame.size.width - cardPad*2, 24)];
    zoomSlider.minimumValue = 0.05f;
    zoomSlider.maximumValue = 1.0f;
    zoomSlider.value = agmod_getFlexZoom();
    zoomSlider.minimumTrackTintColor = kAccent;
    zoomSlider.maximumTrackTintColor = CRGBA(40, 40, 55, 1.0);
    [zoomSlider addTarget:self action:@selector(zoomSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [zoomCard addSubview:zoomSlider];
    zy += 30;

    UILabel *pinchHint = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, zy, zoomCard.frame.size.width - cardPad*2, 14)];
    pinchHint.text = @"Pinch with two fingers to zoom in-game";
    pinchHint.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    pinchHint.textColor = kTextDim;
    [zoomCard addSubview:pinchHint];
    zy += 20;

    [self resizeCard:zoomCard toHeight:zy + 4];
    [_scrollView addSubview:zoomCard];
    y += zoomCard.frame.size.height + 10;

    // ── GAMEPLAY ──
    y = [self addSection:@"GAMEPLAY" icon:@"⚔️" atY:y width:w pad:pad];

    UIView *gameCard = [self cardAt:y width:w pad:pad height:0];
    CGFloat gy = cardPad;
    gy = [self addToggleInCard:gameCard atY:gy label:@"Auto-Respawn" on:agmod_isAutoContinue()
        action:^(BOOL on){ agmod_setAutoContinue(on); }];
    gy = [self addToggleInCard:gameCard atY:gy label:@"Unlock All Skins" on:agmod_isUnlockAllSkins()
        action:^(BOOL on){ agmod_setUnlockAllSkins(on); }];
    gy = [self addToggleInCard:gameCard atY:gy label:@"120 FPS" on:agmod_isUnlockFPS()
        action:^(BOOL on){ agmod_setUnlockFPS(on); }];
    gy = [self addToggleInCard:gameCard atY:gy label:@"Enemy Mass" on:agmod_isShowEnemyMass()
        action:^(BOOL on){ agmod_setShowEnemyMass(on); }];

    [self resizeCard:gameCard toHeight:gy + 4];
    [_scrollView addSubview:gameCard];
    y += gameCard.frame.size.height + 10;

    // ── VISUALS ──
    y = [self addSection:@"VISUALS" icon:@"\U0001F3A8" atY:y width:w pad:pad];

    UIView *visCard = [self cardAt:y width:w pad:pad height:0];
    CGFloat vy = cardPad;
    vy = [self addToggleInCard:visCard atY:vy label:@"Dark Mode" on:agmod_isDarkMode()
        action:^(BOOL on){ agmod_setDarkMode(on); }];
    vy = [self addToggleInCard:visCard atY:vy label:@"Performance Mode" on:agmod_isFastMode()
        action:^(BOOL on){ agmod_setFastMode(on); }];
    vy = [self addToggleInCard:visCard atY:vy label:@"Hide Grid" on:agmod_isHideGrid()
        action:^(BOOL on){ agmod_setHideGrid(on); }];
    vy = [self addToggleInCard:visCard atY:vy label:@"Hide Borders" on:agmod_isHideBorders()
        action:^(BOOL on){ agmod_setHideBorders(on); }];

    [self resizeCard:visCard toHeight:vy + 4];
    [_scrollView addSubview:visCard];
    y += visCard.frame.size.height + 10;

    // ── MACROS ──
    y = [self addSection:@"MACROS" icon:@"⚡" atY:y width:w pad:pad];

    UIView *macroCard = [self cardAt:y width:w pad:pad height:0];
    CGFloat my = cardPad;

    my = [self addToggleInCard:macroCard atY:my label:@"Auto-Feed" on:agmod_isFeedMacroActive()
        action:^(BOOL on){ agmod_setFeedMacroActive(on); }];

    // Feed speed slider
    UILabel *feedLbl = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, my, 80, 14)];
    feedLbl.text = @"Feed Speed";
    feedLbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    feedLbl.textColor = kTextDim;
    [macroCard addSubview:feedLbl];

    UILabel *feedVal = [[UILabel alloc] initWithFrame:CGRectMake(macroCard.frame.size.width - cardPad - 50, my, 50, 14)];
    feedVal.text = [NSString stringWithFormat:@"%.0fms", agmod_getFeedMacroRate()];
    feedVal.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightBold];
    feedVal.textColor = kOrange;
    feedVal.textAlignment = NSTextAlignmentRight;
    feedVal.tag = 501;
    [macroCard addSubview:feedVal];
    my += 16;

    UISlider *feedSlider = [[UISlider alloc] initWithFrame:CGRectMake(cardPad, my, macroCard.frame.size.width - cardPad*2, 22)];
    feedSlider.minimumValue = 10.0f;
    feedSlider.maximumValue = 200.0f;
    feedSlider.value = agmod_getFeedMacroRate();
    feedSlider.minimumTrackTintColor = kOrange;
    feedSlider.maximumTrackTintColor = CRGBA(40, 40, 55, 1.0);
    feedSlider.tag = 601;
    [feedSlider addTarget:self action:@selector(feedSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [macroCard addSubview:feedSlider];
    my += 28;

    my = [self addToggleInCard:macroCard atY:my label:@"Auto-Split" on:agmod_isSplitMacroActive()
        action:^(BOOL on){ agmod_setSplitMacroActive(on); }];

    // Split speed slider
    UILabel *splitLbl = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, my, 80, 14)];
    splitLbl.text = @"Split Speed";
    splitLbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    splitLbl.textColor = kTextDim;
    [macroCard addSubview:splitLbl];

    UILabel *splitVal = [[UILabel alloc] initWithFrame:CGRectMake(macroCard.frame.size.width - cardPad - 50, my, 50, 14)];
    splitVal.text = [NSString stringWithFormat:@"%.0fms", agmod_getSplitMacroRate()];
    splitVal.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightBold];
    splitVal.textColor = kOrange;
    splitVal.textAlignment = NSTextAlignmentRight;
    splitVal.tag = 502;
    [macroCard addSubview:splitVal];
    my += 16;

    UISlider *splitSlider = [[UISlider alloc] initWithFrame:CGRectMake(cardPad, my, macroCard.frame.size.width - cardPad*2, 22)];
    splitSlider.minimumValue = 30.0f;
    splitSlider.maximumValue = 300.0f;
    splitSlider.value = agmod_getSplitMacroRate();
    splitSlider.minimumTrackTintColor = kOrange;
    splitSlider.maximumTrackTintColor = CRGBA(40, 40, 55, 1.0);
    splitSlider.tag = 602;
    [splitSlider addTarget:self action:@selector(splitSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [macroCard addSubview:splitSlider];
    my += 30;

    [self resizeCard:macroCard toHeight:my + 4];
    [_scrollView addSubview:macroCard];
    y += macroCard.frame.size.height + 10;

    // ── BOTS ──
    y = [self addSection:@"BOTS" icon:@"\U0001F916" atY:y width:w pad:pad];

    UIView *botCard = [self cardAt:y width:w pad:pad height:0];
    CGFloat by = cardPad;

    by = [self addTextFieldInCard:botCard atY:by label:@"Server URL" text:agmod_getBotServerURL() tag:200];
    by = [self addTextFieldInCard:botCard atY:by label:@"Secret Key" text:agmod_getBotSecretKey() tag:201];
    by = [self addTextFieldInCard:botCard atY:by label:@"Bot Name" text:agmod_getBotName() tag:202];

    // Bot mode
    UISegmentedControl *botSeg = [[UISegmentedControl alloc] initWithItems:@[@"Follow", @"Feed", @"Farm"]];
    botSeg.frame = CGRectMake(cardPad, by, botCard.frame.size.width - cardPad*2, 30);
    botSeg.selectedSegmentIndex = MIN(agmod_getBotMode(), 2);
    botSeg.selectedSegmentTintColor = kAccent;
    [botSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]} forState:UIControlStateSelected];
    [botSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: kTextSec, NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
    [botSeg addTarget:self action:@selector(botModeChanged:) forControlEvents:UIControlEventValueChanged];
    [botCard addSubview:botSeg];
    by += 38;

    // Launch/Stop button
    BOOL running = agmod_isBotsRunning();
    UIButton *botBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    botBtn.frame = CGRectMake(cardPad, by, botCard.frame.size.width - cardPad*2, 42);
    botBtn.layer.cornerRadius = 12;
    if (running) {
        botBtn.backgroundColor = kRedDim;
        botBtn.layer.borderWidth = 1;
        botBtn.layer.borderColor = kRed.CGColor;
        [botBtn setTitle:@"STOP BOTS" forState:UIControlStateNormal];
        [botBtn setTitleColor:kRed forState:UIControlStateNormal];
        [botBtn addTarget:self action:@selector(stopBotsTapped) forControlEvents:UIControlEventTouchUpInside];
    } else {
        botBtn.backgroundColor = kAccent;
        [botBtn setTitle:@"LAUNCH BOTS" forState:UIControlStateNormal];
        [botBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [botBtn addTarget:self action:@selector(launchBotsTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    botBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [botCard addSubview:botBtn];
    by += 50;

    // Console ID
    NSString *cid = agmod_getConsoleId();
    if (cid.length > 0) {
        UILabel *cidLbl = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, by, botCard.frame.size.width - cardPad*2, 14)];
        cidLbl.text = [NSString stringWithFormat:@"Console ID: %@", cid];
        cidLbl.font = [UIFont monospacedDigitSystemFontOfSize:9 weight:UIFontWeightMedium];
        cidLbl.textColor = kAccent;
        cidLbl.adjustsFontSizeToFitWidth = YES;
        cidLbl.minimumScaleFactor = 0.5f;
        [botCard addSubview:cidLbl];
        by += 18;
    }

    // Copy Console ID button
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(cardPad, by, botCard.frame.size.width - cardPad*2, 36);
    copyBtn.layer.cornerRadius = 10;
    copyBtn.backgroundColor = kGreenDim;
    copyBtn.layer.borderWidth = 1;
    copyBtn.layer.borderColor = kGreen.CGColor;
    [copyBtn setTitle:@"COPY CONSOLE ID" forState:UIControlStateNormal];
    [copyBtn setTitleColor:kGreen forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [copyBtn addTarget:self action:@selector(copyServerURLTapped) forControlEvents:UIControlEventTouchUpInside];
    [botCard addSubview:copyBtn];
    by += 44;

    [self resizeCard:botCard toHeight:by + 4];
    [_scrollView addSubview:botCard];
    y += botCard.frame.size.height + 10;

    // ── Bottom actions ──
    y += 4;
    CGFloat btnW = (w - pad*2 - 16) / 3.0f;

    UIButton *saveBtn = [self pillBtn:@"Save" color:kAccent frame:CGRectMake(pad, y, btnW, 38) action:@selector(saveTapped)];
    [_scrollView addSubview:saveBtn];

    UIButton *resetBtn = [self pillBtn:@"Reset" color:kRed frame:CGRectMake(pad + btnW + 8, y, btnW, 38) action:@selector(resetTapped)];
    [_scrollView addSubview:resetBtn];

    UIButton *cfgBtn = [self pillBtn:@"Server" color:kBlue frame:CGRectMake(pad + (btnW + 8)*2, y, btnW, 38) action:@selector(configTapped)];
    [_scrollView addSubview:cfgBtn];
    y += 48;

    if (@available(iOS 11.0, *)) {
        y += _hostWindow.safeAreaInsets.bottom;
    }
    y += 16;

    _scrollView.contentSize = CGSizeMake(w, y);
}

#pragma mark - UI Builders

- (UIView *)cardAt:(CGFloat)y width:(CGFloat)w pad:(CGFloat)pad height:(CGFloat)h {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w - pad*2, h > 0 ? h : 400)];
    card.backgroundColor = kCard;
    card.layer.cornerRadius = 14;
    card.layer.borderWidth = 0.5f;
    card.layer.borderColor = kCardBorder.CGColor;
    return card;
}

- (void)resizeCard:(UIView *)card toHeight:(CGFloat)h {
    CGRect f = card.frame;
    f.size.height = h;
    card.frame = f;
}

- (CGFloat)addSection:(NSString *)title icon:(NSString *)icon atY:(CGFloat)y width:(CGFloat)w pad:(CGFloat)pad {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(pad + 2, y, w - pad*2, 18)];
    lbl.text = [NSString stringWithFormat:@"%@ %@", icon, title];
    lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    lbl.textColor = kTextDim;
    [_scrollView addSubview:lbl];
    return y + 22;
}

typedef void(^ToggleBlock)(BOOL on);

- (CGFloat)addToggleInCard:(UIView *)card atY:(CGFloat)y label:(NSString *)label on:(BOOL)isOn action:(ToggleBlock)action {
    CGFloat cw = card.frame.size.width;
    CGFloat cardPad = 12;

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, y + 4, cw - 70, 24)];
    lbl.text = label;
    lbl.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    lbl.textColor = kTextPri;
    [card addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.transform = CGAffineTransformMakeScale(0.7f, 0.7f);
    CGSize swSize = sw.frame.size;
    sw.frame = CGRectMake(cw - swSize.width - 6, y + 2, swSize.width, swSize.height);
    sw.on = isOn;
    sw.onTintColor = kAccent;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) {
        UISwitch *s = (UISwitch *)a.sender;
        if (action) action(s.isOn);
    }] forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];

    return y + 34;
}

- (CGFloat)addTextFieldInCard:(UIView *)card atY:(CGFloat)y label:(NSString *)label text:(NSString *)text tag:(NSInteger)tag {
    CGFloat cw = card.frame.size.width;
    CGFloat cardPad = 12;

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, y, 80, 14)];
    lbl.text = label;
    lbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    lbl.textColor = kTextDim;
    [card addSubview:lbl];

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(cardPad, y + 14, cw - cardPad*2, 32)];
    tf.text = text ?: @"";
    tf.textColor = kTextPri;
    tf.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    tf.backgroundColor = CRGBA(15, 15, 25, 1.0);
    tf.layer.cornerRadius = 8;
    tf.layer.borderWidth = 0.5f;
    tf.layer.borderColor = CRGBA(50, 50, 70, 0.5).CGColor;
    tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 32)];
    tf.leftViewMode = UITextFieldViewModeAlways;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.returnKeyType = UIReturnKeyDone;
    tf.tag = tag;
    tf.delegate = (id<UITextFieldDelegate>)self;
    [card addSubview:tf];

    return y + 52;
}

- (UIButton *)pillBtn:(NSString *)title color:(UIColor *)color frame:(CGRect)frame action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    btn.backgroundColor = [color colorWithAlphaComponent:0.15f];
    btn.layer.cornerRadius = 10;
    btn.layer.borderWidth = 1;
    btn.layer.borderColor = [color colorWithAlphaComponent:0.4f].CGColor;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:color forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

#pragma mark - Actions

- (void)zoomSliderChanged:(UISlider *)slider {
    agmod_setFlexZoom(slider.value);
    UILabel *val = [slider.superview viewWithTag:500];
    if ([val isKindOfClass:[UILabel class]]) {
        val.text = [NSString stringWithFormat:@"%.0f%%", slider.value * 100];
    }
}

- (void)feedSliderChanged:(UISlider *)slider {
    agmod_setFeedMacroRate(slider.value);
    UILabel *val = [slider.superview viewWithTag:501];
    if ([val isKindOfClass:[UILabel class]]) {
        val.text = [NSString stringWithFormat:@"%.0fms", slider.value];
    }
}

- (void)splitSliderChanged:(UISlider *)slider {
    agmod_setSplitMacroRate(slider.value);
    UILabel *val = [slider.superview viewWithTag:502];
    if ([val isKindOfClass:[UILabel class]]) {
        val.text = [NSString stringWithFormat:@"%.0fms", slider.value];
    }
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

- (void)copyServerURLTapped {
    BOOL copied = agmod_copyGameServerURL();
    UIViewController *vc = _hostWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;

    if (copied) {
        NSString *consoleId = agmod_getConsoleId();
        NSString *serverIP = agmod_getCurrentServerIP();
        NSString *msg = [NSString stringWithFormat:@"Console ID: %@\n\nPaste this in the UID / Bot Key field on the dashboard.%@",
            consoleId, serverIP.length > 0 ? [NSString stringWithFormat:@"\nServer: %@", serverIP] : @""];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Console ID Copied!"
            message:msg preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:alert animated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (vc.presentedViewController == alert) [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
            message:@"Console ID not available. Restart the app." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:alert animated:YES completion:nil];
    }
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

- (void)applyTextFields {
    // Find text fields by walking the card views
    for (UIView *cardView in _scrollView.subviews) {
        UITextField *urlField = [cardView viewWithTag:200];
        if ([urlField isKindOfClass:[UITextField class]] && urlField.text.length > 0)
            agmod_setBotServerURL(urlField.text);
        UITextField *keyField = [cardView viewWithTag:201];
        if ([keyField isKindOfClass:[UITextField class]] && keyField.text.length > 0)
            agmod_setBotSecretKey(keyField.text);
        UITextField *nameField = [cardView viewWithTag:202];
        if ([nameField isKindOfClass:[UITextField class]] && nameField.text.length > 0)
            agmod_setBotName(nameField.text);
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
