APP := build/Macpeek.app
ICON := build/AppIcon.icns
BUILD := swift build -c release --arch arm64 --arch x86_64
BIN = $(shell $(BUILD) --show-bin-path)

.PHONY: app install release test snapshots energy clean

app: $(ICON)
	$(BUILD)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Helpers $(APP)/Contents/Resources
	cp $(BIN)/MacpeekApp $(APP)/Contents/MacOS/
	cp $(BIN)/macpeek $(APP)/Contents/Helpers/
	cp Resources/Info.plist $(APP)/Contents/
	cp $(ICON) $(APP)/Contents/Resources/
	codesign --force --sign - $(APP)/Contents/Helpers/macpeek
	codesign --force --sign - $(APP)

$(ICON): scripts/make-icon.swift
	rm -rf build/AppIcon.iconset
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o $(ICON)

install: app
	-pkill -x MacpeekApp
	rm -rf /Applications/Macpeek.app
	cp -R $(APP) /Applications/
	open /Applications/Macpeek.app

release: app
	cd build && rm -f Macpeek.zip && ditto -c -k --keepParent Macpeek.app Macpeek.zip
	cd build && LC_ALL=C shasum -a 256 Macpeek.zip > Macpeek.zip.sha256

test:
	swift test

snapshots: $(ICON)
	swift run MacpeekApp --snapshots build/snapshots
	cp build/AppIcon.iconset/icon_512x512.png build/snapshots/icon.png

energy: app
	scripts/energy-check.sh $(APP)

clean:
	rm -rf .build build
