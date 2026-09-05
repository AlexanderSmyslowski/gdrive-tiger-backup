#import <Cocoa/Cocoa.h>

#import "UpdateSupport.h"
#import "TestApplicationSupport.h"

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface AppDelegate (AutomaticUpdateContract)
- (void)automaticUpdateTick;
- (void)maybeOfferUpdateConsent;
- (void)setAutomaticUpdatesEnabled:(BOOL)enabled;
- (NSAlert *)updatePreferencesAlertForConsent:(BOOL)consent;
- (void)automaticUpdateStateChanged;
- (void)handleUpdateNotificationAction:(NSString *)action userInfo:(NSDictionary *)info identifier:(NSString *)identifier;
@end

@interface UpdateTestSettings : NSObject
@property(nonatomic) UNAuthorizationStatus authorizationStatus;
@end
@implementation UpdateTestSettings
@end

@interface UpdateTestNotification : NSObject
@property(nonatomic, strong) UNNotificationRequest *request;
@end
@implementation UpdateTestNotification
@end
@interface UpdateTestResponse : NSObject
@property(nonatomic, copy) NSString *actionIdentifier;
@property(nonatomic, strong) UpdateTestNotification *notification;
@end
@implementation UpdateTestResponse
@end

@interface UpdateTestCenter : NSObject
@property(nonatomic, strong) UpdateTestSettings *settings;
@property(nonatomic) NSInteger permissionCalls;
@property(nonatomic, strong) UNNotificationRequest *request;
@property(nonatomic, copy) void (^delivery)(NSError *);
@property(nonatomic, copy) void (^settingsCompletion)(UNNotificationSettings *);
@property(nonatomic) BOOL deferSettings;
@property(nonatomic) BOOL deferAuthorization;
@property(nonatomic, copy) void (^authorizationCompletion)(BOOL, NSError *);
@property(nonatomic, strong) NSMutableArray *removed;
@end
@implementation UpdateTestCenter
- (void)getNotificationSettingsWithCompletionHandler:(void (^)(UNNotificationSettings *))completion {
    if (self.deferSettings) self.settingsCompletion = completion;
    else completion((id)self.settings);
}
- (void)requestAuthorizationWithOptions:(UNAuthorizationOptions)options completionHandler:(void (^)(BOOL, NSError *))completion {
    (void)options; self.permissionCalls++;
    if (self.deferAuthorization) self.authorizationCompletion = completion;
    else completion(NO, nil);
}
- (void)addNotificationRequest:(UNNotificationRequest *)request withCompletionHandler:(void (^)(NSError *))completion {
    self.request = request; self.delivery = completion;
}
- (void)removeDeliveredNotificationsWithIdentifiers:(NSArray *)identifiers { [self.removed addObjectsFromArray:identifiers]; }
- (void)removePendingNotificationRequestsWithIdentifiers:(NSArray *)identifiers { [self.removed addObjectsFromArray:identifiers]; }
@end

@interface UpdateTestWindow : NSWindow
@property(nonatomic) BOOL pretendVisible;
@property(nonatomic) BOOL pretendSheet;
@end
@implementation UpdateTestWindow
- (BOOL)isVisible { return self.pretendVisible; }
- (NSWindow *)attachedSheet { return self.pretendSheet ? self : nil; }
@end

@interface DeferredUpdateChecker : GDTUpdateChecker
@property(nonatomic) NSInteger calls;
@property(nonatomic, copy) void (^pendingCompletion)(NSDictionary<NSString *, NSString *> *result);
@end

@implementation DeferredUpdateChecker

- (void)checkCurrentVersion:(NSString *)currentVersion
                 completion:(void (^)(NSDictionary<NSString *, NSString *> *))completion {
    (void)currentVersion;
    self.calls++;
    self.pendingCompletion = completion;
}

@end

@interface UpdateTestDelegate : AppDelegate
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *presentedResult;
@property(nonatomic, strong) NSURL *openedURL;
@property(nonatomic, strong) UpdateTestCenter *center;
@property(nonatomic) BOOL pretendActive;
@property(nonatomic) NSInteger consentPresentations;
@property(nonatomic, copy) void (^consentCompletion)(NSModalResponse);
@end

@implementation UpdateTestDelegate

- (BOOL)updateApplicationIsActive { return self.pretendActive; }
- (UNUserNotificationCenter *)backupNotificationCenter { return (id)self.center; }
- (void)presentUpdatePreferencesAlert:(NSAlert *)alert completion:(void (^)(NSModalResponse))completion {
    (void)alert; self.consentPresentations++; self.consentCompletion = completion;
}

- (void)presentUpdateResult:(NSDictionary<NSString *, NSString *> *)result {
    self.presentedResult = result;
}

- (BOOL)openUpdateURL:(NSURL *)url {
    self.openedURL = url;
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

static void DrainMainQueue(void) {
    for (NSUInteger pass = 0; pass < 4; pass++) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

static void TestAutomaticUI(NSDictionary *menuSnapshot) {
    UpdateTestDelegate *delegate = [UpdateTestDelegate new];
    delegate.language = @"de";
    delegate.center = [UpdateTestCenter new];
    delegate.center.settings = [UpdateTestSettings new];
    delegate.center.settings.authorizationStatus = UNAuthorizationStatusDenied;
    delegate.center.removed = [NSMutableArray array];
    NSString *domain = [@"GDTUpdateUITests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:domain];
    DeferredUpdateChecker *checker = [DeferredUpdateChecker new];
    GDTAutomaticUpdatePolicy *policy = [[GDTAutomaticUpdatePolicy alloc] initWithDefaults:defaults checker:checker currentVersion:@"2.0.0"];
    __block NSDate *now = [NSDate dateWithTimeIntervalSince1970:2000000000];
    policy.clock = ^{ return now; };
    BOOL implemented = [delegate respondsToSelector:@selector(automaticUpdateTick)];
    NSMenu *menu = [delegate statusMenuForSnapshot:menuSnapshot];
    Assert([menu itemWithTitle:T(@"de", @"updateSettings")].action == @selector(showUpdatePreferences:),
           @"status menu exposes compact app-wide update settings");
    Assert(implemented, @"controller supports consent-gated background update scheduling");
    if (!implemented) { [defaults removePersistentDomainForName:domain]; return; }
    [delegate setValue:policy forKey:@"automaticUpdatePolicy"];
    __weak UpdateTestDelegate *weakDelegate = delegate;
    policy.stateChanged = ^{ [weakDelegate automaticUpdateStateChanged]; };
    UpdateTestWindow *window = [[UpdateTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    delegate.window = window;
    delegate.lastOverviewSnapshot = menuSnapshot;
    [delegate automaticUpdateTick];
    Assert(checker.calls == 0 && delegate.consentPresentations == 0, @"headless startup neither checks nor offers consent");
    delegate.overviewMode = YES;
    [delegate setValue:@YES forKey:@"updateConsentRequested"];
    [delegate maybeOfferUpdateConsent];
    window.pretendVisible = YES; [delegate maybeOfferUpdateConsent];
    delegate.pretendActive = YES;
    delegate.lastOverviewSnapshot = @{@"status": @"running"}; [delegate maybeOfferUpdateConsent];
    delegate.lastOverviewSnapshot = menuSnapshot; window.pretendSheet = YES; [delegate maybeOfferUpdateConsent];
    Assert(delegate.consentPresentations == 0, @"consent waits for visible active idle overview without another sheet");
    window.pretendSheet = NO;
    UpdateTestResponse *externalResponse = [UpdateTestResponse new];
    externalResponse.actionIdentifier = @"GDT_UNKNOWN_EXTERNAL_VOLUME_IGNORE";
    externalResponse.notification = [UpdateTestNotification new];
    UNMutableNotificationContent *externalContent = [UNMutableNotificationContent new];
    externalContent.categoryIdentifier = @"GDT_UNKNOWN_EXTERNAL_VOLUME";
    externalResponse.notification.request = [UNNotificationRequest requestWithIdentifier:@"unknown-volume-test"
        content:externalContent trigger:nil];
    __block BOOL responseFinished = NO;
    [delegate userNotificationCenter:(id)delegate.center didReceiveNotificationResponse:(id)externalResponse
        withCompletionHandler:^{ responseFinished = YES; }];
    DrainMainQueue();
    [delegate applicationDidBecomeActive:[NSNotification notificationWithName:NSApplicationDidBecomeActiveNotification object:NSApp]];
    Assert(responseFinished && !delegate.updateConsentRequested && delegate.consentPresentations == 0,
           @"unknown-volume notification activation cancels previously deferred update consent");
    delegate.updateConsentRequested = YES;
    [delegate maybeOfferUpdateConsent]; [delegate maybeOfferUpdateConsent];
    Assert(delegate.consentPresentations == 1, @"eligible visible intent offers exactly one consent sheet");
    delegate.consentCompletion(NSModalResponseCancel);
    Assert(!policy.answered && checker.calls == 0, @"closing consent is not permission to contact GitHub");
    [delegate maybeOfferUpdateConsent];
    Assert(delegate.consentPresentations == 1, @"dismissed consent is not repeatedly shown in the same session");
    [delegate setAutomaticUpdatesEnabled:NO];
    [delegate automaticUpdateTick];
    Assert(policy.answered && checker.calls == 0, @"refusal persists without automatic HTTP");
    NSAlert *preferences = [delegate updatePreferencesAlertForConsent:NO];
    Assert([preferences.accessoryView isKindOfClass:NSButton.class] && preferences.buttons.count == 2,
           @"settings use a native checkbox with save and cancel controls");
    [delegate setAutomaticUpdatesEnabled:YES];
    DrainMainQueue();
    Assert(checker.calls == 1 && delegate.center.permissionCalls == 0,
           @"explicit opt-in checks once without reprompting denied system permission");
    DeferredUpdateChecker *manualChecker = [DeferredUpdateChecker new];
    delegate.updateChecker = manualChecker;
    [delegate checkForUpdates:nil];
    Assert(manualChecker.calls == 1 && checker.calls == 1,
           @"explicit manual check remains available during automatic HTTP");
    checker.pendingCompletion(@{@"status": @"updateAvailable", @"version": @"2.1.0"});
    Assert(!delegate.presentedResult && !delegate.center.request &&
           [[delegate statusMenuForSnapshot:menuSnapshot] itemWithTitle:
               [NSString stringWithFormat:T(@"de", @"updateAvailableMenu"), @"2.1.0"]],
           @"denied notification permission leaves passive discovery without a result dialog");
    manualChecker.pendingCompletion(@{@"status": @"current", @"version": @"2.0.0"});
    Assert([delegate.presentedResult[@"status"] isEqual:@"current"],
           @"only the manual request completion produces the explicit result dialog");
    delegate.presentedResult = nil;
    [delegate buildMainMenu];
    Assert([NSApp.mainMenu.itemArray.firstObject.submenu itemWithTitle:T(@"de", @"updateSettings")],
           @"application menu exposes the same update preferences");
    now = [now dateByAddingTimeInterval:86400];
    delegate.center.settings.authorizationStatus = UNAuthorizationStatusAuthorized;
    [delegate automaticUpdateTick];
    checker.pendingCompletion(@{@"status": @"updateAvailable", @"version": @"2.2.0"});
    UNNotificationRequest *notice = delegate.center.request;
    Assert([notice.content.categoryIdentifier isEqual:@"GDT_UPDATE_AVAILABLE"] && !notice.content.sound &&
           notice.content.interruptionLevel == UNNotificationInterruptionLevelPassive,
           @"automatic release notice is passive and silent in its own category");
    [delegate handleUpdateNotificationAction:@"GDT_UPDATE_OPEN" userInfo:@{@"version": @"evil"} identifier:notice.identifier];
    Assert(!delegate.openedURL, @"malformed update actions never open a URL");
    NSMutableDictionary *payload = [notice.content.userInfo mutableCopy]; payload[@"url"] = @"https://evil.invalid";
    [delegate handleUpdateNotificationAction:@"GDT_UPDATE_OPEN" userInfo:payload identifier:notice.identifier];
    Assert([delegate.openedURL.absoluteString isEqual:@"https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"],
           @"explicit notification action ignores payload URLs and opens the official page");
    [delegate handleUpdateNotificationAction:@"GDT_UPDATE_LATER" userInfo:payload identifier:notice.identifier];
    Assert([delegate.center.removed containsObject:notice.identifier] && [policy.availableVersion isEqual:@"2.2.0"],
           @"later removes only the update notice and retains passive discovery");
    [delegate setAutomaticUpdatesEnabled:NO]; [delegate setAutomaticUpdatesEnabled:YES];
    [delegate.center.removed removeAllObjects];
    delegate.center.delivery(nil);
    DrainMainQueue();
    Assert([delegate.center.removed containsObject:notice.identifier], @"delayed delivery cannot resurrect opted-out notices");
    delegate.center.deferSettings = YES;
    now = [now dateByAddingTimeInterval:86400]; [delegate automaticUpdateTick];
    checker.pendingCompletion(@{@"status": @"updateAvailable", @"version": @"2.3.0"});
    void (^settingsCompletion)(UNNotificationSettings *) = delegate.center.settingsCompletion;
    Assert(settingsCompletion != nil, @"release delivery waits at the injected notification-settings boundary");
    [delegate setAutomaticUpdatesEnabled:NO]; [delegate setAutomaticUpdatesEnabled:YES];
    if (settingsCompletion) settingsCompletion((id)delegate.center.settings);
    Assert(delegate.center.request == notice, @"opt-out invalidates a notice waiting on notification settings");
    NSSet *categories = [delegate appNotificationCategories];
    Assert([delegate presentationOptionsForNotificationCategoryIdentifier:@"GDT_UPDATE_AVAILABLE"] == UNNotificationPresentationOptionList &&
           ([delegate presentationOptionsForNotificationCategoryIdentifier:@"GDT_BACKUP_ALERT"] & UNNotificationPresentationOptionSound),
           @"foreground update notices stay list-only and silent without changing backup alerts");
    Assert(categories.count == 4 && [[categories valueForKey:@"identifier"] containsObject:@"GDT_BACKUP_ALERT"] &&
           [[categories valueForKey:@"identifier"] containsObject:@"GDT_UNKNOWN_EXTERNAL_VOLUME"],
           @"update category preserves existing backup and unknown-volume categories");
    [delegate setAutomaticUpdatesEnabled:NO];
    delegate.center.deferSettings = NO;
    delegate.center.settings.authorizationStatus = UNAuthorizationStatusNotDetermined;
    [delegate automaticUpdateTick]; DrainMainQueue();
    Assert(delegate.center.permissionCalls == 0, @"background checks never ask for OS notification permission");
    [delegate setAutomaticUpdatesEnabled:YES]; DrainMainQueue();
    Assert(delegate.center.permissionCalls == 1, @"only explicit update opt-in may request OS alert permission");
    [delegate setAutomaticUpdatesEnabled:NO];
    [delegate setAutomaticUpdatesEnabled:YES]; [delegate setAutomaticUpdatesEnabled:NO];
    DrainMainQueue();
    Assert(delegate.center.permissionCalls == 1, @"opt-out cancels an authorization check awaiting its callback");
    delegate.center.deferAuthorization = YES;
    now = [now dateByAddingTimeInterval:86400];
    NSInteger beforePermission = checker.calls;
    [delegate setAutomaticUpdatesEnabled:YES]; DrainMainQueue();
    [delegate automaticUpdateTick];
    Assert(checker.calls == beforePermission,
           @"first opt-in waits for OS permission decision before starting automatic HTTP");
    delegate.center.settings.authorizationStatus = UNAuthorizationStatusAuthorized;
    delegate.center.authorizationCompletion(YES, nil); DrainMainQueue();
    Assert(checker.calls == beforePermission + 1, @"permission response resumes one due automatic check");
    checker.pendingCompletion(@{@"status": @"updateAvailable", @"version": @"2.4.0"});
    Assert([delegate.center.request.content.userInfo[@"version"] isEqual:@"2.4.0"],
           @"granting first opt-in permission does not lose the first release notice");
    UNNotificationRequest *failedNotice = delegate.center.request;
    delegate.center.delivery([NSError errorWithDomain:@"UpdateTestDelivery" code:1 userInfo:nil]);
    DrainMainQueue();
    [delegate automaticUpdateStateChanged];
    Assert([policy.availableVersion isEqual:@"2.4.0"] && delegate.center.request == failedNotice &&
           !delegate.presentedResult, @"delivery failure retains passive discovery without retry or modal UI");
    for (NSString *language in @[@"de", @"fr"]) {
        delegate.language = language;
        for (NSNumber *consent in @[@NO, @YES]) {
            NSAlert *alert = [delegate updatePreferencesAlertForConsent:consent.boolValue];
            [alert layout];
            if (!consent.boolValue) {
                NSButton *checkbox = (NSButton *)alert.accessoryView;
                Assert(checkbox.frame.size.width >= checkbox.intrinsicContentSize.width,
                       @"localized automatic-update checkbox is not clipped");
            }
            NSString *directory = NSProcessInfo.processInfo.environment[@"GDT_UPDATE_PREVIEW_DIR"];
            if (directory.length) {
                NSView *view = alert.window.contentView;
                NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
                [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
                NSString *name = [NSString stringWithFormat:@"update-%@-%@.png", language, consent.boolValue ? @"consent" : @"settings"];
                Assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                    writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES], @"isolated native update UI preview renders");
            }
        }
    }
    [defaults removePersistentDomainForName:domain];
    [window close];
}

int main(void) {
    setbuf(stdout, NULL);
    @autoreleasepool {
        NSApplication *testApplication =
            GDTInitializeAccessoryTestApplication();
        Assert(testApplication.activationPolicy ==
                   NSApplicationActivationPolicyAccessory,
               @"the update UI harness stays out of the Dock");
        UpdateTestDelegate *delegate = [[UpdateTestDelegate alloc] init];
        delegate.language = @"de";
        DeferredUpdateChecker *checker = [[DeferredUpdateChecker alloc] init];
        [delegate setValue:checker forKey:@"updateChecker"];

        NSDictionary<NSString *, NSString *> *menuSnapshot = @{
            @"status": @"unknown", @"lastRun": @"–", @"lastRunDetail": @"",
            @"nextRun": @"–", @"target": @"–", @"storage": @"–"
        };
        TestAutomaticUI(menuSnapshot);
        NSMenu *statusMenu = [delegate statusMenuForSnapshot:menuSnapshot];
        NSMenuItem *statusUpdate = [statusMenu itemWithTitle:T(@"de", @"updateCheck")];
        [delegate buildMainMenu];
        NSMenuItem *appUpdate = [NSApp.mainMenu.itemArray.firstObject.submenu
            itemWithTitle:T(@"de", @"updateCheck")];
        Assert(statusUpdate && appUpdate &&
               statusUpdate.action == NSSelectorFromString(@"checkForUpdates:") &&
               appUpdate.action == statusUpdate.action &&
               statusUpdate.target == delegate && appUpdate.target == delegate,
               @"application and menu bar expose one manual update action");
        Assert(checker.calls == 0,
               @"building or displaying update controls never starts a network check");

        SEL checkSelector = NSSelectorFromString(@"checkForUpdates:");
        if ([delegate respondsToSelector:checkSelector]) {
            typedef void (*CheckMethod)(id, SEL, id);
            CheckMethod check = (CheckMethod)[delegate methodForSelector:checkSelector];
            check(delegate, checkSelector, nil);
            check(delegate, checkSelector, nil);
        }
        Assert(checker.calls == 1 && [[delegate valueForKey:@"updateChecking"] boolValue],
               @"one visible checking state ignores repeated update clicks");
        checker.pendingCompletion(@{
            @"status": @"updateAvailable", @"version": @"2.1.0",
            @"releaseURL": @"https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"
        });
        Assert(![[delegate valueForKey:@"updateChecking"] boolValue] &&
               [delegate.presentedResult[@"status"] isEqualToString:@"updateAvailable"],
               @"one finished check publishes one explicit result");

        SEL openSelector = NSSelectorFromString(@"openOfficialReleasePage:");
        Assert([delegate respondsToSelector:openSelector],
               @"update UI has one explicit release-page action");
        if ([delegate respondsToSelector:openSelector]) {
            typedef void (*OpenMethod)(id, SEL, id);
            OpenMethod open = (OpenMethod)[delegate methodForSelector:openSelector];
            open(delegate, openSelector, nil);
        }
        Assert([delegate.openedURL.absoluteString isEqualToString:
                   @"https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"],
               @"update action opens only the fixed official release page");

        NSArray<NSString *> *keys = @[
            @"updateCheck", @"updateChecking", @"updateAvailableTitle",
            @"updateAvailableMessage", @"updateCurrentTitle", @"updateCurrentMessage",
            @"updateUnavailableTitle", @"updateUnavailableMessage", @"updateOpenRelease",
            @"updateSettings", @"updateConsentTitle", @"updatePrivacyMessage", @"updateAutomatic",
            @"updateEnable", @"updateDecline", @"updateAvailableMenu", @"updateNoticeMessage", @"updateLater"
        ];
        BOOL localized = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            for (NSString *key in keys) {
                NSString *value = T(language, key);
                localized = localized && value.length && ![value isEqualToString:key];
            }
        }
        Assert(localized, @"manual update flow is localized in every supported language");
    }

    if (failures > 0) {
        printf("%d update UI test(s) failed.\n", failures);
        return 1;
    }
    printf("All update UI tests passed.\n");
    return 0;
}
