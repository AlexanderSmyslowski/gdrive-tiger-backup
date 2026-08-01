#import "OnboardingSupport.h"

#import "Localization.h"

NSString * const GDTOnboardingVersion = @"1";
NSString * const GDTOnboardingVersionKey = @"GDRIVE_BACKUP_ONBOARDING_VERSION";

BOOL GDTOnboardingNeedsPresentation(NSDictionary<NSString *, NSString *> *config) {
    NSString *version = config[GDTOnboardingVersionKey] ?: @"";
    return ![version isEqualToString:GDTOnboardingVersion];
}

NSDictionary<NSString *, NSString *> *GDTOnboardingCompletionUpdate(void) {
    return @{GDTOnboardingVersionKey: GDTOnboardingVersion};
}

NSDictionary<NSString *, NSString *> *GDTOnboardingConfigurationUpdates(
    NSDictionary<NSString *, NSString *> *config,
    NSString *automaticTarget) {
    NSMutableDictionary<NSString *, NSString *> *updates =
        [config mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *target = [automaticTarget.lowercaseString isEqualToString:@"nas"]
        ? @"nas" : @"apfs";
    updates[@"GDRIVE_BACKUP_TARGET"] = target;
    updates[@"GDRIVE_BACKUP_SCHEDULE"] = @"daily";
    updates[@"GDRIVE_BACKUP_NOTIFY_FAILURES"] = @"1";
    return updates;
}

@interface TigerOnboardingView ()
@property(nonatomic, strong, readwrite) NSArray<NSButton *> *destinationButtons;
@property(nonatomic, strong, readwrite) NSButton *backButton;
@property(nonatomic, strong, readwrite) NSButton *advanceButton;
@property(nonatomic, strong, readwrite) NSButton *advancedSetupButton;
@property(nonatomic, strong, readwrite) NSButton *cancelButton;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *descriptionLabel;
@property(nonatomic, strong) NSTextField *automaticLabel;
@property(nonatomic, strong) NSTextField *manualLabel;
@property(nonatomic, strong) NSTextField *readinessLabel;
@property(nonatomic, strong) NSTextField *scheduleLabel;
@property(nonatomic, strong) NSTextField *notificationLabel;
@property(nonatomic, strong) NSArray<NSTextField *> *stepLabels;
@end

@implementation TigerOnboardingView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    _language = @"en";
    _step = GDTOnboardingStepDestination;
    _automaticDestination = @"";
    _manualDestination = @"";
    _readinessSummary = @"";
    _scheduleSummary = @"";
    _notificationSummary = @"";
    _manualDestinationVisible = NO;
    _canAdvance = NO;
    [self buildControls];
    [self refreshText];
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (NSTextField *)labelWithFrame:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = YES;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 0;
    label.accessibilityRole = NSAccessibilityStaticTextRole;
    return label;
}

- (NSButton *)buttonWithFrame:(NSRect)frame {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.bezelStyle = NSBezelStyleRounded;
    button.accessibilityRole = NSAccessibilityButtonRole;
    return button;
}

- (void)buildControls {
    self.titleLabel = [self labelWithFrame:NSMakeRect(30, 24, 590, 34)];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:22];
    [self addSubview:self.titleLabel];

    self.descriptionLabel = [self labelWithFrame:NSMakeRect(30, 68, 590, 56)];
    self.descriptionLabel.font = [NSFont systemFontOfSize:14];
    [self addSubview:self.descriptionLabel];

    NSMutableArray<NSTextField *> *steps = [NSMutableArray array];
    NSArray<NSValue *> *stepFrames = @[
        [NSValue valueWithRect:NSMakeRect(30, 140, 180, 26)],
        [NSValue valueWithRect:NSMakeRect(230, 140, 180, 26)],
        [NSValue valueWithRect:NSMakeRect(430, 140, 180, 26)]
    ];
    for (NSValue *value in stepFrames) {
        NSTextField *label = [self labelWithFrame:value.rectValue];
        label.alignment = NSTextAlignmentCenter;
        label.font = [NSFont boldSystemFontOfSize:12];
        [self addSubview:label];
        [steps addObject:label];
    }
    self.stepLabels = steps;

    self.automaticLabel = [self labelWithFrame:NSMakeRect(48, 236, 554, 40)];
    self.automaticLabel.font = [NSFont systemFontOfSize:16];
    [self addSubview:self.automaticLabel];
    self.manualLabel = [self labelWithFrame:NSMakeRect(48, 282, 554, 40)];
    self.manualLabel.font = [NSFont systemFontOfSize:16];
    [self addSubview:self.manualLabel];
    self.readinessLabel = [self labelWithFrame:NSMakeRect(48, 314, 554, 90)];
    [self addSubview:self.readinessLabel];
    self.scheduleLabel = [self labelWithFrame:NSMakeRect(48, 414, 554, 46)];
    [self addSubview:self.scheduleLabel];
    self.notificationLabel = [self labelWithFrame:NSMakeRect(48, 468, 554, 46)];
    [self addSubview:self.notificationLabel];

    NSButton *nasButton = [self buttonWithFrame:NSMakeRect(48, 194, 160, 30)];
    NSButton *externalButton = [self buttonWithFrame:NSMakeRect(222, 194, 160, 30)];
    nasButton.accessibilityIdentifier = @"onboarding-automatic-nas";
    externalButton.accessibilityIdentifier = @"onboarding-automatic-external";
    nasButton.target = self;
    nasButton.action = @selector(nasDestinationPressed:);
    externalButton.target = self;
    externalButton.action = @selector(externalDestinationPressed:);
    self.destinationButtons = @[nasButton, externalButton];
    [self addSubview:nasButton];
    [self addSubview:externalButton];

    self.backButton = [self buttonWithFrame:NSMakeRect(30, 548, 112, 32)];
    self.advanceButton = [self buttonWithFrame:NSMakeRect(454, 548, 166, 32)];
    self.advancedSetupButton = [self buttonWithFrame:NSMakeRect(170, 548, 160, 32)];
    self.cancelButton = [self buttonWithFrame:NSMakeRect(342, 548, 100, 32)];
    self.backButton.target = self;
    self.backButton.action = @selector(backPressed:);
    self.advanceButton.target = self;
    self.advanceButton.action = @selector(advancePressed:);
    self.advancedSetupButton.target = self;
    self.advancedSetupButton.action = @selector(advancedPressed:);
    self.cancelButton.target = self;
    self.cancelButton.action = @selector(cancelPressed:);
    [self addSubview:self.backButton];
    [self addSubview:self.advancedSetupButton];
    [self addSubview:self.cancelButton];
    [self addSubview:self.advanceButton];
}

- (void)setLanguage:(NSString *)language {
    _language = [language copy] ?: @"en";
    [self refreshText];
}

- (void)setStep:(GDTOnboardingStep)step {
    _step = step;
    [self refreshText];
}

- (void)setAutomaticDestination:(NSString *)automaticDestination {
    _automaticDestination = [automaticDestination copy] ?: @"";
    [self refreshText];
}

- (void)setManualDestination:(NSString *)manualDestination {
    _manualDestination = [manualDestination copy] ?: @"";
    [self refreshText];
}

- (void)setReadinessSummary:(NSString *)readinessSummary {
    _readinessSummary = [readinessSummary copy] ?: @"";
    [self refreshText];
}

- (void)setScheduleSummary:(NSString *)scheduleSummary {
    _scheduleSummary = [scheduleSummary copy] ?: @"";
    [self refreshText];
}

- (void)setNotificationSummary:(NSString *)notificationSummary {
    _notificationSummary = [notificationSummary copy] ?: @"";
    [self refreshText];
}

- (void)setManualDestinationVisible:(BOOL)manualDestinationVisible {
    _manualDestinationVisible = manualDestinationVisible;
    [self refreshText];
}

- (void)setCanAdvance:(BOOL)canAdvance {
    _canAdvance = canAdvance;
    self.advanceButton.enabled = canAdvance;
}

- (void)refreshText {
    if (!self.titleLabel) return;
    NSString *language = self.language ?: @"en";
    self.titleLabel.stringValue = T(language, @"onboardingTitle");
    self.descriptionLabel.stringValue = T(language, @"onboardingDescription");
    self.stepLabels[0].stringValue = T(language, @"onboardingStepDestination");
    self.stepLabels[1].stringValue = T(language, @"onboardingStepReadiness");
    self.stepLabels[2].stringValue = T(language, @"onboardingStepSchedule");
    self.automaticLabel.stringValue = self.automaticDestination.length
        ? [NSString stringWithFormat:@"%@ %@", T(language, @"onboardingAutomaticTarget"), self.automaticDestination]
        : T(language, @"onboardingChooseAutomaticTarget");
    self.manualLabel.stringValue = self.manualDestinationVisible && self.manualDestination.length
        ? [NSString stringWithFormat:@"%@ %@", T(language, @"onboardingManualTarget"), self.manualDestination]
        : T(language, @"onboardingManualTargetNone");
    self.readinessLabel.stringValue = [NSString stringWithFormat:@"%@ %@",
        T(language, @"onboardingReadiness"), self.readinessSummary ?: @""];
    self.scheduleLabel.stringValue = [NSString stringWithFormat:@"%@ %@",
        T(language, @"onboardingSchedule"), self.scheduleSummary ?: @""];
    self.notificationLabel.stringValue = [NSString stringWithFormat:@"%@ %@",
        T(language, @"onboardingNotifications"), self.notificationSummary ?: @""];
    self.destinationButtons[0].title = T(language, @"nas");
    self.destinationButtons[1].title = T(language, @"externalVolume");
    self.backButton.title = T(language, @"onboardingBack");
    self.advanceButton.title = self.step == GDTOnboardingStepSchedule
        ? T(language, @"onboardingFinish") : T(language, @"onboardingContinue");
    self.advancedSetupButton.title = T(language, @"onboardingAdvanced");
    self.cancelButton.title = T(language, @"cancel");
    self.backButton.enabled = self.step != GDTOnboardingStepDestination;
    self.advanceButton.enabled = self.canAdvance;
    self.automaticLabel.hidden = self.step != GDTOnboardingStepDestination;
    self.manualLabel.hidden = self.step != GDTOnboardingStepDestination;
    self.destinationButtons[0].hidden = self.step != GDTOnboardingStepDestination;
    self.destinationButtons[1].hidden = self.step != GDTOnboardingStepDestination;
    self.readinessLabel.hidden = self.step != GDTOnboardingStepReadiness;
    self.scheduleLabel.hidden = self.step != GDTOnboardingStepSchedule;
    self.notificationLabel.hidden = self.step != GDTOnboardingStepSchedule;
}

- (void)applyReadinessSnapshot:(NSDictionary<NSString *, id> *)snapshot {
    NSString *overall = snapshot[@"overall"] ?: @"unknown";
    NSString *key = [overall isEqualToString:@"ready"]
        ? @"setupCheckReady" : @"setupCheckNeedsAttention";
    self.readinessSummary = [NSString stringWithFormat:@"%@ (%@)", T(self.language, key), overall];
    self.canAdvance = [overall isEqualToString:@"ready"];
}

- (void)backPressed:(id)sender {
    (void)sender;
    if (self.backHandler) self.backHandler();
}

- (void)advancePressed:(id)sender {
    (void)sender;
    if (self.canAdvance && self.advanceHandler) self.advanceHandler();
}

- (void)advancedPressed:(id)sender {
    (void)sender;
    if (self.advancedSetupHandler) self.advancedSetupHandler();
}

- (void)cancelPressed:(id)sender {
    (void)sender;
    if (self.cancelHandler) self.cancelHandler();
}

- (void)nasDestinationPressed:(id)sender {
    (void)sender;
    if (self.destinationHandler) self.destinationHandler(@"nas");
}

- (void)externalDestinationPressed:(id)sender {
    (void)sender;
    if (self.destinationHandler) self.destinationHandler(@"apfs");
}

@end
