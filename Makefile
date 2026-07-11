APP_DIR := /Applications/GDrive Backup Tiger.app
APP_SOURCES := \
	macos/GDriveBackupTiger/main.m \
	macos/GDriveBackupTiger/ConfigSupport.m \
	macos/GDriveBackupTiger/Localization.m
OBJC_FLAGS := -fobjc-arc -Wall -Wextra -Werror
MACOS_DEPLOYMENT_TARGET ?= 13.0
APP_ARCH_FLAGS ?= -arch arm64 -arch x86_64
APP_OBJC_FLAGS := $(OBJC_FLAGS) -mmacosx-version-min=$(MACOS_DEPLOYMENT_TARGET) $(APP_ARCH_FLAGS)

.PHONY: build install dry-run pkg test clean

build:
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	install -m 644 macos/GDriveBackupTiger/Info.plist "$(APP_DIR)/Contents/Info.plist"
	clang $(APP_OBJC_FLAGS) -framework Cocoa $(APP_SOURCES) -o "$(APP_DIR)/Contents/MacOS/GDriveBackupTiger"
	@ICON_WORK="$$(/usr/bin/mktemp -d "$${TMPDIR:-/tmp}/gdrive-tiger-icon.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa macos/GDriveBackupTiger/IconGenerator.m -o "$$ICON_WORK/IconGenerator"; \
		"$$ICON_WORK/IconGenerator" "$$ICON_WORK/AppIcon.iconset"; \
		iconutil -c icns "$$ICON_WORK/AppIcon.iconset" -o "$(APP_DIR)/Contents/Resources/AppIcon.icns"; \
		./scripts/trash-path.sh "$$ICON_WORK"
	codesign --force --deep --sign - "$(APP_DIR)"

install:
	./install.sh

dry-run:
	/usr/local/bin/backup-google-drive.sh --dry-run

pkg:
	./packaging/build-pkg.sh

test:
	bash tests/app-trash-mode-test.sh
	bash tests/backup-control-test.sh
	bash tests/backup-encryption-test.sh
	bash tests/backup-versioning-test.sh
	bash tests/encryption-ui-test.sh
	bash tests/release-metadata-test.sh
	bash tests/trash-path-test.sh
	bash tests/window-behavior-test.sh
	@CONFIG_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-config-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Foundation -I macos/GDriveBackupTiger \
			tests/config-support-test.m macos/GDriveBackupTiger/ConfigSupport.m -o "$$CONFIG_TEST_BIN"; \
		"$$CONFIG_TEST_BIN"; \
		./scripts/trash-path.sh "$$CONFIG_TEST_BIN"
	bash -n bin/backup-google-drive.sh install.sh packaging/build-pkg.sh packaging/verify-pkg.sh packaging/scripts/postinstall scripts/*.sh tests/*.sh
	plutil -lint launchd/com.commcats.gdrivebackup.plist macos/GDriveBackupTiger/Info.plist
	shellcheck -x bin/backup-google-drive.sh install.sh packaging/build-pkg.sh packaging/verify-pkg.sh packaging/scripts/postinstall scripts/*.sh tests/*.sh

clean:
	@for path in build dist; do if [ -e "$$path" ]; then ./scripts/trash-path.sh "$$path"; fi; done
