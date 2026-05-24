APP_DIR := /Applications/GDrive Backup Tiger.app

.PHONY: build install dry-run pkg clean

build:
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources" build
	install -m 644 macos/GDriveBackupTiger/Info.plist "$(APP_DIR)/Contents/Info.plist"
	clang -fobjc-arc -framework Cocoa macos/GDriveBackupTiger/main.m -o "$(APP_DIR)/Contents/MacOS/GDriveBackupTiger"
	clang -fobjc-arc -framework Cocoa macos/GDriveBackupTiger/IconGenerator.m -o build/IconGenerator
	rm -rf build/AppIcon.iconset
	build/IconGenerator build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o "$(APP_DIR)/Contents/Resources/AppIcon.icns"
	codesign --force --deep --sign - "$(APP_DIR)"

install:
	./install.sh

dry-run:
	/usr/local/bin/backup-google-drive.sh --dry-run

pkg:
	./packaging/build-pkg.sh

clean:
	rm -rf build dist
