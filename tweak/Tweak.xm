// Tweak.xm — Agar.io iOS Mod (Logos/Theos)
// Target: Agar.io v26.6.0 (arm64)
// Build with Theos + CydiaSubstrate

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <MetalKit/MetalKit.h>
#import "headers/AgarIO.h"
#import "NativeMenu.h"
#import "ModAPI.h"

// ============================================================================
// GLOBAL STATE
// ============================================================================

static BOOL g_modEnabled = YES;

// Zoom
static BOOL g_zoomEnabled = NO;
static int  g_zoomMode = 0; // 0=DynamicCell, 1=StableCell, 2=SpeedCell
static float g_flexZoom = 0.5f;

// Mass display
static BOOL g_showEnemyMass = NO;

// Macros
static float g_feedMacroRate = 50.0f;   // ms between feed shots
static float g_splitMacroRate = 100.0f; // ms between splits
static BOOL  g_feedMacroActive = NO;
static BOOL  g_splitMacroActive = NO;

// Visual
static BOOL g_fastMode = NO;
static BOOL g_darkMode = NO;

// Skins
static BOOL g_unlockAllSkins = NO;

// Auto continue
static BOOL g_autoContinue = NO;

// FPS
static BOOL g_unlockFPS = NO;

// Server loader
static BOOL g_serverLoaderEnabled = NO;
static NSString *g_targetServerIP = nil;

// Bot communication
static NSString *g_botServerURL = nil;
static NSString *g_botSecretKey = nil;
static NSString *g_botName = nil;
static BOOL g_botsRunning = NO;
static int  g_botMode = 0; // 0=move,1=feed,2=farm,3=makevirus,4=breakvirus,5=teamer

// Current game info
static NSString *g_currentGameServerIP = nil;
static NSString *g_currentPartyCode = nil;
static NSString *g_currentGameWSURL = nil;
static NSString *g_sessionId = nil;
static NSString *g_consoleId = nil; // Miniclip UUID or generated fallback — used as Console ID for bot server

// Visual toggles
static BOOL g_hideGrid = NO;
static BOOL g_hideBorders = NO;
static BOOL g_hideProfilePics = NO;
static BOOL g_hideFriendTracker = NO;
static BOOL g_hideTokenCounter = NO;

// Internal references
static GameplayWidget *g_gameplayWidgetRef = nil;
static dispatch_source_t g_feedMacroTimer = nil;
static dispatch_source_t g_splitMacroTimer = nil;

// Enemy mass storage: cellId -> mass
static NSMutableDictionary<NSNumber *, NSNumber *> *g_enemyCellMasses = nil;

// ============================================================================
// MOD SETTINGS — Singleton for NSUserDefaults persistence
// ============================================================================

@interface ModSettings : NSObject
@property (nonatomic, strong) NSUserDefaults *defaults;
+ (instancetype)shared;
- (void)loadSettings;
- (void)saveSettings;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (void)setFloat:(float)value forKey:(NSString *)key;
- (float)floatForKey:(NSString *)key;
- (void)setInteger:(int)value forKey:(NSString *)key;
- (int)integerForKey:(NSString *)key;
- (void)setString:(NSString *)value forKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;
@end

@implementation ModSettings

+ (instancetype)shared {
    static ModSettings *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ModSettings alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *docsPath = [NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *prefsPath = [docsPath stringByAppendingPathComponent:@"__user_defaults__"];

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:prefsPath]) {
            [fm createDirectoryAtPath:prefsPath
              withIntermediateDirectories:YES
                              attributes:nil
                                   error:nil];
        }

        NSString *plistPath = [prefsPath stringByAppendingPathComponent:@"com.xrd.mod.plist"];
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.xrd.mod"];

        if (![fm fileExistsAtPath:plistPath]) {
            [self applyDefaults];
        }

        [self loadSettings];
    }
    return self;
}

- (void)applyDefaults {
    NSDictionary *defaultValues = @{
        @"mod_enabled":        @(YES),
        @"enable_zoom":        @(NO),
        @"zoom_mode":          @(0),
        @"flex_zoom":          @(0.5f),
        @"show_enemy_mass":    @(NO),
        @"feed_macro_rate":    @(50.0f),
        @"split_macro_rate":   @(100.0f),
        @"fast_mode":          @(NO),
        @"dark_mode":          @(NO),
        @"unlock_all_skins":   @(NO),
        @"auto_continue":      @(NO),
        @"unlock_fps":         @(NO),
        @"server_loader":      @(NO),
        @"target_server_ip":   @"",
        @"bot_server_url":     @"",
        @"bot_secret_key":     @"",
        @"bot_name":           @"Bot",
        @"bot_mode":           @(0),
        @"hide_grid":          @(NO),
        @"hide_borders":       @(NO),
        @"hide_profile_pics":  @(NO),
        @"hide_friend_tracker":@(NO),
        @"hide_token_counter": @(NO),
    };
    [_defaults registerDefaults:defaultValues];
}

- (void)loadSettings {
    g_modEnabled         = [_defaults boolForKey:@"mod_enabled"];
    g_zoomEnabled        = [_defaults boolForKey:@"enable_zoom"];
    g_zoomMode           = (int)[_defaults integerForKey:@"zoom_mode"];
    g_flexZoom           = [_defaults floatForKey:@"flex_zoom"];
    g_showEnemyMass      = [_defaults boolForKey:@"show_enemy_mass"];
    g_feedMacroRate      = [_defaults floatForKey:@"feed_macro_rate"];
    g_splitMacroRate     = [_defaults floatForKey:@"split_macro_rate"];
    g_fastMode           = [_defaults boolForKey:@"fast_mode"];
    g_darkMode           = [_defaults boolForKey:@"dark_mode"];
    g_unlockAllSkins     = [_defaults boolForKey:@"unlock_all_skins"];
    g_autoContinue       = [_defaults boolForKey:@"auto_continue"];
    g_unlockFPS          = [_defaults boolForKey:@"unlock_fps"];
    g_serverLoaderEnabled= [_defaults boolForKey:@"server_loader"];
    g_targetServerIP     = [_defaults stringForKey:@"target_server_ip"];
    g_botServerURL       = [_defaults stringForKey:@"bot_server_url"];
    g_botSecretKey       = [_defaults stringForKey:@"bot_secret_key"];
    g_botName            = [_defaults stringForKey:@"bot_name"];
    g_botMode            = (int)[_defaults integerForKey:@"bot_mode"];
    g_hideGrid           = [_defaults boolForKey:@"hide_grid"];
    g_hideBorders        = [_defaults boolForKey:@"hide_borders"];
    g_hideProfilePics    = [_defaults boolForKey:@"hide_profile_pics"];
    g_hideFriendTracker  = [_defaults boolForKey:@"hide_friend_tracker"];
    g_hideTokenCounter   = [_defaults boolForKey:@"hide_token_counter"];

    if (g_feedMacroRate < 10.0f) g_feedMacroRate = 10.0f;
    if (g_splitMacroRate < 30.0f) g_splitMacroRate = 30.0f;
    if (g_flexZoom < 0.0f) g_flexZoom = 0.0f;
    if (g_flexZoom > 1.0f) g_flexZoom = 1.0f;
}

- (void)saveSettings {
    [_defaults setBool:g_modEnabled         forKey:@"mod_enabled"];
    [_defaults setBool:g_zoomEnabled        forKey:@"enable_zoom"];
    [_defaults setInteger:g_zoomMode        forKey:@"zoom_mode"];
    [_defaults setFloat:g_flexZoom          forKey:@"flex_zoom"];
    [_defaults setBool:g_showEnemyMass      forKey:@"show_enemy_mass"];
    [_defaults setFloat:g_feedMacroRate     forKey:@"feed_macro_rate"];
    [_defaults setFloat:g_splitMacroRate    forKey:@"split_macro_rate"];
    [_defaults setBool:g_fastMode           forKey:@"fast_mode"];
    [_defaults setBool:g_darkMode           forKey:@"dark_mode"];
    [_defaults setBool:g_unlockAllSkins     forKey:@"unlock_all_skins"];
    [_defaults setBool:g_autoContinue       forKey:@"auto_continue"];
    [_defaults setBool:g_unlockFPS          forKey:@"unlock_fps"];
    [_defaults setBool:g_serverLoaderEnabled forKey:@"server_loader"];
    [_defaults setObject:(g_targetServerIP ?: @"") forKey:@"target_server_ip"];
    [_defaults setObject:(g_botServerURL ?: @"")   forKey:@"bot_server_url"];
    [_defaults setObject:(g_botSecretKey ?: @"")   forKey:@"bot_secret_key"];
    [_defaults setObject:(g_botName ?: @"Bot")     forKey:@"bot_name"];
    [_defaults setInteger:g_botMode         forKey:@"bot_mode"];
    [_defaults setBool:g_hideGrid           forKey:@"hide_grid"];
    [_defaults setBool:g_hideBorders        forKey:@"hide_borders"];
    [_defaults setBool:g_hideProfilePics    forKey:@"hide_profile_pics"];
    [_defaults setBool:g_hideFriendTracker  forKey:@"hide_friend_tracker"];
    [_defaults setBool:g_hideTokenCounter   forKey:@"hide_token_counter"];
    [_defaults synchronize];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [_defaults setBool:value forKey:key];
    [_defaults synchronize];
}

- (BOOL)boolForKey:(NSString *)key {
    return [_defaults boolForKey:key];
}

- (void)setFloat:(float)value forKey:(NSString *)key {
    [_defaults setFloat:value forKey:key];
    [_defaults synchronize];
}

- (float)floatForKey:(NSString *)key {
    return [_defaults floatForKey:key];
}

- (void)setInteger:(int)value forKey:(NSString *)key {
    [_defaults setInteger:value forKey:key];
    [_defaults synchronize];
}

- (int)integerForKey:(NSString *)key {
    return (int)[_defaults integerForKey:key];
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
    [_defaults setObject:(value ?: @"") forKey:key];
    [_defaults synchronize];
}

- (NSString *)stringForKey:(NSString *)key {
    return [_defaults stringForKey:key] ?: @"";
}

@end

// ============================================================================
// BOT MANAGER — Communicates with external bot server
// ============================================================================

@interface BotManager : NSObject
+ (instancetype)shared;
- (void)checkVersion:(void (^)(BOOL success, NSString *message))completion;
- (void)validateSecretKey:(NSString *)key completion:(void (^)(BOOL valid, NSString *message))completion;
- (void)startBotsWithMode:(int)mode completion:(void (^)(BOOL success, NSString *response))completion;
- (void)stopBots:(void (^)(BOOL success))completion;
- (void)sendBotCommand:(NSString *)command params:(NSDictionary *)params completion:(void (^)(NSDictionary *response))completion;
@end

@implementation BotManager

+ (instancetype)shared {
    static BotManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BotManager alloc] init];
    });
    return instance;
}

- (NSURLSession *)session {
    static NSURLSession *s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 15.0;
        config.timeoutIntervalForResource = 30.0;
        s = [NSURLSession sessionWithConfiguration:config];
    });
    return s;
}

- (void)checkVersion:(void (^)(BOOL success, NSString *message))completion {
    if (!g_botServerURL || g_botServerURL.length == 0) {
        if (completion) completion(NO, @"Bot server URL not configured");
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:@"%@/api", g_botServerURL];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) completion(NO, @"Invalid bot server URL");
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSString *body = @"action=check_version&client_version=2.0";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

    [[self.session dataTaskWithRequest:request completionHandler:^(
        NSData *data, NSURLResponse *response, NSError *error) {

        if (error) {
            if (completion) completion(NO, error.localizedDescription);
            return;
        }

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode != 200) {
            if (completion) completion(NO, [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]);
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || !json) {
            if (completion) completion(NO, @"Invalid server response");
            return;
        }

        BOOL success = [json[@"success"] boolValue];
        NSString *msg = json[@"message"] ?: @"";
        if (completion) completion(success, msg);

    }] resume];
}

- (void)validateSecretKey:(NSString *)key completion:(void (^)(BOOL valid, NSString *message))completion {
    if (!g_botServerURL || g_botServerURL.length == 0) {
        if (completion) completion(NO, @"Bot server URL not configured");
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:@"%@/getsecretkey.php", g_botServerURL];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) completion(NO, @"Invalid URL");
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:
        [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *body = [NSString stringWithFormat:@"secret_key=%@&session_id=%@",
        encodedKey, g_sessionId ?: @""];
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

    [[self.session dataTaskWithRequest:request completionHandler:^(
        NSData *data, NSURLResponse *response, NSError *error) {

        if (error) {
            if (completion) completion(NO, error.localizedDescription);
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || !json) {
            if (completion) completion(NO, @"Invalid response");
            return;
        }

        BOOL valid = [json[@"valid"] boolValue];
        NSString *msg = json[@"message"] ?: @"";
        if (completion) completion(valid, msg);

    }] resume];
}

- (void)startBotsWithMode:(int)mode completion:(void (^)(BOOL success, NSString *response))completion {
    [self sendBotCommand:@"start" params:@{
        @"mode": @(mode),
        @"bot_name": g_botName ?: @"Bot",
        @"targetip": g_currentGameServerIP ?: @"",
        @"party_code": g_currentPartyCode ?: @""
    } completion:^(NSDictionary *resp) {
        if (resp) {
            BOOL success = [resp[@"success"] boolValue];
            NSString *msg = resp[@"message"] ?: @"";
            g_botsRunning = success;
            if (completion) completion(success, msg);
        } else {
            if (completion) completion(NO, @"No response from server");
        }
    }];
}

- (void)stopBots:(void (^)(BOOL success))completion {
    [self sendBotCommand:@"stop" params:@{} completion:^(NSDictionary *resp) {
        g_botsRunning = NO;
        if (completion) completion(resp != nil && [resp[@"success"] boolValue]);
    }];
}

- (void)sendBotCommand:(NSString *)command params:(NSDictionary *)params
    completion:(void (^)(NSDictionary *response))completion {

    if (!g_botServerURL || g_botServerURL.length == 0) {
        if (completion) completion(nil);
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:@"%@/botter2.php", g_botServerURL];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) completion(nil);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSMutableString *bodyStr = [NSMutableString stringWithFormat:@"action=%@", command];
    [bodyStr appendFormat:@"&session_id=%@", g_sessionId ?: @""];
    [bodyStr appendFormat:@"&secret_key=%@",
        [g_botSecretKey stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLQueryAllowedCharacterSet]] ?: @""];

    for (NSString *key in params) {
        NSString *val = [NSString stringWithFormat:@"%@", params[key]];
        NSString *encoded = [val stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLQueryAllowedCharacterSet]];
        [bodyStr appendFormat:@"&%@=%@", key, encoded];
    }

    request.HTTPBody = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];

    [[self.session dataTaskWithRequest:request completionHandler:^(
        NSData *data, NSURLResponse *response, NSError *error) {

        if (error || !data) {
            if (completion) completion(nil);
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr) {
            if (completion) completion(nil);
            return;
        }
        if (completion) completion(json);

    }] resume];
}

@end

// ============================================================================
// MACRO ENGINE — GCD-based rapid fire macros
// ============================================================================

static void stopFeedMacro(void);
static void stopSplitMacro(void);

static void startFeedMacro(void) {
    if (g_feedMacroTimer) return;
    if (!g_gameplayWidgetRef) return;

    g_feedMacroActive = YES;
    dispatch_queue_t queue = dispatch_get_main_queue();
    g_feedMacroTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

    uint64_t intervalNs = (uint64_t)(g_feedMacroRate * NSEC_PER_MSEC);
    if (intervalNs < 10 * NSEC_PER_MSEC) intervalNs = 10 * NSEC_PER_MSEC;

    dispatch_source_set_timer(g_feedMacroTimer,
        dispatch_time(DISPATCH_TIME_NOW, 0),
        intervalNs,
        1 * NSEC_PER_MSEC);

    dispatch_source_set_event_handler(g_feedMacroTimer, ^{
        if (!g_feedMacroActive || !g_gameplayWidgetRef) {
            stopFeedMacro();
            return;
        }
        [g_gameplayWidgetRef shootMass];
    });

    dispatch_resume(g_feedMacroTimer);
}

static void stopFeedMacro(void) {
    g_feedMacroActive = NO;
    if (g_feedMacroTimer) {
        dispatch_source_cancel(g_feedMacroTimer);
        g_feedMacroTimer = nil;
    }
}

static void startSplitMacro(void) {
    if (g_splitMacroTimer) return;
    if (!g_gameplayWidgetRef) return;

    g_splitMacroActive = YES;
    dispatch_queue_t queue = dispatch_get_main_queue();
    g_splitMacroTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

    uint64_t intervalNs = (uint64_t)(g_splitMacroRate * NSEC_PER_MSEC);
    if (intervalNs < 30 * NSEC_PER_MSEC) intervalNs = 30 * NSEC_PER_MSEC;

    dispatch_source_set_timer(g_splitMacroTimer,
        dispatch_time(DISPATCH_TIME_NOW, 0),
        intervalNs,
        1 * NSEC_PER_MSEC);

    dispatch_source_set_event_handler(g_splitMacroTimer, ^{
        if (!g_splitMacroActive || !g_gameplayWidgetRef) {
            stopSplitMacro();
            return;
        }
        [g_gameplayWidgetRef splitPlayer];
    });

    dispatch_resume(g_splitMacroTimer);
}

static void stopSplitMacro(void) {
    g_splitMacroActive = NO;
    if (g_splitMacroTimer) {
        dispatch_source_cancel(g_splitMacroTimer);
        g_splitMacroTimer = nil;
    }
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

static NSString *generateSessionId(void) {
    NSMutableString *sid = [NSMutableString stringWithCapacity:32];
    static const char chars[] = "abcdefghijklmnopqrstuvwxyz0123456789";
    for (int i = 0; i < 32; i++) {
        [sid appendFormat:@"%c", chars[arc4random_uniform(sizeof(chars) - 1)]];
    }
    return [sid copy];
}

static NSString *formatMass(float mass) {
    if (mass >= 1000000.0f) {
        return [NSString stringWithFormat:@"%.1fM", mass / 1000000.0f];
    } else if (mass >= 1000.0f) {
        return [NSString stringWithFormat:@"%.1fK", mass / 1000.0f];
    }
    return [NSString stringWithFormat:@"%.0f", mass];
}

static NSString *getOrCreateConsoleId(void) {
    NSString *existing = [[ModSettings shared].defaults stringForKey:@"console_id"];
    if (existing && existing.length >= 8) return existing;

    NSString *consoleId = [[NSUUID UUID] UUIDString];
    [[ModSettings shared].defaults setObject:consoleId forKey:@"console_id"];
    [[ModSettings shared].defaults synchronize];
    return consoleId;
}

static void reportServerToBackend(NSString *serverUrl) {
    if (!g_botServerURL || g_botServerURL.length == 0) return;
    if (!g_consoleId || g_consoleId.length == 0) return;
    if (!serverUrl || serverUrl.length == 0) return;

    NSString *urlStr = [NSString stringWithFormat:@"%@/api/report-server", g_botServerURL];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.timeoutInterval = 10.0;

    NSDictionary *body = @{@"token": g_consoleId, @"server_url": serverUrl, @"party_code": g_currentPartyCode ?: @""};
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    request.HTTPBody = jsonData;

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(
        NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[XRD] Auto-report failed: %@", error.localizedDescription);
        } else {
            NSLog(@"[XRD] Auto-reported server for console ID %@", g_consoleId);
        }
    }] resume];
}

// ============================================================================
// HOOKS — %group Core
// ============================================================================

%group Core

// --- AppDelegate: Entry point ---
%hook AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;

    g_sessionId = generateSessionId();
    g_enemyCellMasses = [NSMutableDictionary new];

    [[ModSettings shared] loadSettings];
    g_consoleId = getOrCreateConsoleId();

    NSLog(@"[XRD] Mod initialized — session: %@, console ID: %@", g_sessionId, g_consoleId);
    NSLog(@"[XRD] Zoom: %@ | EnemyMass: %@ | Skins: %@ | FPS: %@ | Dark: %@",
        g_zoomEnabled ? @"ON" : @"OFF",
        g_showEnemyMass ? @"ON" : @"OFF",
        g_unlockAllSkins ? @"ON" : @"OFF",
        g_unlockFPS ? @"ON" : @"OFF",
        g_darkMode ? @"ON" : @"OFF");

    if (g_botServerURL && g_botServerURL.length > 0) {
        [[BotManager shared] checkVersion:^(BOOL success, NSString *message) {
            NSLog(@"[XRD] Bot server version check: %@ — %@",
                success ? @"OK" : @"FAIL", message);
        }];
    }

    return result;
}

%end

%end // group Core

// ============================================================================
// HOOKS — %group ZoomHack
// ============================================================================

%group ZoomHack

%hook GameplaySettings

- (float)calculateZoom:(float)mass cellAmount:(int)cellAmount {
    if (!g_modEnabled || !g_zoomEnabled) {
        return %orig;
    }

    float originalZoom = %orig;

    @try {
        float phoneRatio = 1.0f;
        if ([self respondsToSelector:@selector(calculatePhoneRatioForZoom)])
            phoneRatio = [self calculatePhoneRatioForZoom];

        switch (g_zoomMode) {
            case 0: { // DynamicCell
                float baseFactor = 0.3f, amplitude = 0.5f, decay = 0.001f;
                if ([self respondsToSelector:@selector(variableZoomBase)])
                    baseFactor = self.variableZoomBase;
                if ([self respondsToSelector:@selector(variableZoomAmplitude)])
                    amplitude = self.variableZoomAmplitude;
                if ([self respondsToSelector:@selector(variableZoomDecay)])
                    decay = self.variableZoomDecay;

                float dynamicZoom = baseFactor + amplitude * expf(-decay * mass);
                float scaleFactor = [self getScaleFactorForNumberOfCells:cellAmount];
                float modifiedZoom = dynamicZoom * scaleFactor * phoneRatio;

                float lerpFactor = g_flexZoom;
                float finalZoom = originalZoom * (1.0f - lerpFactor) + modifiedZoom * lerpFactor * 0.4f;

                if (finalZoom < 0.05f) finalZoom = 0.05f;
                if (finalZoom > 2.0f) finalZoom = 2.0f;
                return finalZoom;
            }

            case 1: { // StableCell
                float stableBase = 0.15f + (g_flexZoom * 0.35f);
                float scaleFactor = [self getScaleFactorForNumberOfCells:cellAmount];
                float stableZoom = stableBase * scaleFactor * phoneRatio;

                if (stableZoom < 0.05f) stableZoom = 0.05f;
                if (stableZoom > 1.5f) stableZoom = 1.5f;
                return stableZoom;
            }

            case 2: { // SpeedCell
                float speedBase = 0.08f + (g_flexZoom * 0.12f);
                float speedZoom = speedBase * phoneRatio;

                if (speedZoom < 0.03f) speedZoom = 0.03f;
                if (speedZoom > 0.5f) speedZoom = 0.5f;
                return speedZoom;
            }

            default:
                return originalZoom;
        }
    } @catch (NSException *e) {
        NSLog(@"[XRD] ZoomHack exception: %@", e);
        return originalZoom;
    }
}

- (float)getScaleFactorForNumberOfCells:(int)count {
    if (!g_modEnabled || !g_zoomEnabled) {
        return %orig;
    }

    float originalScale = %orig;

    // Provide a gentler scale curve so multi-cell doesn't zoom in too much
    if (count <= 1) return originalScale;

    float customScale;
    if (count <= 4) {
        customScale = 1.0f - (count - 1) * 0.05f;
    } else if (count <= 8) {
        customScale = 0.85f - (count - 4) * 0.04f;
    } else if (count <= 16) {
        customScale = 0.69f - (count - 8) * 0.02f;
    } else {
        customScale = 0.53f;
    }

    float blendedScale = originalScale * 0.3f + customScale * 0.7f;
    if (blendedScale < 0.3f) blendedScale = 0.3f;
    if (blendedScale > 1.0f) blendedScale = 1.0f;

    return blendedScale;
}

%end

%end // group ZoomHack

// ============================================================================
// HOOKS — %group MassDisplay
// ============================================================================

%group MassDisplay

%hook ScoreWidget

- (void)initPlayerMassLabelWithMass:(float)mass {
    %orig;

    if (!g_modEnabled || !g_showEnemyMass) return;

    // After the original sets up the player mass label, we also want to ensure
    // all visible enemy cells have their mass displayed. The actual rendering
    // of enemy mass labels is handled in the cell view draw hooks.
}

%end

%hook BaseArenaState

- (void)processGameArenaState:(id)state updateRate:(float)rate {
    %orig;

    if (!g_modEnabled || !g_showEnemyMass) return;

    // After processing the arena state update, extract cell data.
    // The state object contains cell arrays with mass information.
    // We parse it to populate g_enemyCellMasses for rendering.
    @try {
        if ([state respondsToSelector:@selector(objectForKey:)]) {
            NSDictionary *stateDict = (NSDictionary *)state;
            NSArray *cells = stateDict[@"cells"];
            if ([cells isKindOfClass:[NSArray class]]) {
                for (id cellData in cells) {
                    if ([cellData respondsToSelector:@selector(objectForKey:)]) {
                        NSDictionary *cd = (NSDictionary *)cellData;
                        NSNumber *cellId = cd[@"id"];
                        NSNumber *mass = cd[@"mass"];
                        if (cellId && mass) {
                            g_enemyCellMasses[cellId] = mass;
                        }
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // Silently ignore parse errors from state format variations
    }
}

- (void)handleCellsDied:(id)cells {
    %orig;

    if (!g_modEnabled || !g_showEnemyMass) return;

    // Remove dead cells from the mass tracking dictionary
    @try {
        if ([cells isKindOfClass:[NSArray class]]) {
            for (id cellData in (NSArray *)cells) {
                if ([cellData respondsToSelector:@selector(objectForKey:)]) {
                    NSNumber *cellId = ((NSDictionary *)cellData)[@"id"];
                    if (cellId) {
                        [g_enemyCellMasses removeObjectForKey:cellId];
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // Ignore
    }
}

- (void)handleCellsDisappeared:(id)cells {
    %orig;

    if (!g_modEnabled || !g_showEnemyMass) return;

    @try {
        if ([cells isKindOfClass:[NSArray class]]) {
            for (id cellData in (NSArray *)cells) {
                if ([cellData respondsToSelector:@selector(objectForKey:)]) {
                    NSNumber *cellId = ((NSDictionary *)cellData)[@"id"];
                    if (cellId) {
                        [g_enemyCellMasses removeObjectForKey:cellId];
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // Ignore
    }
}

%end

%end // group MassDisplay

// ============================================================================
// HOOKS — %group SkinUnlock
// ============================================================================

%group SkinUnlock

%hook UserWallet

- (BOOL)isProductActivated:(NSString *)productId {
    if (g_modEnabled && g_unlockAllSkins) {
        return YES;
    }
    return %orig;
}

- (int)quantityOwnedOf:(NSString *)productId {
    if (g_modEnabled && g_unlockAllSkins) {
        return 999;
    }
    return %orig;
}

%end

%hook AgarCell

- (void)setupSkinWithId:(NSString *)skinId isShopCell:(BOOL)isShop {
    if (g_modEnabled && g_unlockAllSkins) {
        // Allow any skin to be set up regardless of ownership
        %orig(skinId, NO);
        return;
    }
    %orig;
}

- (BOOL)attemptSetMysterySkinWithName:(NSString *)name hasTemporarySkin:(BOOL)hasTmp {
    if (g_modEnabled && g_unlockAllSkins) {
        return YES;
    }
    return %orig;
}

%end

%end // group SkinUnlock

// ============================================================================
// HOOKS — %group AutoContinue
// ============================================================================

%group AutoContinue

%hook ContinueGame

- (void)showContinuePopupWithMass:(float)mass keep:(float)keep customData:(id)data {
    if (g_modEnabled && g_autoContinue) {
        NSLog(@"[XRD] Auto-continue: mass=%.0f, keep=%.0f", mass, keep);

        // Skip the popup entirely. Dispatch the respawn on next runloop iteration
        // so the game state machine has time to settle.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
            // Attempt to restart by calling the play callback through the menu system
            StateMachine *sm = [%c(StateMachine) performSelector:@selector(sharedInstance)
                withObject:nil];
            if (sm && [sm respondsToSelector:@selector(isInArena)]) {
                if (![sm isInArena]) {
                    // Try to re-enter via the menu play button
                    MenuMain *menu = [%c(MenuMain) performSelector:@selector(sharedInstance)
                        withObject:nil];
                    if (menu && [menu respondsToSelector:@selector(playButtonCallback)]) {
                        [menu playButtonCallback];
                    }
                }
            }
        });

        return;
    }
    %orig;
}

%end

%end // group AutoContinue

// ============================================================================
// HOOKS — %group FPSUnlock
// ============================================================================

%group FPSUnlock

%hook BaseArenaView

- (void)framerateControl:(float)dt {
    if (g_modEnabled && g_unlockFPS) {
        // Bypass the frame rate limiter entirely. The original method
        // throttles rendering; we skip it to let the display link
        // run at the maximum refresh rate.
        return;
    }
    %orig;
}

%end

%end // group FPSUnlock

// ============================================================================
// HOOKS — %group ServerLoader
// ============================================================================

%group ServerLoader

%hook OnlineArenaState

- (void)prepareToEnterArena {
    %orig;

    // Capture the current server IP from the connection state
    @try {
        if ([self respondsToSelector:@selector(valueForKey:)]) {
            id connection = [self valueForKey:@"connection"];
            if (connection && [connection respondsToSelector:@selector(valueForKey:)]) {
                NSString *host = [connection valueForKey:@"host"];
                if (host) {
                    g_currentGameServerIP = [host copy];
                    NSLog(@"[XRD] Connected to server: %@", g_currentGameServerIP);
                    if (!g_currentGameWSURL || g_currentGameWSURL.length == 0) {
                        NSString *constructed = agmod_getGameServerWSURL();
                        reportServerToBackend(constructed);
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // KVC may not work on all builds; fail silently
    }
}

%end

%hook ContentPartyCreatedOrJoinedView

- (void)setupLayoutWithPartyCode:(NSString *)code isFacebookAccount:(BOOL)isFB subtitle:(NSString *)subtitle {
    %orig;

    if (code && code.length > 0) {
        g_currentPartyCode = [code copy];
        NSLog(@"[XRD] Party code captured: %@", g_currentPartyCode);

        // Re-report so the backend gets the party code even when the party is
        // created/joined mid-game, after the WebSocket already reported empty.
        NSString *serverUrl = (g_currentGameWSURL && g_currentGameWSURL.length > 0)
            ? g_currentGameWSURL
            : agmod_getGameServerWSURL();
        reportServerToBackend(serverUrl);
    }
}

%end

%end // group ServerLoader

// ============================================================================
// HOOKS — %group UserCapture — Capture Miniclip UUID as Console ID
// ============================================================================

%group UserCapture

%hook UserInfo

- (NSString *)userId {
    NSString *uid = %orig;
    if (uid && uid.length > 0 && ![uid isEqualToString:g_consoleId]) {
        g_consoleId = [uid copy];
        [[ModSettings shared].defaults setObject:uid forKey:@"console_id"];
        [[ModSettings shared].defaults synchronize];
        NSLog(@"[XRD] Console ID updated from Miniclip UUID: %@", g_consoleId);
    }
    return uid;
}

%end

%end // group UserCapture

// ============================================================================
// HOOKS — %group FastMode
// ============================================================================

%group FastMode

%hook AgarCellView

- (void)setIsSimpleDraw:(BOOL)simple {
    if (g_modEnabled && g_fastMode) {
        %orig(YES);
        return;
    }
    %orig;
}

- (void)draw {
    if (g_modEnabled && g_fastMode) {
        // When fast mode is active, force simple draw before rendering
        [self setIsSimpleDraw:YES];
    }
    %orig;
}

%end

%hook SoftBodyCellView

- (void)draw {
    if (g_modEnabled && g_fastMode) {
        // Skip soft body physics rendering in fast mode to improve performance.
        // Soft body calculations are expensive and unnecessary for competitive play.
        return;
    }
    %orig;
}

%end

%end // group FastMode

// ============================================================================
// HOOKS — %group DarkMode
// ============================================================================

%group DarkMode

%hook BaseArenaState

- (void)setupHudAndAddToView {
    %orig;

    if (!g_modEnabled || !g_darkMode) return;

    // Apply dark overlay to the arena background after HUD setup
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }

        if (!keyWindow) return;

        // Check if dark overlay already exists
        UIView *darkOverlay = [keyWindow viewWithTag:9990001];
        if (!darkOverlay) {
            darkOverlay = [[UIView alloc] initWithFrame:keyWindow.bounds];
            darkOverlay.tag = 9990001;
            darkOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
            darkOverlay.userInteractionEnabled = NO;
            darkOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [keyWindow insertSubview:darkOverlay atIndex:1];
        }
    });
}

- (void)onExit {
    %orig;

    // Remove dark overlay when leaving arena
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            UIView *darkOverlay = [window viewWithTag:9990001];
            if (darkOverlay) {
                [darkOverlay removeFromSuperview];
            }
        }
    });
}

%end

%end // group DarkMode

// ============================================================================
// HOOKS — %group VisualMods
// ============================================================================

%group VisualMods

// Hide friend tracker
%hook FriendTrackerWidget

- (void)trackClosestFriend {
    if (g_modEnabled && g_hideFriendTracker) {
        return;
    }
    %orig;
}

%end

// Hide token counter
%hook CollectibleCounterWidget

%end

// Hide leaderboard profile pics
%hook LeaderboardWidget

- (void)updateLeaderboard:(id)data {
    %orig;

    if (!g_modEnabled || !g_hideProfilePics) return;

    // After the leaderboard updates, hide the avatar images
    // by traversing the node's children
    @try {
        if ([self respondsToSelector:@selector(valueForKey:)]) {
            NSArray *entries = [self valueForKey:@"entries"];
            if ([entries isKindOfClass:[NSArray class]]) {
                for (id entry in entries) {
                    if ([entry respondsToSelector:@selector(valueForKey:)]) {
                        id avatar = [entry valueForKey:@"avatar"];
                        if (avatar && [avatar respondsToSelector:@selector(setVisible:)]) {
                            [(CCNode *)avatar setVisible:NO];
                        }
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // Graceful degradation
    }
}

%end

%end // group VisualMods

// ============================================================================
// HOOKS — %group GameplayCapture — Capture references for macros
// ============================================================================

%group GameplayCapture

%hook GameplayWidget

- (void)setup {
    %orig;
    g_gameplayWidgetRef = self;
    NSLog(@"[XRD] GameplayWidget captured for macros");
}

- (void)cleanup {
    if (g_gameplayWidgetRef == self) {
        stopFeedMacro();
        stopSplitMacro();
        g_gameplayWidgetRef = nil;
        NSLog(@"[XRD] GameplayWidget released");
    }
    %orig;
}

%end

%end // group GameplayCapture

// ============================================================================
// HOOKS — %group FPSUnlockDisplay — CADisplayLink / MTKView unlock
// ============================================================================

static void unlockFPSInViewHierarchy(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:[MTKView class]]) {
        ((MTKView *)view).preferredFramesPerSecond = 120;
        NSLog(@"[XRD] MTKView FPS set to 120");
        return;
    }
    for (UIView *subview in view.subviews) {
        unlockFPSInViewHierarchy(subview);
    }
}

%group FPSUnlockDisplay

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!g_modEnabled || !g_unlockFPS) return;
    unlockFPSInViewHierarchy(self.view);
}

%end

%end // group FPSUnlockDisplay

// ============================================================================
// HOOKS — %group GridAndBorderHide
// ============================================================================

%group GridAndBorderHide

%hook BaseArenaState

- (void)update:(float)dt {
    %orig;

    if (!g_modEnabled) return;

    // Apply grid/border hide per frame.
    // The game re-draws grid lines and border markers each update cycle.
    // We suppress their visibility flags here.
    @try {
        if (g_hideGrid) {
            id gridNode = nil;
            if ([self respondsToSelector:@selector(valueForKey:)]) {
                gridNode = [self valueForKey:@"gridNode"];
            }
            if (gridNode && [gridNode respondsToSelector:@selector(setVisible:)]) {
                [(CCNode *)gridNode setVisible:NO];
            }
        }

        if (g_hideBorders) {
            id borderNode = nil;
            if ([self respondsToSelector:@selector(valueForKey:)]) {
                borderNode = [self valueForKey:@"borderNode"];
            }
            if (borderNode && [borderNode respondsToSelector:@selector(setVisible:)]) {
                [(CCNode *)borderNode setVisible:NO];
            }
        }
    } @catch (NSException *e) {
        // Suppress errors from missing ivars
    }
}

%end

%end // group GridAndBorderHide

// ============================================================================
// HOOKS — %group EnemyMassRenderer
// ============================================================================

%group EnemyMassRenderer

%hook AgarCellView

- (void)draw {
    %orig;

    if (!g_modEnabled || !g_showEnemyMass) return;

    id cellObj = nil;
    if ([self respondsToSelector:@selector(cell)])
        cellObj = [self performSelector:@selector(cell)];
    if (!cellObj) return;

    AgarCell *cell = (AgarCell *)cellObj;
    if ([cell respondsToSelector:@selector(isVirus)] && cell.isVirus) return;

    float mass = 0;
    if ([cell respondsToSelector:@selector(mass)])
        mass = cell.mass;
    if (mass < 10.0f) return;

    // Check if this cell already has our mass label attached
    static const NSInteger kMassLabelTag = 8880001;
    id existingLabel = nil;

    @try {
        if ([self respondsToSelector:@selector(valueForKey:)]) {
            id node = [self valueForKey:@"node"];
            if (node && [node respondsToSelector:@selector(valueForKey:)]) {
                NSArray *children = [node valueForKey:@"children"];
                if ([children isKindOfClass:[NSArray class]]) {
                    for (id child in children) {
                        if ([child respondsToSelector:@selector(tag)]) {
                            if ([(CCNode *)child tag] == kMassLabelTag) {
                                existingLabel = child;
                                break;
                            }
                        }
                    }
                }
            }

            if (!existingLabel) {
                // Create a mass label using CCLabelTTF
                Class labelClass = NSClassFromString(@"CCLabelTTF");
                if (labelClass) {
                    id label = [[labelClass alloc] init];
                    if (label) {
                        if ([label respondsToSelector:@selector(setFontName:)]) {
                            [(CCLabelTTF *)label setFontName:@"Helvetica-Bold"];
                        }
                        if ([label respondsToSelector:@selector(setAnchorPoint:)]) {
                            [(CCLabelTTF *)label setAnchorPoint:CGPointMake(0.5f, 0.5f)];
                        }
                        if ([label respondsToSelector:@selector(setTag:)]) {
                            [(CCNode *)label setTag:kMassLabelTag];
                        }

                        id parentNode = [self valueForKey:@"node"];
                        if (parentNode && [parentNode respondsToSelector:@selector(addChild:z:)]) {
                            [(CCNode *)parentNode addChild:label z:100];
                        }
                        existingLabel = label;
                    }
                }
            }

            // Update mass text
            if (existingLabel && [existingLabel respondsToSelector:@selector(setString:)]) {
                NSString *massText = formatMass(mass);
                [existingLabel performSelector:@selector(setString:) withObject:massText];
            }
        }
    } @catch (NSException *e) {
        // Fail gracefully on incompatible builds
    }
}

%end

%end // group EnemyMassRenderer

// ============================================================================
// HOOKS — %group ConnectionInterceptor — Server IP redirection
// ============================================================================

%group ConnectionInterceptor

%hook OnlineArenaState

- (void)sendNetworkMessageEnterGame:(id)params {
    if (g_modEnabled && g_serverLoaderEnabled && g_targetServerIP && g_targetServerIP.length > 0) {
        NSLog(@"[XRD] Server loader: redirecting to %@", g_targetServerIP);

        // Attempt to modify the connection parameters to target our server
        @try {
            if ([params respondsToSelector:@selector(setValue:forKey:)]) {
                [(NSMutableDictionary *)params setValue:g_targetServerIP forKey:@"server"];
            } else if ([params isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *mutableParams = [params mutableCopy];
                mutableParams[@"server"] = g_targetServerIP;
                %orig(mutableParams);
                return;
            }
        } @catch (NSException *e) {
            NSLog(@"[XRD] Server loader: failed to redirect — %@", e.reason);
        }
    }
    %orig;
}

%end

%end // group ConnectionInterceptor

// ============================================================================
// HOOKS — %group WebSocketCapture — Intercept WebSocket URLs
// ============================================================================

%group WebSocketCapture

%hook NSURLSession

- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url {
    NSString *urlStr = url.absoluteString;
    if ([urlStr containsString:@"agar"] || [urlStr containsString:@"live-arena"] || [urlStr containsString:@"miniclippt"]) {
        g_currentGameWSURL = [urlStr copy];
        NSLog(@"[XRD] WebSocket URL captured: %@", g_currentGameWSURL);
        reportServerToBackend(g_currentGameWSURL);
    }
    return %orig;
}

- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url protocols:(NSArray<NSString *> *)protocols {
    NSString *urlStr = url.absoluteString;
    if ([urlStr containsString:@"agar"] || [urlStr containsString:@"live-arena"] || [urlStr containsString:@"miniclippt"]) {
        g_currentGameWSURL = [urlStr copy];
        NSLog(@"[XRD] WebSocket URL captured: %@", g_currentGameWSURL);
        reportServerToBackend(g_currentGameWSURL);
    }
    return %orig;
}

- (NSURLSessionWebSocketTask *)webSocketTaskWithRequest:(NSURLRequest *)request {
    NSString *urlStr = request.URL.absoluteString;
    if ([urlStr containsString:@"agar"] || [urlStr containsString:@"live-arena"] || [urlStr containsString:@"miniclippt"]) {
        g_currentGameWSURL = [urlStr copy];
        NSLog(@"[XRD] WebSocket URL captured: %@", g_currentGameWSURL);
        reportServerToBackend(g_currentGameWSURL);
    }
    return %orig;
}

%end

%end // group WebSocketCapture

// ============================================================================
// HOOKS — %group TokenCounterHide
// ============================================================================

%group TokenCounterHide

%hook CollectibleCounterWidget

// Hide the arena token counter by making the widget invisible whenever
// it would normally appear
- (instancetype)init {
    id result = %orig;
    if (g_modEnabled && g_hideTokenCounter && result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                if ([result respondsToSelector:@selector(valueForKey:)]) {
                    id node = [result valueForKey:@"node"];
                    if (node && [node respondsToSelector:@selector(setVisible:)]) {
                        [(CCNode *)node setVisible:NO];
                    }
                }
            } @catch (NSException *e) {
                // Ignore
            }
        });
    }
    return result;
}

%end

%end // group TokenCounterHide

// ============================================================================
// HOOKS — %group FriendTrackerHide
// ============================================================================

%group FriendTrackerHide

%hook FriendTrackerWidget

- (instancetype)init {
    id result = %orig;
    if (g_modEnabled && g_hideFriendTracker && result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                if ([result respondsToSelector:@selector(valueForKey:)]) {
                    id node = [result valueForKey:@"node"];
                    if (node && [node respondsToSelector:@selector(setVisible:)]) {
                        [(CCNode *)node setVisible:NO];
                    }
                }
            } @catch (NSException *e) {
                // Ignore
            }
        });
    }
    return result;
}

%end

%end // group FriendTrackerHide

// ============================================================================
// HOOKS — %group CellMassOverlay — Enhanced mass display on cell draw
// ============================================================================

%group CellMassOverlay

%hook AgarCell

- (instancetype)initWithCellState:(id)state name:(NSString *)name isShopCell:(BOOL)isShop
    isPartyCell:(BOOL)isParty isSkinEditorCell:(BOOL)isSkinEditor isSoloLevellingCell:(BOOL)isSolo {

    id result = %orig;

    if (g_modEnabled && g_showEnemyMass && result) {
        @try {
            AgarCell *cell = (AgarCell *)result;
            if ([cell respondsToSelector:@selector(cellId)] &&
                [cell respondsToSelector:@selector(mass)]) {
                if (cell.cellId > 0 && cell.mass > 0) {
                    g_enemyCellMasses[@(cell.cellId)] = @(cell.mass);
                }
            }
        } @catch (NSException *e) {}
    }

    return result;
}

%end

%end // group CellMassOverlay

// ============================================================================
// PUBLIC API — Functions callable from the mod menu (ImGui or other UI)
// ============================================================================

// These functions are exported so the mod menu can call them directly.

extern "C" {

void agmod_setZoomEnabled(BOOL enabled) {
    g_zoomEnabled = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"enable_zoom"];
}

void agmod_setZoomMode(int mode) {
    g_zoomMode = mode;
    [[ModSettings shared] setInteger:mode forKey:@"zoom_mode"];
}

void agmod_setFlexZoom(float value) {
    if (value < 0.0f) value = 0.0f;
    if (value > 1.0f) value = 1.0f;
    g_flexZoom = value;
    [[ModSettings shared] setFloat:value forKey:@"flex_zoom"];
}

void agmod_setShowEnemyMass(BOOL enabled) {
    g_showEnemyMass = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"show_enemy_mass"];
    if (!enabled) {
        [g_enemyCellMasses removeAllObjects];
    }
}

void agmod_setFeedMacroRate(float rateMs) {
    if (rateMs < 10.0f) rateMs = 10.0f;
    if (rateMs > 1000.0f) rateMs = 1000.0f;
    g_feedMacroRate = rateMs;
    [[ModSettings shared] setFloat:rateMs forKey:@"feed_macro_rate"];

    // Restart timer if active to apply new rate
    if (g_feedMacroActive) {
        stopFeedMacro();
        startFeedMacro();
    }
}

void agmod_setFeedMacroActive(BOOL active) {
    if (active && !g_feedMacroActive) {
        startFeedMacro();
    } else if (!active && g_feedMacroActive) {
        stopFeedMacro();
    }
}

void agmod_setSplitMacroRate(float rateMs) {
    if (rateMs < 30.0f) rateMs = 30.0f;
    if (rateMs > 1000.0f) rateMs = 1000.0f;
    g_splitMacroRate = rateMs;
    [[ModSettings shared] setFloat:rateMs forKey:@"split_macro_rate"];

    if (g_splitMacroActive) {
        stopSplitMacro();
        startSplitMacro();
    }
}

void agmod_setSplitMacroActive(BOOL active) {
    if (active && !g_splitMacroActive) {
        startSplitMacro();
    } else if (!active && g_splitMacroActive) {
        stopSplitMacro();
    }
}

void agmod_setFastMode(BOOL enabled) {
    g_fastMode = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"fast_mode"];
}

void agmod_setDarkMode(BOOL enabled) {
    g_darkMode = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"dark_mode"];

    // Apply or remove dark overlay immediately
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            UIView *overlay = [window viewWithTag:9990001];
            if (enabled && !overlay) {
                overlay = [[UIView alloc] initWithFrame:window.bounds];
                overlay.tag = 9990001;
                overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
                overlay.userInteractionEnabled = NO;
                overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [window insertSubview:overlay atIndex:1];
            } else if (!enabled && overlay) {
                [overlay removeFromSuperview];
            }
        }
    });
}

void agmod_setUnlockAllSkins(BOOL enabled) {
    g_unlockAllSkins = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"unlock_all_skins"];
}

void agmod_setAutoContinue(BOOL enabled) {
    g_autoContinue = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"auto_continue"];
}

static void agmod_findAndUnlockMTKView(UIView *view);

void agmod_setUnlockFPS(BOOL enabled) {
    g_unlockFPS = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"unlock_fps"];

    if (enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = nil;
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
            if (keyWindow) {
                agmod_findAndUnlockMTKView(keyWindow.rootViewController.view);
            }
        });
    }
}

static void agmod_findAndUnlockMTKView(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:NSClassFromString(@"MTKView")]) {
        ((MTKView *)view).preferredFramesPerSecond = 120;
    }
    for (UIView *sub in view.subviews) {
        agmod_findAndUnlockMTKView(sub);
    }
}

void agmod_setServerLoaderEnabled(BOOL enabled) {
    g_serverLoaderEnabled = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"server_loader"];
}

void agmod_setTargetServerIP(NSString *ip) {
    g_targetServerIP = [ip copy];
    [[ModSettings shared] setString:ip forKey:@"target_server_ip"];
}

void agmod_setBotServerURL(NSString *url) {
    g_botServerURL = [url copy];
    [[ModSettings shared] setString:url forKey:@"bot_server_url"];
}

void agmod_setBotSecretKey(NSString *key) {
    g_botSecretKey = [key copy];
    [[ModSettings shared] setString:key forKey:@"bot_secret_key"];
}

void agmod_setBotName(NSString *name) {
    g_botName = [name copy];
    [[ModSettings shared] setString:name forKey:@"bot_name"];
}

void agmod_setBotMode(int mode) {
    if (mode < 0) mode = 0;
    if (mode > 5) mode = 5;
    g_botMode = mode;
    [[ModSettings shared] setInteger:mode forKey:@"bot_mode"];
}

void agmod_startBots(void) {
    [[BotManager shared] startBotsWithMode:g_botMode completion:^(BOOL success, NSString *response) {
        NSLog(@"[XRD] Bots start: %@ — %@", success ? @"OK" : @"FAIL", response);
    }];
}

void agmod_stopBots(void) {
    [[BotManager shared] stopBots:^(BOOL success) {
        NSLog(@"[XRD] Bots stop: %@", success ? @"OK" : @"FAIL");
    }];
}

void agmod_validateBotKey(void (^callback)(BOOL valid, NSString *msg)) {
    [[BotManager shared] validateSecretKey:g_botSecretKey completion:callback];
}

void agmod_setHideGrid(BOOL enabled) {
    g_hideGrid = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"hide_grid"];
}

void agmod_setHideBorders(BOOL enabled) {
    g_hideBorders = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"hide_borders"];
}

void agmod_setHideProfilePics(BOOL enabled) {
    g_hideProfilePics = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"hide_profile_pics"];
}

void agmod_setHideFriendTracker(BOOL enabled) {
    g_hideFriendTracker = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"hide_friend_tracker"];
}

void agmod_setHideTokenCounter(BOOL enabled) {
    g_hideTokenCounter = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"hide_token_counter"];
}

void agmod_setModEnabled(BOOL enabled) {
    g_modEnabled = enabled;
    [[ModSettings shared] setBool:enabled forKey:@"mod_enabled"];
    if (!enabled) {
        stopFeedMacro();
        stopSplitMacro();
    }
}

void agmod_saveAllSettings(void) {
    [[ModSettings shared] saveSettings];
}

void agmod_reloadSettings(void) {
    [[ModSettings shared] loadSettings];
}

// Getters for the mod menu UI
BOOL    agmod_isModEnabled(void)        { return g_modEnabled; }
BOOL    agmod_isZoomEnabled(void)       { return g_zoomEnabled; }
int     agmod_getZoomMode(void)         { return g_zoomMode; }
float   agmod_getFlexZoom(void)         { return g_flexZoom; }
BOOL    agmod_isShowEnemyMass(void)     { return g_showEnemyMass; }
float   agmod_getFeedMacroRate(void)    { return g_feedMacroRate; }
float   agmod_getSplitMacroRate(void)   { return g_splitMacroRate; }
BOOL    agmod_isFeedMacroActive(void)   { return g_feedMacroActive; }
BOOL    agmod_isSplitMacroActive(void)  { return g_splitMacroActive; }
BOOL    agmod_isFastMode(void)          { return g_fastMode; }
BOOL    agmod_isDarkMode(void)          { return g_darkMode; }
BOOL    agmod_isUnlockAllSkins(void)    { return g_unlockAllSkins; }
BOOL    agmod_isAutoContinue(void)      { return g_autoContinue; }
BOOL    agmod_isUnlockFPS(void)         { return g_unlockFPS; }
BOOL    agmod_isServerLoaderEnabled(void) { return g_serverLoaderEnabled; }
NSString *agmod_getTargetServerIP(void) { return g_targetServerIP ?: @""; }
NSString *agmod_getBotServerURL(void)   { return g_botServerURL ?: @""; }
NSString *agmod_getBotSecretKey(void)   { return g_botSecretKey ?: @""; }
NSString *agmod_getBotName(void)        { return g_botName ?: @"Bot"; }
int     agmod_getBotMode(void)          { return g_botMode; }
BOOL    agmod_isBotsRunning(void)       { return g_botsRunning; }
NSString *agmod_getCurrentServerIP(void){ return g_currentGameServerIP ?: @""; }
NSString *agmod_getCurrentPartyCode(void){ return g_currentPartyCode ?: @""; }
NSString *agmod_getSessionId(void)      { return g_sessionId ?: @""; }

NSString *agmod_getGameServerWSURL(void) {
    if (g_currentGameWSURL && g_currentGameWSURL.length > 0) {
        return g_currentGameWSURL;
    }
    if (g_currentGameServerIP && g_currentGameServerIP.length > 0) {
        if (g_currentPartyCode && g_currentPartyCode.length > 0) {
            return [NSString stringWithFormat:@"wss://%@?party_id=%@",
                g_currentGameServerIP, g_currentPartyCode];
        }
        return [NSString stringWithFormat:@"wss://%@", g_currentGameServerIP];
    }
    return @"";
}

BOOL agmod_copyGameServerURL(void) {
    if (!g_consoleId || g_consoleId.length == 0) return NO;
    [[UIPasteboard generalPasteboard] setString:g_consoleId];
    return YES;
}

NSString *agmod_getConsoleId(void) { return g_consoleId ?: @""; }
BOOL    agmod_isHideGrid(void)          { return g_hideGrid; }
BOOL    agmod_isHideBorders(void)       { return g_hideBorders; }
BOOL    agmod_isHideProfilePics(void)   { return g_hideProfilePics; }
BOOL    agmod_isHideFriendTracker(void) { return g_hideFriendTracker; }
BOOL    agmod_isHideTokenCounter(void)  { return g_hideTokenCounter; }

} // extern "C"

// ============================================================================
// CONSTRUCTOR — %ctor
// ============================================================================

%ctor {
    @autoreleasepool {
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];

        if (![bundleId isEqualToString:@"com.miniclip.agar.io"] &&
            ![bundleId hasPrefix:@"com.miniclip.agar"]) {
            return;
        }

        NSLog(@"[XRD] Loading tweak for bundle: %@", bundleId);

        @try {
            [ModSettings shared];

            %init(Core);

            // Each hook in its own @try so one failure doesn't kill the rest
            @try { %init(FPSUnlockDisplay); } @catch (NSException *e) { NSLog(@"[XRD] FPSUnlockDisplay failed: %@", e); }

            if (objc_getClass("GameplayWidget"))
                @try { %init(GameplayCapture); } @catch (NSException *e) { NSLog(@"[XRD] GameplayCapture failed: %@", e); }

            if (objc_getClass("GameplaySettings"))
                @try { %init(ZoomHack); } @catch (NSException *e) { NSLog(@"[XRD] ZoomHack failed: %@", e); }

            if (objc_getClass("AgarCell"))
                @try { %init(CellMassOverlay); } @catch (NSException *e) { NSLog(@"[XRD] CellMassOverlay failed: %@", e); }

            if (objc_getClass("ScoreWidget") || objc_getClass("BaseArenaState"))
                @try { %init(MassDisplay); } @catch (NSException *e) { NSLog(@"[XRD] MassDisplay failed: %@", e); }

            if (objc_getClass("AgarCellView"))
                @try { %init(EnemyMassRenderer); } @catch (NSException *e) { NSLog(@"[XRD] EnemyMassRenderer failed: %@", e); }

            if (objc_getClass("UserWallet"))
                @try { %init(SkinUnlock); } @catch (NSException *e) { NSLog(@"[XRD] SkinUnlock failed: %@", e); }

            if (objc_getClass("ContinueGame"))
                @try { %init(AutoContinue); } @catch (NSException *e) { NSLog(@"[XRD] AutoContinue failed: %@", e); }

            if (objc_getClass("BaseArenaView"))
                @try { %init(FPSUnlock); } @catch (NSException *e) { NSLog(@"[XRD] FPSUnlock failed: %@", e); }

            if (objc_getClass("AgarCellView") || objc_getClass("SoftBodyCellView"))
                @try { %init(FastMode); } @catch (NSException *e) { NSLog(@"[XRD] FastMode failed: %@", e); }

            if (objc_getClass("BaseArenaState"))
                @try { %init(DarkMode); } @catch (NSException *e) { NSLog(@"[XRD] DarkMode failed: %@", e); }

            if (objc_getClass("BaseArenaState"))
                @try { %init(GridAndBorderHide); } @catch (NSException *e) { NSLog(@"[XRD] GridAndBorderHide failed: %@", e); }

            if (objc_getClass("FriendTrackerWidget"))
                @try { %init(FriendTrackerHide); } @catch (NSException *e) { NSLog(@"[XRD] FriendTrackerHide failed: %@", e); }

            if (objc_getClass("CollectibleCounterWidget"))
                @try { %init(TokenCounterHide); } @catch (NSException *e) { NSLog(@"[XRD] TokenCounterHide failed: %@", e); }

            if (objc_getClass("OnlineArenaState"))
                @try { %init(ServerLoader); } @catch (NSException *e) { NSLog(@"[XRD] ServerLoader failed: %@", e); }

            if (objc_getClass("UserInfo"))
                @try { %init(UserCapture); } @catch (NSException *e) { NSLog(@"[XRD] UserCapture failed: %@", e); }

            if (objc_getClass("OnlineArenaState"))
                @try { %init(ConnectionInterceptor); } @catch (NSException *e) { NSLog(@"[XRD] ConnectionInterceptor failed: %@", e); }

            @try { %init(WebSocketCapture); } @catch (NSException *e) { NSLog(@"[XRD] WebSocketCapture failed: %@", e); }

            if (objc_getClass("FriendTrackerWidget") || objc_getClass("LeaderboardWidget"))
                @try { %init(VisualMods); } @catch (NSException *e) { NSLog(@"[XRD] VisualMods failed: %@", e); }

            NSLog(@"[XRD] All hook groups initialized");

            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                    static dispatch_once_t menuOnce;
                    dispatch_once(&menuOnce, ^{
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            @try {
                                UIWindow *window = nil;
                                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                                    if ([scene isKindOfClass:[UIWindowScene class]]) {
                                        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                                            if (w.isKeyWindow) { window = w; break; }
                                        }
                                        if (window) break;
                                    }
                                }
                                if (!window) {
                                    for (UIWindow *w in [UIApplication sharedApplication].windows) {
                                        if (w.isKeyWindow) { window = w; break; }
                                    }
                                }
                                if (!window) {
                                    NSArray *windows = [UIApplication sharedApplication].windows;
                                    if (windows.count > 0) window = windows[0];
                                }
                                if (window) {
                                    [[XRDMenuController shared] setupWithWindow:window];
                                    NSLog(@"[XRD] Native menu initialized on window: %@", window);
                                } else {
                                    NSLog(@"[XRD] No window found for menu");
                                }
                            } @catch (NSException *e) {
                                NSLog(@"[XRD] Menu setup failed: %@", e);
                            }
                        });
                    });
                }];

        } @catch (NSException *e) {
            NSLog(@"[XRD] FATAL: Hook init failed: %@ — %@", e.name, e.reason);
        }
    }
}
