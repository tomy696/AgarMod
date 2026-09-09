ARCHS = arm64
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = agar.io

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XRD

XRD_FILES = \
	tweak/Tweak.xm \
	tweak/imgui/imgui.cpp \
	tweak/imgui/imgui_draw.cpp \
	tweak/imgui/imgui_tables.cpp \
	tweak/imgui/imgui_widgets.cpp \
	tweak/imgui/imgui_impl_metal.mm \
	tweak/imgui/imgui_impl_ios.mm \
	tweak/imgui/ModMenuRenderer.mm \
	tweak/imgui/ModMenu.mm

XRD_FRAMEWORKS = UIKit Foundation Metal MetalKit QuartzCore
XRD_LIBRARIES = substrate

XRD_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/tweak/headers -I$(THEOS_PROJECT_DIR)/tweak/imgui
XRD_CCFLAGS = -std=c++17
XRD_CXXFLAGS = -std=c++17

XRD_OBJCXXFLAGS = -std=c++17

XRD_LOGOS_DEFAULT_GENERATOR = internal
XRD_EXTRA_FLAGS = -x objective-c++

include $(THEOS_MAKE_PATH)/tweak.mk
