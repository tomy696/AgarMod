ARCHS = arm64
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = agar.io

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AgarMod

AgarMod_FILES = \
	tweak/Tweak.xm \
	tweak/imgui/imgui.cpp \
	tweak/imgui/imgui_draw.cpp \
	tweak/imgui/imgui_tables.cpp \
	tweak/imgui/imgui_widgets.cpp \
	tweak/imgui/imgui_impl_metal.mm \
	tweak/imgui/imgui_impl_ios.mm \
	tweak/imgui/ModMenuRenderer.mm \
	tweak/imgui/ModMenu.mm

AgarMod_FRAMEWORKS = UIKit Foundation Metal MetalKit QuartzCore
AgarMod_LIBRARIES = substrate

AgarMod_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/tweak/headers -I$(THEOS_PROJECT_DIR)/tweak/imgui
AgarMod_CCFLAGS = -std=c++17
AgarMod_CXXFLAGS = -std=c++17

# ObjC++ flags for .xm (Logos) and .mm files
AgarMod_OBJCXXFLAGS = -std=c++17

# Treat .xm as ObjC++ so Logos processes it with C++ support
AgarMod_LOGOS_DEFAULT_GENERATOR = internal
AgarMod_EXTRA_FLAGS = -x objective-c++

include $(THEOS_MAKE_PATH)/tweak.mk
