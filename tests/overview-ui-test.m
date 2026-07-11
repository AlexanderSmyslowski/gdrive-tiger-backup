#import <Cocoa/Cocoa.h>

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface OverviewLaunchDelegate : AppDelegate
@property(nonatomic) NSInteger launchCalls;
@property(nonatomic) BOOL launchSucceeds;
@end

@implementation OverviewLaunchDelegate

- (BOOL)launchBackupWithArgument:(NSString *)argument assumeYes:(BOOL)assumeYes {
    (void)argument;
    (void)assumeYes;
    self.launchCalls++;
    return self.launchSucceeds;
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
               @"overview, setup, confirmation, and progress processes stay isolated");
        Assert([delegate shouldInstallStatusItemForMode:@"overview"] &&
               [delegate shouldInstallStatusItemForMode:@"menubar"] &&
               ![delegate shouldInstallStatusItemForMode:@"setup"] &&
               ![delegate shouldInstallStatusItemForMode:@"confirm"] &&
               ![delegate shouldInstallStatusItemForMode:@"progress"],
               @"menu bar status exists only in the persistent controller modes");

        OverviewLaunchDelegate *guardedLaunch = [[OverviewLaunchDelegate alloc] init];
        guardedLaunch.language = @"en";
        guardedLaunch.launchSucceeds = YES;
        [guardedLaunch startOverviewBackup:nil];
        [guardedLaunch startOverviewBackup:nil];
        Assert(guardedLaunch.launchCalls == 1,
               @"overview blocks repeated clicks while a backup launch is pending");

        OverviewLaunchDelegate *failedLaunch = [[OverviewLaunchDelegate alloc] init];
        failedLaunch.language = @"en";
        failedLaunch.launchSucceeds = NO;
        [failedLaunch startOverviewBackup:nil];
        [failedLaunch startOverviewBackup:nil];
        Assert(failedLaunch.launchCalls == 2,
               @"overview launch failures remain explicitly retryable");

        NSArray<NSString *> *overviewKeys = @[
            @"overviewSubtitle", @"overviewLastRun", @"overviewNextRun",
            @"overviewTarget", @"overviewStorage", @"overviewSettings",
            @"overviewOpen", @"overviewNeverRun", @"overviewUnavailable",
            @"overviewFreeOf", @"overviewStatusInterrupted", @"overviewStatusUnknown"
        ];
        BOOL allOverviewTextLocalized = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            for (NSString *key in overviewKeys) {
                NSString *value = T(language, key);
                allOverviewTextLocalized = allOverviewTextLocalized &&
                    value.length > 0 && ![value isEqualToString:key];
            }
        }
        Assert(allOverviewTextLocalized,
               @"overview and menu bar text is localized in all supported languages");

        BOOL actionTitlesFit = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            view.language = language;
            actionTitlesFit = actionTitlesFit && restoreButton != nil &&
                view.settingsButton.frame.size.width >= ceil(view.settingsButton.cell.cellSize.width) &&
                restoreButton.frame.size.width >= ceil(restoreButton.cell.cellSize.width) &&
                view.backupButton.frame.size.width >= ceil(view.backupButton.cell.cellSize.width);
        }
        Assert(actionTitlesFit,
               @"overview action titles remain fully visible in every supported language");

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
               [menuTitles containsObject:T(@"en", @"restoreTitle")] &&
               [menuTitles containsObject:T(@"en", @"overviewSettings")] &&
               [[menuTitles componentsJoinedByString:@" "] containsString:@"Successful"] &&
               [[menuTitles componentsJoinedByString:@" "] containsString:@"Today, 20:00"] &&
               [[menuTitles componentsJoinedByString:@" "] containsString:@"/Volumes/Archive"] &&
               [[menuTitles componentsJoinedByString:@" "] containsString:@"812 GB"],
               @"menu bar exposes the same status, schedule, target, storage, and actions");
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
