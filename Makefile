APP_DIR := /Applications/GDrive Backup Tiger.app
APP_SOURCES := \
	macos/GDriveBackupTiger/main.m \
	macos/GDriveBackupTiger/ConfigSupport.m \
	macos/GDriveBackupTiger/ProfileSupport.m \
	macos/GDriveBackupTiger/BackupStatusSupport.m \
	macos/GDriveBackupTiger/SetupHealthSupport.m \
	macos/GDriveBackupTiger/RestoreSupport.m \
	macos/GDriveBackupTiger/RestoreBrowserView.m \
	macos/GDriveBackupTiger/DiagnosticsSupport.m \
	macos/GDriveBackupTiger/DiagnosticsView.m \
	macos/GDriveBackupTiger/UpdateSupport.m \
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
	xattr -cr "$(APP_DIR)"
	codesign --force --deep --sign - "$(APP_DIR)"

install:
	./install.sh

dry-run:
	/usr/local/bin/backup-google-drive.sh --dry-run

pkg:
	./packaging/build-pkg.sh

test:
	bash tests/app-launch-status-test.sh
	bash tests/app-trash-mode-test.sh
	bash tests/backup-control-test.sh
	bash tests/backup-profile-test.sh
	bash tests/backup-encryption-test.sh
	bash tests/backup-outcome-test.sh
	bash tests/backup-versioning-test.sh
	bash tests/encryption-ui-test.sh
	bash tests/launch-agent-safety-test.sh
	bash tests/release-metadata-test.sh
	bash tests/update-flow-safety-test.sh
	@RUN_STATE_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-run-state-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/run-state-ui-test.m macos/GDriveBackupTiger/ConfigSupport.m \
			macos/GDriveBackupTiger/ProfileSupport.m \
			macos/GDriveBackupTiger/BackupStatusSupport.m macos/GDriveBackupTiger/SetupHealthSupport.m \
			macos/GDriveBackupTiger/RestoreSupport.m macos/GDriveBackupTiger/RestoreBrowserView.m \
			macos/GDriveBackupTiger/DiagnosticsSupport.m macos/GDriveBackupTiger/DiagnosticsView.m \
			macos/GDriveBackupTiger/UpdateSupport.m \
			macos/GDriveBackupTiger/Localization.m -o "$$RUN_STATE_TEST_BIN"; \
		"$$RUN_STATE_TEST_BIN"; \
		./scripts/trash-path.sh "$$RUN_STATE_TEST_BIN"
	@ACCESSIBILITY_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-accessibility-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/tiger-accessibility-test.m macos/GDriveBackupTiger/ConfigSupport.m \
			macos/GDriveBackupTiger/ProfileSupport.m \
			macos/GDriveBackupTiger/BackupStatusSupport.m macos/GDriveBackupTiger/SetupHealthSupport.m \
			macos/GDriveBackupTiger/RestoreSupport.m macos/GDriveBackupTiger/RestoreBrowserView.m \
			macos/GDriveBackupTiger/DiagnosticsSupport.m macos/GDriveBackupTiger/DiagnosticsView.m \
			macos/GDriveBackupTiger/UpdateSupport.m \
			macos/GDriveBackupTiger/Localization.m -o "$$ACCESSIBILITY_TEST_BIN"; \
		"$$ACCESSIBILITY_TEST_BIN"; \
		./scripts/trash-path.sh "$$ACCESSIBILITY_TEST_BIN"
	@STATUS_SUPPORT_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-status-support-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Foundation -I macos/GDriveBackupTiger \
			tests/status-support-test.m macos/GDriveBackupTiger/BackupStatusSupport.m \
			-o "$$STATUS_SUPPORT_TEST_BIN"; \
		"$$STATUS_SUPPORT_TEST_BIN"; \
		./scripts/trash-path.sh "$$STATUS_SUPPORT_TEST_BIN"
	@PROFILE_SUPPORT_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-profile-support-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Foundation -I macos/GDriveBackupTiger \
			tests/profile-support-test.m macos/GDriveBackupTiger/ConfigSupport.m \
			macos/GDriveBackupTiger/ProfileSupport.m -o "$$PROFILE_SUPPORT_TEST_BIN"; \
		"$$PROFILE_SUPPORT_TEST_BIN"; \
		./scripts/trash-path.sh "$$PROFILE_SUPPORT_TEST_BIN"
	@SETUP_HEALTH_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-setup-health-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Foundation -I macos/GDriveBackupTiger \
			tests/setup-health-test.m macos/GDriveBackupTiger/SetupHealthSupport.m \
			-o "$$SETUP_HEALTH_TEST_BIN"; \
		"$$SETUP_HEALTH_TEST_BIN"; \
		./scripts/trash-path.sh "$$SETUP_HEALTH_TEST_BIN"
	@RESTORE_SUPPORT_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-restore-support-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Foundation -I macos/GDriveBackupTiger \
			tests/restore-support-test.m macos/GDriveBackupTiger/RestoreSupport.m \
			-o "$$RESTORE_SUPPORT_TEST_BIN"; \
		"$$RESTORE_SUPPORT_TEST_BIN"; \
		./scripts/trash-path.sh "$$RESTORE_SUPPORT_TEST_BIN"
	@RESTORE_UI_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-restore-ui-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/restore-ui-test.m macos/GDriveBackupTiger/RestoreBrowserView.m \
			macos/GDriveBackupTiger/ConfigSupport.m macos/GDriveBackupTiger/Localization.m \
			-o "$$RESTORE_UI_TEST_BIN"; \
		"$$RESTORE_UI_TEST_BIN"; \
		./scripts/trash-path.sh "$$RESTORE_UI_TEST_BIN"
	@DIAGNOSTICS_SUPPORT_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-diagnostics-support-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Foundation -I macos/GDriveBackupTiger \
			tests/diagnostics-support-test.m macos/GDriveBackupTiger/DiagnosticsSupport.m \
			-o "$$DIAGNOSTICS_SUPPORT_TEST_BIN"; \
		"$$DIAGNOSTICS_SUPPORT_TEST_BIN"; \
		./scripts/trash-path.sh "$$DIAGNOSTICS_SUPPORT_TEST_BIN"
	@UPDATE_SUPPORT_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-update-support-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Foundation -I macos/GDriveBackupTiger \
			tests/update-support-test.m macos/GDriveBackupTiger/UpdateSupport.m \
			-o "$$UPDATE_SUPPORT_TEST_BIN"; \
		"$$UPDATE_SUPPORT_TEST_BIN"; \
		./scripts/trash-path.sh "$$UPDATE_SUPPORT_TEST_BIN"
	@DIAGNOSTICS_UI_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-diagnostics-ui-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/diagnostics-ui-test.m macos/GDriveBackupTiger/DiagnosticsView.m \
			macos/GDriveBackupTiger/ConfigSupport.m macos/GDriveBackupTiger/Localization.m \
			-o "$$DIAGNOSTICS_UI_TEST_BIN"; \
		"$$DIAGNOSTICS_UI_TEST_BIN"; \
		./scripts/trash-path.sh "$$DIAGNOSTICS_UI_TEST_BIN"
	@DIAGNOSTICS_INTEGRATION_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-diagnostics-integration-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/diagnostics-integration-test.m macos/GDriveBackupTiger/ConfigSupport.m \
			macos/GDriveBackupTiger/ProfileSupport.m \
			macos/GDriveBackupTiger/BackupStatusSupport.m macos/GDriveBackupTiger/SetupHealthSupport.m \
			macos/GDriveBackupTiger/RestoreSupport.m macos/GDriveBackupTiger/RestoreBrowserView.m \
			macos/GDriveBackupTiger/DiagnosticsSupport.m macos/GDriveBackupTiger/DiagnosticsView.m \
			macos/GDriveBackupTiger/UpdateSupport.m \
			macos/GDriveBackupTiger/Localization.m -o "$$DIAGNOSTICS_INTEGRATION_TEST_BIN"; \
		"$$DIAGNOSTICS_INTEGRATION_TEST_BIN"; \
		./scripts/trash-path.sh "$$DIAGNOSTICS_INTEGRATION_TEST_BIN"
	@SETUP_HEALTH_UI_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-setup-health-ui-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/setup-health-ui-test.m macos/GDriveBackupTiger/ConfigSupport.m \
			macos/GDriveBackupTiger/ProfileSupport.m \
			macos/GDriveBackupTiger/BackupStatusSupport.m macos/GDriveBackupTiger/SetupHealthSupport.m \
			macos/GDriveBackupTiger/RestoreSupport.m macos/GDriveBackupTiger/RestoreBrowserView.m \
			macos/GDriveBackupTiger/DiagnosticsSupport.m macos/GDriveBackupTiger/DiagnosticsView.m \
			macos/GDriveBackupTiger/UpdateSupport.m \
			macos/GDriveBackupTiger/Localization.m -o "$$SETUP_HEALTH_UI_TEST_BIN"; \
		"$$SETUP_HEALTH_UI_TEST_BIN"; \
		./scripts/trash-path.sh "$$SETUP_HEALTH_UI_TEST_BIN"
	@OVERVIEW_UI_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-overview-ui-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/overview-ui-test.m macos/GDriveBackupTiger/ConfigSupport.m \
			macos/GDriveBackupTiger/ProfileSupport.m \
			macos/GDriveBackupTiger/BackupStatusSupport.m macos/GDriveBackupTiger/SetupHealthSupport.m \
			macos/GDriveBackupTiger/RestoreSupport.m macos/GDriveBackupTiger/RestoreBrowserView.m \
			macos/GDriveBackupTiger/DiagnosticsSupport.m macos/GDriveBackupTiger/DiagnosticsView.m \
			macos/GDriveBackupTiger/UpdateSupport.m \
			macos/GDriveBackupTiger/Localization.m \
			-o "$$OVERVIEW_UI_TEST_BIN"; \
		"$$OVERVIEW_UI_TEST_BIN"; \
		./scripts/trash-path.sh "$$OVERVIEW_UI_TEST_BIN"
	@SETUP_SAFETY_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-setup-safety-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/setup-safety-test.m macos/GDriveBackupTiger/ConfigSupport.m \
			macos/GDriveBackupTiger/ProfileSupport.m \
			macos/GDriveBackupTiger/BackupStatusSupport.m macos/GDriveBackupTiger/SetupHealthSupport.m \
			macos/GDriveBackupTiger/RestoreSupport.m macos/GDriveBackupTiger/RestoreBrowserView.m \
			macos/GDriveBackupTiger/DiagnosticsSupport.m macos/GDriveBackupTiger/DiagnosticsView.m \
			macos/GDriveBackupTiger/UpdateSupport.m \
			macos/GDriveBackupTiger/Localization.m \
			-o "$$SETUP_SAFETY_TEST_BIN"; \
		"$$SETUP_SAFETY_TEST_BIN"; \
		./scripts/trash-path.sh "$$SETUP_SAFETY_TEST_BIN"
	@MOUNT_TRIGGER_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-mount-trigger-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/mount-trigger-test.m macos/GDriveBackupTiger/ConfigSupport.m \
			macos/GDriveBackupTiger/ProfileSupport.m \
			macos/GDriveBackupTiger/BackupStatusSupport.m macos/GDriveBackupTiger/SetupHealthSupport.m \
			macos/GDriveBackupTiger/RestoreSupport.m macos/GDriveBackupTiger/RestoreBrowserView.m \
			macos/GDriveBackupTiger/DiagnosticsSupport.m macos/GDriveBackupTiger/DiagnosticsView.m \
			macos/GDriveBackupTiger/UpdateSupport.m \
			macos/GDriveBackupTiger/Localization.m \
			-o "$$MOUNT_TRIGGER_TEST_BIN"; \
		"$$MOUNT_TRIGGER_TEST_BIN"; \
		./scripts/trash-path.sh "$$MOUNT_TRIGGER_TEST_BIN"
	@PROFILE_UI_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-profile-ui-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/profile-ui-test.m macos/GDriveBackupTiger/ConfigSupport.m \
			macos/GDriveBackupTiger/ProfileSupport.m macos/GDriveBackupTiger/BackupStatusSupport.m \
			macos/GDriveBackupTiger/SetupHealthSupport.m macos/GDriveBackupTiger/RestoreSupport.m \
			macos/GDriveBackupTiger/RestoreBrowserView.m macos/GDriveBackupTiger/DiagnosticsSupport.m \
			macos/GDriveBackupTiger/DiagnosticsView.m macos/GDriveBackupTiger/UpdateSupport.m \
			macos/GDriveBackupTiger/Localization.m \
			-o "$$PROFILE_UI_TEST_BIN"; \
		"$$PROFILE_UI_TEST_BIN"; \
		./scripts/trash-path.sh "$$PROFILE_UI_TEST_BIN"
	@UPDATE_UI_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-update-ui-test.XXXXXX")"; \
		clang $(OBJC_FLAGS) -framework Cocoa -I macos/GDriveBackupTiger \
			tests/update-ui-test.m macos/GDriveBackupTiger/ConfigSupport.m \
			macos/GDriveBackupTiger/ProfileSupport.m macos/GDriveBackupTiger/BackupStatusSupport.m \
			macos/GDriveBackupTiger/SetupHealthSupport.m macos/GDriveBackupTiger/RestoreSupport.m \
			macos/GDriveBackupTiger/RestoreBrowserView.m macos/GDriveBackupTiger/DiagnosticsSupport.m \
			macos/GDriveBackupTiger/DiagnosticsView.m macos/GDriveBackupTiger/UpdateSupport.m \
			macos/GDriveBackupTiger/Localization.m -o "$$UPDATE_UI_TEST_BIN"; \
		"$$UPDATE_UI_TEST_BIN"; \
		./scripts/trash-path.sh "$$UPDATE_UI_TEST_BIN"
	bash tests/trash-path-test.sh
	bash tests/window-behavior-test.sh
	bash tests/setup-window-health-test.sh
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
