// ModMenu.h
// Mod menu UI built with Dear ImGui.
// Draws all tabs (Player, Visuals, Bots, Macros, Settings).
// Uses the agmod_* C API from Tweak.xm for all state access.

#pragma once

#include "imgui.h"
#import <Foundation/Foundation.h>

// ============================================================================
// Font Awesome 5 icon codepoints used in tab headers
// ============================================================================
#define ICON_FA_USER            "\xef\x80\x87"   // U+F007
#define ICON_FA_EYE             "\xef\x81\xae"   // U+F06E
#define ICON_FA_ROBOT           "\xef\x95\x80"   // U+F544
#define ICON_FA_BOLT            "\xef\x82\xa7"   // U+F0E7
#define ICON_FA_COG             "\xef\x80\x93"   // U+F013
#define ICON_FA_PLAY            "\xef\x81\x8b"   // U+F04B
#define ICON_FA_STOP            "\xef\x81\x8d"   // U+F04D
#define ICON_FA_CHECK_CIRCLE    "\xef\x81\x98"   // U+F058
#define ICON_FA_TIMES_CIRCLE    "\xef\x81\x97"   // U+F057
#define ICON_FA_SAVE            "\xef\x83\x87"   // U+F0C7
#define ICON_FA_UNDO            "\xef\x83\xa2"   // U+F0E2
#define ICON_FA_INFO_CIRCLE     "\xef\x81\x9a"   // U+F05A
#define ICON_FA_CIRCLE          "\xef\x84\x91"   // U+F111
#define ICON_FA_CROSSHAIRS      "\xef\x81\x9b"   // U+F05B
#define ICON_FA_SEARCH_PLUS     "\xef\x80\x8e"   // U+F00E
#define ICON_FA_GAMEPAD         "\xef\x84\x9b"   // U+F11B
#define ICON_FA_REDO            "\xef\x80\x9e"   // U+F01E
#define ICON_FA_PALETTE         "\xef\x94\xbf"   // U+F53F
#define ICON_FA_TACHOMETER_ALT  "\xef\x8f\xbd"   // U+F3FD
#define ICON_FA_PAINT_BRUSH     "\xef\x87\xbc"   // U+F1FC
#define ICON_FA_MOON            "\xef\x86\x86"   // U+F186
#define ICON_FA_ROCKET          "\xef\x84\xb5"   // U+F135
#define ICON_FA_WEIGHT          "\xef\x92\x96"   // U+F496
#define ICON_FA_EYE_SLASH       "\xef\x81\xb0"   // U+F070
#define ICON_FA_SERVER          "\xef\x88\xb3"   // U+F233
#define ICON_FA_SIGNAL          "\xef\x80\x92"   // U+F012
#define ICON_FA_UTENSILS        "\xef\x8b\xa7"   // U+F2E7
#define ICON_FA_EXPAND_ARROWS_ALT "\xef\x8c\x9e" // U+F31E
#define ICON_FA_COMPRESS_ARROWS_ALT "\xef\x9c\x8c" // U+F78C
#define ICON_FA_NETWORK_WIRED   "\xef\x9b\xbf"   // U+F6FF
#define ICON_FA_PLUG            "\xef\x87\xa6"   // U+F1E6
#define ICON_FA_CODE            "\xef\x84\xa1"   // U+F121

// ============================================================================
// Tweak.xm C API — getters/setters for all mod state
// ============================================================================

extern "C" {

// Setters
void agmod_setZoomEnabled(BOOL enabled);
void agmod_setZoomMode(int mode);
void agmod_setFlexZoom(float value);
void agmod_setShowEnemyMass(BOOL enabled);
void agmod_setFeedMacroRate(float rateMs);
void agmod_setFeedMacroActive(BOOL active);
void agmod_setSplitMacroRate(float rateMs);
void agmod_setSplitMacroActive(BOOL active);
void agmod_setFastMode(BOOL enabled);
void agmod_setDarkMode(BOOL enabled);
void agmod_setUnlockAllSkins(BOOL enabled);
void agmod_setAutoContinue(BOOL enabled);
void agmod_setUnlockFPS(BOOL enabled);
void agmod_setServerLoaderEnabled(BOOL enabled);
void agmod_setTargetServerIP(NSString *ip);
void agmod_setBotServerURL(NSString *url);
void agmod_setBotSecretKey(NSString *key);
void agmod_setBotName(NSString *name);
void agmod_setBotMode(int mode);
void agmod_setModEnabled(BOOL enabled);
void agmod_setHideGrid(BOOL enabled);
void agmod_setHideBorders(BOOL enabled);
void agmod_setHideProfilePics(BOOL enabled);
void agmod_setHideFriendTracker(BOOL enabled);
void agmod_setHideTokenCounter(BOOL enabled);

// Actions
void agmod_startBots(void);
void agmod_stopBots(void);
void agmod_validateBotKey(void (^callback)(BOOL valid, NSString *msg));
void agmod_saveAllSettings(void);
void agmod_reloadSettings(void);

// Getters
BOOL     agmod_isModEnabled(void);
BOOL     agmod_isZoomEnabled(void);
int      agmod_getZoomMode(void);
float    agmod_getFlexZoom(void);
BOOL     agmod_isShowEnemyMass(void);
float    agmod_getFeedMacroRate(void);
float    agmod_getSplitMacroRate(void);
BOOL     agmod_isFeedMacroActive(void);
BOOL     agmod_isSplitMacroActive(void);
BOOL     agmod_isFastMode(void);
BOOL     agmod_isDarkMode(void);
BOOL     agmod_isUnlockAllSkins(void);
BOOL     agmod_isAutoContinue(void);
BOOL     agmod_isUnlockFPS(void);
BOOL     agmod_isServerLoaderEnabled(void);
NSString *agmod_getTargetServerIP(void);
NSString *agmod_getBotServerURL(void);
NSString *agmod_getBotSecretKey(void);
NSString *agmod_getBotName(void);
int      agmod_getBotMode(void);
BOOL     agmod_isBotsRunning(void);
NSString *agmod_getCurrentServerIP(void);
NSString *agmod_getCurrentPartyCode(void);
NSString *agmod_getSessionId(void);
BOOL     agmod_isHideGrid(void);
BOOL     agmod_isHideBorders(void);
BOOL     agmod_isHideProfilePics(void);
BOOL     agmod_isHideFriendTracker(void);
BOOL     agmod_isHideTokenCounter(void);

} // extern "C"

// ============================================================================
// Public API
// ============================================================================

namespace ModMenu {
    void ApplyCustomStyle();
    void Draw();
}
