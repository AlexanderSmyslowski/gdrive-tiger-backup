#import <Cocoa/Cocoa.h>

#import "OnboardingSupport.h"
#import "Localization.h"
#import "TestApplicationSupport.h"

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
    } else {
        printf("not ok - %s\n", name.UTF8String);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        GDTInitializeAccessoryTestApplication();
        TigerOnboardingView *view =
            [[TigerOnboardingView alloc] initWithFrame:NSMakeRect(0, 0, 650, 620)];
        NSArray<NSTextField *> *steps = [view valueForKey:@"stepLabels"];
        Assert(steps.count == 3 &&
               steps[0].stringValue.length > 0 &&
               steps[1].stringValue.length > 0 &&
               steps[2].stringValue.length > 0,
               @"onboarding exposes three visible native step labels");
        Assert(view.destinationButtons.count == 2 &&
               [view.destinationButtons[0].accessibilityRole
                   isEqualToString:NSAccessibilityButtonRole] &&
               view.destinationButtons[0].accessibilityLabel.length > 0 &&
               view.advanceButton.accessibilityLabel.length > 0 &&
               view.advancedSetupButton.accessibilityLabel.length > 0,
               @"destination and escape actions have native accessibility semantics");

        view.language = @"de";
        view.automaticDestination = @"NAS / Netzwerk";
        view.manualDestination = @"Toshiba_4TB";
        view.manualDestinationVisible = YES;
        view.scheduleSummary = @"täglich 20:00";
        view.notificationSummary = @"aktiv";
        Assert([view valueForKey:@"automaticLabel"] &&
               [[[view valueForKey:@"automaticLabel"] stringValue]
                   containsString:@"Automatisch:"] &&
               [[[view valueForKey:@"manualLabel"] stringValue]
                   containsString:@"Manuell:"],
               @"German copy distinguishes automatic and manual destinations");

        view.step = GDTOnboardingStepReadiness;
        [view applyReadinessSnapshot:@{@"overall": @"failure"}];
        Assert(view.step == GDTOnboardingStepReadiness && !view.canAdvance &&
               [[view valueForKey:@"readinessLabel"] stringValue].length > 0,
               @"readiness failure keeps the continue action disabled");
        [view applyReadinessSnapshot:@{@"overall": @"ready"}];
        Assert(view.canAdvance && view.advanceButton.enabled,
               @"ready health snapshot enables the next step");

        NSArray<NSString *> *keys = @[
            @"onboardingTitle", @"onboardingDescription",
            @"onboardingStepDestination", @"onboardingStepReadiness",
            @"onboardingStepSchedule", @"onboardingAutomaticTarget",
            @"onboardingChooseAutomaticTarget", @"onboardingManualTarget",
            @"onboardingManualTargetNone", @"onboardingReadiness",
            @"onboardingSchedule", @"onboardingNotifications",
            @"onboardingBack", @"onboardingContinue", @"onboardingFinish",
            @"onboardingAdvanced"
        ];
        BOOL localized = YES;
        for (NSString *language in SupportedLanguageCodes()) {
            for (NSString *key in keys) {
                NSString *value = T(language, key);
                localized = localized && value.length > 0 && ![value isEqualToString:key];
            }
        }
        Assert(localized, @"onboarding copy exists in every supported language");
    }
    return failures == 0 ? 0 : 1;
}
