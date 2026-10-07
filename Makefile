APP := build/Macpeek.app
BUILD := swift build -c release --arch arm64 --arch x86_64
BIN = $(shell $(BUILD) --show-bin-path)

.PHONY: app install release test clean

app:
	$(BUILD)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Helpers $(APP)/Contents/Resources
	cp $(BIN)/MacpeekApp $(APP)/Contents/MacOS/
	cp $(BIN)/macpeek $(APP)/Contents/Helpers/
	cp Resources/Info.plist $(APP)/Contents/
	if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(APP)/Contents/Resources/; fi
	codesign --force --sign - $(APP)/Contents/Helpers/macpeek
	codesign --force --sign - $(APP)

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

clean:
	rm -rf .build build
