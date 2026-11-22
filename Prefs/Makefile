ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ThermalFusePrefs
ThermalFusePrefs_FILES = TFPrefsRootListController.m
ThermalFusePrefs_INSTALL_PATH = /Library/PreferenceBundles
ThermalFusePrefs_FRAMEWORKS = UIKit
ThermalFusePrefs_USE_MODULES = 0
ThermalFusePrefs_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/bundle.mk
