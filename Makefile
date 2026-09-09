ARCHS = arm64
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = agar.io

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XRD

XRD_FILES = \
	tweak/Tweak.xm \
	tweak/NativeMenu.mm

XRD_FRAMEWORKS = UIKit Foundation MetalKit
XRD_LIBRARIES = substrate

XRD_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/tweak/headers -I$(THEOS_PROJECT_DIR)/tweak
XRD_CCFLAGS = -std=c++17
XRD_CXXFLAGS = -std=c++17

XRD_OBJCXXFLAGS = -std=c++17

XRD_LOGOS_DEFAULT_GENERATOR = internal
XRD_EXTRA_FLAGS = -x objective-c++

include $(THEOS_MAKE_PATH)/tweak.mk
