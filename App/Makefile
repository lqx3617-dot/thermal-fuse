ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ThermalFuseApp
ThermalFuseApp_FILES = main.m TFAppDelegate.m ../Prefs/TFPrefsRootListController.m
ThermalFuseApp_FRAMEWORKS = UIKit CoreGraphics
ThermalFuseApp_USE_MODULES = 0
ThermalFuseApp_CFLAGS = -fobjc-arc -I../Prefs

include $(THEOS)/makefiles/application.mk
