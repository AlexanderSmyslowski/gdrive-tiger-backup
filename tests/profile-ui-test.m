#import <Cocoa/Cocoa.h>

#import "ProfileSupport.h"

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface ProfileTestDelegate : AppDelegate
@property(nonatomic) BOOL fakeUnsavedChanges;
@property(nonatomic) BOOL scheduleSucceeds;
@property(nonatomic) NSInteger scheduleCalls;
@property(nonatomic, copy) NSString *appliedSchedule;
@end

@implementation ProfileTestDelegate

- (BOOL)hasUnsavedSetupChanges {
    return self.fakeUnsavedChanges;
}

- (BOOL)applySchedule:(NSString *)schedule error:(NSError **)error {
    self.scheduleCalls++;
    self.appliedSchedule = schedule;
    if (self.scheduleSucceeds) return YES;
    if (error) {
        *error = [NSError errorWithDomain:@"tests.profile.schedule"
                                      code:1
                                  userInfo:@{NSLocalizedDescriptionKey: @"schedule failed"}];
    }
    return NO;
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
        [NSApplication sharedApplication];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"gdrive-profile-ui-%@", NSUUID.UUID.UUIDString]];
        NSString *legacy = [root stringByAppendingPathComponent:@"config"];
        GDTWriteConfigUpdatesAtPath(@{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_VOLUME": @"/Volumes/Default",
            @"GDRIVE_BACKUP_SCHEDULE": @"manual"
        }, legacy, nil);
        GDTProfileStore *store = [[GDTProfileStore alloc] initWithConfigDirectory:root];
        [store migrateLegacyConfigAtPath:legacy error:nil];
        NSDictionary *nasProfile = [store createProfileNamed:@"Büro-NAS"
                                               copyingConfig:@{
                                                   @"GDRIVE_BACKUP_TARGET": @"nas",
                                                   @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/Buero",
                                                   @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
                                                   @"GDRIVE_BACKUP_SCHEDULE": @"hourly"
                                               }
                                                       error:nil];

        ProfileTestDelegate *delegate = [[ProfileTestDelegate alloc] init];
        delegate.language = @"de";
        delegate.scheduleSucceeds = YES;
        [delegate setValue:store forKey:@"profileStore"];
        NSView *content = [[TigerSetupView alloc] initWithFrame:NSMakeRect(0, 0, 650, 690)];
        SEL installSelector = NSSelectorFromString(@"installProfileControlsInContentView:");
        if ([delegate respondsToSelector:installSelector]) {
            typedef void (*InstallMethod)(id, SEL, NSView *);
            InstallMethod install = (InstallMethod)[delegate methodForSelector:installSelector];
            install(delegate, installSelector, content);
        }
        NSPopUpButton *popup = [delegate valueForKey:@"profilePopup"];
        NSButton *createButton = [delegate valueForKey:@"profileCreateButton"];
        NSButton *renameButton = [delegate valueForKey:@"profileRenameButton"];
        NSButton *deleteButton = [delegate valueForKey:@"profileDeleteButton"];
        Assert(popup.numberOfItems == 2 &&
               [popup.selectedItem.representedObject isEqualToString:@"default"] &&
               [popup.accessibilityRole isEqualToString:NSAccessibilityPopUpButtonRole] &&
               [createButton.accessibilityRole isEqualToString:NSAccessibilityButtonRole] &&
               [renameButton.accessibilityRole isEqualToString:NSAccessibilityButtonRole] &&
               [deleteButton.accessibilityRole isEqualToString:NSAccessibilityButtonRole],
               @"setup exposes native accessible profile selection and management");

        NSArray<NSString *> *profileKeys = @[
            @"profileLabel", @"profileDefault", @"profileCreate", @"profileRename",
            @"profileDelete", @"profileUnsavedSwitch", @"profileActivated",
            @"profileNamePrompt", @"profileDeleteConfirm", @"discardChanges"
        ];
        BOOL localized = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            for (NSString *key in profileKeys) {
                NSString *value = T(language, key);
                localized = localized && value.length && ![value isEqualToString:key];
            }
        }
        Assert(localized, @"profile workflow is localized in every supported language");

        SEL activateSelector = NSSelectorFromString(@"activateProfileID:discardingUnsavedChanges:error:");
        Assert([delegate respondsToSelector:activateSelector],
               @"profile activation has one testable transactional entry point");
        if ([delegate respondsToSelector:activateSelector]) {
            typedef BOOL (*ActivateMethod)(id, SEL, NSString *, BOOL, NSError **);
            ActivateMethod activate = (ActivateMethod)[delegate methodForSelector:activateSelector];
            delegate.fakeUnsavedChanges = YES;
            NSError *error = nil;
            BOOL blocked = !activate(delegate, activateSelector, nasProfile[@"id"], NO, &error);
            Assert(blocked && error && [store.activeProfileID isEqualToString:@"default"] &&
                   delegate.scheduleCalls == 0,
                   @"unsaved setup changes block profile switching without explicit discard");

            error = nil;
            BOOL activated = activate(delegate, activateSelector, nasProfile[@"id"], YES, &error);
            Assert(activated && !error && [store.activeProfileID isEqualToString:nasProfile[@"id"]] &&
                   [delegate.appliedSchedule isEqualToString:@"hourly"],
                   @"explicit discard activates exactly one saved profile and its schedule");

            delegate.fakeUnsavedChanges = NO;
            delegate.scheduleSucceeds = NO;
            error = nil;
            BOOL failed = !activate(delegate, activateSelector, @"default", NO, &error);
            Assert(failed && error && [store.activeProfileID isEqualToString:nasProfile[@"id"]],
                   @"schedule activation failure rolls back to the previous profile");
        }

        delegate.language = @"de";
        NSDictionary *overview = [delegate overviewSnapshotForConfig:@{
            @"GDRIVE_BACKUP_PROFILE_NAME": @"Büro-NAS",
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/Buero",
            @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
            @"GDRIVE_BACKUP_SCHEDULE": @"manual"
        } summaryPath:@"/missing" now:[NSDate date] calendar:NSCalendar.currentCalendar];
        Assert([overview[@"target"] isEqualToString:
                   @"Büro-NAS · NAS / Netzwerk · Buero/GoogleDrive-Backup"] &&
               [overview[@"target"] rangeOfString:@"/Volumes/"].location == NSNotFound,
               @"overview and menu status identify the profile, device kind, and NAS folder");

        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:root]
                                    resultingItemURL:nil error:nil];
    }

    if (failures > 0) {
        printf("%d profile UI test(s) failed.\n", failures);
        return 1;
    }
    printf("All profile UI tests passed.\n");
    return 0;
}
