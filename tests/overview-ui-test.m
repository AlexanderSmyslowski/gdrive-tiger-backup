#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface OverviewLaunchDelegate : AppDelegate
@property(nonatomic) NSInteger launchCalls;
@property(nonatomic) BOOL launchSucceeds;
@property(nonatomic) BOOL sawImmediatePreparingState;
@property(nonatomic) NSInteger progressHandoffCalls;
@property(nonatomic) NSInteger overviewShowCalls;
@property(nonatomic) NSInteger dockRestoreCalls;
@end

@implementation OverviewLaunchDelegate

- (BOOL)launchBackupWithArgument:(NSString *)argument assumeYes:(BOOL)assumeYes {
    (void)argument;
    (void)assumeYes;
    self.launchCalls++;
    TigerOverviewView *view = [self.window.contentView isKindOfClass:TigerOverviewView.class]
        ? (TigerOverviewView *)self.window.contentView : nil;
    self.sawImmediatePreparingState = view &&
        [view.lastRunValueLabel.stringValue isEqualToString:T(self.language ?: @"en", @"statusBackupPreparing")] &&
        !view.backupButton.enabled;
    return self.launchSucceeds;
}

- (void)handoffOverviewDockPresenceToManualProgress {
    self.progressHandoffCalls++;
}

- (void)showOverviewWindow {
    self.overviewShowCalls++;
}

- (void)restoreWindowFromDock {
    self.dockRestoreCalls++;
}

@end

@interface SetupPresentationDelegate : AppDelegate
@property(nonatomic) NSInteger mountedNASRefreshCalls;
@property(nonatomic) BOOL sawVisibleSetupAtRefresh;
@end

@implementation SetupPresentationDelegate

- (void)refreshMountedNASAllowingTargetAutoSelection:(BOOL)allowAutomaticTargetSelection {
    (void)allowAutomaticTargetSelection;
    self.mountedNASRefreshCalls++;
    self.sawVisibleSetupAtRefresh = self.setupWindow.isVisible;
}

@end

@interface AsyncMountedNASDelegate : AppDelegate
@property(nonatomic, strong) dispatch_semaphore_t loadStarted;
@property(nonatomic, strong) dispatch_semaphore_t allowLoadToFinish;
@property(nonatomic) NSInteger loadCalls;
@end

@implementation AsyncMountedNASDelegate

- (NSArray<NSDictionary<NSString *, NSString *> *> *)mountedNetworkVolumes {
    self.loadCalls++;
    dispatch_semaphore_signal(self.loadStarted);
    dispatch_semaphore_wait(self.allowLoadToFinish, DISPATCH_TIME_FOREVER);
    return @[@{
        @"name": @"Archive",
        @"path": @"/Volumes/Archive",
        @"url": @"smb://server/Archive",
        @"writable": @"1",
        @"readable": @"1"
    }];
}

@end

@interface FakeSetupWindow : NSObject
@property(nonatomic) BOOL visible;
@end

@implementation FakeSetupWindow

- (BOOL)isVisible {
    return self.visible;
}

- (BOOL)isMiniaturized {
    return NO;
}

- (void)setDelegate:(id)delegate {
    (void)delegate;
}

- (void)orderOut:(id)sender {
    (void)sender;
    self.visible = NO;
}

- (void)close {
    self.visible = NO;
}

@end

@interface AppDelegate (MountedNASCompletionTesting)
- (void)completeMountedNetworkVolumeDiscovery:
    (NSArray<NSDictionary<NSString *, NSString *> *> *)volumes
    generation:(NSUInteger)generation
    allowingTargetAutoSelection:(BOOL)allowAutomaticTargetSelection;
@end

@interface RebuildMountedNASDelegate : AsyncMountedNASDelegate
@property(nonatomic, strong) dispatch_semaphore_t completionObserved;
@property(nonatomic) NSInteger completionCalls;
@property(nonatomic) NSInteger rebuildShowCalls;
@end

@implementation RebuildMountedNASDelegate

- (void)showSetupWindow {
    self.rebuildShowCalls++;
    FakeSetupWindow *window = [[FakeSetupWindow alloc] init];
    window.visible = YES;
    self.setupWindow = (NSWindow *)(id)window;
    self.mountedNasPopup =
        [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 28)];
}

- (void)completeMountedNetworkVolumeDiscovery:
    (NSArray<NSDictionary<NSString *, NSString *> *> *)volumes
    generation:(NSUInteger)generation
    allowingTargetAutoSelection:(BOOL)allowAutomaticTargetSelection {
    self.completionCalls++;
    Method productionMethod = class_getInstanceMethod(AppDelegate.class, _cmd);
    if (productionMethod) {
        typedef void (*CompletionMethod)(
            id, SEL, NSArray<NSDictionary<NSString *, NSString *> *> *,
            NSUInteger, BOOL);
        CompletionMethod completion =
            (CompletionMethod)method_getImplementation(productionMethod);
        completion(self, _cmd, volumes, generation,
                   allowAutomaticTargetSelection);
    }
    dispatch_semaphore_signal(self.completionObserved);
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

int main(void) {
    @autoreleasepool {
        TigerOverviewView *view = [[TigerOverviewView alloc] initWithFrame:NSMakeRect(0, 0, 620, 420)];
        view.language = @"en";
        view.lastRunText = @"Successful";
        view.lastRunDetail = @"Today, 19:42";
        view.nextRunText = @"Today, 20:00";
        view.targetText = @"Archive — /Volumes/Archive";
        view.storageText = @"812 GB free of 2 TB";
        view.status = @"success";

        NSArray<NSTextField *> *valueLabels = @[
            view.lastRunValueLabel,
            view.lastRunDetailLabel,
            view.nextRunValueLabel,
            view.targetValueLabel,
            view.storageValueLabel
        ];
        BOOL nativeStaticValues = YES;
        for (NSTextField *label in valueLabels) {
            nativeStaticValues = nativeStaticValues && label != nil &&
                !label.editable && !label.selectable &&
                [label.accessibilityRole isEqualToString:NSAccessibilityStaticTextRole] &&
                label.accessibilityLabel.length > 0;
        }
        Assert(nativeStaticValues,
               @"overview exposes last run, schedule, target, and storage as native accessible text");
        Assert([view.lastRunValueLabel.stringValue isEqualToString:@"Successful"] &&
               [view.nextRunValueLabel.stringValue isEqualToString:@"Today, 20:00"] &&
               [view.targetValueLabel.stringValue isEqualToString:@"Archive — /Volumes/Archive"] &&
               [view.storageValueLabel.stringValue isEqualToString:@"812 GB free of 2 TB"],
               @"overview applies one shared snapshot without losing values");

        SEL restoreButtonSelector = NSSelectorFromString(@"restoreButton");
        NSButton *restoreButton = nil;
        if ([view respondsToSelector:restoreButtonSelector]) {
            typedef NSButton *(*ButtonMethod)(id, SEL);
            ButtonMethod buttonMethod = (ButtonMethod)[view methodForSelector:restoreButtonSelector];
            restoreButton = buttonMethod(view, restoreButtonSelector);
        }
        Assert(view.backupButton != nil && view.settingsButton != nil && restoreButton != nil &&
               [view.backupButton.keyEquivalent isEqualToString:@"\r"] &&
               [view.backupButton.accessibilityRole isEqualToString:NSAccessibilityButtonRole] &&
               [view.settingsButton.accessibilityRole isEqualToString:NSAccessibilityButtonRole] &&
               [restoreButton.accessibilityRole isEqualToString:NSAccessibilityButtonRole],
               @"overview actions use native keyboard and VoiceOver controls");

        __block NSInteger backupActions = 0;
        __block NSInteger settingsActions = 0;
        __block NSInteger restoreActions = 0;
        view.backupHandler = ^{ backupActions++; };
        view.settingsHandler = ^{ settingsActions++; };
        SEL setRestoreHandlerSelector = NSSelectorFromString(@"setRestoreHandler:");
        if ([view respondsToSelector:setRestoreHandlerSelector]) {
            typedef void (*SetHandlerMethod)(id, SEL, id);
            SetHandlerMethod setHandler = (SetHandlerMethod)[view methodForSelector:setRestoreHandlerSelector];
            setHandler(view, setRestoreHandlerSelector, [^{ restoreActions++; } copy]);
        }
        [view.backupButton performClick:nil];
        [view.settingsButton performClick:nil];
        [restoreButton performClick:nil];
        Assert(backupActions == 1 && settingsActions == 1 && restoreActions == 1,
               @"overview actions fire exactly once");

        __block NSString *largeCommandOutput = nil;
        __block int largeCommandStatus = -1;
        dispatch_semaphore_t commandFinished = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            largeCommandOutput = RunCommand(@"/usr/bin/awk", @[
                @"BEGIN { for (i = 0; i < 20000; i++) print \"0123456789abcdef\" }"
            ], nil, &largeCommandStatus);
            dispatch_semaphore_signal(commandFinished);
        });
        BOOL largeCommandCompleted =
            dispatch_semaphore_wait(commandFinished,
                dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
        Assert(largeCommandCompleted &&
               largeCommandStatus == 0 &&
               largeCommandOutput.length > 300000,
               @"command runner drains output larger than its pipe without deadlocking");

        AsyncMountedNASDelegate *asyncMountedNAS =
            [[AsyncMountedNASDelegate alloc] init];
        asyncMountedNAS.language = @"en";
        asyncMountedNAS.loadStarted = dispatch_semaphore_create(0);
        asyncMountedNAS.allowLoadToFinish = dispatch_semaphore_create(0);
        asyncMountedNAS.setupWindow = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 100, 100)
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered
                          defer:NO];
        asyncMountedNAS.mountedNasPopup =
            [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 28)];
        [asyncMountedNAS refreshMountedNASAllowingTargetAutoSelection:NO];
        BOOL mountedLoadStarted =
            dispatch_semaphore_wait(asyncMountedNAS.loadStarted,
                dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0;
        [asyncMountedNAS refreshMountedNASAllowingTargetAutoSelection:NO];
        dispatch_semaphore_signal(asyncMountedNAS.allowLoadToFinish);
        NSDate *mountedLoadDeadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (!asyncMountedNAS.mountedNasPopup.enabled &&
               [mountedLoadDeadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:
                [NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Assert(mountedLoadStarted &&
               asyncMountedNAS.loadCalls == 1 &&
               asyncMountedNAS.mountedNasPopup.enabled &&
               asyncMountedNAS.mountedNasPopup.numberOfItems == 2,
               @"mounted-volume discovery stays asynchronous and coalesces repeated refreshes");

        RebuildMountedNASDelegate *staleMountedNAS =
            [[RebuildMountedNASDelegate alloc] init];
        staleMountedNAS.language = @"en";
        staleMountedNAS.loadStarted = dispatch_semaphore_create(0);
        staleMountedNAS.allowLoadToFinish = dispatch_semaphore_create(0);
        staleMountedNAS.completionObserved = dispatch_semaphore_create(0);
        FakeSetupWindow *staleSetupWindow = [[FakeSetupWindow alloc] init];
        staleSetupWindow.visible = YES;
        staleMountedNAS.setupWindow = (NSWindow *)(id)staleSetupWindow;
        staleMountedNAS.mountedNasPopup =
            [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 28)];
        [staleMountedNAS refreshMountedNASAllowingTargetAutoSelection:NO];
        BOOL staleLoadStarted =
            dispatch_semaphore_wait(staleMountedNAS.loadStarted,
                dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0;
        SEL rebuildForStaleSelector =
            NSSelectorFromString(@"rebuildSetupWindowPreservingVisibility");
        if ([staleMountedNAS respondsToSelector:rebuildForStaleSelector]) {
            typedef void (*VoidMethod)(id, SEL);
            ((VoidMethod)[staleMountedNAS methodForSelector:rebuildForStaleSelector])(
                staleMountedNAS, rebuildForStaleSelector);
        }
        NSPopUpButton *replacementMountedPopup = staleMountedNAS.mountedNasPopup;
        dispatch_semaphore_signal(staleMountedNAS.allowLoadToFinish);
        NSDate *staleCompletionDeadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        BOOL staleCompletionObserved = NO;
        while (!staleCompletionObserved &&
               [staleCompletionDeadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:
                [NSDate dateWithTimeIntervalSinceNow:0.01]];
            staleCompletionObserved =
                dispatch_semaphore_wait(staleMountedNAS.completionObserved,
                    DISPATCH_TIME_NOW) == 0;
        }
        Assert(class_getInstanceMethod(
                   AppDelegate.class,
                   @selector(completeMountedNetworkVolumeDiscovery:generation:
                             allowingTargetAutoSelection:)) != NULL &&
               staleLoadStarted &&
               staleMountedNAS.loadCalls == 1 &&
               staleMountedNAS.rebuildShowCalls == 1 &&
               staleCompletionObserved &&
               staleMountedNAS.completionCalls == 1 &&
               replacementMountedPopup.numberOfItems == 0,
               @"stale mounted-volume results cannot overwrite rebuilt setup controls");

        NSString *originalConfigPath =
            [NSProcessInfo.processInfo.environment[@"GDRIVE_BACKUP_CONFIG"] copy];
        NSString *setupConfigPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-setup-presentation-%@", NSUUID.UUID.UUIDString]];
        [@"GDRIVE_BACKUP_TARGET=apfs\nGDRIVE_BACKUP_SCHEDULE=manual\n"
            writeToFile:setupConfigPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        setenv("GDRIVE_BACKUP_CONFIG", setupConfigPath.UTF8String, 1);

        SetupPresentationDelegate *setupPresenter = [[SetupPresentationDelegate alloc] init];
        setupPresenter.language = @"en";
        setupPresenter.overviewMode = YES;
        setupPresenter.window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 620, 420)
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered
                          defer:NO];
        NSWindow *overviewWindow = setupPresenter.window;
        [setupPresenter showBackupSetup:nil];
        SEL setupWindowSelector = NSSelectorFromString(@"setupWindow");
        NSWindow *firstSetupWindow = [setupPresenter respondsToSelector:setupWindowSelector]
            ? [setupPresenter valueForKey:@"setupWindow"] : nil;
        [setupPresenter showBackupSetup:nil];
        NSWindow *secondSetupWindow = [setupPresenter respondsToSelector:setupWindowSelector]
            ? [setupPresenter valueForKey:@"setupWindow"] : nil;
        Assert(firstSetupWindow != nil &&
               firstSetupWindow == secondSetupWindow &&
               setupPresenter.window == overviewWindow &&
               setupPresenter.mountedNASRefreshCalls == 1 &&
               setupPresenter.sawVisibleSetupAtRefresh,
               @"repeated setup clicks reuse one in-process window and preserve the overview");
        setupPresenter.menubarOnlyMode = YES;
        BOOL setupRequestsForegroundProgress =
            [setupPresenter shouldShowProgressForTrigger:@"manual" fromVisibleWindow:YES];
        BOOL persistentSetupStaysOwnedByController =
            ![setupPresenter windowShouldClose:firstSetupWindow] &&
            setupPresenter.window == overviewWindow &&
            !firstSetupWindow.isVisible;
        Assert(setupRequestsForegroundProgress && persistentSetupStaysOwnedByController,
               @"embedded setup can request progress and closes without terminating its controller");

        SEL rebuildSetupSelector =
            NSSelectorFromString(@"rebuildSetupWindowPreservingVisibility");
        BOOL exposesVisibilityPreservingRebuild =
            [setupPresenter respondsToSelector:rebuildSetupSelector];
        if (exposesVisibilityPreservingRebuild) {
            typedef void (*VoidMethod)(id, SEL);
            ((VoidMethod)[setupPresenter methodForSelector:rebuildSetupSelector])(
                setupPresenter, rebuildSetupSelector);
        }
        NSWindow *hiddenSetupAfterRebuild =
            [setupPresenter valueForKey:@"setupWindow"];
        Assert(exposesVisibilityPreservingRebuild &&
               !hiddenSetupAfterRebuild.isVisible,
               @"rebuilding settings never reopens a setup window the user closed");

        [setupPresenter showBackupSetup:nil];
        NSWindow *visibleSetupBeforeRebuild =
            [setupPresenter valueForKey:@"setupWindow"];
        if (exposesVisibilityPreservingRebuild) {
            typedef void (*VoidMethod)(id, SEL);
            ((VoidMethod)[setupPresenter methodForSelector:rebuildSetupSelector])(
                setupPresenter, rebuildSetupSelector);
        }
        NSWindow *visibleSetupAfterRebuild =
            [setupPresenter valueForKey:@"setupWindow"];
        Assert(exposesVisibilityPreservingRebuild &&
               visibleSetupAfterRebuild.isVisible &&
               visibleSetupAfterRebuild != visibleSetupBeforeRebuild,
               @"rebuilding visible settings replaces only the setup window");

        [setupPresenter windowShouldClose:visibleSetupAfterRebuild];
        setupPresenter.overviewMode = NO;
        setupPresenter.setupMode = YES;
        BOOL handledSetupReopen =
            ![setupPresenter applicationShouldHandleReopen:NSApp
                                         hasVisibleWindows:NO];
        setupPresenter.rebuildingSetupWindow = YES;
        BOOL rebuildKeepsStandaloneAppAlive =
            ![setupPresenter applicationShouldTerminateAfterLastWindowClosed:NSApp];
        setupPresenter.rebuildingSetupWindow = NO;
        Assert(handledSetupReopen &&
               visibleSetupAfterRebuild.isVisible &&
               !visibleSetupAfterRebuild.isMiniaturized &&
               rebuildKeepsStandaloneAppAlive,
               @"Dock reopen restores the standalone setup window instead of another window");
        [visibleSetupAfterRebuild orderOut:nil];
        if (originalConfigPath.length) {
            setenv("GDRIVE_BACKUP_CONFIG", originalConfigPath.UTF8String, 1);
        } else {
            unsetenv("GDRIVE_BACKUP_CONFIG");
        }
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:setupConfigPath]
                                    resultingItemURL:nil error:nil];

        NSString *successGlyph = view.statusSymbolLabel.stringValue;
        NSString *successDescription = view.statusSymbolLabel.accessibilityLabel;
        view.status = @"failure";
        Assert(successGlyph.length > 0 &&
               ![successGlyph isEqualToString:view.statusSymbolLabel.stringValue] &&
               successDescription.length > 0 &&
               ![successDescription isEqualToString:view.statusSymbolLabel.accessibilityLabel],
               @"overview status differs by glyph and spoken text instead of color alone");

        AppDelegate *delegate = [[AppDelegate alloc] init];
        Assert([[delegate applicationModeForArguments:@[@"app"]] isEqualToString:@"overview"] &&
               [[delegate applicationModeForArguments:@[@"app", @"--setup"]] isEqualToString:@"setup"] &&
               [[delegate applicationModeForArguments:@[@"app", @"--confirm"]] isEqualToString:@"confirm"] &&
               [[delegate applicationModeForArguments:@[@"app", @"/tmp/sentinel"]] isEqualToString:@"progress"],
               @"standalone setup, confirmation, and progress entry modes remain explicit");
        Assert([delegate shouldInstallStatusItemForMode:@"overview"] &&
               [delegate shouldInstallStatusItemForMode:@"menubar"] &&
               ![delegate shouldInstallStatusItemForMode:@"setup"] &&
               ![delegate shouldInstallStatusItemForMode:@"confirm"] &&
               ![delegate shouldInstallStatusItemForMode:@"progress"],
               @"menu bar status exists only in the persistent controller modes");

        SEL foregroundSelector = NSSelectorFromString(@"shouldForegroundProgressForArguments:");
        BOOL manualProgressComesForward = NO;
        BOOL scheduledProgressStaysPassive = NO;
        if ([delegate respondsToSelector:foregroundSelector]) {
            typedef BOOL (*ForegroundMethod)(id, SEL, NSArray<NSString *> *);
            ForegroundMethod method = (ForegroundMethod)[delegate methodForSelector:foregroundSelector];
            manualProgressComesForward = method(delegate, foregroundSelector,
                @[@"app", @"/tmp/sentinel", @"/tmp/progress", @"/tmp/state", @"--foreground"]);
            scheduledProgressStaysPassive = !method(delegate, foregroundSelector,
                @[@"app", @"/tmp/sentinel", @"/tmp/progress", @"/tmp/state"]);
        }
        Assert(manualProgressComesForward && scheduledProgressStaysPassive,
               @"only an explicit progress request receives a Dock presence");

        SEL collectionSelector = NSSelectorFromString(@"statusWindowCollectionBehavior");
        NSWindowCollectionBehavior progressCollectionBehavior = NSWindowCollectionBehaviorDefault;
        if ([delegate respondsToSelector:collectionSelector]) {
            typedef NSWindowCollectionBehavior (*CollectionMethod)(id, SEL);
            CollectionMethod method = (CollectionMethod)[delegate methodForSelector:collectionSelector];
            progressCollectionBehavior = method(delegate, collectionSelector);
        }
        delegate.confirmMode = YES;
        NSWindowCollectionBehavior passiveConfirmationBehavior = NSWindowCollectionBehaviorDefault;
        if ([delegate respondsToSelector:collectionSelector]) {
            typedef NSWindowCollectionBehavior (*CollectionMethod)(id, SEL);
            CollectionMethod method = (CollectionMethod)[delegate methodForSelector:collectionSelector];
            passiveConfirmationBehavior = method(delegate, collectionSelector);
        }
        delegate.confirmMode = NO;
        NSWindowCollectionBehavior fullscreenIntrusionFlags =
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary;
        Assert([delegate respondsToSelector:collectionSelector] &&
               (progressCollectionBehavior & fullscreenIntrusionFlags) == 0 &&
               (passiveConfirmationBehavior & fullscreenIntrusionFlags) == 0 &&
               (progressCollectionBehavior & NSWindowCollectionBehaviorFullScreenNone) != 0,
               @"background progress and confirmation windows cannot enter another app's fullscreen Space");

        SEL hidesOnDeactivateSelector =
            NSSelectorFromString(@"statusWindowShouldHideOnDeactivate");
        BOOL passiveConfirmationRemainsVisible = NO;
        BOOL backgroundProgressHidesWhenInactive = NO;
        if ([delegate respondsToSelector:hidesOnDeactivateSelector]) {
            typedef BOOL (*HidesOnDeactivateMethod)(id, SEL);
            HidesOnDeactivateMethod method =
                (HidesOnDeactivateMethod)[delegate methodForSelector:hidesOnDeactivateSelector];
            delegate.confirmMode = YES;
            passiveConfirmationRemainsVisible =
                !method(delegate, hidesOnDeactivateSelector);
            delegate.confirmMode = NO;
            backgroundProgressHidesWhenInactive =
                method(delegate, hidesOnDeactivateSelector);
        }
        Assert(passiveConfirmationRemainsVisible && backgroundProgressHidesWhenInactive,
               @"passive confirmation stays visible without making background progress intrusive");

        SEL showProgressSelector = NSSelectorFromString(@"shouldShowProgressForTrigger:fromVisibleWindow:");
        BOOL visibleOverviewShowsProgress = NO;
        BOOL hiddenOverviewStaysHeadless = NO;
        BOOL menuBarStaysHeadless = NO;
        BOOL automaticTriggerStaysHeadless = NO;
        if ([delegate respondsToSelector:showProgressSelector]) {
            typedef BOOL (*ShowProgressMethod)(id, SEL, NSString *, BOOL);
            ShowProgressMethod method = (ShowProgressMethod)[delegate methodForSelector:showProgressSelector];
            delegate.overviewMode = YES;
            delegate.menubarOnlyMode = NO;
            visibleOverviewShowsProgress = method(delegate, showProgressSelector, @"manual", YES);
            hiddenOverviewStaysHeadless = !method(delegate, showProgressSelector, @"manual", NO);
            delegate.menubarOnlyMode = YES;
            menuBarStaysHeadless = !method(delegate, showProgressSelector, @"manual", YES);
            automaticTriggerStaysHeadless = !method(delegate, showProgressSelector, @"mount", YES);
            delegate.overviewMode = NO;
            delegate.menubarOnlyMode = NO;
        }
        Assert(visibleOverviewShowsProgress && hiddenOverviewStaysHeadless &&
               menuBarStaysHeadless && automaticTriggerStaysHeadless,
               @"only a visible window's direct manual action requests progress UI");

        OverviewLaunchDelegate *guardedLaunch = [[OverviewLaunchDelegate alloc] init];
        guardedLaunch.language = @"en";
        guardedLaunch.launchSucceeds = YES;
        guardedLaunch.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 420)
                                                           styleMask:NSWindowStyleMaskTitled
                                                             backing:NSBackingStoreBuffered
                                                               defer:NO];
        guardedLaunch.window.contentView = [[TigerOverviewView alloc] initWithFrame:NSMakeRect(0, 0, 620, 420)];
        [guardedLaunch startOverviewBackup:nil];
        [guardedLaunch startOverviewBackup:nil];
        Assert(guardedLaunch.launchCalls == 1 && guardedLaunch.sawImmediatePreparingState &&
               guardedLaunch.progressHandoffCalls == 1,
               @"overview shows preparation, disables repeats, and yields its Dock icon after launch");

        OverviewLaunchDelegate *failedLaunch = [[OverviewLaunchDelegate alloc] init];
        failedLaunch.language = @"en";
        failedLaunch.launchSucceeds = NO;
        [failedLaunch startOverviewBackup:nil];
        [failedLaunch startOverviewBackup:nil];
        Assert(failedLaunch.launchCalls == 2 && failedLaunch.progressHandoffCalls == 0,
               @"overview launch failures remain retryable without surrendering their Dock icon");

        NSArray<NSString *> *overviewKeys = @[
            @"overviewSubtitle", @"overviewLastRun", @"overviewNextRun",
            @"overviewTarget", @"overviewStorage", @"overviewSettings",
            @"overviewOpen", @"overviewNeverRun", @"overviewUnavailable",
            @"overviewFreeOf", @"overviewStatusInterrupted", @"overviewStatusUnknown",
            @"automaticBackupsPaused", @"pauseAutomaticBackups", @"resumeAutomaticBackups",
            @"automaticRetryRunning", @"automaticRetryRunningShort",
            @"backupProgressCurrentPhase", @"progressAreaFormat", @"progressPreparing",
            @"progressChecking", @"progressTransferredFormat",
            @"progressCheckedListedFormat"
        ];
        BOOL allOverviewTextLocalized = YES;
        BOOL allProgressAreaFormatsLocalized = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            for (NSString *key in overviewKeys) {
                NSString *value = T(language, key);
                allOverviewTextLocalized = allOverviewTextLocalized &&
                    value.length > 0 && ![value isEqualToString:key];
            }
            NSString *formattedArea = [NSString stringWithFormat:
                T(language, @"progressAreaFormat"), @"3", @"5"];
            allProgressAreaFormatsLocalized = allProgressAreaFormatsLocalized &&
                [formattedArea containsString:@"3"] && [formattedArea containsString:@"5"];
        }
        Assert(allOverviewTextLocalized && allProgressAreaFormatsLocalized,
               @"overview and menu bar text is localized in all supported languages");
        Assert([T(@"de", @"overviewStorage") isEqualToString:@"Freier Zielspeicher"] &&
               [T(@"en", @"overviewStorage") isEqualToString:@"Destination free space"],
               @"capacity is labelled as destination free space instead of progress");

        BOOL actionTitlesFit = YES;
        BOOL capacityCaptionFits = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            view.language = language;
            actionTitlesFit = actionTitlesFit && restoreButton != nil &&
                view.settingsButton.frame.size.width >= ceil(view.settingsButton.cell.cellSize.width) &&
                restoreButton.frame.size.width >= ceil(restoreButton.cell.cellSize.width) &&
                view.backupButton.frame.size.width >= ceil(view.backupButton.cell.cellSize.width);
            capacityCaptionFits = capacityCaptionFits &&
                view.storageCaptionLabel.frame.size.width >=
                    ceil(view.storageCaptionLabel.cell.cellSize.width);
        }
        Assert(actionTitlesFit,
               @"overview action titles remain fully visible in every supported language");
        Assert(capacityCaptionFits,
               @"destination free-space caption remains fully visible in every supported language");

        NSString *summaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-overview-summary-%@", NSUUID.UUID.UUIDString]];
        [@"protocol=1\nstatus=success\npid=123\nstarted_at=1783789200\nfinished_at=1783792800\nexit_code=0\ntrigger=schedule\ntarget=apfs\ndestination=/Volumes/Archive\n"
            writeToFile:summaryPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *capacityPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-overview-capacity-%@", NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:capacityPath
                                withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *config = @{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_DEST_ROOT": capacityPath,
            @"GDRIVE_BACKUP_SCHEDULE": @"daily"
        };
        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:2 * 60 * 60];
        NSDateComponents *nowParts = [[NSDateComponents alloc] init];
        nowParts.year = 2026;
        nowParts.month = 7;
        nowParts.day = 11;
        nowParts.hour = 19;
        NSDate *now = [calendar dateFromComponents:nowParts];
        delegate.language = @"en";
        NSDictionary *dailyNAS = @{
            @"GDRIVE_BACKUP_PROFILE_ID": @"default",
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/alexander",
            @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
            @"GDRIVE_BACKUP_SCHEDULE": @"daily"
        };
        NSDictionary *retrySummary = @{
            @"protocol": @"1", @"status": @"running", @"pid": @"123",
            @"started_at": @"1785522633", @"trigger": @"schedule-retry",
            @"retry_origin_started_at": @"1785520805", @"retry_attempt": @"1"
        };
        NSDictionary *retryProgress = @{
            @"label": @"Shared Drive", @"phase": @"3/5", @"percent": @"63",
            @"detail": @"1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s"
        };
        NSDictionary *retrySnapshot = [delegate overviewSnapshotForConfig:dailyNAS
            summary:retrySummary status:@"running" progress:retryProgress
            now:now calendar:calendar];
        NSString *phaseText = [NSString stringWithFormat:T(@"en", @"progressAreaFormat"),
            @"3", @"5"];
        NSString *retryStart = [[delegate overviewDateFormatterWithCalendar:calendar]
            stringFromDate:[NSDate dateWithTimeIntervalSince1970:1785522633]];
        Assert([retrySnapshot[@"retryRunning"] isEqualToString:@"1"] &&
               [retrySnapshot[@"lastRun"] isEqualToString:T(@"en", @"automaticRetryRunning")] &&
               [retrySnapshot[@"lastRunDetail"] isEqualToString:retryStart] &&
               [retrySnapshot[@"progressPhase"] isEqualToString:phaseText] &&
               [retrySnapshot[@"progressPercent"] isEqualToString:@"63"] &&
               [retrySnapshot[@"progressDetail"] isEqualToString:
                   @"1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s"],
               @"running automatic retry has explicit phase progress");

        NSMenu *retryMenu = [delegate statusMenuForSnapshot:retrySnapshot];
        NSString *retryMenuText = [[retryMenu.itemArray valueForKey:@"title"]
            componentsJoinedByString:@" "];
        NSMenuItem *retryProgressItem = nil;
        for (NSMenuItem *item in retryMenu.itemArray) {
            if ([item.title containsString:T(@"en", @"automaticRetryRunningShort")]) {
                retryProgressItem = item;
                break;
            }
        }
        NSMenuItem *retryBackup = [retryMenu itemWithTitle:T(@"en", @"backupNow")];
        NSMenuItem *retryOpen = [retryMenu itemWithTitle:T(@"en", @"overviewOpen")];
        Assert([retryMenuText containsString:T(@"en", @"automaticRetryRunningShort")] &&
               [retryMenuText containsString:phaseText] &&
               [retryMenuText containsString:@"63 %"] &&
               retryProgressItem != nil && !retryProgressItem.enabled &&
               retryBackup != nil && !retryBackup.enabled &&
               retryOpen != nil && retryOpen.enabled,
               @"menu bar exposes compact retry progress");

        NSDictionary *preparingRetrySnapshot = [delegate overviewSnapshotForConfig:dailyNAS
            summary:retrySummary status:@"running" progress:nil
            now:now calendar:calendar];
        Assert([preparingRetrySnapshot[@"progressVisible"] isEqualToString:@"1"] &&
               [preparingRetrySnapshot[@"progressPercent"] isEqualToString:@""] &&
               [preparingRetrySnapshot[@"progressDetail"] isEqualToString:
                   T(@"en", @"progressPreparing")] &&
               [preparingRetrySnapshot[@"progressPhase"] isEqualToString:@""] &&
               ![preparingRetrySnapshot[@"progressDetail"] containsString:@"Shared Drive"] &&
               ![preparingRetrySnapshot[@"progressDetail"] containsString:@"MiB/s"],
               @"retry without telemetry stays visibly indeterminate without invented detail");

        NSDictionary *phaseOnlyRetrySnapshot = [delegate overviewSnapshotForConfig:dailyNAS
            summary:retrySummary status:@"running" progress:@{
                @"label": @"Shared Drive", @"phase": @"4/5"
            } now:now calendar:calendar];
        Assert([phaseOnlyRetrySnapshot[@"progressVisible"] isEqualToString:@"1"] &&
               [phaseOnlyRetrySnapshot[@"progressPhase"]
                   isEqualToString:[NSString stringWithFormat:T(@"en", @"progressAreaFormat"),
                       @"4", @"5"]] &&
               [phaseOnlyRetrySnapshot[@"progressPercent"] isEqualToString:@""] &&
               [phaseOnlyRetrySnapshot[@"progressDetail"]
                   isEqualToString:T(@"en", @"progressChecking")],
               @"fresh copy-phase telemetry names the active check while remaining indeterminate");

        NSDictionary *checkingRetrySnapshot = [delegate overviewSnapshotForConfig:dailyNAS
            summary:retrySummary status:@"running" progress:@{
                @"label": @"Shared Drive", @"phase": @"4/5",
                @"checked": @"43129", @"listed": @"103256"
            } now:now calendar:calendar];
        NSString *checkingDetail = [NSString stringWithFormat:
            T(@"en", @"progressCheckedListedFormat"), @"43,129", @"103,256"];
        Assert([checkingRetrySnapshot[@"progressPercent"] isEqualToString:@""] &&
               [checkingRetrySnapshot[@"progressDetail"] isEqualToString:checkingDetail] &&
               ![checkingRetrySnapshot[@"progressDetail"]
                   isEqualToString:T(@"en", @"progressPreparing")],
               @"aggregate check counters visibly prove that an indeterminate retry is active");
        NSString *checkingMenuText = [[[[delegate
            statusMenuForSnapshot:checkingRetrySnapshot] itemArray] valueForKey:@"title"]
            componentsJoinedByString:@" "];
        Assert([checkingMenuText containsString:checkingDetail],
               @"menu bar exposes aggregate activity when no percentage is trustworthy");

        NSDictionary *transferringRetrySnapshot = [delegate overviewSnapshotForConfig:dailyNAS
            summary:retrySummary status:@"running" progress:@{
                @"label": @"Shared Drive", @"phase": @"4/5",
                @"checked": @"43129", @"listed": @"103256",
                @"transferred": @"12.000 MiB", @"speed": @"1.500 MiB/s"
            } now:now calendar:calendar];
        NSString *transferringDetail = [NSString stringWithFormat:
            T(@"en", @"progressTransferredFormat"), @"12.000 MiB", @"1.500 MiB/s"];
        Assert([transferringRetrySnapshot[@"progressPercent"] isEqualToString:@""] &&
               [transferringRetrySnapshot[@"progressDetail"]
                   isEqualToString:transferringDetail],
               @"unknown-total byte activity takes precedence over comparison counters");
        NSString *transferringMenuText = [[[[delegate
            statusMenuForSnapshot:transferringRetrySnapshot] itemArray] valueForKey:@"title"]
            componentsJoinedByString:@" "];
        Assert([transferringMenuText containsString:transferringDetail],
               @"menu bar exposes transfer activity when no percentage is trustworthy");

        NSDictionary *zeroTransferRetrySnapshot = [delegate overviewSnapshotForConfig:dailyNAS
            summary:retrySummary status:@"running" progress:@{
                @"label": @"Shared Drive", @"phase": @"4/5",
                @"checked": @"0", @"listed": @"1",
                @"transferred": @"0 B", @"speed": @"0 B/s"
            } now:now calendar:calendar];
        NSString *zeroCheckDetail = [NSString stringWithFormat:
            T(@"en", @"progressCheckedListedFormat"), @"0", @"1"];
        Assert([zeroTransferRetrySnapshot[@"progressDetail"] isEqualToString:zeroCheckDetail],
               @"zero-byte unknown-total activity still reports useful comparison counters");

        NSDictionary<NSString *, NSString *> *snapshot =
            [delegate overviewSnapshotForConfig:config summaryPath:summaryPath now:now calendar:calendar];
        Assert([snapshot[@"status"] isEqualToString:@"success"] &&
               snapshot[@"lastRun"].length > 0 && snapshot[@"lastRunDetail"].length > 0 &&
               snapshot[@"nextRun"].length > 0 &&
               [snapshot[@"target"] containsString:capacityPath.lastPathComponent] &&
               ![snapshot[@"storage"] isEqualToString:T(@"en", @"overviewUnavailable")],
               @"one honest snapshot feeds both overview and menu bar values");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:summaryPath]
                                    resultingItemURL:nil error:nil];
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:capacityPath]
                                    resultingItemURL:nil error:nil];

        NSDictionary<NSString *, NSString *> *emptySnapshot =
            [delegate overviewSnapshotForConfig:@{@"GDRIVE_BACKUP_SCHEDULE": @"manual"}
                                     summaryPath:@"/path/that/does/not/exist"
                                             now:now
                                        calendar:calendar];
        Assert([emptySnapshot[@"status"] isEqualToString:@"unknown"] &&
               [emptySnapshot[@"lastRun"] isEqualToString:T(@"en", @"overviewNeverRun")] &&
               [emptySnapshot[@"nextRun"] isEqualToString:T(@"en", @"scheduleManual")],
               @"missing history and manual schedules stay explicit instead of guessed");

        NSDictionary<NSString *, NSString *> *nasSnapshot =
            [delegate overviewSnapshotForConfig:@{
                @"GDRIVE_BACKUP_TARGET": @"nas",
                @"GDRIVE_BACKUP_NAS_URL": @"smb://private-user:secret-password@wdmycloudex2100.local/alexander",
                @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/alexander",
                @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
                @"GDRIVE_BACKUP_PROFILE_NAME": @"Default",
                @"GDRIVE_BACKUP_SCHEDULE": @"manual"
            }
                                     summaryPath:@"/path/that/does/not/exist"
                                             now:now
                                        calendar:calendar];
        Assert([nasSnapshot[@"target"] isEqualToString:
                   @"NAS / Network · wdmycloudex2100.local · alexander/GoogleDrive-Backup"] &&
               [nasSnapshot[@"target"] rangeOfString:@"private-user"].location == NSNotFound &&
               [nasSnapshot[@"target"] rangeOfString:@"secret-password"].location == NSNotFound,
               @"NAS target identifies the server and share without exposing credentials");

        NSDictionary<NSString *, NSString *> *diskSnapshot =
            [delegate overviewSnapshotForConfig:@{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup",
                @"GDRIVE_BACKUP_SCHEDULE": @"manual"
            }
                                     summaryPath:@"/path/that/does/not/exist"
                                             now:now
                                        calendar:calendar];
        Assert([diskSnapshot[@"target"] isEqualToString:
                   @"External disk · GoogleDrive-Backup"],
               @"local target is explicitly identified as an external disk");

        NSDictionary<NSString *, NSString *> *pausedSnapshot =
            [delegate overviewSnapshotForConfig:@{
                @"GDRIVE_BACKUP_TARGET": @"apfs",
                @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup",
                @"GDRIVE_BACKUP_SCHEDULE": @"daily",
                @"GDRIVE_BACKUP_PAUSED": @"1"
            }
                                     summaryPath:@"/path/that/does/not/exist"
                                             now:now
                                        calendar:calendar];
        Assert([pausedSnapshot[@"nextRun"] isEqualToString:T(@"en", @"automaticBackupsPaused")] &&
               [pausedSnapshot[@"automaticBackupsPaused"] isEqualToString:@"1"],
               @"overview says automatic backups are paused instead of inventing a next run");

        NSDictionary<NSString *, NSString *> *menuSnapshot = @{
            @"status": @"success",
            @"lastRun": @"Successful",
            @"lastRunDetail": @"Today, 19:42",
            @"nextRun": @"Today, 20:00",
            @"target": @"Archive — /Volumes/Archive",
            @"storage": @"812 GB free of 2 TB"
        };
        NSMenu *statusMenu = [delegate statusMenuForSnapshot:menuSnapshot];
        NSArray<NSString *> *menuTitles = [statusMenu.itemArray valueForKey:@"title"];
        Assert([menuTitles containsObject:T(@"en", @"overviewOpen")] &&
               [menuTitles containsObject:T(@"en", @"backupNow")] &&
               [menuTitles containsObject:T(@"en", @"pauseAutomaticBackups")] &&
               [menuTitles containsObject:T(@"en", @"restoreTitle")] &&
               [menuTitles containsObject:T(@"en", @"overviewSettings")] &&
               [[menuTitles componentsJoinedByString:@" "] containsString:@"Successful"] &&
               [[menuTitles componentsJoinedByString:@" "] containsString:@"Today, 20:00"] &&
               [[menuTitles componentsJoinedByString:@" "] containsString:@"/Volumes/Archive"] &&
               [[menuTitles componentsJoinedByString:@" "] containsString:@"812 GB"],
               @"menu bar exposes the same status, schedule, target, storage, and actions");

        OverviewLaunchDelegate *reopenDelegate = [[OverviewLaunchDelegate alloc] init];
        reopenDelegate.overviewMode = YES;
        reopenDelegate.menubarOnlyMode = YES;
        BOOL handledReopen = [reopenDelegate applicationShouldHandleReopen:NSApp
                                                          hasVisibleWindows:NO];
        Assert(!handledReopen && reopenDelegate.overviewShowCalls == 1,
               @"Finder reopen promotes a menu-bar-only controller to the visible overview");

        OverviewLaunchDelegate *hiddenOverviewDelegate = [[OverviewLaunchDelegate alloc] init];
        hiddenOverviewDelegate.overviewMode = YES;
        hiddenOverviewDelegate.window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 100, 100)
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered
                          defer:NO];
        BOOL handledHiddenOverview = [hiddenOverviewDelegate applicationShouldHandleReopen:NSApp
                                                                          hasVisibleWindows:NO];
        Assert(!handledHiddenOverview && hiddenOverviewDelegate.overviewShowCalls == 1 &&
               hiddenOverviewDelegate.dockRestoreCalls == 0,
               @"Finder reopen restores a hidden overview with normal Dock presence");

        NSMenu *pausedMenu = [delegate statusMenuForSnapshot:pausedSnapshot];
        Assert([pausedMenu itemWithTitle:T(@"en", @"resumeAutomaticBackups")] != nil,
               @"paused menu offers one explicit way to resume automatic backups");

        NSString *pauseConfigPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-overview-pause-%@", NSUUID.UUID.UUIDString]];
        [@"GDRIVE_BACKUP_PAUSED=0\n" writeToFile:pauseConfigPath atomically:YES
                                        encoding:NSUTF8StringEncoding error:nil];
        setenv("GDRIVE_BACKUP_CONFIG", pauseConfigPath.UTF8String, 1);
        SEL toggleSelector = NSSelectorFromString(@"toggleAutomaticBackupsPaused:");
        if ([delegate respondsToSelector:toggleSelector]) {
            typedef void (*ToggleMethod)(id, SEL, id);
            ToggleMethod toggle = (ToggleMethod)[delegate methodForSelector:toggleSelector];
            toggle(delegate, toggleSelector, nil);
        }
        NSDictionary *pausedConfig = GDTReadConfigDictionaryAtPath(pauseConfigPath);
        Assert([pausedConfig[@"GDRIVE_BACKUP_PAUSED"] isEqualToString:@"1"],
               @"pause action persists the automatic-backup guard without changing the schedule");
        unsetenv("GDRIVE_BACKUP_CONFIG");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:pauseConfigPath]
                                    resultingItemURL:nil error:nil];
        Assert([delegate respondsToSelector:NSSelectorFromString(@"showRestoreBrowser:")],
               @"overview and menu bar route to one restore browser workflow");

        delegate.overviewMode = YES;
        delegate.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        delegate.restoreWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                              styleMask:NSWindowStyleMaskTitled
                                                                backing:NSBackingStoreBuffered
                                                                  defer:NO];
        Assert([delegate windowShouldClose:delegate.restoreWindow],
               @"closing restore closes only that window and leaves the overview controller alive");

        TigerOverviewView *appliedView = [[TigerOverviewView alloc] initWithFrame:NSMakeRect(0, 0, 620, 420)];
        [delegate applyOverviewSnapshot:menuSnapshot toView:appliedView];
        Assert([appliedView.status isEqualToString:@"success"] &&
               [appliedView.lastRunText isEqualToString:@"Successful"] &&
               [appliedView.nextRunText isEqualToString:@"Today, 20:00"] &&
               [appliedView.targetText containsString:@"/Volumes/Archive"] &&
               [appliedView.storageText containsString:@"812 GB"],
               @"window and menu bar share one snapshot without divergent status logic");
    }

    if (failures > 0) {
        printf("%d overview UI test(s) failed.\n", failures);
        return 1;
    }
    printf("All overview UI tests passed.\n");
    return 0;
}
