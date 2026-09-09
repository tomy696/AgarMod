// ModMenu.mm — XRD Mod Menu
// Premium ImGui interface for Agar.io mod

#import "ModMenu.h"
#import "imgui.h"

#import <Foundation/Foundation.h>

// ============================================================================
// Local text input buffers
// ============================================================================

static char s_botServerURL[256]  = "";
static char s_botSecretKey[128]  = "";
static char s_botName[64]        = "";
static char s_targetServerIP[128]= "";
static bool s_buffersInitialized = false;

static int  s_currentTab     = 0;
static float s_headerPulse   = 0.0f;

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
// XRD Custom Style — Dark purple/violet theme
// ============================================================================

void ModMenu::ApplyCustomStyle() {
    ImGuiStyle& style = ImGui::GetStyle();

    style.WindowRounding    = 12.0f;
    style.FrameRounding     = 6.0f;
    style.GrabRounding      = 6.0f;
    style.TabRounding       = 8.0f;
    style.ChildRounding     = 8.0f;
    style.PopupRounding     = 6.0f;
    style.ScrollbarRounding = 6.0f;

    style.WindowPadding    = ImVec2(14.0f, 14.0f);
    style.FramePadding     = ImVec2(10.0f, 6.0f);
    style.ItemSpacing      = ImVec2(8.0f, 8.0f);
    style.ItemInnerSpacing = ImVec2(6.0f, 4.0f);
    style.IndentSpacing    = 20.0f;
    style.ScrollbarSize    = 10.0f;
    style.GrabMinSize      = 12.0f;

    style.WindowBorderSize = 1.0f;
    style.ChildBorderSize  = 1.0f;
    style.FrameBorderSize  = 0.0f;
    style.TabBorderSize    = 0.0f;
    style.Alpha            = 1.0f;

    ImVec4* c = style.Colors;

    // XRD palette — deep purple with violet accents
    ImVec4 bg       = ImVec4(0.06f, 0.04f, 0.10f, 0.95f);
    ImVec4 bgChild  = ImVec4(0.08f, 0.06f, 0.14f, 0.60f);
    ImVec4 accent   = ImVec4(0.55f, 0.30f, 1.00f, 1.00f);  // violet
    ImVec4 accentLt = ImVec4(0.70f, 0.45f, 1.00f, 1.00f);
    ImVec4 accentDk = ImVec4(0.40f, 0.20f, 0.75f, 1.00f);
    ImVec4 text     = ImVec4(0.95f, 0.93f, 1.00f, 1.00f);
    ImVec4 textDim  = ImVec4(0.55f, 0.50f, 0.65f, 1.00f);
    ImVec4 frame    = ImVec4(0.10f, 0.08f, 0.18f, 1.00f);
    ImVec4 frameHov = ImVec4(0.14f, 0.10f, 0.24f, 1.00f);
    ImVec4 border   = ImVec4(0.25f, 0.18f, 0.40f, 0.50f);

    c[ImGuiCol_Text]                  = text;
    c[ImGuiCol_TextDisabled]          = textDim;
    c[ImGuiCol_WindowBg]              = bg;
    c[ImGuiCol_ChildBg]               = bgChild;
    c[ImGuiCol_PopupBg]               = ImVec4(0.08f, 0.06f, 0.14f, 0.96f);
    c[ImGuiCol_Border]                = border;
    c[ImGuiCol_BorderShadow]          = ImVec4(0.0f, 0.0f, 0.0f, 0.0f);
    c[ImGuiCol_FrameBg]               = frame;
    c[ImGuiCol_FrameBgHovered]        = frameHov;
    c[ImGuiCol_FrameBgActive]         = ImVec4(0.18f, 0.14f, 0.30f, 1.0f);
    c[ImGuiCol_TitleBg]               = ImVec4(0.04f, 0.03f, 0.08f, 1.0f);
    c[ImGuiCol_TitleBgActive]         = ImVec4(0.06f, 0.04f, 0.12f, 1.0f);
    c[ImGuiCol_TitleBgCollapsed]      = ImVec4(0.04f, 0.03f, 0.08f, 0.5f);
    c[ImGuiCol_MenuBarBg]             = ImVec4(0.08f, 0.06f, 0.12f, 1.0f);
    c[ImGuiCol_ScrollbarBg]           = ImVec4(0.05f, 0.04f, 0.08f, 0.5f);
    c[ImGuiCol_ScrollbarGrab]         = ImVec4(0.25f, 0.20f, 0.35f, 1.0f);
    c[ImGuiCol_ScrollbarGrabHovered]  = ImVec4(0.35f, 0.28f, 0.50f, 1.0f);
    c[ImGuiCol_ScrollbarGrabActive]   = accent;
    c[ImGuiCol_CheckMark]             = accent;
    c[ImGuiCol_SliderGrab]            = accentDk;
    c[ImGuiCol_SliderGrabActive]      = accent;
    c[ImGuiCol_Button]                = ImVec4(0.14f, 0.10f, 0.24f, 1.0f);
    c[ImGuiCol_ButtonHovered]         = accentDk;
    c[ImGuiCol_ButtonActive]          = accent;
    c[ImGuiCol_Header]                = ImVec4(0.14f, 0.10f, 0.24f, 1.0f);
    c[ImGuiCol_HeaderHovered]         = accentDk;
    c[ImGuiCol_HeaderActive]          = accent;
    c[ImGuiCol_Separator]             = border;
    c[ImGuiCol_SeparatorHovered]      = accentDk;
    c[ImGuiCol_SeparatorActive]       = accent;
    c[ImGuiCol_ResizeGrip]            = ImVec4(0.20f, 0.15f, 0.30f, 0.25f);
    c[ImGuiCol_ResizeGripHovered]     = accentDk;
    c[ImGuiCol_ResizeGripActive]      = accent;
    c[ImGuiCol_Tab]                   = ImVec4(0.10f, 0.08f, 0.18f, 1.0f);
    c[ImGuiCol_TabHovered]            = accentDk;
    c[ImGuiCol_TabActive]             = accent;
    c[ImGuiCol_TabUnfocused]          = ImVec4(0.08f, 0.06f, 0.12f, 1.0f);
    c[ImGuiCol_TabUnfocusedActive]    = ImVec4(0.14f, 0.10f, 0.24f, 1.0f);
    c[ImGuiCol_PlotLines]             = accent;
    c[ImGuiCol_PlotLinesHovered]      = accentLt;
    c[ImGuiCol_PlotHistogram]         = accent;
    c[ImGuiCol_PlotHistogramHovered]  = accentLt;
    c[ImGuiCol_TableHeaderBg]         = ImVec4(0.10f, 0.08f, 0.18f, 1.0f);
    c[ImGuiCol_TableBorderStrong]     = border;
    c[ImGuiCol_TableBorderLight]      = ImVec4(0.15f, 0.12f, 0.25f, 1.0f);
    c[ImGuiCol_TableRowBg]            = ImVec4(0.0f, 0.0f, 0.0f, 0.0f);
    c[ImGuiCol_TableRowBgAlt]         = ImVec4(1.0f, 1.0f, 1.0f, 0.02f);
    c[ImGuiCol_TextSelectedBg]        = ImVec4(accent.x, accent.y, accent.z, 0.35f);
    c[ImGuiCol_DragDropTarget]        = accent;
    c[ImGuiCol_NavHighlight]          = accent;
    c[ImGuiCol_NavWindowingHighlight] = ImVec4(1.0f, 1.0f, 1.0f, 0.70f);
    c[ImGuiCol_NavWindowingDimBg]     = ImVec4(0.8f, 0.8f, 0.8f, 0.20f);
    c[ImGuiCol_ModalWindowDimBg]      = ImVec4(0.0f, 0.0f, 0.0f, 0.60f);
}

// ============================================================================
// Helpers
// ============================================================================

static void SectionHeader(const char* icon, const char* label) {
    ImGui::Spacing();
    ImGui::TextColored(ImVec4(0.55f, 0.30f, 1.00f, 1.0f), "%s", icon);
    ImGui::SameLine();
    ImGui::TextColored(ImVec4(0.75f, 0.70f, 0.85f, 1.0f), "%s", label);
    ImGui::Spacing();
}

static bool StyledToggle(const char* label, bool value) {
    bool v = value;
    if (v) {
        ImGui::PushStyleColor(ImGuiCol_FrameBg,       ImVec4(0.30f, 0.15f, 0.55f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_FrameBgHovered, ImVec4(0.35f, 0.20f, 0.65f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_FrameBgActive,  ImVec4(0.40f, 0.25f, 0.75f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_CheckMark,      ImVec4(0.70f, 0.45f, 1.00f, 1.0f));
    }

    bool changed = ImGui::Checkbox(label, &v);

    if (value) {
        ImGui::PopStyleColor(4);
    }

    return changed;
}

static void StatusDot(bool active) {
    ImVec4 col = active
        ? ImVec4(0.20f, 0.90f, 0.40f, 1.0f)
        : ImVec4(0.50f, 0.40f, 0.60f, 0.5f);
    ImGui::TextColored(col, "%s", active ? ICON_FA_CIRCLE : ICON_FA_CIRCLE);
    ImGui::SameLine();
}

static void AccentButton(const char* label, ImVec2 size, bool highlight = false) {
    if (highlight) {
        ImGui::PushStyleColor(ImGuiCol_Button,        ImVec4(0.55f, 0.30f, 1.00f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered,  ImVec4(0.65f, 0.40f, 1.00f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive,   ImVec4(0.75f, 0.50f, 1.00f, 1.0f));
    }
    ImGui::Button(label, size);
    if (highlight) ImGui::PopStyleColor(3);
}

// ============================================================================
// Header
// ============================================================================

static void DrawHeader() {
    s_headerPulse += ImGui::GetIO().DeltaTime * 1.5f;
    float glow = 0.5f + 0.5f * sinf(s_headerPulse);

    ImGui::PushFont(ImGui::GetIO().Fonts->Fonts[0]);

    ImVec4 titleCol = ImVec4(0.55f + 0.15f * glow, 0.30f + 0.15f * glow, 1.0f, 1.0f);
    ImGui::TextColored(titleCol, "  X R D");
    ImGui::SameLine();
    ImGui::TextColored(ImVec4(0.45f, 0.38f, 0.58f, 1.0f), "v2.0");

    ImGui::PopFont();

    ImVec2 p = ImGui::GetCursorScreenPos();
    ImDrawList* dl = ImGui::GetWindowDrawList();
    float w = ImGui::GetContentRegionAvail().x;
    ImU32 left  = IM_COL32(140, 76, 255, (int)(180 * glow));
    ImU32 right = IM_COL32(140, 76, 255, 0);
    dl->AddRectFilledMultiColor(
        ImVec2(p.x, p.y),
        ImVec2(p.x + w, p.y + 2),
        left, right, right, left);
    ImGui::Dummy(ImVec2(0, 6));
}

// ============================================================================
// Tab: Player
// ============================================================================

static void DrawPlayerTab() {
    SectionHeader(ICON_FA_CROSSHAIRS, "ZOOM");

    bool zoom = agmod_isZoomEnabled();
    if (StyledToggle(ICON_FA_SEARCH_PLUS " Zoom Hack", zoom)) {
        agmod_setZoomEnabled(!zoom);
        zoom = !zoom;
    }

    if (zoom) {
        ImGui::Indent(20.0f);

        int mode = agmod_getZoomMode();
        ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Mode");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
        if (ImGui::Combo("##ZoomMode", &mode, kZoomModes, IM_ARRAYSIZE(kZoomModes))) {
            agmod_setZoomMode(mode);
        }

        float flex = agmod_getFlexZoom();
        ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Intensity");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
        if (ImGui::SliderFloat("##FlexZoom", &flex, 0.05f, 1.0f, "%.2f")) {
            agmod_setFlexZoom(flex);
        }

        ImGui::Unindent(20.0f);
    }

    SectionHeader(ICON_FA_GAMEPAD, "GAMEPLAY");

    bool autoCont = agmod_isAutoContinue();
    if (StyledToggle(ICON_FA_REDO " Auto-Respawn", autoCont)) {
        agmod_setAutoContinue(!autoCont);
    }

    bool skins = agmod_isUnlockAllSkins();
    if (StyledToggle(ICON_FA_PALETTE " Unlock All Skins", skins)) {
        agmod_setUnlockAllSkins(!skins);
    }

    bool fps = agmod_isUnlockFPS();
    if (StyledToggle(ICON_FA_TACHOMETER_ALT " 120 FPS", fps)) {
        agmod_setUnlockFPS(!fps);
    }
}

// ============================================================================
// Tab: Visuals
// ============================================================================

static void DrawVisualsTab() {
    SectionHeader(ICON_FA_PAINT_BRUSH, "RENDERING");

    bool dark = agmod_isDarkMode();
    if (StyledToggle(ICON_FA_MOON " Dark Mode", dark)) {
        agmod_setDarkMode(!dark);
    }

    bool fast = agmod_isFastMode();
    if (StyledToggle(ICON_FA_ROCKET " Performance Mode", fast)) {
        agmod_setFastMode(!fast);
    }

    bool mass = agmod_isShowEnemyMass();
    if (StyledToggle(ICON_FA_WEIGHT " Enemy Mass ESP", mass)) {
        agmod_setShowEnemyMass(!mass);
    }

    SectionHeader(ICON_FA_EYE_SLASH, "HIDE ELEMENTS");

    bool grid = agmod_isHideGrid();
    if (StyledToggle("Grid", grid)) {
        agmod_setHideGrid(!grid);
    }

    bool borders = agmod_isHideBorders();
    if (StyledToggle("Borders", borders)) {
        agmod_setHideBorders(!borders);
    }

    bool friends = agmod_isHideFriendTracker();
    if (StyledToggle("Friend Tracker", friends)) {
        agmod_setHideFriendTracker(!friends);
    }

    bool tokens = agmod_isHideTokenCounter();
    if (StyledToggle("Token Counter", tokens)) {
        agmod_setHideTokenCounter(!tokens);
    }
}

// ============================================================================
// Tab: Bots
// ============================================================================

static void DrawBotsTab() {
    SectionHeader(ICON_FA_SERVER, "CONNECTION");

    ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Server URL");
    ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
    if (ImGui::InputText("##BotServerURL", s_botServerURL, sizeof(s_botServerURL))) {
        agmod_setBotServerURL([NSString stringWithUTF8String:s_botServerURL]);
    }

    ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Secret Key");
    ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
    if (ImGui::InputText("##BotSecretKey", s_botSecretKey, sizeof(s_botSecretKey),
                         ImGuiInputTextFlags_Password)) {
        agmod_setBotSecretKey([NSString stringWithUTF8String:s_botSecretKey]);
    }

    SectionHeader(ICON_FA_ROBOT, "BOT CONFIG");

    ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Bot Name");
    ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
    if (ImGui::InputText("##BotName", s_botName, sizeof(s_botName))) {
        agmod_setBotName([NSString stringWithUTF8String:s_botName]);
    }

    int botMode = agmod_getBotMode();
    ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Mode");
    ImGui::SameLine();
    ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
    if (ImGui::Combo("##BotMode", &botMode, kBotModes, IM_ARRAYSIZE(kBotModes))) {
        agmod_setBotMode(botMode);
    }

    ImGui::Spacing();
    ImGui::Spacing();

    float btnW = ImGui::GetContentRegionAvail().x;
    bool running = agmod_isBotsRunning();

    if (running) {
        ImGui::PushStyleColor(ImGuiCol_Button,        ImVec4(0.70f, 0.12f, 0.12f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered,  ImVec4(0.85f, 0.18f, 0.18f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive,   ImVec4(1.00f, 0.25f, 0.25f, 1.0f));

        if (ImGui::Button(ICON_FA_STOP " STOP BOTS", ImVec2(btnW, 40.0f))) {
            agmod_stopBots();
        }

        ImGui::PopStyleColor(3);
    } else {
        ImGui::PushStyleColor(ImGuiCol_Button,        ImVec4(0.55f, 0.30f, 1.00f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered,  ImVec4(0.65f, 0.40f, 1.00f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive,   ImVec4(0.75f, 0.50f, 1.00f, 1.0f));

        if (ImGui::Button(ICON_FA_PLAY " LAUNCH BOTS", ImVec2(btnW, 40.0f))) {
            agmod_startBots();
        }

        ImGui::PopStyleColor(3);
    }

    // Status
    ImGui::Spacing();
    SectionHeader(ICON_FA_SIGNAL, "STATUS");

    if (running) {
        StatusDot(true);
        ImGui::TextColored(ImVec4(0.20f, 0.90f, 0.40f, 1.0f), "Active");
        ImGui::Text("Mode: %s", kBotModes[agmod_getBotMode()]);

        NSString *serverIP = agmod_getCurrentServerIP();
        if (serverIP && serverIP.length > 0) {
            ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Server: %s", [serverIP UTF8String]);
        }

        NSString *party = agmod_getCurrentPartyCode();
        if (party && party.length > 0) {
            ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Party: %s", [party UTF8String]);
        }
    } else {
        StatusDot(false);
        ImGui::TextColored(ImVec4(0.50f, 0.40f, 0.60f, 1.0f), "Offline");
    }
}

// ============================================================================
// Tab: Macros
// ============================================================================

static void DrawMacrosTab() {
    SectionHeader(ICON_FA_BOLT, "FEED MACRO");

    bool feedActive = agmod_isFeedMacroActive();
    if (StyledToggle(ICON_FA_UTENSILS " Auto-Feed", feedActive)) {
        agmod_setFeedMacroActive(!feedActive);
        feedActive = !feedActive;
    }

    if (feedActive) {
        ImGui::Indent(20.0f);
        float feedRate = agmod_getFeedMacroRate();
        ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Speed (ms)");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
        if (ImGui::SliderFloat("##FeedRate", &feedRate, 10.0f, 200.0f, "%.0f")) {
            agmod_setFeedMacroRate(feedRate);
        }
        ImGui::Unindent(20.0f);
    }

    SectionHeader(ICON_FA_EXPAND_ARROWS_ALT, "SPLIT MACRO");

    bool splitActive = agmod_isSplitMacroActive();
    if (StyledToggle(ICON_FA_COMPRESS_ARROWS_ALT " Auto-Split", splitActive)) {
        agmod_setSplitMacroActive(!splitActive);
        splitActive = !splitActive;
    }

    if (splitActive) {
        ImGui::Indent(20.0f);
        float splitRate = agmod_getSplitMacroRate();
        ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Speed (ms)");
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
    SectionHeader(ICON_FA_NETWORK_WIRED, "SERVER LOADER");

    bool serverLoader = agmod_isServerLoaderEnabled();
    if (StyledToggle(ICON_FA_PLUG " Custom Server", serverLoader)) {
        agmod_setServerLoaderEnabled(!serverLoader);
        serverLoader = !serverLoader;
    }

    if (serverLoader) {
        ImGui::Indent(20.0f);
        ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "Target IP");
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
        if (ImGui::InputText("##TargetIP", s_targetServerIP, sizeof(s_targetServerIP))) {
            agmod_setTargetServerIP([NSString stringWithUTF8String:s_targetServerIP]);
        }
        ImGui::Unindent(20.0f);
    }

    SectionHeader(ICON_FA_SAVE, "DATA");

    float halfW = (ImGui::GetContentRegionAvail().x - ImGui::GetStyle().ItemSpacing.x) * 0.5f;

    ImGui::PushStyleColor(ImGuiCol_Button,        ImVec4(0.55f, 0.30f, 1.00f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered,  ImVec4(0.65f, 0.40f, 1.00f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive,   ImVec4(0.75f, 0.50f, 1.00f, 1.0f));

    if (ImGui::Button(ICON_FA_SAVE " Save", ImVec2(halfW, 36.0f))) {
        agmod_saveAllSettings();
    }

    ImGui::PopStyleColor(3);

    ImGui::SameLine();

    ImGui::PushStyleColor(ImGuiCol_Button,        ImVec4(0.50f, 0.12f, 0.12f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered,  ImVec4(0.60f, 0.18f, 0.18f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive,   ImVec4(0.70f, 0.25f, 0.25f, 1.0f));

    if (ImGui::Button(ICON_FA_UNDO " Reset", ImVec2(halfW, 36.0f))) {
        agmod_reloadSettings();
        s_buffersInitialized = false;
        SyncBuffersFromAPI();
    }

    ImGui::PopStyleColor(3);

    // Credits
    ImGui::Spacing();
    ImGui::Spacing();

    ImGui::PushStyleColor(ImGuiCol_ChildBg, ImVec4(0.06f, 0.04f, 0.10f, 0.8f));
    ImGui::BeginChild("##credits", ImVec2(0, 60), true);

    ImGui::TextColored(ImVec4(0.55f, 0.30f, 1.00f, 1.0f), ICON_FA_CODE " XRD");
    ImGui::SameLine();
    ImGui::TextColored(ImVec4(0.45f, 0.38f, 0.58f, 1.0f), "v2.0.0");
    ImGui::TextColored(ImVec4(0.40f, 0.35f, 0.50f, 1.0f), "ImGui %s | Metal Backend", ImGui::GetVersion());

    NSString *sid = agmod_getSessionId();
    if (sid && sid.length > 0) {
        ImGui::TextColored(ImVec4(0.30f, 0.25f, 0.40f, 1.0f), "ID: %.8s", [sid UTF8String]);
    }

    ImGui::EndChild();
    ImGui::PopStyleColor();
}

// ============================================================================
// Main Draw
// ============================================================================

void ModMenu::Draw() {
    SyncBuffersFromAPI();

    ImGuiIO& io = ImGui::GetIO();

    ImVec2 windowSize(340.0f, 480.0f);
    ImGui::SetNextWindowSize(windowSize, ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowPos(
        ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f),
        ImGuiCond_FirstUseEver,
        ImVec2(0.5f, 0.5f)
    );

    ImGuiWindowFlags windowFlags =
        ImGuiWindowFlags_NoCollapse |
        ImGuiWindowFlags_NoSavedSettings |
        ImGuiWindowFlags_NoTitleBar;

    ImGui::Begin("##XRD", nullptr, windowFlags);

    DrawHeader();

    if (ImGui::BeginTabBar("##Tabs", ImGuiTabBarFlags_None)) {

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

        if (ImGui::BeginTabItem(ICON_FA_COG " Config")) {
            s_currentTab = 4;
            DrawSettingsTab();
            ImGui::EndTabItem();
        }

        ImGui::EndTabBar();
    }

    ImGui::End();
}
