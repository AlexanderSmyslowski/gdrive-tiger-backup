#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const GDTOnboardingVersion;
FOUNDATION_EXPORT NSString * const GDTOnboardingVersionKey;

FOUNDATION_EXPORT BOOL GDTOnboardingNeedsPresentation(
    NSDictionary<NSString *, NSString *> *config);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *GDTOnboardingCompletionUpdate(void);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *GDTOnboardingConfigurationUpdates(
    NSDictionary<NSString *, NSString *> *config,
    NSString *automaticTarget);

typedef NS_ENUM(NSInteger, GDTOnboardingStep) {
    GDTOnboardingStepDestination = 0,
    GDTOnboardingStepReadiness = 1,
    GDTOnboardingStepSchedule = 2
};

@interface TigerOnboardingView : NSView
@property(nonatomic, copy) NSString *language;
@property(nonatomic) GDTOnboardingStep step;
@property(nonatomic, copy) NSString *automaticDestination;
@property(nonatomic, copy) NSString *manualDestination;
@property(nonatomic, copy) NSString *readinessSummary;
@property(nonatomic, copy) NSString *scheduleSummary;
@property(nonatomic, copy) NSString *notificationSummary;
@property(nonatomic) BOOL manualDestinationVisible;
@property(nonatomic) BOOL canAdvance;
@property(nonatomic, copy, nullable) void (^backHandler)(void);
@property(nonatomic, copy, nullable) void (^advanceHandler)(void);
@property(nonatomic, copy, nullable) void (^advancedSetupHandler)(void);
@property(nonatomic, copy, nullable) void (^cancelHandler)(void);
@property(nonatomic, copy, nullable) void (^destinationHandler)(NSString *target);
@property(nonatomic, strong, readonly) NSArray<NSButton *> *destinationButtons;
@property(nonatomic, strong, readonly) NSButton *backButton;
@property(nonatomic, strong, readonly) NSButton *advanceButton;
@property(nonatomic, strong, readonly) NSButton *advancedSetupButton;
@property(nonatomic, strong, readonly) NSButton *cancelButton;
- (void)applyReadinessSnapshot:(NSDictionary<NSString *, id> *)snapshot;
@end

NS_ASSUME_NONNULL_END
