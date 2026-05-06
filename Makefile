# VoiceType — Swift macOS voice-to-text
APP_NAME := VoiceType
BUNDLE := dist/$(APP_NAME).app
SIGN_IDENTITY ?= -
SWIFT_FILES := Sources/VoiceType/*.swift
FRAMEWORKS := -framework AppKit -framework AVFoundation -framework Quartz \
              -framework Accelerate -framework ApplicationServices

.PHONY: build install run stop uninstall clean

## Build — compile + bundle + sign
build:
	@mkdir -p dist/$(APP_NAME).app/Contents/MacOS
	swiftc -o dist/$(APP_NAME) $(FRAMEWORKS) -O $(SWIFT_FILES)
	@cp dist/$(APP_NAME) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp dist/$(APP_NAME).app/Contents/Info.plist $(BUNDLE)/Contents/Info.plist 2>/dev/null || \
		/usr/libexec/PlistBuddy \
			-c "Add :CFBundleName string $(APP_NAME)" \
			-c "Add :CFBundleIdentifier string com.clement.voicetype" \
			-c "Add :CFBundleExecutable string $(APP_NAME)" \
			-c "Add :CFBundlePackageType string APPL" \
			-c "Add :CFBundleVersion string 0.1.0" \
			-c "Add :CFBundleShortVersionString string 0.1.0" \
			-c "Add :LSMinimumSystemVersion string 14.0" \
			-c "Add :NSMicrophoneUsageDescription string VoiceType needs microphone access." \
			-c "Add :NSHighResolutionCapable bool true" \
			$(BUNDLE)/Contents/Info.plist
	@codesign --force --deep --sign "$(SIGN_IDENTITY)" $(BUNDLE)
	@xattr -cr $(BUNDLE)
	@echo "✅ Built + signed with $(SIGN_IDENTITY)"

## Install — copy to /Applications
install: build
	@killall $(APP_NAME) 2>/dev/null || true
	@sleep 1
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(BUNDLE) /Applications/
	@echo "✅ Installed — run: make run"

## Run
run:
	@open /Applications/$(APP_NAME).app

## Stop
stop:
	@killall $(APP_NAME) 2>/dev/null || true

## Uninstall
uninstall: stop
	@rm -rf /Applications/$(APP_NAME).app
	@echo "✅ Uninstalled"

## Clean
clean:
	@rm -rf .build dist
