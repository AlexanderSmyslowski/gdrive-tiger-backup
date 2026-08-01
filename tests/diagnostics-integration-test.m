#import <Cocoa/Cocoa.h>

#import "TestApplicationSupport.h"

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface DiagnosticsLaunchDelegate : AppDelegate
@property(nonatomic) NSInteger refreshCalls;
@end

@implementation DiagnosticsLaunchDelegate

- (void)refreshDiagnostics {
    self.refreshCalls++;
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
        NSApplication *testApplication =
            GDTInitializeAccessoryTestApplication();
        Assert(testApplication.activationPolicy ==
                   NSApplicationActivationPolicyAccessory,
               @"the diagnostics integration harness stays out of the Dock");
        DiagnosticsLaunchDelegate *delegate = [[DiagnosticsLaunchDelegate alloc] init];
        delegate.language = @"de";

        NSDictionary<NSString *, NSString *> *menuSnapshot = @{
            @"status": @"success",
            @"lastRun": @"Fertig",
            @"lastRunDetail": @"Heute, 20:00",
            @"nextRun": @"Morgen, 20:00",
            @"target": @"Backup",
            @"storage": @"100 GB"
        };
        NSMenu *statusMenu = [delegate statusMenuForSnapshot:menuSnapshot];
        NSMenuItem *statusDiagnostics = [statusMenu itemWithTitle:T(@"de", @"diagnosticsTitle")];
        Assert(statusDiagnostics != nil && statusDiagnostics.target == delegate &&
               statusDiagnostics.action == NSSelectorFromString(@"showDiagnostics:"),
               @"menu bar exposes the shared diagnostics workflow");

        [delegate buildMainMenu];
        NSMenu *appMenu = NSApp.mainMenu.itemArray.firstObject.submenu;
        NSMenuItem *appDiagnostics = [appMenu itemWithTitle:T(@"de", @"diagnosticsTitle")];
        Assert(appDiagnostics != nil && appDiagnostics.target == delegate &&
               appDiagnostics.action == NSSelectorFromString(@"showDiagnostics:"),
               @"application menu exposes the shared diagnostics workflow");

        SEL showSelector = NSSelectorFromString(@"showDiagnostics:");
        Assert([delegate respondsToSelector:showSelector],
               @"diagnostics have one reusable application entry point");
        if ([delegate respondsToSelector:showSelector]) {
            typedef void (*ShowMethod)(id, SEL, id);
            ShowMethod show = (ShowMethod)[delegate methodForSelector:showSelector];
            show(delegate, showSelector, nil);
            NSWindow *firstWindow = [delegate valueForKey:@"diagnosticsWindow"];
            show(delegate, showSelector, nil);
            NSWindow *secondWindow = [delegate valueForKey:@"diagnosticsWindow"];
            Assert(firstWindow != nil && firstWindow == secondWindow &&
                   delegate.refreshCalls == 2,
                   @"diagnostics reuse one window and refresh on every explicit opening");
            Assert(firstWindow.level == NSNormalWindowLevel &&
                   (firstWindow.styleMask & NSWindowStyleMaskClosable) != 0 &&
                   (firstWindow.styleMask & NSWindowStyleMaskMiniaturizable) != 0 &&
                   (firstWindow.styleMask & NSWindowStyleMaskResizable) != 0 &&
                   [firstWindow.contentView isKindOfClass:NSClassFromString(@"GDTDiagnosticsView")],
                   @"diagnostics use a normal resizable native window that can fall behind other apps");
            Assert([delegate windowShouldClose:firstWindow],
                   @"closing diagnostics closes only that window and leaves the controller alive");
        }

        SEL writeSelector = NSSelectorFromString(@"writeDiagnosticsReport:toURL:error:");
        BOOL privateWrite = NO;
        if ([delegate respondsToSelector:writeSelector]) {
            typedef BOOL (*WriteMethod)(id, SEL, NSString *, NSURL *, NSError **);
            WriteMethod write = (WriteMethod)[delegate methodForSelector:writeSelector];
            NSURL *reportURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
                stringByAppendingPathComponent:[NSString stringWithFormat:
                    @"gdrive-diagnostics-%@.txt", NSUUID.UUID.UUIDString]]];
            NSError *error = nil;
            NSString *report = @"GDrive Backup Tiger Diagnostics\nprotocol=1\n";
            BOOL written = write(delegate, writeSelector, report, reportURL, &error);
            NSDictionary *attributes = [NSFileManager.defaultManager
                attributesOfItemAtPath:reportURL.path error:nil];
            NSString *saved = [NSString stringWithContentsOfURL:reportURL
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
            privateWrite = written && !error && [saved isEqualToString:report] &&
                ([attributes[NSFilePosixPermissions] unsignedShortValue] & 0777) == 0600;
            if ([NSFileManager.defaultManager fileExistsAtPath:reportURL.path]) {
                [NSFileManager.defaultManager trashItemAtURL:reportURL
                                            resultingItemURL:nil error:nil];
            }
        }
        Assert(privateWrite,
               @"explicitly saved diagnostics are atomic, exact, and owner-only");
    }

    if (failures > 0) {
        printf("%d diagnostics integration test(s) failed.\n", failures);
        return 1;
    }
    printf("All diagnostics integration tests passed.\n");
    return 0;
}
