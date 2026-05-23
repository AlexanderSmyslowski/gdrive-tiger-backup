APP_DIR := $(HOME)/Applications/GDrive\ Backup\ Tiger.app

.PHONY: build install dry-run

build:
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	install -m 644 macos/GDriveBackupTiger/Info.plist "$(APP_DIR)/Contents/Info.plist"
	clang -fobjc-arc -framework Cocoa macos/GDriveBackupTiger/main.m -o "$(APP_DIR)/Contents/MacOS/GDriveBackupTiger"
	codesign --force --deep --sign - "$(APP_DIR)"

install:
	./install.sh

dry-run:
	/usr/local/bin/backup-google-drive.sh --dry-run
