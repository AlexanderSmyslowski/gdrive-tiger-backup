#import <Cocoa/Cocoa.h>

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface SetupHealthAsyncDelegate : AppDelegate
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *testUpdates;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *testSavedConfig;
@end

@implementation SetupHealthAsyncDelegate

- (NSDictionary<NSString *, NSString *> *)currentSetupUpdates {
    return self.testUpdates ?: @{};
}

- (NSDictionary<NSString *, NSString *> *)savedSetupConfig {
    return self.testSavedConfig ?: @{};
}

@end

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static void ApplySnapshot(NSView *view, NSDictionary<NSString *, id> *snapshot) {
    SEL selector = NSSelectorFromString(@"applySnapshot:");
    if (![view respondsToSelector:selector]) {
        return;
    }
    typedef void (*ApplyMethod)(id, SEL, NSDictionary *);
    ApplyMethod method = (ApplyMethod)[view methodForSelector:selector];
    method(view, selector, snapshot);
}

static void CompleteCheck(AppDelegate *delegate, NSDictionary<NSString *, id> *snapshot) {
    SEL selector = NSSelectorFromString(@"completeSetupHealthCheck:");
    if (![delegate respondsToSelector:selector]) {
        return;
    }
    typedef void (*CompleteMethod)(id, SEL, NSDictionary *);
    CompleteMethod method = (CompleteMethod)[delegate methodForSelector:selector];
    method(delegate, selector, snapshot);
}

static void RunCheck(AppDelegate *delegate) {
    SEL selector = NSSelectorFromString(@"runSetupHealthCheck:");
    if (![delegate respondsToSelector:selector]) {
        return;
    }
    typedef void (*RunMethod)(id, SEL, id);
    RunMethod method = (RunMethod)[delegate methodForSelector:selector];
    method(delegate, selector, nil);
}

static void InstallHealthView(AppDelegate *delegate, NSView *contentView) {
    SEL selector = NSSelectorFromString(@"installSetupHealthViewInContentView:");
    if (![delegate respondsToSelector:selector]) {
        return;
    }
    typedef void (*InstallMethod)(id, SEL, NSView *);
    InstallMethod method = (InstallMethod)[delegate methodForSelector:selector];
    method(delegate, selector, contentView);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Class healthViewClass = NSClassFromString(@"TigerSetupHealthView");
        NSView *healthView = healthViewClass
            ? [[healthViewClass alloc] initWithFrame:NSMakeRect(0, 0, 580, 116)]
            : nil;
        NSArray<NSTextField *> *titleLabels = healthView
            ? [healthView valueForKey:@"rowTitleLabels"]
            : nil;
        NSArray<NSTextField *> *detailLabels = healthView
            ? [healthView valueForKey:@"rowDetailLabels"]
            : nil;
        NSArray<NSTextField *> *symbolLabels = healthView
            ? [healthView valueForKey:@"rowSymbolLabels"]
            : nil;
        NSButton *checkButton = healthView
            ? [healthView valueForKey:@"checkButton"]
            : nil;

        BOOL nativeRows = titleLabels.count == 3 &&
            detailLabels.count == 3 &&
            symbolLabels.count == 3;
        for (NSTextField *label in [titleLabels arrayByAddingObjectsFromArray:detailLabels ?: @[]]) {
            nativeRows = nativeRows &&
                [label.accessibilityRole isEqualToString:NSAccessibilityStaticTextRole] &&
                label.accessibilityLabel.length > 0;
        }
        Assert(healthView && nativeRows,
               @"setup health exposes three native text rows with VoiceOver semantics");
        Assert(checkButton &&
               [checkButton.accessibilityRole isEqualToString:NSAccessibilityButtonRole] &&
               checkButton.accessibilityLabel.length > 0,
               @"setup health uses one native accessible check button");

        ApplySnapshot(healthView, @{
            @"overall": @"failure",
            @"dependencies": @{
                @"status": @"ready",
                @"detailKey": @"setupCheckDependenciesReady"
            },
            @"remote": @{
                @"status": @"failure",
                @"detailKey": @"setupCheckRemoteMissing",
                @"action": @"configureRemote"
            },
            @"destination": @{
                @"status": @"blocked",
                @"detailKey": @"setupCheckDestinationUnavailable"
            }
        });
        Assert([symbolLabels[0].stringValue isEqualToString:@"✓"] &&
               [symbolLabels[1].stringValue isEqualToString:@"×"] &&
               [symbolLabels[2].stringValue isEqualToString:@"—"],
               @"ready, failure, and blocked states remain distinct without color");
        Assert([detailLabels[0].stringValue
                   isEqualToString:T(@"en", @"setupCheckDependenciesReady")] &&
               [detailLabels[1].stringValue
                   isEqualToString:T(@"en", @"setupCheckRemoteMissing")] &&
               [detailLabels[1].accessibilityLabel containsString:detailLabels[1].stringValue],
               @"health rows expose localized status text to sighted and VoiceOver users");

        NSArray<NSString *> *healthKeys = @[
            @"setupCheckSectionTitle", @"setupCheckButton", @"setupCheckRunning",
            @"setupCheckNotRun", @"setupCheckDependenciesLabel",
            @"setupCheckRemoteLabel", @"setupCheckDestinationLabel",
            @"setupCheckDependenciesReady", @"setupCheckDependenciesMissing",
            @"setupCheckRemoteBlocked", @"setupCheckRemoteMissing",
            @"setupCheckRemoteReady", @"setupCheckRemoteUnavailable",
            @"setupCheckDestinationReady", @"setupCheckDestinationUnavailable",
            @"setupCheckEncryptedAPFSRequired", @"setupCheckEncryptedAPFSReady",
            @"setupCheckReady", @"setupCheckNeedsAttention"
        ];
        BOOL localized = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            for (NSString *key in healthKeys) {
                NSString *value = T(language, key);
                localized = localized && value.length > 0 && ![value isEqualToString:key];
            }
        }
        Assert(localized, @"setup health text is localized in every supported language");

        [healthView setValue:@"de" forKey:@"language"];
        NSTextField *sectionTitle = nil;
        SEL titleSelector = NSSelectorFromString(@"titleLabel");
        if ([healthView respondsToSelector:titleSelector]) {
            typedef NSTextField *(*TitleMethod)(id, SEL);
            TitleMethod titleMethod = (TitleMethod)[healthView methodForSelector:titleSelector];
            sectionTitle = titleMethod(healthView, titleSelector);
        }
        Assert([titleLabels[0].stringValue isEqualToString:T(@"de", @"setupCheckDependenciesLabel")] &&
               [titleLabels[1].stringValue isEqualToString:T(@"de", @"setupCheckRemoteLabel")] &&
               [titleLabels[2].stringValue isEqualToString:T(@"de", @"setupCheckDestinationLabel")] &&
               [checkButton.title isEqualToString:T(@"de", @"setupCheckButton")],
               @"changing language updates every visible setup-health control");
        Assert(sectionTitle &&
               [sectionTitle.stringValue isEqualToString:T(@"de", @"setupCheckSectionTitle")] &&
               sectionTitle.accessibilityLabel.length > 0,
               @"setup health has one native localized section heading");

        BOOL buttonTitlesFit = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            [healthView setValue:language forKey:@"language"];
            NSFont *font = checkButton.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize];
            CGFloat requiredWidth = [checkButton.title sizeWithAttributes:@{NSFontAttributeName: font}].width + 32.0;
            buttonTitlesFit = buttonTitlesFit &&
                NSWidth(checkButton.frame) >= requiredWidth &&
                NSMaxX(checkButton.frame) <= NSWidth(healthView.bounds);
        }
        Assert(buttonTitlesFit,
               @"localized setup-check button titles remain fully visible");
        [healthView setValue:@"de" forKey:@"language"];

        __block NSInteger checkCalls = 0;
        [healthView setValue:[^{ checkCalls++; } copy] forKey:@"checkHandler"];
        [checkButton performClick:nil];
        [checkButton performClick:nil];
        BOOL allChecking = YES;
        for (NSTextField *symbol in symbolLabels) {
            allChecking = allChecking && [symbol.stringValue isEqualToString:@"…"];
        }
        Assert(checkCalls == 1 && !checkButton.enabled && allChecking,
               @"setup check enters one visible loading state and ignores repeated clicks");
        Assert([detailLabels[0].stringValue isEqualToString:T(@"de", @"setupCheckRunning")] &&
               [detailLabels[0].accessibilityLabel containsString:T(@"de", @"setupCheckRunning")],
               @"checking state is visible and announced instead of relying on animation");

        [healthView setValue:@NO forKey:@"checking"];
        ApplySnapshot(healthView, @{
            @"overall": @"failure",
            @"dependencies": @{
                @"status": @"failure",
                @"detailKey": @"setupCheckDependenciesMissing",
                @"missing": @[@"flock", @"jq"]
            },
            @"remote": @{
                @"status": @"blocked",
                @"detailKey": @"setupCheckRemoteBlocked"
            },
            @"destination": @{
                @"status": @"ready",
                @"detailKey": @"setupCheckDestinationReady"
            }
        });
        NSString *expectedMissing = [NSString stringWithFormat:
            T(@"de", @"setupCheckDependenciesMissing"), @"flock, jq"];
        Assert([detailLabels[0].stringValue isEqualToString:expectedMissing] &&
               ![detailLabels[0].stringValue containsString:@"%@"],
               @"missing tools are named in plain language without raw placeholders");

        AppDelegate *delegate = [[AppDelegate alloc] init];
        delegate.language = @"de";
        delegate.statusField = [[NSTextField alloc] init];
        TigerSetupHealthView *integratedView =
            [[TigerSetupHealthView alloc] initWithFrame:NSMakeRect(0, 0, 580, 116)];
        integratedView.language = @"de";
        integratedView.checking = YES;
        SEL setViewSelector = NSSelectorFromString(@"setSetupHealthView:");
        if ([delegate respondsToSelector:setViewSelector]) {
            typedef void (*SetViewMethod)(id, SEL, TigerSetupHealthView *);
            SetViewMethod setView = (SetViewMethod)[delegate methodForSelector:setViewSelector];
            setView(delegate, setViewSelector, integratedView);
        }
        CompleteCheck(delegate, @{
            @"overall": @"ready",
            @"dependencies": @{
                @"status": @"ready", @"detailKey": @"setupCheckDependenciesReady"
            },
            @"remote": @{
                @"status": @"ready", @"detailKey": @"setupCheckRemoteReady"
            },
            @"destination": @{
                @"status": @"ready", @"detailKey": @"setupCheckDestinationReady"
            }
        });
        Assert(!integratedView.checking &&
               [delegate.statusField.stringValue isEqualToString:T(@"de", @"setupCheckReady")] &&
               [integratedView.rowSymbolLabels[0].stringValue isEqualToString:@"✓"],
               @"completed setup check updates rows and reports one ready result inline");

        CompleteCheck(delegate, @{
            @"overall": @"failure",
            @"dependencies": @{
                @"status": @"failure",
                @"detailKey": @"setupCheckDependenciesMissing",
                @"missing": @[@"flock"]
            },
            @"remote": @{
                @"status": @"blocked", @"detailKey": @"setupCheckRemoteBlocked"
            },
            @"destination": @{
                @"status": @"ready", @"detailKey": @"setupCheckDestinationReady"
            }
        });
        Assert([delegate.statusField.stringValue
                   isEqualToString:T(@"de", @"setupCheckNeedsAttention")],
               @"failed setup check reports attention inline without opening a modal");

        SEL invalidateSelector = NSSelectorFromString(@"invalidateSetupHealth:");
        if ([delegate respondsToSelector:invalidateSelector]) {
            typedef void (*InvalidateMethod)(id, SEL, id);
            InvalidateMethod invalidate = (InvalidateMethod)[delegate methodForSelector:invalidateSelector];
            invalidate(delegate, invalidateSelector, nil);
        }
        Assert([integratedView.rowSymbolLabels[0].stringValue isEqualToString:@"?"] &&
               [integratedView.rowSymbolLabels[1].stringValue isEqualToString:@"?"] &&
               [integratedView.rowSymbolLabels[2].stringValue isEqualToString:@"?"] &&
               [delegate.statusField.stringValue isEqualToString:T(@"de", @"setupCheckNotRun")],
               @"editing setup invalidates a previously completed system check");

        SetupHealthAsyncDelegate *asyncDelegate = [[SetupHealthAsyncDelegate alloc] init];
        asyncDelegate.language = @"en";
        asyncDelegate.statusField = [[NSTextField alloc] init];
        asyncDelegate.setupBackupButton = [[NSButton alloc] init];
        asyncDelegate.setupDryRunButton = [[NSButton alloc] init];
        asyncDelegate.setupHealthView =
            [[TigerSetupHealthView alloc] initWithFrame:NSMakeRect(0, 0, 580, 116)];
        asyncDelegate.testSavedConfig = @{@"RCLONE_REMOTE": @"gdrive"};
        asyncDelegate.testUpdates = @{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_VOLUME": NSTemporaryDirectory(),
            @"GDRIVE_BACKUP_ENCRYPTION": @"none"
        };
        __block NSInteger asyncRunnerCalls = 0;
        __block BOOL ranOffMainThread = YES;
        GDTSetupHealthChecker *asyncChecker = [[GDTSetupHealthChecker alloc] init];
        asyncChecker.commandAvailability = ^BOOL(NSString *command) {
            (void)command;
            return YES;
        };
        asyncChecker.commandRunner =
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                (void)command;
                ranOffMainThread = ranOffMainThread && !NSThread.isMainThread;
                asyncRunnerCalls++;
                return [arguments.firstObject isEqualToString:@"listremotes"]
                    ? @{@"status": @0, @"output": @"gdrive:\n"}
                    : @{@"status": @0, @"output": @"{}"};
            };
        asyncDelegate.setupHealthChecker = asyncChecker;
        __weak SetupHealthAsyncDelegate *weakAsyncDelegate = asyncDelegate;
        asyncDelegate.setupHealthView.checkHandler = ^{
            RunCheck(weakAsyncDelegate);
        };

        [asyncDelegate.setupHealthView.checkButton performClick:nil];
        BOOL disabledDuringCheck = asyncDelegate.setupHealthCheckInFlight &&
            !asyncDelegate.setupBackupButton.enabled &&
            !asyncDelegate.setupDryRunButton.enabled;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (asyncDelegate.setupHealthCheckInFlight && [deadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                  beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Assert(disabledDuringCheck && ranOffMainThread && asyncRunnerCalls == 2,
               @"setup check runs off the main thread and disables start actions once");
        Assert(!asyncDelegate.setupHealthCheckInFlight &&
               asyncDelegate.setupBackupButton.enabled &&
               asyncDelegate.setupDryRunButton.enabled &&
               [asyncDelegate.statusField.stringValue isEqualToString:T(@"en", @"setupCheckReady")],
               @"asynchronous setup check restores actions and publishes one final result");

        asyncChecker.commandRunner =
            ^NSDictionary<NSString *, id> *(NSString *command, NSArray<NSString *> *arguments) {
                (void)command;
                [NSThread sleepForTimeInterval:0.03];
                return [arguments.firstObject isEqualToString:@"listremotes"]
                    ? @{@"status": @0, @"output": @"gdrive:\n"}
                    : @{@"status": @0, @"output": @"{}"};
            };
        [asyncDelegate.setupHealthView.checkButton performClick:nil];
        if ([asyncDelegate respondsToSelector:invalidateSelector]) {
            typedef void (*InvalidateMethod)(id, SEL, id);
            InvalidateMethod invalidate = (InvalidateMethod)[asyncDelegate methodForSelector:invalidateSelector];
            invalidate(asyncDelegate, invalidateSelector, nil);
        }
        deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (asyncDelegate.setupHealthCheckInFlight && [deadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                  beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Assert([asyncDelegate.setupHealthView.rowSymbolLabels[0].stringValue isEqualToString:@"?"] &&
               [asyncDelegate.statusField.stringValue isEqualToString:T(@"en", @"setupCheckNotRun")],
               @"an edit during an asynchronous check discards the stale result");

        AppDelegate *layoutDelegate = [[AppDelegate alloc] init];
        layoutDelegate.language = @"fr";
        TigerSetupView *setupContent =
            [[TigerSetupView alloc] initWithFrame:NSMakeRect(0, 0, 650, 640)];
        InstallHealthView(layoutDelegate, setupContent);
        Assert(layoutDelegate.setupHealthView.superview == setupContent &&
               NSWidth(layoutDelegate.setupHealthView.frame) >= 580 &&
               layoutDelegate.setupHealthView.checkHandler != nil,
               @"setup installs one full-width health section with a wired action");
        Assert([layoutDelegate.setupHealthView.language isEqualToString:@"fr"] &&
               [layoutDelegate.setupHealthView.titleLabel.stringValue
                   isEqualToString:T(@"fr", @"setupCheckSectionTitle")],
               @"installed health section inherits the setup language");
    }

    if (failures > 0) {
        printf("%d setup health UI test(s) failed.\n", failures);
        return 1;
    }
    printf("All setup health UI tests passed.\n");
    return 0;
}
