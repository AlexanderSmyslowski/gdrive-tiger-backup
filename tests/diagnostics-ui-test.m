#import <Cocoa/Cocoa.h>

#import "Localization.h"

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
    if (![view respondsToSelector:selector]) return;
    typedef void (*ApplyMethod)(id, SEL, NSDictionary *);
    ApplyMethod method = (ApplyMethod)[view methodForSelector:selector];
    method(view, selector, snapshot);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Class viewClass = NSClassFromString(@"GDTDiagnosticsView");
        Assert(viewClass != Nil, @"native diagnostics view is available");
        if (viewClass) {
            NSView *view = [[viewClass alloc] initWithFrame:NSMakeRect(0, 0, 680, 520)];
            NSArray<NSTextField *> *titleLabels = [view valueForKey:@"rowTitleLabels"];
            NSArray<NSTextField *> *detailLabels = [view valueForKey:@"rowDetailLabels"];
            NSArray<NSTextField *> *symbolLabels = [view valueForKey:@"rowSymbolLabels"];
            NSButton *refreshButton = [view valueForKey:@"refreshButton"];
            NSButton *copyButton = [view valueForKey:@"copyButton"];
            NSButton *saveButton = [view valueForKey:@"saveButton"];
            NSTextField *privacyLabel = [view valueForKey:@"privacyLabel"];
            NSTextField *overallLabel = [view valueForKey:@"overallLabel"];

            BOOL nativeRows = titleLabels.count == 7 && detailLabels.count == 7 &&
                symbolLabels.count == 7;
            for (NSTextField *label in [titleLabels arrayByAddingObjectsFromArray:detailLabels ?: @[]]) {
                nativeRows = nativeRows &&
                    [label.accessibilityRole isEqualToString:NSAccessibilityStaticTextRole] &&
                    label.accessibilityLabel.length > 0;
            }
            Assert(nativeRows && refreshButton && copyButton && saveButton &&
                   [refreshButton.accessibilityRole isEqualToString:NSAccessibilityButtonRole] &&
                   [copyButton.accessibilityRole isEqualToString:NSAccessibilityButtonRole] &&
                   [saveButton.accessibilityRole isEqualToString:NSAccessibilityButtonRole],
                   @"diagnostics use seven native accessible rows and native actions");

            NSArray<NSString *> *keys = @[
                @"diagnosticsTitle", @"diagnosticsSubtitle", @"diagnosticsOverallReady",
                @"diagnosticsOverallAttention", @"diagnosticsTools", @"diagnosticsRemote",
                @"diagnosticsDestination", @"diagnosticsSchedule", @"diagnosticsLastRun",
                @"diagnosticsController", @"diagnosticsScript", @"diagnosticsReady",
                @"diagnosticsFailure", @"diagnosticsBlocked", @"diagnosticsUnknown",
                @"diagnosticsMissingTools", @"diagnosticsRefresh", @"diagnosticsRefreshing",
                @"diagnosticsCopy", @"diagnosticsSave", @"diagnosticsPrivacy",
                @"diagnosticsCopied", @"diagnosticsSaved", @"diagnosticsManual",
                @"diagnosticsLoaded", @"diagnosticsNotLoaded",
                @"backupNotificationNASRetryBody"
            ];
            BOOL localized = YES;
            for (NSString *language in SupportedLanguageCodes()) {
                for (NSString *key in keys) {
                    NSString *value = T(language, key);
                    localized = localized && value.length > 0 && ![value isEqualToString:key];
                }
            }
            Assert(localized, @"diagnostics UI is localized in every supported language");

            NSDictionary *snapshot = @{
                @"overall": @"attention",
                @"app": @{@"version": @"1.9.0", @"build": @"15"},
                @"system": @{@"osVersion": @"macOS 15.5", @"architecture": @"arm64"},
                @"dependencies": @{@"status": @"failure", @"missing": @[@"flock", @"jq"]},
                @"remote": @{@"status": @"blocked"},
                @"destination": @{@"status": @"ready", @"kind": @"nas", @"encryption": @"none"},
                @"schedule": @{@"mode": @"daily", @"loaded": @YES},
                @"controller": @{@"loaded": @YES},
                @"script": @{@"installed": @YES, @"executable": @YES},
                @"lastRun": @{@"status": @"failure", @"reason": @"nas_mount_not_ready"}
            };
            [view setValue:@"de" forKey:@"language"];
            ApplySnapshot(view, snapshot);
            Assert([symbolLabels[0].stringValue isEqualToString:@"×"] &&
                   [symbolLabels[1].stringValue isEqualToString:@"—"] &&
                   [symbolLabels[2].stringValue isEqualToString:@"✓"] &&
                   [overallLabel.stringValue isEqualToString:T(@"de", @"diagnosticsOverallAttention")],
                   @"diagnostic states remain distinct without relying on color");
            NSString *missingText = [NSString stringWithFormat:T(@"de", @"diagnosticsMissingTools"),
                                     @"flock, jq"];
            Assert([detailLabels[0].stringValue isEqualToString:missingText] &&
                   ![detailLabels[0].stringValue containsString:@"%@"] &&
                   [detailLabels[4].stringValue containsString:T(@"de", @"backupNotificationNASRetryBody")],
                   @"diagnostics explain missing tools and the safe retryable NAS reason");
            Assert([privacyLabel.stringValue isEqualToString:T(@"de", @"diagnosticsPrivacy")] &&
                   privacyLabel.accessibilityLabel.length > 0,
                   @"diagnostics disclose exactly what the safe report omits");

            [view setValue:@"protocol=1\noverall=attention\n" forKey:@"report"];
            __block NSInteger refreshCalls = 0;
            __block NSString *copiedReport = nil;
            __block NSString *savedReport = nil;
            [view setValue:[^{ refreshCalls++; } copy] forKey:@"refreshHandler"];
            [view setValue:[^(NSString *report) { copiedReport = report; } copy]
                    forKey:@"copyHandler"];
            [view setValue:[^(NSString *report) { savedReport = report; } copy]
                    forKey:@"saveHandler"];
            [refreshButton performClick:nil];
            [refreshButton performClick:nil];
            Assert(refreshCalls == 1 && !refreshButton.enabled &&
                   [overallLabel.stringValue isEqualToString:T(@"de", @"diagnosticsRefreshing")],
                   @"diagnostic refresh has one visible loading state and ignores repeats");
            [view setValue:@NO forKey:@"loading"];
            [copyButton performClick:nil];
            [saveButton performClick:nil];
            Assert([copiedReport isEqualToString:@"protocol=1\noverall=attention\n"] &&
                   [savedReport isEqualToString:copiedReport],
                   @"copy and save actions receive only the prebuilt safe report");

            SEL feedbackSelector = NSSelectorFromString(@"showFeedbackKey:");
            if ([view respondsToSelector:feedbackSelector]) {
                typedef void (*FeedbackMethod)(id, SEL, NSString *);
                FeedbackMethod feedback = (FeedbackMethod)[view methodForSelector:feedbackSelector];
                feedback(view, feedbackSelector, @"diagnosticsCopied");
            }
            Assert([overallLabel.stringValue isEqualToString:T(@"de", @"diagnosticsCopied")],
                   @"copy feedback is visible and localized");

            BOOL actionTitlesFit = YES;
            for (NSString *language in SupportedLanguageCodes()) {
                [view setValue:language forKey:@"language"];
                actionTitlesFit = actionTitlesFit &&
                    NSWidth(refreshButton.frame) >= ceil(refreshButton.cell.cellSize.width) &&
                    NSWidth(copyButton.frame) >= ceil(copyButton.cell.cellSize.width) &&
                    NSWidth(saveButton.frame) >= ceil(saveButton.cell.cellSize.width);
            }
            Assert(actionTitlesFit, @"localized diagnostics action titles remain fully visible");
        }
    }

    if (failures > 0) {
        printf("%d diagnostics UI test(s) failed.\n", failures);
        return 1;
    }
    printf("All diagnostics UI tests passed.\n");
    return 0;
}
