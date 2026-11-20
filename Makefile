TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = thermalmonitord

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ThermalFuse
ThermalFuse_FILES = Sources/Tweak.xm
ThermalFuse_CFLAGS = -fobjc-arc -ISources
ThermalFuse_FRAMEWORKS = Foundation UIKit

include $(THEOS)/makefiles/tweak.mk
