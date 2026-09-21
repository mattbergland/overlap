XCODEGEN := /opt/homebrew/bin/xcodegen
PROJECT := Overlap.xcodeproj
SCHEME := Overlap
APP := $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $$2; exit}')/Overlap.app

.PHONY: generate build test run clean

generate:
	$(XCODEGEN) generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug test

run: build
	open "$(APP)"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
