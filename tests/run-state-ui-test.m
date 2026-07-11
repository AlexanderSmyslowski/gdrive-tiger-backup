#import <Cocoa/Cocoa.h>

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

@interface RunStateDelegate : AppDelegate
@property(nonatomic) NSInteger terminalCalls;
@property(nonatomic, copy) NSString *capturedTerminalStatus;
@end

@implementation RunStateDelegate

- (void)showTerminalStateAndQuit:(NSString *)status {
    self.terminalCalls++;
    self.capturedTerminalStatus = status;
}

@end

static int failures = 0;

static NSString *RunStatus(AppDelegate *delegate, NSString *path) {
    SEL selector = NSSelectorFromString(@"runStatusAtPath:");
    if (![delegate respondsToSelector:selector]) {
        return nil;
    }
    typedef NSString *(*RunStatusMethod)(id, SEL, NSString *);
    RunStatusMethod method = (RunStatusMethod)[delegate methodForSelector:selector];
    return method(delegate, selector, path);
}

static NSString *RunReason(AppDelegate *delegate, NSString *path) {
    SEL selector = NSSelectorFromString(@"runReasonAtPath:");
    if (![delegate respondsToSelector:selector]) {
        return nil;
    }
    typedef NSString *(*RunReasonMethod)(id, SEL, NSString *);
    RunReasonMethod method = (RunReasonMethod)[delegate methodForSelector:selector];
    return method(delegate, selector, path);
}

static NSData *RenderedTerminalState(TigerBackupView *view, NSString *status) {
    SEL selector = NSSelectorFromString(@"setTerminalStatus:");
    if (![view respondsToSelector:selector]) {
        return nil;
    }
    typedef void (*SetStatusMethod)(id, SEL, NSString *);
    SetStatusMethod method = (SetStatusMethod)[view methodForSelector:selector];
    method(view, selector, status);
    view.phase = 0;
    [view.timer invalidate];
    view.timer = nil;
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static void AssertEqual(NSString *actual, NSString *expected, NSString *name) {
    if ([actual isEqualToString:expected]) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s (expected=%s actual=%s)\n",
           name.UTF8String,
           expected.UTF8String,
           (actual ?: @"<nil>").UTF8String);
    failures++;
}

int main(void) {
    @autoreleasepool {
        AppDelegate *delegate = [[AppDelegate alloc] init];
        AssertEqual(RunStatus(delegate, @"/path/that/does/not/exist"),
                    @"pending",
                    @"transiently missing run state remains pending");

        NSString *malformedPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-malformed-%@", NSUUID.UUID.UUIDString]];
        [@"protocol=1\nstatus=running\n" writeToFile:malformedPath
                                               atomically:YES
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
        AssertEqual(RunStatus(delegate, malformedPath), @"pending", @"partial run state remains pending");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:malformedPath]
                                   resultingItemURL:nil
                                              error:nil];

        NSString *successPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-success-%@", NSUUID.UUID.UUIDString]];
        [@"protocol=1\nstatus=success\npid=123\nexit_code=0\n" writeToFile:successPath
                                                atomically:YES
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
        AssertEqual(RunStatus(delegate, successPath), @"success", @"explicit successful run is accepted");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:successPath]
                                   resultingItemURL:nil
                                              error:nil];

        NSString *permissionPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-permission-%@", NSUUID.UUID.UUIDString]];
        [@"protocol=1\nstatus=failure\npid=123\nexit_code=1\nreason=destination_permission_denied\n"
            writeToFile:permissionPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        AssertEqual(RunStatus(delegate, permissionPath), @"failure", @"explicit permission failure is terminal");
        AssertEqual(RunReason(delegate, permissionPath),
                    @"destination_permission_denied",
                    @"safe destination permission reason is exposed to the UI");

        SEL detailSelector = NSSelectorFromString(@"localizedTerminalDetailForReason:");
        NSString *permissionDetail = nil;
        if ([delegate respondsToSelector:detailSelector]) {
            typedef NSString *(*DetailMethod)(id, SEL, NSString *);
            DetailMethod detailMethod = (DetailMethod)[delegate methodForSelector:detailSelector];
            permissionDetail = detailMethod(delegate, detailSelector, @"destination_permission_denied");
        }
        AssertEqual(permissionDetail,
                    T(@"en", @"failedPermissionHint"),
                    @"permission failure has a specific localized explanation");

        TigerBackupView *permissionView = [[TigerBackupView alloc] initWithFrame:NSMakeRect(0, 0, 392, 162)];
        permissionView.language = @"en";
        SEL setDetailSelector = NSSelectorFromString(@"setTerminalDetail:");
        if ([permissionView respondsToSelector:setDetailSelector]) {
            typedef void (*SetDetailMethod)(id, SEL, NSString *);
            SetDetailMethod setDetail = (SetDetailMethod)[permissionView methodForSelector:setDetailSelector];
            setDetail(permissionView, setDetailSelector, permissionDetail);
        }
        permissionView.terminalStatus = @"failure";
        AssertEqual(permissionView.detailLabel.stringValue,
                    T(@"en", @"failedPermissionHint"),
                    @"specific permission explanation is visible in the terminal state");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:permissionPath]
                                   resultingItemURL:nil
                                              error:nil];

        for (NSString *exitCode in @[@"129", @"130", @"143"]) {
            NSString *cancelledPath = [NSTemporaryDirectory()
                stringByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-cancelled-%@", NSUUID.UUID.UUIDString]];
            NSString *contents = [NSString stringWithFormat:@"protocol=1\nstatus=cancelled\npid=123\nexit_code=%@\n", exitCode];
            [contents writeToFile:cancelledPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            AssertEqual(RunStatus(delegate, cancelledPath),
                        @"cancelled",
                        [NSString stringWithFormat:@"signal %@ stays cancelled", exitCode]);
            [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:cancelledPath]
                                       resultingItemURL:nil
                                                  error:nil];
        }

        NSString *legacyPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-legacy-%@", NSUUID.UUID.UUIDString]];
        [@"status=success\nexit_code=0\n" writeToFile:legacyPath
                                                atomically:YES
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
        AssertEqual(RunStatus(delegate, legacyPath), @"failure", @"unversioned state fails closed");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:legacyPath]
                                   resultingItemURL:nil
                                              error:nil];

        NSString *skippedPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-skipped-%@", NSUUID.UUID.UUIDString]];
        [@"protocol=1\nstatus=skipped\npid=123\nreason=already_running\nexit_code=0\n" writeToFile:skippedPath
                                                                                               atomically:YES
                                                                                                 encoding:NSUTF8StringEncoding
                                                                                                    error:nil];
        AssertEqual(RunStatus(delegate, skippedPath), @"skipped", @"concurrent run stays skipped");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:skippedPath]
                                   resultingItemURL:nil
                                              error:nil];

        NSString *declinedPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-declined-%@", NSUUID.UUID.UUIDString]];
        [@"protocol=1\nstatus=skipped\npid=123\nreason=user_declined\nexit_code=0\n"
            writeToFile:declinedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        AssertEqual(RunStatus(delegate, declinedPath),
                    @"skipped",
                    @"declined destination confirmation stays skipped");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:declinedPath]
                                   resultingItemURL:nil
                                              error:nil];

        NSString *runningPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-running-%@", NSUUID.UUID.UUIDString]];
        NSString *runningContents = [NSString stringWithFormat:@"protocol=1\nstatus=running\npid=%d\n", getpid()];
        [runningContents writeToFile:runningPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        AssertEqual(RunStatus(delegate, runningPath), @"running", @"live process remains running");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:runningPath]
                                   resultingItemURL:nil
                                              error:nil];

        NSString *orphanPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-orphan-%@", NSUUID.UUID.UUIDString]];
        [@"protocol=1\nstatus=running\npid=99999999\n" writeToFile:orphanPath
                                                            atomically:YES
                                                              encoding:NSUTF8StringEncoding
                                                                 error:nil];
        AssertEqual(RunStatus(delegate, orphanPath), @"failure", @"orphaned run fails closed");
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:orphanPath]
                                   resultingItemURL:nil
                                              error:nil];

        NSString *sentinelPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-sentinel-%@", NSUUID.UUID.UUIDString]];
        NSString *sentinelContents = [NSString stringWithFormat:@"%d\n", getpid()];
        [sentinelContents writeToFile:sentinelPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        RunStateDelegate *pendingDelegate = [[RunStateDelegate alloc] init];
        pendingDelegate.runStatePath = @"/path/that/does/not/exist";
        pendingDelegate.sentinelPath = sentinelPath;
        [pendingDelegate checkSentinel];
        if (pendingDelegate.terminalCalls == 0) {
            printf("ok - live sentinel tolerates a transient missing run state\n");
        } else {
            printf("not ok - live sentinel was reported terminal while state was pending\n");
            failures++;
        }

        [@"99999999\n" writeToFile:sentinelPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [pendingDelegate checkSentinel];
        if (pendingDelegate.terminalCalls == 1 &&
            [pendingDelegate.capturedTerminalStatus isEqualToString:@"failure"]) {
            printf("ok - dead sentinel owner still fails closed\n");
        } else {
            printf("not ok - dead sentinel owner did not fail closed\n");
            failures++;
        }
        [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:sentinelPath]
                                   resultingItemURL:nil
                                              error:nil];

        TigerBackupView *view = [[TigerBackupView alloc] initWithFrame:NSMakeRect(0, 0, 392, 162)];
        NSData *successImage = RenderedTerminalState(view, @"success");
        NSData *failureImage = RenderedTerminalState(view, @"failure");
        NSData *cancelledImage = RenderedTerminalState(view, @"cancelled");
        NSData *skippedImage = RenderedTerminalState(view, @"skipped");
        NSData *runningImage = RenderedTerminalState(view, @"");
        if (successImage && failureImage && cancelledImage &&
            skippedImage && runningImage &&
            ![successImage isEqualToData:failureImage] &&
            ![failureImage isEqualToData:cancelledImage] &&
            ![successImage isEqualToData:cancelledImage] &&
            ![skippedImage isEqualToData:runningImage]) {
            printf("ok - terminal outcomes have distinct rendering\n");
        } else {
            printf("not ok - terminal outcomes do not have distinct rendering\n");
            failures++;
        }

        for (NSString *language in SupportedLanguageCodes()) {
            for (NSString *key in @[@"failed", @"failedHint", @"failedPermissionHint", @"cancelled", @"cancelledHint", @"skipped", @"skippedHint"]) {
                NSString *localized = T(language, key);
                if (localized.length > 0 && ![localized isEqualToString:key]) {
                    printf("ok - %s is localized for %s\n", key.UTF8String, language.UTF8String);
                } else {
                    printf("not ok - %s is not localized for %s\n", key.UTF8String, language.UTF8String);
                    failures++;
                }
            }
        }

        SEL applySelector = NSSelectorFromString(@"applyTerminalStatus:toView:");
        for (NSString *terminalStatus in @[@"success", @"failure", @"cancelled", @"skipped"]) {
            TigerBackupView *terminalView = [[TigerBackupView alloc] initWithFrame:NSMakeRect(0, 0, 392, 162)];
            if ([delegate respondsToSelector:applySelector]) {
                typedef void (*ApplyTerminalMethod)(id, SEL, NSString *, TigerBackupView *);
                ApplyTerminalMethod method = (ApplyTerminalMethod)[delegate methodForSelector:applySelector];
                method(delegate, applySelector, terminalStatus, terminalView);
            }
            AssertEqual(terminalView.terminalStatus,
                        terminalStatus,
                        [NSString stringWithFormat:@"%@ outcome is applied to the visible view", terminalStatus]);
        }
    }

    if (failures > 0) {
        printf("%d run state UI test(s) failed.\n", failures);
        return 1;
    }
    printf("All run state UI tests passed.\n");
    return 0;
}
