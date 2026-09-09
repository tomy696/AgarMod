// AgarIO.h — Reconstructed game class headers from reverse engineering
// Agar.io v26.6.0 (iOS, arm64)
// These headers are minimal declarations for Cydia Substrate hooking

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

// ============================================================================
// FORWARD DECLARATIONS
// ============================================================================

@class AgarCell, AgarCellView, SoftBodyCellView, PlayerAvatar;
@class GameplaySettings, BaseArenaState, OnlineArenaState;
@class MenuMain, MenuPause, MenuRegionSelector, MenuSettingsNode;
@class ScoreWidget, ControlsWidget, ConnectionStatusWidget;
@class StateMachine, UserInfo, UserWallet;
@class LeaderboardWidget, FriendTrackerWidget;
@class CollectibleCounterWidget;

// ============================================================================
// AgarCell — Main cell entity
// ============================================================================

@interface AgarCell : NSObject
@property (nonatomic, assign) float mass;
@property (nonatomic, assign) float radius;
@property (nonatomic, assign) float x;
@property (nonatomic, assign) float y;
@property (nonatomic, assign) BOOL isVirus;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *skinId;
@property (nonatomic, assign) unsigned int ownerId;
@property (nonatomic, assign) unsigned int cellId;

- (instancetype)initWithCellState:(id)state name:(NSString *)name isPartyCell:(BOOL)isParty;
- (instancetype)initWithCellState:(id)state name:(NSString *)name isShopCell:(BOOL)isShop;
- (instancetype)initWithCellState:(id)state name:(NSString *)name isShopCell:(BOOL)isShop isPartyCell:(BOOL)isParty isSkinEditorCell:(BOOL)isSkinEditor isSoloLevellingCell:(BOOL)isSolo;
- (void)setupSkinWithId:(NSString *)skinId isShopCell:(BOOL)isShop;
- (BOOL)attemptSetMysterySkinWithName:(NSString *)name hasTemporarySkin:(BOOL)hasTmp;
- (BOOL)isArenaToken;
- (void)maybeSetupArenaTokenSkins;
@end

// ============================================================================
// AgarCellView — Cell rendering view
// ============================================================================

@interface AgarCellView : NSObject
@property (nonatomic, strong) AgarCell *cell;
@property (nonatomic, assign) float targetRadius;
- (void)draw;
- (void)setIsSimpleDraw:(BOOL)simple;
- (void)addImage:(UIImage *)image;
@end

// ============================================================================
// SoftBodyCellView — Soft-body physics cell rendering
// ============================================================================

@interface SoftBodyCellView : NSObject
- (void)draw;
@end

// ============================================================================
// GameplaySettings — Core game settings singleton
// ============================================================================

@interface GameplaySettings : NSObject

+ (instancetype)sharedGameplaySettings;
+ (void)releaseSharedGameplaySettings;
+ (BOOL)isGameplaySettingsInitialized;

- (float)calculateZoom:(float)mass cellAmount:(int)cellAmount;
- (float)getScaleFactorForNumberOfCells:(int)count;
- (float)getMaxScaleFactorForNumberOfCells:(int)count;
- (float)calculatePhoneRatioForZoom;

@property (nonatomic, assign) float zoomMultiplier;
@property (nonatomic, assign) float variableZoomBase;
@property (nonatomic, assign) float variableZoomAmplitude;
@property (nonatomic, assign) float variableZoomDecay;
@property (nonatomic, assign) float cameraPositionSnapRate;
@property (nonatomic, assign) float cameraScaleSnapRate;
@property (nonatomic, assign) float scaleFactorForEating;
@property (nonatomic, assign) float scaleFactorForMergingBack;

@property (nonatomic, assign) float baseRadius;
@property (nonatomic, assign) float maxCellRadius;
@property (nonatomic, assign) float halfSizeForSplitting;
@property (nonatomic, assign) float respawnMass;
@property (nonatomic, assign) int maxNumberOfCellsPerOwnerId;
@property (nonatomic, assign) float onSplitVelocity;
@property (nonatomic, assign) float onShootFoodVelocity;

@property (nonatomic, assign) float minDPadRadiusFactor;
@property (nonatomic, assign) float angleToSendDirection;
@property (nonatomic, assign) float timeToSendDirection;

@property (nonatomic, assign) float minSizeViewportForBots;
@property (nonatomic, assign) float maxSizeViewportForBots;
@property (nonatomic, assign) int leaderboardSize;
@property (nonatomic, assign) int partyCodeLength;

@end

// ============================================================================
// BaseArenaState / OnlineArenaState — Game state managers
// ============================================================================

@interface BaseArenaState : NSObject

@property (nonatomic, assign) float cameraX;
@property (nonatomic, assign) float cameraY;
@property (nonatomic, assign) float cameraScale;
@property (nonatomic, assign) BOOL drawNextCameraFrame;
@property (nonatomic, readonly) float mCameraPositionSnapRate;
@property (nonatomic, readonly) float mCameraScaleSnapRate;
@property (nonatomic, readonly) float mMinRadiusToSplit;
@property (nonatomic, readonly) int mMaxPlayerCells;
@property (nonatomic, assign) CGRect viewport;
@property (nonatomic, assign) CGRect viewportBounds;

- (void)onEnter;
- (void)onExit;
- (void)onDeath;
- (void)update:(float)dt;
- (void)setupWithGameType:(int)gameType;
- (void)setupHudAndAddToView;
- (void)processGameArenaState:(id)state updateRate:(float)rate;
- (void)sendGameLeave;
- (void)handleCellsAppeared:(id)cells UpdateRate:(float)rate;
- (void)handleCellsChanged:(id)cells UpdateRate:(float)rate;
- (void)handleCellsDied:(id)cells;
- (void)handleCellsDisappeared:(id)cells;
- (void)setupNetworkCallbacks;
- (void)registerForNetworkMessages;

- (void)setCameraScale:(float)scale;
- (void)setInitialCameraScale;
- (void)updateZoom:(float)dt;
- (void)resetToInitialZoom;
- (void)onCameraChanged:(float)x scale:(float)scale;
- (void)updateCameraTarget:(float)dt;
- (void)jumpCameraTo:(CGPoint)position;
- (void)updateViewportPosition;

- (float)totalPlayerMass;
- (void)updateMassLabel;

- (void)updateLeaderboard:(id)data;

- (void)sendDirection:(id)direction;
- (void)sendDirectionTCP:(id)direction;
- (void)sendDirectionUDP:(id)direction;
- (void)onNewDirection:(id)direction priority:(int)priority;

@end

@interface OnlineArenaState : BaseArenaState
- (void)sendNetworkMessageEnterGame:(id)params;
- (void)prepareToEnterArena;
- (void)retryJoinArena;
- (void)closeAndLeaveArena;
- (void)onMovedToNewArena;
@end

@interface OnlineClassicArenaState : OnlineArenaState
@end

@interface BattleRoyaleArenaState : OnlineArenaState
@end

@interface RushArenaState : OnlineArenaState
@end

@interface BurstArenaState : OnlineArenaState
@end

// ============================================================================
// BaseArenaView — Arena rendering
// ============================================================================

@interface BaseArenaView : NSObject
@property (nonatomic, assign) CGRect viewportBounds;
- (void)framerateControl:(float)dt;
@end

// ============================================================================
// GameplayWidget — Game HUD
// ============================================================================

@interface GameplayWidget : NSObject
@property (nonatomic, strong) UIButton *splitButton;
@property (nonatomic, strong) UIButton *alternativeSplitButton;
- (void)splitPlayer;
- (void)shootMass;
- (void)updateButtons;
- (void)setup;
- (void)cleanup;
- (void)createJoystick;
- (void)onInputAxisChangedCallback:(id)callback priority:(int)priority;
@end

// ============================================================================
// ScoreWidget — Score display
// ============================================================================

@interface ScoreWidget : NSObject
- (void)showAndSetScore:(int)score;
- (void)initPlayerMassLabelWithMass:(float)mass;
@end

// ============================================================================
// ControlsWidget — Game controls
// ============================================================================

@interface ControlsWidget : NSObject
- (void)touchBegan:(id)touch point:(CGPoint)point shouldNotifyListeners:(BOOL)notify;
- (void)touchMoved:(id)touch point:(CGPoint)point;
- (void)touchEnded:(id)touch point:(CGPoint)point;
- (void)clearTouches;
- (void)setMinAngleVariationStep:(float)step;
- (float)aimMinAngleVariationStep;
- (float)aimMinVariationStep;
- (float)timeToSendTCPAxis;
@end

// ============================================================================
// Menu classes
// ============================================================================

@interface MenuMain : NSObject
- (void)playButtonCallback;
- (void)playClassicGame;
- (void)playBurstModeGame;
- (void)playOfflineZenGame;
- (void)tabButtonCallback;
@end

@interface MenuPause : NSObject
@end

@interface MenuRegionSelector : NSObject
- (void)changeRegion;
@end

@interface MenuSettingsNode : NSObject
@end

@interface MenuShopSkinsNode : NSObject
@end

@interface MenuShopSkinsView : NSObject
@end

// ============================================================================
// Party system
// ============================================================================

@interface ContentPartyCreatedOrJoinedView : NSObject
- (void)setupLayoutWithPartyCode:(NSString *)code isFacebookAccount:(BOOL)isFB subtitle:(NSString *)subtitle;
@end

// ============================================================================
// StateMachine — Game state machine
// ============================================================================

@interface StateMachine : NSObject
- (void)startClassicMode:(id)params;
- (void)startRushMode;
- (void)sendNetworkMessageEnterGame:(id)params;
- (void)prepareLoadingScreen;
- (id)instanceOfStateOnTop;
- (id)currentStateInstance;
- (BOOL)isInArena;
@end

// ============================================================================
// ContinueGame
// ============================================================================

@interface ContinueGame : NSObject
- (void)showContinuePopupWithMass:(float)mass keep:(float)keep customData:(id)data;
@end

// ============================================================================
// Player / User
// ============================================================================

@interface PlayerAvatar : NSObject
@end

@interface UserInfo : NSObject
@property (nonatomic, strong) NSString *userId;
@property (nonatomic, assign) BOOL isPayingUser;
- (id)account;
@end

@interface UserWallet : NSObject
- (BOOL)isProductActivated:(NSString *)productId;
- (int)quantityOwnedOf:(NSString *)productId;
@end

// ============================================================================
// Leaderboard / Friends
// ============================================================================

@interface LeaderboardWidget : NSObject
- (void)updateLeaderboard:(id)data;
@end

@interface FriendTrackerWidget : NSObject
- (void)trackClosestFriend;
@end

// ============================================================================
// ConnectionStatusWidget
// ============================================================================

@interface ConnectionStatusWidget : NSObject
@end

// ============================================================================
// CollectibleCounterWidget
// ============================================================================

@interface CollectibleCounterWidget : NSObject
@end

// ============================================================================
// AppDelegate
// ============================================================================

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

// ============================================================================
// Cocos2d helpers (used by the game engine)
// ============================================================================

@interface CCNode : NSObject
@property (nonatomic, assign) CGPoint position;
@property (nonatomic, assign) CGSize contentSize;
@property (nonatomic, assign) CGPoint anchorPoint;
@property (nonatomic, assign) NSInteger tag;
- (void)setColor:(id)color;
- (void)addChild:(id)child;
- (void)addChild:(id)child z:(int)z;
- (id)parent;
- (void)setVisible:(BOOL)visible;
@end

@interface CCSprite : CCNode
+ (instancetype)spriteWithSpriteFrameName:(NSString *)name textureFilename:(NSString *)filename;
- (id)displayFrame;
- (void)setDisplayFrame:(id)frame;
@end

@interface CCLabelTTF : CCNode
- (void)setFontName:(NSString *)name;
- (void)setAnchorPoint:(CGPoint)anchor;
@end

@interface CCTextureCache : NSObject
@end

// ============================================================================
// Offline Mode Manager (C++ - ObjC bridge)
// ============================================================================

@interface OfflineModeManager : NSObject
@end

// ============================================================================
// Skin Editor
// ============================================================================

@interface UserCustomSkins : NSObject
@end

@interface SkinEditor : NSObject
@end
