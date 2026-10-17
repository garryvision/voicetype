# VoiceType : Swift macOS voice-to-text
APP_NAME := VoiceType
BUNDLE := dist/$(APP_NAME).app
# Clément's stable certificate when present (keeps macOS permissions across builds),
# ad-hoc signature otherwise (friends' Macs)
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning 2>/dev/null | grep -q '"VoiceType Signing"' && echo "VoiceType Signing" || echo -)
VERSION := 0.4.0
PLIST := $(BUNDLE)/Contents/Info.plist
SWIFT_FILES := Sources/VoiceType/*.swift
FRAMEWORKS := -framework AppKit -framework AVFoundation -framework Quartz \
              -framework Accelerate -framework ApplicationServices

.PHONY: build test install run stop uninstall clean

## Test : standalone Swift tests (Command Line Tools do not ship XCTest)
test:
	@mkdir -p .build/tests
	swiftc -o .build/tests/VoiceTypeTests \
		Sources/VoiceType/TranscriptCleaner.swift \
		Sources/VoiceType/ProcessRunner.swift \
		Sources/VoiceType/ComparisonAudio.swift \
		Tests/VoiceTypeTests/main.swift
	@.build/tests/VoiceTypeTests
	@bash Tests/test-install-parakeet.sh

## Build : compile + bundle + sign
build:
	@mkdir -p dist/$(APP_NAME).app/Contents/MacOS
	swiftc -o dist/$(APP_NAME) $(FRAMEWORKS) -O $(SWIFT_FILES)
	@cp dist/$(APP_NAME) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@if [ ! -f $(BUNDLE)/Contents/Info.plist ]; then \
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
			$(BUNDLE)/Contents/Info.plist ; \
	fi
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" \
		-c "Set :CFBundleShortVersionString $(VERSION)" $(PLIST)
	@codesign --force --sign "$(SIGN_IDENTITY)" $(BUNDLE)
	@xattr -cr $(BUNDLE)
	@echo "Built and signed with $(SIGN_IDENTITY)"

## Install : overwrite the files inside the existing bundle. Never delete it and never
## cp -R onto it (the copy lands inside). Same certificate = permissions kept.
install: build
	@killall $(APP_NAME) 2>/dev/null || true
	@sleep 1
	@ditto $(BUNDLE) /Applications/$(APP_NAME).app
	@codesign --verify --strict /Applications/$(APP_NAME).app
	@echo "Installed $(VERSION). Run: make run"

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
