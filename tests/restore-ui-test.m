#import <Cocoa/Cocoa.h>

#import "Localization.h"
#import "TestApplicationSupport.h"

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
               @"the restore UI harness stays out of the Dock");
        Class viewClass = NSClassFromString(@"GDTRestoreBrowserView");
        Assert(viewClass != Nil, @"restore browser view is available");
        if (viewClass) {
            NSView *view = [[viewClass alloc] initWithFrame:NSMakeRect(0, 0, 820, 560)];
            NSTableView *itemsTable = [view valueForKey:@"itemsTable"];
            NSTableView *versionsTable = [view valueForKey:@"versionsTable"];
            NSButton *backButton = [view valueForKey:@"backButton"];
            NSButton *openButton = [view valueForKey:@"openButton"];
            NSButton *restoreButton = [view valueForKey:@"restoreButton"];
            NSButton *revealButton = [view valueForKey:@"revealButton"];
            NSTextField *statusLabel = [view valueForKey:@"statusLabel"];
            NSTextField *itemsHeadingLabel = [view respondsToSelector:NSSelectorFromString(@"itemsHeadingLabel")]
                ? [view valueForKey:@"itemsHeadingLabel"] : nil;
            NSTextField *versionsHeadingLabel = [view respondsToSelector:NSSelectorFromString(@"versionsHeadingLabel")]
                ? [view valueForKey:@"versionsHeadingLabel"] : nil;
            Assert(itemsTable && versionsTable && backButton && openButton && restoreButton &&
                   [itemsTable.accessibilityRole isEqualToString:NSAccessibilityTableRole] &&
                   [versionsTable.accessibilityRole isEqualToString:NSAccessibilityTableRole],
                   @"restore browser uses native accessible tables and buttons");

            NSArray<NSString *> *keys = @[
                @"restoreTitle", @"restoreSubtitle", @"restoreFilesColumn",
                @"restoreVersionsColumn", @"restoreSizeColumn", @"restoreBack",
                @"restoreOpenFolder", @"restoreAction", @"restoreLoading",
                @"restoreEmpty", @"restoreTargetUnavailable", @"restoreCurrent",
                @"restoreHistorical", @"restoreVerified", @"restoreIntegrityFailed",
                @"restoreFailed", @"restoreShowInFinder", @"restoreNoVersions",
                @"restoreChooseDestination"
            ];
            BOOL localized = YES;
            for (NSString *language in SupportedLanguageCodes()) {
                for (NSString *key in keys) {
                    NSString *value = T(language, key);
                    localized = localized && value.length > 0 && ![value isEqualToString:key];
                }
            }
            Assert(localized, @"restore workflow is localized in every supported language");

            [view setValue:@"de" forKey:@"language"];
            Assert([backButton.title isEqualToString:T(@"de", @"restoreBack")] &&
                   [openButton.title isEqualToString:T(@"de", @"restoreOpenFolder")] &&
                   [restoreButton.title isEqualToString:T(@"de", @"restoreAction")] &&
                   [itemsTable.tableColumns.firstObject.title isEqualToString:T(@"de", @"restoreFilesColumn")],
                   @"changing language updates visible restore controls");
            Assert([itemsHeadingLabel.stringValue isEqualToString:T(@"de", @"restoreFilesColumn")] &&
                   [versionsHeadingLabel.stringValue isEqualToString:T(@"de", @"restoreVersionsColumn")] &&
                   itemsHeadingLabel.accessibilityLabel.length > 0 &&
                   versionsHeadingLabel.accessibilityLabel.length > 0,
                   @"both restore tables have visible localized section headings");
            Assert(versionsTable.tableColumns.firstObject.width >= 180.0,
                   @"version dates have enough width to remain readable");

            NSArray *entries = @[
                @{@"name": @"Folder", @"relativePath": @"My Drive/Folder", @"kind": @"directory"},
                @{@"name": @"Report.txt", @"relativePath": @"My Drive/Report.txt", @"kind": @"file"}
            ];
            NSArray *versions = @[
                @{@"kind": @"current", @"displayDate": @"Current", @"displaySize": @"2 KB",
                  @"sourceURL": [NSURL fileURLWithPath:@"/tmp/current"]},
                @{@"kind": @"historical", @"displayDate": @"10 July", @"displaySize": @"1 KB",
                  @"sourceURL": [NSURL fileURLWithPath:@"/tmp/old"]}
            ];
            [view setValue:entries forKey:@"entries"];
            [view setValue:versions forKey:@"versions"];
            Assert(itemsTable.numberOfRows == 2 && versionsTable.numberOfRows == 2,
                   @"restore browser presents files and actual available versions");

            __block NSString *selectedFile = nil;
            __block NSString *openedFolder = nil;
            __block NSInteger restoreCalls = 0;
            [view setValue:[^(NSString *path) { selectedFile = path; } copy]
                    forKey:@"fileSelectionHandler"];
            [view setValue:[^(NSString *path) { openedFolder = path; } copy]
                    forKey:@"browseHandler"];
            [view setValue:[^(NSDictionary *version) { (void)version; restoreCalls++; } copy]
                    forKey:@"restoreHandler"];

            [itemsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:NSTableViewSelectionDidChangeNotification object:itemsTable];
            Assert([selectedFile isEqualToString:@"My Drive/Report.txt"] && !openButton.enabled,
                   @"selecting a file requests its versions without pretending it is a folder");

            [view setValue:versions forKey:@"versions"];
            [versionsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:NSTableViewSelectionDidChangeNotification object:versionsTable];
            [restoreButton performClick:nil];
            Assert(restoreButton.enabled && restoreCalls == 1,
                   @"one selected version enables one explicit restore action");

            [itemsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:NSTableViewSelectionDidChangeNotification object:itemsTable];
            [openButton performClick:nil];
            Assert(openButton.enabled && [openedFolder isEqualToString:@"My Drive/Folder"],
                   @"folder navigation has a native keyboard-accessible action");

            [view setValue:@YES forKey:@"loading"];
            Assert(!backButton.enabled && !openButton.enabled && !restoreButton.enabled &&
                   [statusLabel.stringValue isEqualToString:T(@"de", @"restoreLoading")],
                   @"loading is explicit and disables conflicting restore actions");

            SEL verifiedSelector = NSSelectorFromString(@"showVerifiedDestinationURL:sha256:");
            if ([view respondsToSelector:verifiedSelector]) {
                typedef void (*VerifiedMethod)(id, SEL, NSURL *, NSString *);
                VerifiedMethod verified = (VerifiedMethod)[view methodForSelector:verifiedSelector];
                verified(view, verifiedSelector,
                         [NSURL fileURLWithPath:@"/tmp/Report restored.txt"],
                         @"abcdef0123456789");
            }
            Assert(!revealButton.hidden &&
                   [statusLabel.stringValue containsString:T(@"de", @"restoreVerified")] &&
                   [statusLabel.accessibilityLabel containsString:@"SHA-256"],
                   @"verified restore exposes its destination and integrity proof");
        }
    }

    if (failures > 0) {
        printf("%d restore UI test(s) failed.\n", failures);
        return 1;
    }
    printf("All restore UI tests passed.\n");
    return 0;
}
