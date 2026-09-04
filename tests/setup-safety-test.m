#import <Cocoa/Cocoa.h>

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface SetupSafetyDelegate : AppDelegate
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *testUpdates;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *testSavedConfig;
@property(nonatomic) NSInteger saveCalls;
@property(nonatomic) NSInteger launchCalls;
@property(nonatomic) NSInteger dismissCalls;
@property(nonatomic) BOOL launchSucceeds;
@property(nonatomic, copy) void (^dryRunCompletion)(NSInteger status);
@end

@implementation SetupSafetyDelegate

- (NSDictionary<NSString *, NSString *> *)currentSetupUpdates {
    return self.testUpdates ?: @{};
}

- (NSDictionary<NSString *, NSString *> *)savedSetupConfig {
    return self.testSavedConfig ?: @{};
}

- (BOOL)saveSetupValues {
    self.saveCalls++;
    return YES;
}

- (BOOL)launchBackupWithArgument:(NSString *)argument assumeYes:(BOOL)assumeYes {
    (void)argument;
    (void)assumeYes;
    self.launchCalls++;
    return self.launchSucceeds;
}

- (BOOL)launchBackupWithArgument:(NSString *)argument
                       assumeYes:(BOOL)assumeYes
                      completion:(void (^)(NSInteger status))completion {
    (void)argument;
    (void)assumeYes;
    self.launchCalls++;
    self.dryRunCompletion = completion;
    return self.launchSucceeds;
}

- (void)dismissSetupAfterBackupLaunch {
    self.dismissCalls++;
}

@end

@interface SetupIdentityDelegate : AppDelegate
@property(nonatomic) NSInteger volumeUUIDLookupCalls;
@end

@implementation SetupIdentityDelegate

- (NSString *)volumeUUIDForPath:(NSString *)path {
    (void)path;
    self.volumeUUIDLookupCalls++;
    return @"WRONG-VOLUME-UUID";
}

@end

@interface EmbeddedSetupDismissDelegate : AppDelegate
@property(nonatomic) NSInteger dockHandoffCalls;
@end

@implementation EmbeddedSetupDismissDelegate

- (void)handoffOverviewDockPresenceToManualProgress {
    self.dockHandoffCalls++;
}

@end

@interface UnknownVolumeSetupDelegate : AppDelegate
@property(nonatomic) NSInteger showSetupCalls;
@property(nonatomic) NSInteger saveCalls;
@property(nonatomic) NSInteger launchCalls;
@end

@implementation UnknownVolumeSetupDelegate

- (void)showSetupWindow {
    self.showSetupCalls++;
}

- (BOOL)saveSetupValues {
    self.saveCalls++;
    return YES;
}

- (BOOL)launchBackupWithArgument:(NSString *)argument
                         trigger:(NSString *)trigger
                       assumeYes:(BOOL)assumeYes {
    (void)argument;
    (void)trigger;
    (void)assumeYes;
    self.launchCalls++;
    return YES;
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

static BOOL DryRunPending(AppDelegate *delegate) {
    SEL selector = NSSelectorFromString(@"dryRunPending");
    if (![delegate respondsToSelector:selector]) return NO;
    typedef BOOL (*BoolMethod)(id, SEL);
    return ((BoolMethod)[delegate methodForSelector:selector])(delegate, selector);
}

static SetupSafetyDelegate *Delegate(NSDictionary *saved, NSDictionary *updates) {
    SetupSafetyDelegate *delegate = [[SetupSafetyDelegate alloc] init];
    delegate.language = @"en";
    delegate.statusField = [[NSTextField alloc] init];
    delegate.setupBackupButton = [[NSButton alloc] init];
    delegate.setupDryRunButton = [[NSButton alloc] init];
    delegate.testSavedConfig = saved;
    delegate.testUpdates = updates;
    delegate.launchSucceeds = YES;
    return delegate;
}

int main(void) {
    @autoreleasepool {
        SetupIdentityDelegate *legacyIdentityDelegate =
            [[SetupIdentityDelegate alloc] init];
        SEL loadIdentitySelector =
            NSSelectorFromString(@"loadConfiguredAPFSIdentityFromConfig:");
        BOOL exposesSafeIdentityLoader =
            [legacyIdentityDelegate respondsToSelector:loadIdentitySelector];
        if (exposesSafeIdentityLoader) {
            typedef void (*LoadIdentityMethod)(
                id, SEL, NSDictionary<NSString *, NSString *> *);
            ((LoadIdentityMethod)[legacyIdentityDelegate
                methodForSelector:loadIdentitySelector])(
                    legacyIdentityDelegate,
                    loadIdentitySelector,
                    @{
                        @"GDRIVE_BACKUP_VOLUME":
                            @"/Volumes/GoogleDrive-Backup",
                        @"GDRIVE_BACKUP_VOLUME_NAME":
                            @"GoogleDrive-Backup"
                    });
        }
        Assert(exposesSafeIdentityLoader &&
               legacyIdentityDelegate.volumeUUIDLookupCalls == 0 &&
               [legacyIdentityDelegate.configuredAPFSVolumePath
                   isEqualToString:@"/Volumes/GoogleDrive-Backup"] &&
               legacyIdentityDelegate.configuredAPFSVolumeUUID.length == 0,
               @"legacy setup changes never bind whichever same-name volume currently owns the saved path");

        NSDictionary *saved = @{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_SCHEDULE": @"manual",
            @"GDRIVE_BACKUP_ENCRYPTION": @"none"
        };
        SetupSafetyDelegate *unsaved = Delegate(saved, @{
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_SCHEDULE": @"manual",
            @"GDRIVE_BACKUP_ENCRYPTION": @"none",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/Archive",
            @"GDRIVE_BACKUP_NAS_URL": @"",
            @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
            @"GDRIVE_BACKUP_NAS_START_ON_MOUNT": @"0"
        });
        [unsaved startBackupNow:nil];
        Assert(unsaved.saveCalls == 0 && unsaved.launchCalls == 0 &&
               [unsaved.statusField.stringValue isEqualToString:T(@"en", @"statusUnsavedChanges")],
               @"Backup now neither saves nor launches when setup changes are unsaved");

        [unsaved startDryRun:nil];
        Assert(unsaved.saveCalls == 0 && unsaved.launchCalls == 0,
               @"check run also leaves unsaved setup untouched");

        SetupSafetyDelegate *savedDelegate = Delegate(saved, saved);
        [savedDelegate startBackupNow:nil];
        [savedDelegate startBackupNow:nil];
        Assert(savedDelegate.saveCalls == 0 && savedDelegate.launchCalls == 1 &&
               savedDelegate.dismissCalls == 1 &&
               [savedDelegate.statusField.stringValue isEqualToString:T(@"en", @"statusBackupPreparing")],
               @"Backup now launches once, reports preparation, and dismisses setup once");

        EmbeddedSetupDismissDelegate *embeddedDismiss =
            [[EmbeddedSetupDismissDelegate alloc] init];
        embeddedDismiss.overviewMode = YES;
        embeddedDismiss.manualLaunchPending = YES;
        embeddedDismiss.setupWindow = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 100, 100)
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered
                          defer:NO];
        [embeddedDismiss.setupWindow orderFront:nil];
        [embeddedDismiss dismissSetupAfterBackupLaunch];
        Assert(embeddedDismiss.dockHandoffCalls == 1 &&
               !embeddedDismiss.manualLaunchPending &&
               !embeddedDismiss.setupWindow.isVisible,
               @"embedded setup yields its Dock presence to one foreground progress window");

        SetupSafetyDelegate *failedDelegate = Delegate(saved, saved);
        failedDelegate.launchSucceeds = NO;
        [failedDelegate startBackupNow:nil];
        [failedDelegate startBackupNow:nil];
        Assert(failedDelegate.launchCalls == 2 && failedDelegate.dismissCalls == 0,
               @"failed launch keeps setup open and allows an explicit retry");

        SetupSafetyDelegate *dryRun = Delegate(saved, saved);
        [dryRun startDryRun:nil];
        BOOL visibleRunningState = dryRun.launchCalls == 1 && DryRunPending(dryRun) &&
            !dryRun.setupBackupButton.enabled && !dryRun.setupDryRunButton.enabled &&
            [dryRun.statusField.stringValue isEqualToString:T(@"en", @"statusDryRunStarted")] &&
            [dryRun.setupDryRunButton.title isEqualToString:T(@"en", @"dryRunRunning")];
        if (dryRun.dryRunCompletion) dryRun.dryRunCompletion(0);
        Assert(visibleRunningState && !DryRunPending(dryRun) &&
               dryRun.setupBackupButton.enabled && dryRun.setupDryRunButton.enabled &&
               [dryRun.statusField.stringValue isEqualToString:T(@"en", @"statusDryRunSucceeded")],
               @"check run visibly transitions from running to successful and restores actions");

        SetupSafetyDelegate *unavailableDryRun = Delegate(saved, saved);
        [unavailableDryRun startDryRun:nil];
        if (unavailableDryRun.dryRunCompletion) unavailableDryRun.dryRunCompletion(69);
        Assert([unavailableDryRun.statusField.stringValue
                   isEqualToString:T(@"en", @"statusDryRunTargetUnavailable")],
               @"check run explains an unavailable destination instead of staying at started");

        SetupSafetyDelegate *failedDryRun = Delegate(saved, saved);
        [failedDryRun startDryRun:nil];
        if (failedDryRun.dryRunCompletion) failedDryRun.dryRunCompletion(1);
        Assert([failedDryRun.statusField.stringValue isEqualToString:T(@"en", @"statusDryRunFailed")],
               @"check run publishes a terminal generic failure state");

        NSError *scheduleError = nil;
        NSData *scheduleData = [[[AppDelegate alloc] init] schedulePlistDataForMode:@"daily"
                                                                              error:&scheduleError];
        NSDictionary *schedulePlist = scheduleData
            ? [NSPropertyListSerialization propertyListWithData:scheduleData
                                                        options:0
                                                         format:nil
                                                          error:&scheduleError]
            : nil;
        NSDictionary *scheduleEnvironment = schedulePlist[@"EnvironmentVariables"];
        Assert(!scheduleError &&
               [scheduleEnvironment[@"GDRIVE_BACKUP_TRIGGER"] isEqualToString:@"schedule"] &&
               [scheduleEnvironment[@"BACKUP_ASSUME_YES"] isEqualToString:@"1"],
               @"automatic schedules approve their verified destination without an unattended prompt");

        BOOL translated = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            NSString *value = T(language, @"statusUnsavedChanges");
            NSString *preparing = T(language, @"statusBackupPreparing");
            NSString *incompatibleEncryption = T(language, @"statusEncryptionIncompatible");
            NSString *invalidCryptRemote = T(language, @"statusCryptRemoteInvalid");
            NSString *dryRunRunning = T(language, @"dryRunRunning");
            NSString *dryRunSucceeded = T(language, @"statusDryRunSucceeded");
            NSString *dryRunUnavailable = T(language, @"statusDryRunTargetUnavailable");
            NSString *dryRunFailed = T(language, @"statusDryRunFailed");
            translated = translated && value.length > 0 && ![value isEqualToString:@"statusUnsavedChanges"] &&
                preparing.length > 0 && ![preparing isEqualToString:@"statusBackupPreparing"] &&
                incompatibleEncryption.length > 0 &&
                ![incompatibleEncryption isEqualToString:@"statusEncryptionIncompatible"] &&
                invalidCryptRemote.length > 0 &&
                ![invalidCryptRemote isEqualToString:@"statusCryptRemoteInvalid"] &&
                dryRunRunning.length > 0 && ![dryRunRunning isEqualToString:@"dryRunRunning"] &&
                dryRunSucceeded.length > 0 && ![dryRunSucceeded isEqualToString:@"statusDryRunSucceeded"] &&
                dryRunUnavailable.length > 0 &&
                ![dryRunUnavailable isEqualToString:@"statusDryRunTargetUnavailable"] &&
                dryRunFailed.length > 0 && ![dryRunFailed isEqualToString:@"statusDryRunFailed"];
        }
        Assert(translated, @"backup start feedback is localized in all supported languages");

        AppDelegate *previewDelegate = [[AppDelegate alloc] init];
        previewDelegate.language = @"en";
        previewDelegate.targetPopup = [[NSPopUpButton alloc] init];
        [previewDelegate.targetPopup addItemWithTitle:@"External disk"];
        previewDelegate.targetPopup.lastItem.representedObject = @"apfs";
        [previewDelegate.targetPopup addItemWithTitle:@"NAS"];
        previewDelegate.targetPopup.lastItem.representedObject = @"nas";
        previewDelegate.schedulePopup = [[NSPopUpButton alloc] init];
        [previewDelegate.schedulePopup addItemWithTitle:@"Manual"];
        previewDelegate.schedulePopup.lastItem.representedObject = @"manual";
        [previewDelegate.schedulePopup addItemWithTitle:@"Daily"];
        previewDelegate.schedulePopup.lastItem.representedObject = @"daily";
        previewDelegate.encryptionPopup = [[NSPopUpButton alloc] init];
        [previewDelegate.encryptionPopup addItemWithTitle:@"None"];
        previewDelegate.encryptionPopup.lastItem.representedObject = @"none";
        previewDelegate.cryptRemoteField = [[NSTextField alloc] init];
        previewDelegate.nasMountField = [[NSTextField alloc] init];
        previewDelegate.nasURLField = [[NSTextField alloc] init];
        previewDelegate.nasSubdirField = [[NSTextField alloc] init];
        previewDelegate.nasSubdirField.stringValue = @"GoogleDrive-Backup";
        previewDelegate.destinationPreviewField = [[NSTextField alloc] init];
        previewDelegate.configuredAPFSVolumePath = @"/Volumes/Exact Backup Disk";
        BOOL exposesAPFSVolumeUUID = [previewDelegate respondsToSelector:
            NSSelectorFromString(@"setConfiguredAPFSVolumeUUID:")];
        if (exposesAPFSVolumeUUID) {
            [previewDelegate setValue:@"11111111-2222-3333-4444-555555555555"
                               forKey:@"configuredAPFSVolumeUUID"];
        }
        NSButton *notificationCheckbox = [[NSButton alloc] init];
        notificationCheckbox.buttonType = NSButtonTypeSwitch;
        notificationCheckbox.state = NSControlStateValueOn;
        BOOL exposesNotificationPreference = [previewDelegate respondsToSelector:
            NSSelectorFromString(@"setNotificationCheckbox:")];
        if (exposesNotificationPreference) {
            [previewDelegate setValue:notificationCheckbox forKey:@"notificationCheckbox"];
        }
        NSButton *successNotificationCheckbox = [[NSButton alloc] init];
        successNotificationCheckbox.buttonType = NSButtonTypeSwitch;
        successNotificationCheckbox.state = NSControlStateValueOff;
        BOOL exposesSuccessNotificationPreference = [previewDelegate respondsToSelector:
            NSSelectorFromString(@"setSuccessNotificationCheckbox:")];
        if (exposesSuccessNotificationPreference) {
            [previewDelegate setValue:successNotificationCheckbox
                               forKey:@"successNotificationCheckbox"];
        }
        [previewDelegate updateDestinationPreview];
        Assert([previewDelegate.destinationPreviewField.stringValue isEqualToString:@"/Volumes/Exact Backup Disk"] &&
               [previewDelegate.destinationPreviewField.toolTip isEqualToString:@"/Volumes/Exact Backup Disk"] &&
               [previewDelegate.destinationPreviewField.accessibilityLabel containsString:@"Exact Backup Disk"],
               @"setup always shows the exact saved external destination in full semantics");
        NSDictionary<NSString *, NSString *> *externalUpdates =
            [previewDelegate currentSetupUpdates];
        Assert(exposesAPFSVolumeUUID &&
               [externalUpdates[@"GDRIVE_BACKUP_VOLUME_UUID"]
                   isEqualToString:@"11111111-2222-3333-4444-555555555555"],
               @"setup saves the stable UUID with an external APFS destination");

        [previewDelegate.targetPopup selectItemAtIndex:1];
        previewDelegate.nasMountField.stringValue = @"/Volumes/Archive";
        [previewDelegate updateDestinationPreview];
        Assert([previewDelegate.destinationPreviewField.stringValue isEqualToString:@"/Volumes/Archive/GoogleDrive-Backup"],
               @"destination preview follows the selected NAS mount and folder");

        NSDictionary<NSString *, NSString *> *notificationUpdates =
            [previewDelegate currentSetupUpdates];
        Assert(exposesNotificationPreference &&
               [notificationUpdates[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] isEqualToString:@"1"],
               @"setup saves the enabled automatic-backup notification preference");
        Assert(exposesSuccessNotificationPreference &&
               [T(@"de", @"notifyBackupSuccesses")
                   isEqualToString:@"Auch erfolgreiche automatische Backups melden"] &&
               [notificationUpdates[@"GDRIVE_BACKUP_NOTIFY_SUCCESSES"] isEqualToString:@"0"],
               @"setup exposes a localized opt-in for successful automatic backups");
        notificationCheckbox.state = NSControlStateValueOff;
        Assert([[previewDelegate currentSetupUpdates][@"GDRIVE_BACKUP_NOTIFY_FAILURES"]
                   isEqualToString:@"0"],
               @"setup persists an explicit notification opt-out");
        successNotificationCheckbox.state = NSControlStateValueOn;
        Assert([[previewDelegate currentSetupUpdates][@"GDRIVE_BACKUP_NOTIFY_SUCCESSES"]
                   isEqualToString:@"1"],
               @"setup persists an explicit routine-success notification opt-in");
        successNotificationCheckbox.state = NSControlStateValueOff;

        UnknownVolumeSetupDelegate *unknownSetup =
            [[UnknownVolumeSetupDelegate alloc] init];
        unknownSetup.language = @"en";
        unknownSetup.targetPopup = [[NSPopUpButton alloc] init];
        [unknownSetup.targetPopup addItemWithTitle:@"External disk"];
        unknownSetup.targetPopup.lastItem.representedObject = @"apfs";
        [unknownSetup.targetPopup addItemWithTitle:@"NAS"];
        unknownSetup.targetPopup.lastItem.representedObject = @"nas";
        [unknownSetup.targetPopup selectItemAtIndex:1];
        unknownSetup.schedulePopup = [[NSPopUpButton alloc] init];
        [unknownSetup.schedulePopup addItemWithTitle:@"Manual"];
        unknownSetup.schedulePopup.lastItem.representedObject = @"manual";
        [unknownSetup.schedulePopup addItemWithTitle:@"Daily"];
        unknownSetup.schedulePopup.lastItem.representedObject = @"daily";
        [unknownSetup.schedulePopup selectItemAtIndex:1];
        unknownSetup.encryptionPopup = [[NSPopUpButton alloc] init];
        [unknownSetup.encryptionPopup addItemWithTitle:@"None"];
        unknownSetup.encryptionPopup.lastItem.representedObject = @"none";
        unknownSetup.cryptRemoteField = [[NSTextField alloc] init];
        unknownSetup.nasMountField = [[NSTextField alloc] init];
        unknownSetup.nasMountField.stringValue = @"/Volumes/alexander";
        unknownSetup.nasURLField = [[NSTextField alloc] init];
        unknownSetup.nasSubdirField = [[NSTextField alloc] init];
        unknownSetup.nasSubdirField.stringValue = @"GoogleDrive-Backup";
        unknownSetup.notificationCheckbox = [[NSButton alloc] init];
        unknownSetup.notificationCheckbox.buttonType = NSButtonTypeSwitch;
        unknownSetup.notificationCheckbox.state = NSControlStateValueOn;
        unknownSetup.destinationPreviewField = [[NSTextField alloc] init];
        unknownSetup.statusField = [[NSTextField alloc] init];

        if ([unknownSetup respondsToSelector:loadIdentitySelector]) {
            typedef void (*LoadIdentityMethod)(
                id, SEL, NSDictionary<NSString *, NSString *> *);
            ((LoadIdentityMethod)[unknownSetup methodForSelector:loadIdentitySelector])(
                unknownSetup,
                loadIdentitySelector,
                @{
                    @"GDRIVE_BACKUP_TARGET": @"nas",
                    @"GDRIVE_BACKUP_SCHEDULE": @"daily",
                    @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/alexander"
                });
        }
        NSDictionary<NSString *, NSString *> *nasOnlyUpdates =
            [unknownSetup currentSetupUpdates];
        Assert(nasOnlyUpdates[@"GDRIVE_BACKUP_VOLUME"] == nil &&
               nasOnlyUpdates[@"GDRIVE_BACKUP_VOLUME_NAME"] == nil &&
               nasOnlyUpdates[@"GDRIVE_BACKUP_VOLUME_UUID"] == nil &&
               [nasOnlyUpdates[@"GDRIVE_BACKUP_TARGET"] isEqualToString:@"nas"] &&
               [nasOnlyUpdates[@"GDRIVE_BACKUP_SCHEDULE"] isEqualToString:@"daily"],
               @"a NAS-only profile does not synthesize or persist a hidden external target");

        unknownSetup.configuredAPFSVolumePath = @"/Volumes/Old Backup";
        unknownSetup.configuredAPFSVolumeUUID = @"OLD-UUID";

        SEL presentUnknownSelector = NSSelectorFromString(
            @"presentSetupForUnknownExternalVolumeDescriptor:");
        if ([unknownSetup respondsToSelector:presentUnknownSelector]) {
            typedef void (*PresentUnknownMethod)(id, SEL, NSDictionary *);
            PresentUnknownMethod presentUnknown =
                (PresentUnknownMethod)[unknownSetup methodForSelector:presentUnknownSelector];
            presentUnknown(unknownSetup, presentUnknownSelector, @{
                @"path": @"/Volumes/TOSHIBA_4TB",
                @"name": @"TOSHIBA_4TB",
                @"volumeUUID": @"TOSHIBA-UUID",
                @"diskID": @"disk20",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"apfs"
            });
        }
        NSDictionary<NSString *, NSString *> *stagedNASUpdates =
            [unknownSetup currentSetupUpdates];
        Assert(unknownSetup.showSetupCalls == 1 &&
               unknownSetup.saveCalls == 0 &&
               unknownSetup.launchCalls == 0 &&
               [stagedNASUpdates[@"GDRIVE_BACKUP_TARGET"] isEqualToString:@"nas"] &&
               [stagedNASUpdates[@"GDRIVE_BACKUP_SCHEDULE"] isEqualToString:@"daily"] &&
               [stagedNASUpdates[@"GDRIVE_BACKUP_NAS_MOUNT"]
                   isEqualToString:@"/Volumes/alexander"] &&
               [stagedNASUpdates[@"GDRIVE_BACKUP_VOLUME"]
                   isEqualToString:@"/Volumes/TOSHIBA_4TB"] &&
               [stagedNASUpdates[@"GDRIVE_BACKUP_VOLUME_NAME"]
                   isEqualToString:@"TOSHIBA_4TB"] &&
               [stagedNASUpdates[@"GDRIVE_BACKUP_VOLUME_UUID"]
                   isEqualToString:@"TOSHIBA-UUID"] &&
               [unknownSetup.statusField.stringValue containsString:@"TOSHIBA_4TB"],
               @"explicit setup stages the external APFS identity without changing the NAS target, schedule, or disk");

        [unknownSetup invalidateSetupHealth:nil];
        BOOL stagedIdentityVisibleAfterHealthInvalidation =
            [unknownSetup.statusField.stringValue containsString:@"TOSHIBA_4TB"];
        [unknownSetup applyMountedNetworkVolumes:@[]
                    allowingTargetAutoSelection:NO];
        BOOL stagedIdentityVisibleAfterNASRefresh =
            [unknownSetup.statusField.stringValue containsString:@"TOSHIBA_4TB"];
        Assert(stagedIdentityVisibleAfterHealthInvalidation &&
               stagedIdentityVisibleAfterNASRefresh,
               @"the explicitly staged external identity stays visible through health invalidation and NAS refresh");

        unknownSetup.configuredAPFSVolumePath = @"/Volumes/TOSHIBA_4TB";
        unknownSetup.configuredAPFSVolumeUUID = @"TOSHIBA-UUID";
        if ([unknownSetup respondsToSelector:presentUnknownSelector]) {
            typedef void (*PresentUnknownMethod)(id, SEL, NSDictionary *);
            PresentUnknownMethod presentUnknown =
                (PresentUnknownMethod)[unknownSetup methodForSelector:presentUnknownSelector];
            presentUnknown(unknownSetup, presentUnknownSelector, @{
                @"path": @"/Volumes/Unsupported",
                @"name": @"Unsupported",
                @"volumeUUID": @"UNSUPPORTED-UUID",
                @"diskID": @"disk22",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @YES,
                @"filesystem": @"exfat"
            });
        }
        Assert([unknownSetup.configuredAPFSVolumePath
                   isEqualToString:@"/Volumes/TOSHIBA_4TB"] &&
               [unknownSetup.configuredAPFSVolumeUUID isEqualToString:@"TOSHIBA-UUID"] &&
               [unknownSetup.statusField.stringValue
                   isEqualToString:T(@"en", @"unknownExternalVolumeUnsupported")] &&
               ![unknownSetup.statusField.stringValue
                   isEqualToString:T(@"en", @"unknownExternalVolumeUnavailable")] &&
               unknownSetup.saveCalls == 0 && unknownSetup.launchCalls == 0,
               @"unsupported external media explains the writable APFS requirement without replacing the staged identity");

        if ([unknownSetup respondsToSelector:presentUnknownSelector]) {
            typedef void (*PresentUnknownMethod)(id, SEL, NSDictionary *);
            PresentUnknownMethod presentUnknown =
                (PresentUnknownMethod)[unknownSetup methodForSelector:presentUnknownSelector];
            presentUnknown(unknownSetup, presentUnknownSelector, @{
                @"path": @"/Volumes/Read Only",
                @"name": @"Read Only",
                @"volumeUUID": @"READ-ONLY-UUID",
                @"diskID": @"disk23",
                @"isLocal": @YES,
                @"isInternal": @NO,
                @"isPhysical": @YES,
                @"isSystemImage": @NO,
                @"isWritable": @NO,
                @"filesystem": @"apfs"
            });
        }
        Assert([unknownSetup.configuredAPFSVolumePath
                   isEqualToString:@"/Volumes/TOSHIBA_4TB"] &&
               [unknownSetup.configuredAPFSVolumeUUID isEqualToString:@"TOSHIBA-UUID"] &&
               [unknownSetup.statusField.stringValue
                   isEqualToString:T(@"en", @"unknownExternalVolumeUnsupported")] &&
               unknownSetup.saveCalls == 0 && unknownSetup.launchCalls == 0,
               @"read-only APFS media gets accurate guidance and cannot replace the staged identity");

        BOOL unsupportedMessageLocalized = YES;
        for (NSString *code in SupportedLanguageCodes()) {
            NSString *message = T(code, @"unknownExternalVolumeUnsupported");
            if (!message.length ||
                [message isEqualToString:@"unknownExternalVolumeUnsupported"]) {
                unsupportedMessageLocalized = NO;
            }
        }
        Assert(unsupportedMessageLocalized,
               @"unsupported external-volume guidance is localized in every language");

        [previewDelegate.targetPopup selectItemAtIndex:0];
        [previewDelegate.schedulePopup selectItemAtIndex:0];
        previewDelegate.configuredAPFSVolumePath = nil;
        previewDelegate.configuredAPFSVolumeUUID = nil;
        notificationCheckbox.state = NSControlStateValueOn;
        successNotificationCheckbox.state = NSControlStateValueOff;
        NSDictionary<NSString *, NSString *> *defaultsWithNotifications = @{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_SCHEDULE": @"manual",
            @"GDRIVE_BACKUP_ENCRYPTION": @"none",
            @"GDRIVE_BACKUP_CRYPT_REMOTE": @"",
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/GoogleDrive-Backup",
            @"GDRIVE_BACKUP_NOTIFY_FAILURES": @"1",
            @"GDRIVE_BACKUP_NOTIFY_SUCCESSES": @"0"
        };
        Assert([previewDelegate setupUpdatesMatchSavedConfig:defaultsWithNotifications
                                                 savedConfig:@{}],
               @"existing profiles default notification preferences without false unsaved changes");
        Assert([previewDelegate setupUpdatesMatchSavedConfig:defaultsWithNotifications
                                                 savedConfig:@{
            @"GDRIVE_BACKUP_NOTIFY_SUCCESSES": @"malformed"
        }],
               @"a missing or malformed routine-success preference remains safely off");

        SEL availabilitySelector = NSSelectorFromString(@"updateNotificationControlAvailability");
        if ([previewDelegate respondsToSelector:availabilitySelector]) {
            typedef void (*VoidMethod)(id, SEL);
            VoidMethod updateAvailability =
                (VoidMethod)[previewDelegate methodForSelector:availabilitySelector];
            [previewDelegate.schedulePopup selectItemAtIndex:0];
            updateAvailability(previewDelegate, availabilitySelector);
            BOOL manualDisabled = !notificationCheckbox.enabled &&
                !successNotificationCheckbox.enabled;
            [previewDelegate.schedulePopup selectItemAtIndex:1];
            updateAvailability(previewDelegate, availabilitySelector);
            Assert(manualDisabled && notificationCheckbox.enabled &&
                   successNotificationCheckbox.enabled,
                   @"both notification choices are available only for an automatic schedule");
        } else {
            Assert(NO, @"both notification choices are available only for an automatic schedule");
        }

        BOOL destinationLabelTranslated = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            NSString *value = T(language, @"destinationPreview");
            destinationLabelTranslated = destinationLabelTranslated &&
                value.length > 0 && ![value isEqualToString:@"destinationPreview"];
        }
        Assert(destinationLabelTranslated,
               @"exact destination label is localized in all supported languages");

        BOOL notificationTextTranslated = YES;
        NSArray<NSString *> *notificationKeys = @[
            @"notifyBackupFailures", @"backupNotificationFailureTitle",
            @"backupNotificationMissedTitle", @"backupNotificationMissedBody",
            @"backupNotificationTargetUnavailable", @"notifyBackupSuccesses",
            @"backupNotificationSuccessTitle", @"backupNotificationSuccessBody",
            @"backupNotificationRecoverySuccessBody",
            @"backupNotificationRetrySuccessBody"
        ];
        for (NSString *language in SupportedLanguageCodes()) {
            for (NSString *key in notificationKeys) {
                NSString *value = T(language, key);
                notificationTextTranslated = notificationTextTranslated &&
                    value.length > 0 && ![value isEqualToString:key];
            }
        }
        Assert(notificationTextTranslated,
               @"notification setup and alert text is localized in all supported languages");

        SEL validationSelector = NSSelectorFromString(@"setupValidationErrorKeyForUpdates:");
        typedef NSString *(*ValidationMethod)(id, SEL, NSDictionary *);
        ValidationMethod validate = [previewDelegate respondsToSelector:validationSelector]
            ? (ValidationMethod)[previewDelegate methodForSelector:validationSelector] : NULL;
        NSString *incompatible = validate ? validate(previewDelegate, validationSelector, @{
            @"GDRIVE_BACKUP_TARGET": @"nas", @"GDRIVE_BACKUP_ENCRYPTION": @"apfs"
        }) : nil;
        NSString *unsafeCrypt = validate ? validate(previewDelegate, validationSelector, @{
            @"GDRIVE_BACKUP_TARGET": @"nas", @"GDRIVE_BACKUP_ENCRYPTION": @"rclone-crypt",
            @"GDRIVE_BACKUP_CRYPT_REMOTE": @"../../unsafe"
        }) : nil;
        NSString *validCrypt = validate ? validate(previewDelegate, validationSelector, @{
            @"GDRIVE_BACKUP_TARGET": @"nas", @"GDRIVE_BACKUP_ENCRYPTION": @"rclone-crypt",
            @"GDRIVE_BACKUP_CRYPT_REMOTE": @"backup-crypt"
        }) : @"missing";
        Assert([incompatible isEqualToString:@"statusEncryptionIncompatible"] &&
               [unsafeCrypt isEqualToString:@"statusCryptRemoteInvalid"] && !validCrypt,
               @"setup refuses incompatible encryption and unsafe crypt remotes before saving");
    }

    if (failures > 0) {
        printf("%d setup safety test(s) failed.\n", failures);
        return 1;
    }
    printf("All setup safety tests passed.\n");
    return 0;
}
