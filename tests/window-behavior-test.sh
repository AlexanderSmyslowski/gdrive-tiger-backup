#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_SOURCE="$ROOT/macos/GDriveBackupTiger/main.m"
failures=0

startup_method="$(/usr/bin/awk '
  /^- \(void\)applicationDidFinishLaunching:/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
sentinel_method="$(/usr/bin/awk '
  /^- \(void\)checkSentinel/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
terminal_method="$(/usr/bin/awk '
  /^- \(void\)showTerminalStateAndQuit:/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
close_method="$(/usr/bin/awk '
  /^- \(BOOL\)windowShouldClose:/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
miniaturize_method="$(/usr/bin/awk '
  /^- \(BOOL\)windowShouldMiniaturize:/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
termination_policy_method="$(/usr/bin/awk '
  /^- \(BOOL\)applicationShouldTerminateAfterLastWindowClosed:/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
status_item_method="$(/usr/bin/awk '
  /^- \(void\)installStatusItemIfNeeded/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
overview_refresh_method="$(/usr/bin/awk '
  /^- \(void\)refreshOverviewStatus/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
status_presentation_method="$(/usr/bin/awk '
  /^- \(void\)updateStatusItemPresentationForSnapshot/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
collection_behavior_method="$(/usr/bin/awk '
  /^- \(NSWindowCollectionBehavior\)statusWindowCollectionBehavior/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
restore_method="$(/usr/bin/awk '
  /^- \(void\)restoreWindowFromDock/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"

check_contains() {
  local expected="$1"
  local description="$2"
  if [[ "$startup_method" == *"$expected"* ]]; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  fi
}

check_absent() {
  local forbidden="$1"
  local description="$2"
  if [[ "$startup_method" != *"$forbidden"* ]]; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  fi
}

check_contains \
  'self.window.level = self.confirmMode ? NSFloatingWindowLevel : NSNormalWindowLevel;' \
  'only confirmation windows use the floating level'
check_absent \
  'self.window.level = NSFloatingWindowLevel;' \
  'normal progress startup does not unconditionally float the window'

safe_progress_presentation=$'if (self.confirmMode && self.progressForegroundMode) {\n        [self.window makeKeyAndOrderFront:nil];\n        [NSApp activateIgnoringOtherApps:YES];\n    } else {\n        [self.window orderFront:nil];\n    }'
check_contains "$safe_progress_presentation" \
  'only an explicitly requested confirmation activates the app or becomes key'

activation_count="$(/usr/bin/grep -Fc '[NSApp activateIgnoringOtherApps:YES];' <<<"$startup_method")"
if [[ "$activation_count" == "1" ]]; then
  printf '%s\n' 'ok - startup has one explicit-confirmation activation path'
else
  printf 'not ok - expected one confirmation-only startup activation, found %s\n' "$activation_count"
  failures=$((failures + 1))
fi

if [[ "$collection_behavior_method" == *'NSWindowCollectionBehaviorManaged'* &&
      "$collection_behavior_method" == *'NSWindowCollectionBehaviorFullScreenNone'* &&
      "$collection_behavior_method" != *'NSWindowCollectionBehaviorCanJoinAllSpaces'* &&
      "$collection_behavior_method" != *'NSWindowCollectionBehaviorFullScreenAuxiliary'* &&
      "$startup_method" == *'self.window.collectionBehavior = [self statusWindowCollectionBehavior];'* &&
      "$startup_method" == *'self.window.hidesOnDeactivate = [self statusWindowShouldHideOnDeactivate];'* ]]; then
  printf '%s\n' 'ok - background status windows stay on one normal Space with mode-specific visibility'
else
  printf '%s\n' 'not ok - a background status window can still enter another app or fullscreen Space'
  failures=$((failures + 1))
fi

if [[ "$startup_method" != *'[self.window orderFrontRegardless];'* ]]; then
  printf '%s\n' 'ok - startup never forces the status window above the active app'
else
  printf '%s\n' 'not ok - startup still uses orderFrontRegardless'
  failures=$((failures + 1))
fi

if [[ "$startup_method" == *'self.progressForegroundMode = [self shouldForegroundProgressForArguments:arguments];'* &&
      "$startup_method" == *'[NSApp setActivationPolicy:self.progressForegroundMode'* ]]; then
  printf '%s\n' 'ok - only explicitly requested manual progress receives a Dock presence'
else
  printf '%s\n' 'not ok - manual progress cannot reliably appear from the Dock'
  failures=$((failures + 1))
fi

if [[ "$terminal_method" != *'activateIgnoringOtherApps:YES'* &&
      "$terminal_method" != *'orderFrontRegardless'* &&
      "$terminal_method" == *'if (self.hiddenByUser || !self.window.isVisible || !NSApp.isActive) {'* &&
      "$terminal_method" == *'[NSApp terminate:nil];'* ]]; then
  printf '%s\n' 'ok - hidden or inactive progress stays hidden when the backup finishes'
else
  printf '%s\n' 'not ok - completion can still reappear over the active app'
  failures=$((failures + 1))
fi

if [[ "$restore_method" != *'orderFrontRegardless'* &&
      "$restore_method" == *'[self.window makeKeyAndOrderFront:nil];'* ]]; then
  printf '%s\n' 'ok - an explicit Dock reopen uses normal AppKit ordering'
else
  printf '%s\n' 'not ok - Dock reopen still relies on forced front ordering'
  failures=$((failures + 1))
fi

if [[ "$startup_method" == *'self.runStatePath = arguments[3];'* ]]; then
  printf '%s\n' 'ok - progress startup receives the explicit run state path'
else
  printf '%s\n' 'not ok - progress startup ignores the explicit run state path'
  failures=$((failures + 1))
fi

if [[ "$sentinel_method" == *'[self showTerminalStateAndQuit:status];'* &&
      "$sentinel_method" != *'[self showCompletionAndQuit];'* ]]; then
  printf '%s\n' 'ok - sentinel disappearance resolves the explicit terminal state'
else
  printf '%s\n' 'not ok - sentinel disappearance still implies success'
  failures=$((failures + 1))
fi

if [[ "$sentinel_method" == *'NSString *status = [self runStatusAtPath:self.runStatePath];'* &&
      "$sentinel_method" == *'if (![status isEqualToString:@"running"]) {'* ]]; then
  printf '%s\n' 'ok - a dead running process is detected even when its sentinel remains'
else
  printf '%s\n' 'not ok - stale sentinels can leave the progress window running forever'
  failures=$((failures + 1))
fi

if [[ "$terminal_method" == *'[self applyTerminalStatus:status toView:contentView];'* &&
      "$terminal_method" != *'[self showCompletionAndQuit];'* ]]; then
  printf '%s\n' 'ok - every terminal outcome is presented instead of success-only handling'
else
  printf '%s\n' 'not ok - non-success terminal outcomes are not presented'
  failures=$((failures + 1))
fi

if [[ "$close_method" == *'if (self.setupMode) {'* &&
      "$close_method" == *'[self finishConfirmation:NO];'* &&
      "$close_method" == *'[self minimizeWindow];'* ]]; then
  printf '%s\n' 'ok - native close control has safe semantics for every mode'
else
  printf '%s\n' 'not ok - native close control can strand or abort the wrong mode'
  failures=$((failures + 1))
fi

if [[ "$miniaturize_method" == *'[self minimizeWindow];'* ]]; then
  printf '%s\n' 'ok - native minimize control preserves the Dock workflow'
else
  printf '%s\n' 'not ok - native minimize control bypasses the Dock workflow'
  failures=$((failures + 1))
fi

if [[ "$startup_method" == *'[self applicationModeForArguments:arguments]'* &&
      "$startup_method" == *'[self showOverviewWindow];'* &&
      "$startup_method" == *'[self installStatusItemIfNeeded];'* ]]; then
  printf '%s\n' 'ok - normal launch opens the overview and installs its menu bar controller'
else
  printf '%s\n' 'not ok - normal launch still bypasses the overview or menu bar controller'
  failures=$((failures + 1))
fi

if [[ "$close_method" == *'if (self.overviewMode) {'* &&
      "$close_method" == *'[self.window orderOut:nil];'* &&
      "$termination_policy_method" == *'return self.setupMode && !self.overviewMode && !self.rebuildingSetupWindow;'* ]]; then
  printf '%s\n' 'ok - closing the overview hides it while the menu bar controller remains alive'
else
  printf '%s\n' 'not ok - closing the overview can terminate the menu bar controller'
  failures=$((failures + 1))
fi

if [[ "$status_item_method" == *'if (self.statusItem)'* &&
      "$status_item_method" == *'NSStatusBar.systemStatusBar'* &&
      "$status_presentation_method" == *'accessibilityLabel'* &&
      "$overview_refresh_method" == *'overviewSnapshotForConfig:'* &&
      "$overview_refresh_method" == *'statusMenuForSnapshot:'* ]]; then
  printf '%s\n' 'ok - one accessible status item reuses the same overview snapshot'
else
  printf '%s\n' 'not ok - menu bar state is missing, duplicated, or disconnected from the overview'
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '%s window behavior regression check(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All window behavior regression checks passed.'
