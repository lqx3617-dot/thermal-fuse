TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ThermalFuse
ThermalFuse_FILES = Sources/TFCore.m Sources/TFThermal.xm Sources/TFSB.xm
ThermalFuse_CFLAGS = -fobjc-arc -ISources
ThermalFuse_FRAMEWORKS = Foundation UIKit

include $(THEOS)/makefiles/tweak.mk

SUBPROJECTS += Prefs App
include $(THEOS)/makefiles/aggregate.mk

# Relaxin = RootHide 架构，编译用 roothide 版 Theos：
#   make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
