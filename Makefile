APP_NAME := CmdTab
BUNDLE_ID := dev.local.cmdtab
CONFIGURATION ?= debug
MACOS_DEPLOYMENT_TARGET := 14.0
SIGN_IDENTITY ?= CmdTab Local Development
BUILD_DIR := .build/$(CONFIGURATION)
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
EXECUTABLE := $(MACOS_DIR)/$(APP_NAME)
SOURCES := $(shell find Sources/$(APP_NAME) -name '*.swift' | sort)

.PHONY: build run clean reset-tcc

build: $(EXECUTABLE)

$(EXECUTABLE): $(SOURCES) Config/Info.plist Config/$(APP_NAME).entitlements
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	cp Config/Info.plist $(CONTENTS_DIR)/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(BUNDLE_ID)" $(CONTENTS_DIR)/Info.plist >/dev/null
	xcrun swiftc \
		-parse-as-library \
		-target arm64-apple-macosx$(MACOS_DEPLOYMENT_TARGET) \
		-Onone \
		-framework AppKit \
		-framework ApplicationServices \
		-framework CoreGraphics \
		-framework SwiftUI \
		-o $(EXECUTABLE) \
		$(SOURCES)
	codesign --force --sign "$(SIGN_IDENTITY)" --entitlements Config/$(APP_NAME).entitlements $(APP_DIR)

run: build
	pkill -x $(APP_NAME) || true
	open $(APP_DIR)

clean:
	rm -rf .build

# Helpful during development if macOS privacy prompts get into a bad state.
reset-tcc:
	tccutil reset Accessibility $(BUNDLE_ID) || true
