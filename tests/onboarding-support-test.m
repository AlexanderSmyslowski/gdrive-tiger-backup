#import <Foundation/Foundation.h>

#import "OnboardingSupport.h"

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
        NSDictionary *missing = @{
            @"GDRIVE_BACKUP_TARGET": @"nas"
        };
        Assert(GDTOnboardingNeedsPresentation(missing),
               @"missing onboarding version requires the first-run flow");

        NSDictionary *complete = @{
            @"GDRIVE_BACKUP_ONBOARDING_VERSION": GDTOnboardingVersion
        };
        Assert(!GDTOnboardingNeedsPresentation(complete),
               @"supported onboarding version suppresses the first-run flow");

        Assert(GDTOnboardingNeedsPresentation(@{
            @"GDRIVE_BACKUP_ONBOARDING_VERSION": @"2"
        }), @"unknown future onboarding versions are not treated as complete");
        Assert(GDTOnboardingNeedsPresentation(@{
            @"GDRIVE_BACKUP_ONBOARDING_VERSION": @"not-a-version"
        }), @"malformed onboarding versions are not treated as complete");

        NSDictionary *unchanged = [missing copy];
        NSDictionary *completion = GDTOnboardingCompletionUpdate();
        Assert([unchanged isEqualToDictionary:missing] &&
               [completion[GDTOnboardingVersionKey] isEqualToString:GDTOnboardingVersion],
               @"completion helper returns an update without mutating its input");
    }
    return failures == 0 ? 0 : 1;
}
