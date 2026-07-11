#import <Cocoa/Cocoa.h>

#import "UpdateSupport.h"

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

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
@end

@implementation UpdateTestDelegate

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

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        UpdateTestDelegate *delegate = [[UpdateTestDelegate alloc] init];
        delegate.language = @"de";
        DeferredUpdateChecker *checker = [[DeferredUpdateChecker alloc] init];
        [delegate setValue:checker forKey:@"updateChecker"];

        NSDictionary<NSString *, NSString *> *menuSnapshot = @{
            @"status": @"unknown", @"lastRun": @"–", @"lastRunDetail": @"",
            @"nextRun": @"–", @"target": @"–", @"storage": @"–"
        };
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
            @"updateUnavailableTitle", @"updateUnavailableMessage", @"updateOpenRelease"
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
