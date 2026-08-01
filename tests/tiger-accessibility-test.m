#import <Cocoa/Cocoa.h>

#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main

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
        TigerBackupView *view = [[TigerBackupView alloc] initWithFrame:NSMakeRect(0, 0, 392, 162)];
        view.language = @"en";
        view.primaryActionTitle = @"Start backup";
        view.secondaryActionTitle = @"Not now";
        view.confirmTitle = @"Use this volume?";
        view.confirmDetail = @"External Backup";
        view.confirmMode = YES;

        NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
        for (NSView *subview in view.subviews) {
            if ([subview isKindOfClass:NSButton.class]) {
                [buttons addObject:(NSButton *)subview];
            }
        }
        NSArray<NSButton *> *visibleConfirmationButtons = [buttons filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(NSButton *button, NSDictionary *bindings) {
                (void)bindings;
                return !button.hidden;
            }]];
        Assert(visibleConfirmationButtons.count == 2, @"confirmation exposes two native buttons");

        NSButton *primary = nil;
        NSButton *secondary = nil;
        for (NSButton *button in visibleConfirmationButtons) {
            if ([button.keyEquivalent isEqualToString:@"\r"]) {
                primary = button;
            } else if ([button.keyEquivalent isEqualToString:@"\e"]) {
                secondary = button;
            }
        }
        Assert(primary != nil, @"Return activates the primary confirmation action");
        Assert(secondary != nil, @"Escape activates the secondary confirmation action");
        Assert([primary.accessibilityRole isEqualToString:NSAccessibilityButtonRole] &&
               [secondary.accessibilityRole isEqualToString:NSAccessibilityButtonRole],
               @"VoiceOver receives native button roles");

        __block NSInteger approvals = 0;
        __block NSInteger rejections = 0;
        view.confirmHandler = ^(BOOL approved) {
            if (approved) {
                approvals++;
            } else {
                rejections++;
            }
        };
        [primary performClick:nil];
        [secondary performClick:nil];
        Assert(approvals == 1 && rejections == 1,
               @"native confirmation actions fire exactly once");

        NSMutableArray<NSTextField *> *labels = [NSMutableArray array];
        for (NSView *subview in view.subviews) {
            if ([subview isKindOfClass:NSTextField.class]) {
                [labels addObject:(NSTextField *)subview];
            }
        }
        NSSet<NSString *> *labelTexts = [NSSet setWithArray:[labels valueForKey:@"stringValue"]];
        Assert(labels.count >= 3 &&
               [labelTexts containsObject:@"Google Drive Backup"] &&
               [labelTexts containsObject:@"Use this volume?"] &&
               [labelTexts containsObject:@"External Backup"],
               @"VoiceOver receives title, status, and detail as native text");
        BOOL allStaticText = YES;
        for (NSTextField *label in labels) {
            allStaticText = allStaticText && !label.editable && !label.selectable &&
                [label.accessibilityRole isEqualToString:NSAccessibilityStaticTextRole];
        }
        Assert(allStaticText, @"status labels expose static text roles");

        NSString *longTarget = @"/Volumes/Archive/GoogleDrive-Backup/Current";
        view.confirmDetail = longTarget;
        Assert(view.detailLabel.lineBreakMode == NSLineBreakByTruncatingMiddle,
               @"long backup targets preserve their beginning and destination name");
        Assert([view.detailLabel.toolTip isEqualToString:longTarget] &&
               [view.detailLabel.accessibilityLabel isEqualToString:longTarget],
               @"the full backup target remains available to pointer and VoiceOver users");

        view.confirmMode = NO;
        view.progressPercent = 44;
        NSMutableArray<NSProgressIndicator *> *progressIndicators = [NSMutableArray array];
        for (NSView *subview in view.subviews) {
            if ([subview isKindOfClass:NSProgressIndicator.class]) {
                [progressIndicators addObject:(NSProgressIndicator *)subview];
            }
        }
        NSProgressIndicator *progress = progressIndicators.firstObject;
        Assert(progressIndicators.count == 1 && !progress.hidden,
               @"running backup exposes one native progress indicator");
        Assert(progress.minValue == 0 && progress.maxValue == 100 && progress.doubleValue == 44,
               @"native progress exposes the current percentage");
        Assert([progress.accessibilityRole isEqualToString:NSAccessibilityProgressIndicatorRole] &&
               progress.accessibilityLabel.length > 0,
               @"VoiceOver receives progress role, label, and value");
        NSButton *cancelBackup = nil;
        for (NSView *subview in view.subviews) {
            if ([subview isKindOfClass:NSButton.class]) {
                NSButton *button = (NSButton *)subview;
                if (!button.hidden && [button.title isEqualToString:T(@"en", @"cancelBackup")]) {
                    cancelBackup = button;
                }
            }
        }
        Assert(primary.hidden && secondary.hidden && cancelBackup != nil &&
               [cancelBackup.keyEquivalent isEqualToString:@"\e"] &&
               [cancelBackup.accessibilityRole isEqualToString:NSAccessibilityButtonRole],
               @"running backup exposes one native keyboard-accessible cancel action");

        BOOL cancelWorkflowLocalized = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            for (NSString *key in @[@"cancelBackup", @"cancelBackupConfirm",
                                    @"cancelBackupDetail", @"cancelBackupAction",
                                    @"cancellingBackup"]) {
                NSString *localized = T(language, key);
                cancelWorkflowLocalized = cancelWorkflowLocalized && localized.length > 0 &&
                    ![localized isEqualToString:key];
            }
        }
        Assert(cancelWorkflowLocalized,
               @"cancel workflow is localized in every supported language");

        BOOL progressLabelLocalized = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            view.language = language;
            NSString *expected = T(language, @"backupProgress");
            progressLabelLocalized = progressLabelLocalized &&
                ![expected isEqualToString:@"backupProgress"] &&
                [progress.accessibilityLabel isEqualToString:expected];
        }
        Assert(progressLabelLocalized,
               @"progress accessibility label follows all supported languages");

        SEL reduceMotionSelector = NSSelectorFromString(@"setReduceMotion:");
        if ([view respondsToSelector:reduceMotionSelector]) {
            typedef void (*SetReduceMotionMethod)(id, SEL, BOOL);
            SetReduceMotionMethod method = (SetReduceMotionMethod)[view methodForSelector:reduceMotionSelector];
            method(view, reduceMotionSelector, YES);
        }
        Assert(view.timer == nil,
               @"Reduce Motion stops the continuous animation timer");
        if ([view respondsToSelector:reduceMotionSelector]) {
            typedef void (*SetReduceMotionMethod)(id, SEL, BOOL);
            SetReduceMotionMethod method = (SetReduceMotionMethod)[view methodForSelector:reduceMotionSelector];
            method(view, reduceMotionSelector, NO);
        }
        Assert(view.timer != nil,
               @"animation can resume when Reduce Motion is disabled");

        AppDelegate *delegate = [[AppDelegate alloc] init];
        delegate.language = @"en";
        TigerOverviewView *overviewView = [[TigerOverviewView alloc]
            initWithFrame:NSMakeRect(0, 0, 620, 420)];
        [delegate applyOverviewSnapshot:@{
            @"status": @"running", @"retryRunning": @"1",
            @"progressVisible": @"1",
            @"progressLabel": T(@"en", @"automaticRetryRunning"),
            @"progressPhase": @"Area 3 of 5", @"progressPercent": @"63",
            @"progressDetail": @"1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s"
        } toView:overviewView];
        Assert(overviewView.progressIndicator != nil &&
               !overviewView.progressIndicator.hidden &&
               !overviewView.progressIndicator.indeterminate &&
               overviewView.progressIndicator.doubleValue == 63 &&
               [overviewView.progressPercentLabel.stringValue isEqualToString:@"63 %"] &&
               [overviewView.progressDetailLabel.stringValue isEqualToString:
                   @"1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s"] &&
               overviewView.progressDetailLabel.frame.size.width >= 400 &&
               !overviewView.backupButton.enabled,
               @"retry overview exposes visible percent and full aggregate detail");
        Assert([overviewView.progressIndicator.accessibilityRole
                   isEqualToString:NSAccessibilityProgressIndicatorRole] &&
               [overviewView.progressIndicator.accessibilityLabel
                   isEqualToString:T(@"en", @"backupProgressCurrentPhase")],
               @"retry progress is announced as current-phase progress");

        [delegate applyOverviewSnapshot:@{
            @"status": @"running", @"retryRunning": @"1",
            @"progressVisible": @"1",
            @"progressLabel": T(@"en", @"automaticRetryRunning"),
            @"progressPhase": @"", @"progressPercent": @"",
            @"progressDetail": T(@"en", @"progressPreparing")
        } toView:overviewView];
        Assert(!overviewView.progressIndicator.hidden &&
               overviewView.progressIndicator.indeterminate &&
               [overviewView.progressPercentLabel.stringValue isEqualToString:@""] &&
               [overviewView.progressDetailLabel.stringValue isEqualToString:
                   T(@"en", @"progressPreparing")],
               @"retry preparation uses an indeterminate native progress indicator");

        SEL delegateReduceSelector = NSSelectorFromString(@"setReduceMotion:");
        SEL durationSelector = NSSelectorFromString(@"animationDuration:");
        CGFloat reducedDuration = -1;
        CGFloat regularDuration = -1;
        if ([delegate respondsToSelector:delegateReduceSelector] &&
            [delegate respondsToSelector:durationSelector]) {
            typedef void (*SetDelegateReduceMethod)(id, SEL, BOOL);
            typedef CGFloat (*AnimationDurationMethod)(id, SEL, CGFloat);
            SetDelegateReduceMethod setReduce = (SetDelegateReduceMethod)[delegate methodForSelector:delegateReduceSelector];
            AnimationDurationMethod duration = (AnimationDurationMethod)[delegate methodForSelector:durationSelector];
            setReduce(delegate, delegateReduceSelector, YES);
            reducedDuration = duration(delegate, durationSelector, 0.22);
            setReduce(delegate, delegateReduceSelector, NO);
            regularDuration = duration(delegate, durationSelector, 0.22);
        }
        Assert(reducedDuration == 0,
               @"Reduce Motion removes window fade durations");
        Assert(fabs(regularDuration - 0.22) < 0.0001,
               @"regular window fade duration remains unchanged");

        SEL styleSelector = NSSelectorFromString(@"statusWindowStyleMask");
        NSWindowStyleMask styleMask = 0;
        if ([delegate respondsToSelector:styleSelector]) {
            typedef NSWindowStyleMask (*WindowStyleMethod)(id, SEL);
            WindowStyleMethod method = (WindowStyleMethod)[delegate methodForSelector:styleSelector];
            styleMask = method(delegate, styleSelector);
        }
        NSWindowStyleMask requiredStyle = NSWindowStyleMaskTitled |
            NSWindowStyleMaskClosable |
            NSWindowStyleMaskMiniaturizable |
            NSWindowStyleMaskFullSizeContentView;
        Assert((styleMask & requiredStyle) == requiredStyle &&
               (styleMask & NSWindowStyleMaskBorderless) == 0,
               @"status window uses native macOS window controls");

        SEL voiceOverSelector = NSSelectorFromString(@"setVoiceOverEnabled:");
        SEL confirmationTimeoutSelector = NSSelectorFromString(@"confirmationTimeout");
        SEL terminalDurationSelector = NSSelectorFromString(@"terminalDisplayDuration");
        NSTimeInterval voiceOverConfirmation = -1;
        NSTimeInterval voiceOverTerminal = -1;
        NSTimeInterval regularConfirmation = -1;
        NSTimeInterval regularTerminal = -1;
        if ([delegate respondsToSelector:voiceOverSelector] &&
            [delegate respondsToSelector:confirmationTimeoutSelector] &&
            [delegate respondsToSelector:terminalDurationSelector]) {
            typedef void (*SetVoiceOverMethod)(id, SEL, BOOL);
            typedef NSTimeInterval (*DurationMethod)(id, SEL);
            SetVoiceOverMethod setVoiceOver = (SetVoiceOverMethod)[delegate methodForSelector:voiceOverSelector];
            DurationMethod confirmationTimeout = (DurationMethod)[delegate methodForSelector:confirmationTimeoutSelector];
            DurationMethod terminalDuration = (DurationMethod)[delegate methodForSelector:terminalDurationSelector];
            setVoiceOver(delegate, voiceOverSelector, YES);
            voiceOverConfirmation = confirmationTimeout(delegate, confirmationTimeoutSelector);
            voiceOverTerminal = terminalDuration(delegate, terminalDurationSelector);
            setVoiceOver(delegate, voiceOverSelector, NO);
            regularConfirmation = confirmationTimeout(delegate, confirmationTimeoutSelector);
            regularTerminal = terminalDuration(delegate, terminalDurationSelector);
        }
        Assert(voiceOverConfirmation == 0 && voiceOverTerminal == 0,
               @"VoiceOver users do not lose prompts or outcomes to timeouts");
        Assert(regularConfirmation == 120 && regularTerminal == 8,
               @"default confirmation and outcome durations remain bounded");

        delegate.language = @"en";
        SEL announcementSelector = NSSelectorFromString(@"terminalAnnouncementForStatus:");
        BOOL announcementsAreDistinct = [delegate respondsToSelector:announcementSelector];
        NSMutableSet<NSString *> *announcements = [NSMutableSet set];
        if (announcementsAreDistinct) {
            typedef NSString *(*AnnouncementMethod)(id, SEL, NSString *);
            AnnouncementMethod method = (AnnouncementMethod)[delegate methodForSelector:announcementSelector];
            for (NSString *status in @[@"success", @"failure", @"cancelled", @"skipped"]) {
                NSString *announcement = method(delegate, announcementSelector, status);
                announcementsAreDistinct = announcementsAreDistinct && announcement.length > 0;
                if (announcement) {
                    [announcements addObject:announcement];
                }
            }
        }
        Assert(announcementsAreDistinct && announcements.count == 4,
               @"VoiceOver receives a distinct terminal outcome announcement");
    }

    if (failures > 0) {
        printf("%d Tiger accessibility test(s) failed.\n", failures);
        return 1;
    }
    printf("All Tiger accessibility tests passed.\n");
    return 0;
}
