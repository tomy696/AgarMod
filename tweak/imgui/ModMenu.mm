// ModMenu.mm
// Mod menu UI built with Dear ImGui.
// Draws tabbed interface with Player, Visuals, Bots, Macros, Settings tabs.
// All state is read/written via the agmod_* C API defined in Tweak.xm.

#import "ModMenu.h"
#import "imgui.h"

#import <Foundation/Foundation.h>

// ============================================================================
// Local text input buffers (synced from/to Tweak.xm via agmod API)
// ============================================================================

static char s_botServerURL[256]  = "";
static char s_botSecretKey[128]  = "";
static char s_botName[64]        = "";
static char s_targetServerIP[128]= "";
static bool s_buffersInitialized = false;

static int  s_currentTab     = 0;

static const char* kBotModes[] = {
    "Move", "Feed", "Farm", "MakeVirus", "BreakVirus", "Teamer"
};

static const char* kZoomModes[] = {
    "Dynamic", "Stable", "Speed"
};

static void SyncBuffersFromAPI() {
    if (s_buffersInitialized) return;

    NSString *url = agmod_getBotServerURL();
    if (url) strncpy(s_botServerURL, [url UTF8String], sizeof(s_botServerURL) - 1);

    NSString *key = agmod_getBotSecretKey();
    if (key) strncpy(s_botSecretKey, [key UTF8String], sizeof(s_botSecretKey) - 1);

    NSString *name = agmod_getBotName();
    if (name) strncpy(s_botName, [name UTF8String], sizeof(s_botName) - 1);

    NSString *ip = agmod_getTargetServerIP();
    if (ip) strncpy(s_targetServerIP, [ip UTF8String], sizeof(s_targetServerIP) - 1);

    s_buffersInitialized = true;
}

// ============================================================================
// Custom ImGui Style
// ============================================================================

void ModMenu::ApplyCustomStyle() {
    ImGuiStyle& style = ImGui::GetStyle();

    style.WindowRounding    = 8.0f;
    style.FrameRounding     = 4.0f;
    style.GrabRounding      = 4.0f;
    style.TabRounding       = 4.0f;
    style.ChildRounding     = 4.0f;
    style.PopupRounding     = 4.0f;
    style.ScrollbarRounding = 4.0f;

    style.WindowPadding    = ImVec2(12.0f, 12.0f);
    style.FramePadding     = ImVec2(8.0f, 4.0f);
    style.ItemSpacing      = ImVec2(8.0f, 6.0f);
    style.ItemInnerSpacing = ImVec2(6.0f, 4.0f);
    style.IndentSpacing    = 20.0f;
    style.ScrollbarSize    = 12.0f;
    style.GrabMinSize      = 10.0f;

    style.WindowBorderSize = 1.0f;
    style.ChildBorderSize  = 0.0f;
    style.FrameBorderSize  = 0.0f;
    style.TabBorderSize    = 0.0f;
    style.Alpha            = 1.0f;

    ImVec4* colors = style.Colors;

    ImVec4 bgColor      = ImVec4(0.059f, 0.059f, 0.059f, 0.92f);
    ImVec4 accentColor  = ImVec4(0.000f, 0.898f, 1.000f, 1.00f);
    ImVec4 accentDim    = ImVec4(0.000f, 0.698f, 0.800f, 1.00f);
    ImVec4 accentDark   = ImVec4(0.000f, 0.500f, 0.600f, 1.00f);
    ImVec4 textColor    = ImVec4(0.950f, 0.950f, 0.950f, 1.00f);
    ImVec4 textDim      = ImVec4(0.600f, 0.600f, 0.600f, 1.00f);
    ImVec4 frameBg      = ImVec4(0.100f, 0.100f, 0.100f, 1.00f);
    ImVec4 frameBgHover = ImVec4(0.150f, 0.150f, 0.150f, 1.00f);

    colors[ImGuiCol_Text]                  = textColor;
    colors[ImGuiCol_TextDisabled]          = textDim;
    colors[ImGuiCol_WindowBg]              = bgColor;
    colors[ImGuiCol_ChildBg]               = ImVec4(0.0f, 0.0f, 0.0f, 0.0f);
    colors[ImGuiCol_PopupBg]               = ImVec4(0.08f, 0.08f, 0.08f, 0.94f);
    colors[ImGuiCol_Border]                = ImVec4(0.20f, 0.20f, 0.20f, 0.50f);
    colors[ImGuiCol_BorderShadow]          = ImVec4(0.0f, 0.0f, 0.0f, 0.0f);
    colors[ImGuiCol_FrameBg]               = frameBg;
    colors[ImGuiCol_FrameBgHovered]        = frameBgHover;
    colors[ImGuiCol_FrameBgActive]         = ImVec4(0.18f, 0.18f, 0.18f, 1.0f);
    colors[ImGuiCol_TitleBg]               = ImVec4(0.04f, 0.04f, 0.04f, 1.0f);
    colors[ImGuiCol_TitleBgActive]         = ImVec4(0.04f, 0.04f, 0.04f, 1.0f);
    colors[ImGuiCol_TitleBgCollapsed]      = ImVec4(0.04f, 0.04f, 0.04f, 0.5f);
    colors[ImGuiCol_MenuBarBg]             = ImVec4(0.08f, 0.08f, 0.08f, 1.0f);
    colors[ImGuiCol_ScrollbarBg]           = ImVec4(0.05f, 0.05f, 0.05f, 0.5f);
    colors[ImGuiCol_ScrollbarGrab]         = ImVec4(0.25f, 0.25f, 0.25f, 1.0f);
    colors[ImGuiCol_ScrollbarGrabHovered]  = ImVec4(0.35f, 0.35f, 0.35f, 1.0f);
    colors[ImGuiCol_ScrollbarGrabActive]   = ImVec4(0.45f, 0.45f, 0.45f, 1.0f);
    colors[ImGuiCol_CheckMark]             = accentColor;
    colors[ImGuiCol_SliderGrab]            = accentDim;
    colors[ImGuiCol_SliderGrabActive]      = accentColor;
    colors[ImGuiCol_Button]                = ImVec4(0.15f, 0.15f, 0.15f, 1.0f);
    colors[ImGuiCol_ButtonHovered]         = accentDark;
    colors[ImGuiCol_ButtonActive]          = accentDim;
    colors[ImGuiCol_Header]                = ImVec4(0.15f, 0.15f, 0.15f, 1.0f);
    colors[ImGuiCol_HeaderHovered]         = accentDark;
    colors[ImGuiCol_HeaderActive]          = accentDim;
    colors[ImGuiCol_Separator]             = ImVec4(0.20f, 0.20f, 0.20f, 0.50f);
    colors[ImGuiCol_SeparatorHovered]      = accentDim;
    colors[ImGuiCol_SeparatorActive]       = accentColor;
    colors[ImGuiCol_ResizeGrip]            = ImVec4(0.20f, 0.20f, 0.20f, 0.25f);
    colors[ImGuiCol_ResizeGripHovered]     = accentDim;
    colors[ImGuiCol_ResizeGripActive]      = accentColor;
    colors[ImGuiCol_Tab]                   = ImVec4(0.10f, 0.10f, 0.10f, 1.0f);
    colors[ImGuiCol_TabHovered]            = accentDark;
    colors[ImGuiCol_TabActive]             = accentDim;
    colors[ImGuiCol_TabUnfocused]          = ImVec4(0.08f, 0.08f, 0.08f, 1.0f);
    colors[ImGuiCol_TabUnfocusedActive]    = ImVec4(0.12f, 0.12f, 0.12f, 1.0f);
    colors[ImGuiCol_PlotLines]             = accentColor;
    colors[ImGuiCol_PlotLinesHovered]      = accentColor;
    colors[ImGuiCol_PlotHistogram]         = accentColor;
    colors[ImGuiCol_PlotHistogramHovered]  = accentColor;
    colors[ImGuiCol_TableHeaderBg]         = ImVec4(0.12f, 0.12f, 0.12f, 1.0f);
    colors[ImGuiCol_TableBorderStrong]     = ImVec4(0.20f, 0.20f, 0.20f, 1.0f);
    colors[ImGuiCol_TableBorderLight]      = ImVec4(0.15f, 0.15f, 0.15f, 1.0f);
    colors[ImGuiCol_TableRowBg]            = ImVec4(0.0f, 0.0f, 0.0f, 0.0f);
    colors[ImGuiCol_TableRowBgAlt]         = ImVec4(1.0f, 1.0f, 1.0f, 0.02f);
    colors[ImGuiCol_TextSelectedBg]        = ImVec4(accentColor.x, accentColor.y, accentColor.z, 0.35f);
    colors[ImGuiCol_DragDropTarget]        = accentColor;
    colors[ImGuiCol_NavHighlight]          = accentColor;
    colors[ImGuiCol_NavWindowingHighlight] = ImVec4(1.0f, 1.0f, 1.0f, 0.70f);
    colors[ImGuiCol_NavWindowingDimBg]     = ImVec4(0.8f, 0.8f, 0.8f, 0.20f);
    colors[ImGuiCol_ModalWindowDimBg]      = ImVec4(0.0f, 0.0f, 0.0f, 0.60f);
}

// ============================================================================
// Helper: styled checkbox with accent highlight when checked
// ============================================================================

static bool StyledCheckbox(const char* label, bool value) {
    bool v = value;
    if (v) {
        ImGui::PushStyleColor(ImGuiCol_FrameBg,        ImVec4(0.0f, 0.45f, 0.55f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_FrameBgHovered,  ImVec4(0.0f, 0.55f, 0.65f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_FrameBgActive,   ImVec4(0.0f, 0.65f, 0.75f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_CheckMark,       ImVec4(0.0f, 0.898f, 1.0f, 1.0f));
    }

    bool changed = ImGui::Checkbox(label, &v);

    if (value) {
        ImGui::PopStyleColor(4);
    }

    if (changed) return true;
    return false;
}

// ============================================================================
// Tab: Player
// ============================================================================

static void DrawPlayerTab() {
    ImGui::Spacing();

    // Zoom hack
    bool zoom = agmod_isZoomEnabled();
    if (StyledCheckbox(ICON_FA_EYE " Zoom Hack", zoom)) {
        agmod_setZoomEnabled(!zoom);
        zoom = !zoom;
    }

    if (zoom) {
        ImGui::Indent(20.0f);

        int mode = agmod_getZoomMode();
        ImGui::Text("Mode:");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
        if (ImGui::Combo("##ZoomMode", &mode, kZoomModes, IM_ARRAYSIZE(kZoomModes))) {
            agmod_setZoomMode(mode);
        }

        float flex = agmod_getFlexZoom();
        ImGui::Text("Flex Zoom:");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
        if (ImGui::SliderFloat("##FlexZoom", &flex, 0.1f, 5.0f, "%.1f")) {
            agmod_setFlexZoom(flex);
        }

        ImGui::Unindent(20.0f);
    }

    ImGui::Separator();

    bool autoCont = agmod_isAutoContinue();
    if (StyledCheckbox(ICON_FA_PLAY " Auto-Continue", autoCont)) {
        agmod_setAutoContinue(!autoCont);
    }

    bool skins = agmod_isUnlockAllSkins();
    if (StyledCheckbox(ICON_FA_USER " Unlock All Skins", skins)) {
        agmod_setUnlockAllSkins(!skins);
    }

    bool fps = agmod_isUnlockFPS();
    if (StyledCheckbox(ICON_FA_BOLT " FPS Unlock (120fps)", fps)) {
        agmod_setUnlockFPS(!fps);
    }
}

// ============================================================================
// Tab: Visuals
// ============================================================================

static void DrawVisualsTab() {
    ImGui::Spacing();

    bool dark = agmod_isDarkMode();
    if (StyledCheckbox("Dark Mode", dark)) {
        agmod_setDarkMode(!dark);
    }

    bool fast = agmod_isFastMode();
    if (StyledCheckbox("Fast Mode (Simple Draw)", fast)) {
        agmod_setFastMode(!fast);
    }

    ImGui::Separator();

    bool mass = agmod_isShowEnemyMass();
    if (StyledCheckbox("Show Enemy Mass", mass)) {
        agmod_setShowEnemyMass(!mass);
    }

    ImGui::Separator();
    ImGui::TextColored(ImVec4(0.6f, 0.6f, 0.6f, 1.0f), "Hide Elements:");

    bool grid = agmod_isHideGrid();
    if (StyledCheckbox("Grid", grid)) {
        agmod_setHideGrid(!grid);
    }

    bool borders = agmod_isHideBorders();
    if (StyledCheckbox("Borders", borders)) {
        agmod_setHideBorders(!borders);
    }

    bool friends = agmod_isHideFriendTracker();
    if (StyledCheckbox("Friend Tracker", friends)) {
        agmod_setHideFriendTracker(!friends);
    }

    bool tokens = agmod_isHideTokenCounter();
    if (StyledCheckbox("Token Counter", tokens)) {
        agmod_setHideTokenCounter(!tokens);
    }
}

// ============================================================================
// Tab: Bots
// ============================================================================

static void DrawBotsTab() {
    ImGui::Spacing();

    ImGui::Text("Server URL:");
    ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
    if (ImGui::InputText("##BotServerURL", s_botServerURL, sizeof(s_botServerURL))) {
        agmod_setBotServerURL([NSString stringWithUTF8String:s_botServerURL]);
    }

    ImGui::Text("Secret Key:");
    ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
    if (ImGui::InputText("##BotSecretKey", s_botSecretKey, sizeof(s_botSecretKey),
                         ImGuiInputTextFlags_Password)) {
        agmod_setBotSecretKey([NSString stringWithUTF8String:s_botSecretKey]);
    }

    ImGui::Text("Bot Name:");
    ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
    if (ImGui::InputText("##BotName", s_botName, sizeof(s_botName))) {
        agmod_setBotName([NSString stringWithUTF8String:s_botName]);
    }

    ImGui::Separator();

    int botMode = agmod_getBotMode();
    ImGui::Text("Bot Mode:");
    ImGui::SameLine();
    ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
    if (ImGui::Combo("##BotMode", &botMode, kBotModes, IM_ARRAYSIZE(kBotModes))) {
        agmod_setBotMode(botMode);
    }

    ImGui::Separator();

    float buttonWidth = ImGui::GetContentRegionAvail().x;
    bool running = agmod_isBotsRunning();

    if (running) {
        ImGui::PushStyleColor(ImGuiCol_Button,         ImVec4(0.6f, 0.1f, 0.1f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered,   ImVec4(0.7f, 0.15f, 0.15f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive,    ImVec4(0.8f, 0.2f, 0.2f, 1.0f));

        if (ImGui::Button(ICON_FA_STOP " Stop Bots", ImVec2(buttonWidth, 36.0f))) {
            agmod_stopBots();
        }

        ImGui::PopStyleColor(3);
    } else {
        ImGui::PushStyleColor(ImGuiCol_Button,         ImVec4(0.0f, 0.45f, 0.55f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered,   ImVec4(0.0f, 0.55f, 0.65f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive,    ImVec4(0.0f, 0.65f, 0.75f, 1.0f));

        if (ImGui::Button(ICON_FA_PLAY " Start Bots", ImVec2(buttonWidth, 36.0f))) {
            agmod_startBots();
        }

        ImGui::PopStyleColor(3);
    }

    // Status
    ImGui::Spacing();
    ImGui::Separator();
    ImGui::TextColored(ImVec4(0.6f, 0.6f, 0.6f, 1.0f), "Status:");

    if (running) {
        ImGui::TextColored(ImVec4(0.0f, 1.0f, 0.4f, 1.0f),
                           ICON_FA_CHECK_CIRCLE " Connected");
        ImGui::Text("Mode: %s", kBotModes[agmod_getBotMode()]);

        NSString *serverIP = agmod_getCurrentServerIP();
        if (serverIP && serverIP.length > 0) {
            ImGui::Text("Server: %s", [serverIP UTF8String]);
        }

        NSString *party = agmod_getCurrentPartyCode();
        if (party && party.length > 0) {
            ImGui::Text("Party: %s", [party UTF8String]);
        }
    } else {
        ImGui::TextColored(ImVec4(0.6f, 0.6f, 0.6f, 1.0f),
                           ICON_FA_TIMES_CIRCLE " Disconnected");
    }
}

// ============================================================================
// Tab: Macros
// ============================================================================

static void DrawMacrosTab() {
    ImGui::Spacing();

    // Feed macro
    bool feedActive = agmod_isFeedMacroActive();
    if (StyledCheckbox(ICON_FA_BOLT " Feed Macro", feedActive)) {
        agmod_setFeedMacroActive(!feedActive);
        feedActive = !feedActive;
    }

    if (feedActive) {
        ImGui::Indent(20.0f);
        float feedRate = agmod_getFeedMacroRate();
        ImGui::Text("Rate (ms):");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
        if (ImGui::SliderFloat("##FeedRate", &feedRate, 10.0f, 200.0f, "%.0f")) {
            agmod_setFeedMacroRate(feedRate);
        }
        ImGui::Unindent(20.0f);
    }

    ImGui::Separator();

    // Split macro
    bool splitActive = agmod_isSplitMacroActive();
    if (StyledCheckbox(ICON_FA_BOLT " Split Macro", splitActive)) {
        agmod_setSplitMacroActive(!splitActive);
        splitActive = !splitActive;
    }

    if (splitActive) {
        ImGui::Indent(20.0f);
        float splitRate = agmod_getSplitMacroRate();
        ImGui::Text("Rate (ms):");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
        if (ImGui::SliderFloat("##SplitRate", &splitRate, 30.0f, 500.0f, "%.0f")) {
            agmod_setSplitMacroRate(splitRate);
        }
        ImGui::Unindent(20.0f);
    }
}

// ============================================================================
// Tab: Settings
// ============================================================================

static void DrawSettingsTab() {
    ImGui::Spacing();

    // Server loader
    bool serverLoader = agmod_isServerLoaderEnabled();
    if (StyledCheckbox("Server Loader", serverLoader)) {
        agmod_setServerLoaderEnabled(!serverLoader);
        serverLoader = !serverLoader;
    }

    if (serverLoader) {
        ImGui::Indent(20.0f);
        ImGui::Text("Target IP:");
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
        if (ImGui::InputText("##TargetIP", s_targetServerIP, sizeof(s_targetServerIP))) {
            agmod_setTargetServerIP([NSString stringWithUTF8String:s_targetServerIP]);
        }
        ImGui::Unindent(20.0f);
    }

    ImGui::Separator();
    ImGui::Spacing();

    // Save / Reset buttons
    float halfWidth = (ImGui::GetContentRegionAvail().x - ImGui::GetStyle().ItemSpacing.x) * 0.5f;

    ImGui::PushStyleColor(ImGuiCol_Button,         ImVec4(0.0f, 0.45f, 0.55f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered,   ImVec4(0.0f, 0.55f, 0.65f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive,    ImVec4(0.0f, 0.65f, 0.75f, 1.0f));

    if (ImGui::Button(ICON_FA_SAVE " Save", ImVec2(halfWidth, 32.0f))) {
        agmod_saveAllSettings();
    }

    ImGui::PopStyleColor(3);

    ImGui::SameLine();

    ImGui::PushStyleColor(ImGuiCol_Button,         ImVec4(0.45f, 0.10f, 0.10f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered,   ImVec4(0.55f, 0.15f, 0.15f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive,    ImVec4(0.65f, 0.20f, 0.20f, 1.0f));

    if (ImGui::Button(ICON_FA_UNDO " Reset", ImVec2(halfWidth, 32.0f))) {
        agmod_reloadSettings();
        s_buffersInitialized = false;
        SyncBuffersFromAPI();
    }

    ImGui::PopStyleColor(3);

    // Credits
    ImGui::Spacing();
    ImGui::Separator();
    ImGui::Spacing();

    ImGui::TextColored(ImVec4(0.5f, 0.5f, 0.5f, 1.0f), ICON_FA_INFO_CIRCLE " Credits");
    ImGui::TextColored(ImVec4(0.6f, 0.6f, 0.6f, 1.0f), "AgarMod v1.0.0");
    ImGui::TextColored(ImVec4(0.5f, 0.5f, 0.5f, 1.0f), "ImGui %s | Metal", ImGui::GetVersion());

    NSString *sid = agmod_getSessionId();
    if (sid && sid.length > 0) {
        ImGui::TextColored(ImVec4(0.4f, 0.4f, 0.4f, 1.0f), "Session: %.8s...", [sid UTF8String]);
    }
}

// ============================================================================
// Main Draw
// ============================================================================

void ModMenu::Draw() {
    SyncBuffersFromAPI();

    ImGuiIO& io = ImGui::GetIO();

    ImVec2 windowSize(320.0f, 450.0f);
    ImGui::SetNextWindowSize(windowSize, ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowPos(
        ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f),
        ImGuiCond_FirstUseEver,
        ImVec2(0.5f, 0.5f)
    );

    ImGuiWindowFlags windowFlags =
        ImGuiWindowFlags_NoCollapse |
        ImGuiWindowFlags_NoSavedSettings;

    ImGui::Begin("AgarMod", nullptr, windowFlags);

    if (ImGui::BeginTabBar("##ModTabs", ImGuiTabBarFlags_None)) {

        if (ImGui::BeginTabItem(ICON_FA_USER " Player")) {
            s_currentTab = 0;
            DrawPlayerTab();
            ImGui::EndTabItem();
        }

        if (ImGui::BeginTabItem(ICON_FA_EYE " Visuals")) {
            s_currentTab = 1;
            DrawVisualsTab();
            ImGui::EndTabItem();
        }

        if (ImGui::BeginTabItem(ICON_FA_ROBOT " Bots")) {
            s_currentTab = 2;
            DrawBotsTab();
            ImGui::EndTabItem();
        }

        if (ImGui::BeginTabItem(ICON_FA_BOLT " Macros")) {
            s_currentTab = 3;
            DrawMacrosTab();
            ImGui::EndTabItem();
        }

        if (ImGui::BeginTabItem(ICON_FA_COG " Settings")) {
            s_currentTab = 4;
            DrawSettingsTab();
            ImGui::EndTabItem();
        }

        ImGui::EndTabBar();
    }

    ImGui::End();
}
