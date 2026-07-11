#import "DiagnosticsView.h"

#import "Localization.h"

@interface GDTDiagnosticsView ()
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *subtitleLabel;
@property(nonatomic, strong, readwrite) NSTextField *overallLabel;
@property(nonatomic, strong) NSTextField *overallSymbolLabel;
@property(nonatomic, strong) NSTextField *systemLabel;
@property(nonatomic, copy, readwrite) NSArray<NSTextField *> *rowTitleLabels;
@property(nonatomic, copy, readwrite) NSArray<NSTextField *> *rowDetailLabels;
@property(nonatomic, copy, readwrite) NSArray<NSTextField *> *rowSymbolLabels;
@property(nonatomic, strong, readwrite) NSButton *refreshButton;
@property(nonatomic, strong, readwrite) NSButton *copyButton;
@property(nonatomic, strong, readwrite) NSButton *saveButton;
@property(nonatomic, strong, readwrite) NSTextField *privacyLabel;
@end

@implementation GDTDiagnosticsView

- (BOOL)isFlipped {
    return YES;
}

- (NSTextField *)labelWithFrame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.accessibilityRole = NSAccessibilityStaticTextRole;
    return label;
}

- (NSButton *)buttonWithAction:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 120, 30)];
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = action;
    button.accessibilityRole = NSAccessibilityButtonRole;
    return button;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    NSColor *ink = [NSColor colorWithCalibratedWhite:0.13 alpha:1.0];
    NSColor *muted = [NSColor colorWithCalibratedWhite:0.36 alpha:1.0];
    NSFont *rowTitleFont = [NSFont boldSystemFontOfSize:11];
    NSFont *rowDetailFont = [NSFont systemFontOfSize:11];

    self.titleLabel = [self labelWithFrame:NSZeroRect font:[NSFont boldSystemFontOfSize:21] color:ink];
    self.subtitleLabel = [self labelWithFrame:NSZeroRect font:[NSFont systemFontOfSize:12] color:muted];
    self.overallSymbolLabel = [self labelWithFrame:NSZeroRect font:[NSFont boldSystemFontOfSize:24] color:ink];
    self.overallSymbolLabel.alignment = NSTextAlignmentCenter;
    self.overallLabel = [self labelWithFrame:NSZeroRect font:[NSFont boldSystemFontOfSize:15] color:ink];
    self.systemLabel = [self labelWithFrame:NSZeroRect font:[NSFont systemFontOfSize:10] color:muted];
    self.systemLabel.alignment = NSTextAlignmentRight;
    for (NSTextField *label in @[
        self.titleLabel, self.subtitleLabel, self.overallSymbolLabel, self.overallLabel, self.systemLabel
    ]) {
        [self addSubview:label];
    }

    NSMutableArray<NSTextField *> *titles = [NSMutableArray array];
    NSMutableArray<NSTextField *> *details = [NSMutableArray array];
    NSMutableArray<NSTextField *> *symbols = [NSMutableArray array];
    for (NSUInteger index = 0; index < 7; index++) {
        NSTextField *symbol = [self labelWithFrame:NSZeroRect font:rowTitleFont color:muted];
        symbol.alignment = NSTextAlignmentCenter;
        NSTextField *title = [self labelWithFrame:NSZeroRect font:rowTitleFont color:ink];
        NSTextField *detail = [self labelWithFrame:NSZeroRect font:rowDetailFont color:muted];
        detail.toolTip = @"";
        [self addSubview:symbol];
        [self addSubview:title];
        [self addSubview:detail];
        [symbols addObject:symbol];
        [titles addObject:title];
        [details addObject:detail];
    }
    self.rowSymbolLabels = symbols;
    self.rowTitleLabels = titles;
    self.rowDetailLabels = details;

    self.privacyLabel = [self labelWithFrame:NSZeroRect font:[NSFont systemFontOfSize:10] color:muted];
    [self addSubview:self.privacyLabel];
    self.refreshButton = [self buttonWithAction:@selector(refreshDiagnostics:)];
    self.copyButton = [self buttonWithAction:@selector(copyReport:)];
    self.saveButton = [self buttonWithAction:@selector(saveReport:)];
    for (NSButton *button in @[self.refreshButton, self.copyButton, self.saveButton]) {
        [self addSubview:button];
    }
    self.refreshButton.nextKeyView = self.copyButton;
    self.copyButton.nextKeyView = self.saveButton;
    self.saveButton.nextKeyView = self.refreshButton;
    self.snapshot = @{};
    self.report = @"";
    self.language = @"en";
    return self;
}

- (void)layout {
    [super layout];
    CGFloat width = NSWidth(self.bounds);
    CGFloat height = NSHeight(self.bounds);
    CGFloat margin = 24.0;
    self.titleLabel.frame = NSMakeRect(margin, 18.0, width - margin * 2.0, 28.0);
    self.subtitleLabel.frame = NSMakeRect(margin + 1.0, 50.0, width - margin * 2.0, 20.0);
    self.overallSymbolLabel.frame = NSMakeRect(margin, 82.0, 34.0, 34.0);
    self.overallLabel.frame = NSMakeRect(margin + 44.0, 86.0, width * 0.48, 24.0);
    self.systemLabel.frame = NSMakeRect(width * 0.50, 89.0, width * 0.50 - margin, 18.0);
    CGFloat rowStart = 126.0;
    CGFloat rowHeight = 39.0;
    for (NSUInteger index = 0; index < self.rowTitleLabels.count; index++) {
        CGFloat y = rowStart + index * rowHeight;
        self.rowSymbolLabels[index].frame = NSMakeRect(margin + 4.0, y + 8.0, 22.0, 18.0);
        self.rowTitleLabels[index].frame = NSMakeRect(margin + 42.0, y + 8.0, 170.0, 18.0);
        self.rowDetailLabels[index].frame = NSMakeRect(margin + 216.0, y + 8.0,
                                                      width - margin * 2.0 - 216.0, 18.0);
    }
    self.privacyLabel.frame = NSMakeRect(margin + 2.0, height - 70.0,
                                        width - margin * 2.0 - 4.0, 18.0);

    CGFloat refreshWidth = MAX(112.0, ceil(self.refreshButton.cell.cellSize.width + 18.0));
    CGFloat copyWidth = MAX(150.0, ceil(self.copyButton.cell.cellSize.width + 18.0));
    CGFloat saveWidth = MAX(150.0, ceil(self.saveButton.cell.cellSize.width + 18.0));
    CGFloat y = height - 39.0;
    self.refreshButton.frame = NSMakeRect(margin, y, refreshWidth, 30.0);
    self.saveButton.frame = NSMakeRect(width - margin - saveWidth, y, saveWidth, 30.0);
    self.copyButton.frame = NSMakeRect(NSMinX(self.saveButton.frame) - 8.0 - copyWidth,
                                      y, copyWidth, 30.0);
}

- (void)setLanguage:(NSString *)language {
    _language = [language copy] ?: @"en";
    self.titleLabel.stringValue = T(_language, @"diagnosticsTitle");
    self.subtitleLabel.stringValue = T(_language, @"diagnosticsSubtitle");
    NSArray<NSString *> *titleKeys = @[
        @"diagnosticsTools", @"diagnosticsRemote", @"diagnosticsDestination",
        @"diagnosticsSchedule", @"diagnosticsLastRun", @"diagnosticsController",
        @"diagnosticsScript"
    ];
    for (NSUInteger index = 0; index < titleKeys.count; index++) {
        self.rowTitleLabels[index].stringValue = T(_language, titleKeys[index]);
        self.rowTitleLabels[index].accessibilityLabel = self.rowTitleLabels[index].stringValue;
    }
    self.refreshButton.title = T(_language, @"diagnosticsRefresh");
    self.copyButton.title = T(_language, @"diagnosticsCopy");
    self.saveButton.title = T(_language, @"diagnosticsSave");
    self.privacyLabel.stringValue = T(_language, @"diagnosticsPrivacy");
    self.privacyLabel.accessibilityLabel = self.privacyLabel.stringValue;
    for (NSButton *button in @[self.refreshButton, self.copyButton, self.saveButton]) {
        button.accessibilityLabel = button.title;
    }
    self.titleLabel.accessibilityLabel = self.titleLabel.stringValue;
    self.subtitleLabel.accessibilityLabel = self.subtitleLabel.stringValue;
    [self applySnapshot:self.snapshot ?: @{}];
    [self setNeedsLayout:YES];
    [self layoutSubtreeIfNeeded];
}

- (NSString *)genericDetailForStatus:(NSString *)status {
    NSDictionary<NSString *, NSString *> *keys = @{
        @"ready": @"diagnosticsReady",
        @"failure": @"diagnosticsFailure",
        @"blocked": @"diagnosticsBlocked",
        @"unknown": @"diagnosticsUnknown"
    };
    return T(self.language ?: @"en", keys[status] ?: @"diagnosticsUnknown");
}

- (void)applyStatus:(NSString *)status detail:(NSString *)detail row:(NSUInteger)row {
    NSDictionary<NSString *, NSArray *> *presentation = @{
        @"ready": @[@"✓", [NSColor colorWithCalibratedRed:0.10 green:0.48 blue:0.18 alpha:1.0]],
        @"failure": @[@"×", [NSColor colorWithCalibratedRed:0.70 green:0.10 blue:0.08 alpha:1.0]],
        @"blocked": @[@"—", [NSColor colorWithCalibratedWhite:0.42 alpha:1.0]],
        @"unknown": @[@"?", [NSColor colorWithCalibratedWhite:0.42 alpha:1.0]]
    };
    NSArray *values = presentation[status] ?: presentation[@"unknown"];
    NSTextField *symbol = self.rowSymbolLabels[row];
    NSTextField *title = self.rowTitleLabels[row];
    NSTextField *detailLabel = self.rowDetailLabels[row];
    symbol.stringValue = values[0];
    symbol.textColor = values[1];
    symbol.accessibilityLabel = detail;
    detailLabel.stringValue = detail;
    detailLabel.toolTip = detail;
    detailLabel.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", title.stringValue, detail];
}

- (void)applySnapshot:(NSDictionary<NSString *, id> *)snapshot {
    _snapshot = [snapshot copy] ?: @{};
    if (self.loading) return;
    NSString *overall = [_snapshot[@"overall"] isEqualToString:@"ready"] ? @"ready" : @"attention";
    self.overallSymbolLabel.stringValue = [overall isEqualToString:@"ready"] ? @"✓" : @"!";
    self.overallLabel.stringValue = T(self.language ?: @"en",
        [overall isEqualToString:@"ready"] ? @"diagnosticsOverallReady" : @"diagnosticsOverallAttention");
    self.overallLabel.accessibilityLabel = self.overallLabel.stringValue;

    NSDictionary *app = [_snapshot[@"app"] isKindOfClass:NSDictionary.class] ? _snapshot[@"app"] : @{};
    NSDictionary *system = [_snapshot[@"system"] isKindOfClass:NSDictionary.class] ? _snapshot[@"system"] : @{};
    self.systemLabel.stringValue = [NSString stringWithFormat:@"v%@ (%@) · %@ · %@",
        app[@"version"] ?: @"?", app[@"build"] ?: @"?",
        system[@"osVersion"] ?: @"?", system[@"architecture"] ?: @"?"];
    self.systemLabel.accessibilityLabel = self.systemLabel.stringValue;

    NSDictionary *dependencies = [_snapshot[@"dependencies"] isKindOfClass:NSDictionary.class]
        ? _snapshot[@"dependencies"] : @{};
    NSString *dependenciesStatus = dependencies[@"status"] ?: @"unknown";
    NSString *dependenciesDetail = [self genericDetailForStatus:dependenciesStatus];
    NSArray *missing = [dependencies[@"missing"] isKindOfClass:NSArray.class] ? dependencies[@"missing"] : @[];
    if (missing.count) {
        dependenciesDetail = [NSString stringWithFormat:T(self.language ?: @"en", @"diagnosticsMissingTools"),
            [missing componentsJoinedByString:@", "]];
    }
    [self applyStatus:dependenciesStatus detail:dependenciesDetail row:0];

    NSDictionary *remote = [_snapshot[@"remote"] isKindOfClass:NSDictionary.class] ? _snapshot[@"remote"] : @{};
    NSString *remoteStatus = remote[@"status"] ?: @"unknown";
    [self applyStatus:remoteStatus detail:[self genericDetailForStatus:remoteStatus] row:1];

    NSDictionary *destination = [_snapshot[@"destination"] isKindOfClass:NSDictionary.class]
        ? _snapshot[@"destination"] : @{};
    NSString *destinationStatus = destination[@"status"] ?: @"unknown";
    NSString *target = [destination[@"kind"] isEqualToString:@"nas"]
        ? T(self.language ?: @"en", @"nas") : T(self.language ?: @"en", @"externalVolume");
    NSString *destinationDetail = [NSString stringWithFormat:@"%@ · %@", target,
        [self genericDetailForStatus:destinationStatus]];
    [self applyStatus:destinationStatus detail:destinationDetail row:2];

    NSDictionary *schedule = [_snapshot[@"schedule"] isKindOfClass:NSDictionary.class] ? _snapshot[@"schedule"] : @{};
    NSString *mode = schedule[@"mode"] ?: @"unknown";
    BOOL manual = [mode isEqualToString:@"manual"];
    BOOL scheduleLoaded = [schedule[@"loaded"] boolValue];
    NSString *scheduleStatus = (manual || scheduleLoaded) ? @"ready" : @"failure";
    NSDictionary<NSString *, NSString *> *scheduleKeys = @{
        @"manual": @"diagnosticsManual", @"login": @"scheduleLogin",
        @"hourly": @"scheduleHourly", @"daily": @"scheduleDaily"
    };
    NSString *scheduleDetail = T(self.language ?: @"en", scheduleKeys[mode] ?: @"diagnosticsUnknown");
    if (!manual && ![mode isEqualToString:@"unknown"]) {
        scheduleDetail = [NSString stringWithFormat:@"%@ · %@", scheduleDetail,
            T(self.language ?: @"en", scheduleLoaded ? @"diagnosticsLoaded" : @"diagnosticsNotLoaded")];
    }
    [self applyStatus:scheduleStatus detail:scheduleDetail row:3];

    NSDictionary *lastRun = [_snapshot[@"lastRun"] isKindOfClass:NSDictionary.class] ? _snapshot[@"lastRun"] : @{};
    NSString *lastStatus = lastRun[@"status"] ?: @"unknown";
    BOOL lastHealthy = [lastStatus isEqualToString:@"success"] || [lastStatus isEqualToString:@"running"];
    NSDictionary<NSString *, NSString *> *lastKeys = @{
        @"success": @"completed", @"failure": @"failed", @"cancelled": @"cancelled",
        @"running": @"running", @"interrupted": @"overviewStatusInterrupted",
        @"unknown": @"overviewStatusUnknown"
    };
    NSString *lastDetail = T(self.language ?: @"en", lastKeys[lastStatus] ?: @"overviewStatusUnknown");
    if ([lastRun[@"reason"] isEqualToString:@"nas_connection_lost"]) {
        lastDetail = [NSString stringWithFormat:@"%@ · %@", lastDetail,
            T(self.language ?: @"en", @"failedNASConnectionHint")];
    } else if ([lastRun[@"reason"] isEqualToString:@"destination_permission_denied"]) {
        lastDetail = [NSString stringWithFormat:@"%@ · %@", lastDetail,
            T(self.language ?: @"en", @"failedPermissionHint")];
    }
    [self applyStatus:lastHealthy ? @"ready" : @"failure" detail:lastDetail row:4];

    NSDictionary *controller = [_snapshot[@"controller"] isKindOfClass:NSDictionary.class]
        ? _snapshot[@"controller"] : @{};
    BOOL controllerLoaded = [controller[@"loaded"] boolValue];
    [self applyStatus:controllerLoaded ? @"ready" : @"failure"
                detail:T(self.language ?: @"en", controllerLoaded ? @"diagnosticsLoaded" : @"diagnosticsNotLoaded")
                   row:5];

    NSDictionary *script = [_snapshot[@"script"] isKindOfClass:NSDictionary.class] ? _snapshot[@"script"] : @{};
    BOOL scriptReady = [script[@"installed"] boolValue] && [script[@"executable"] boolValue];
    [self applyStatus:scriptReady ? @"ready" : @"failure"
                detail:[self genericDetailForStatus:scriptReady ? @"ready" : @"failure"] row:6];
    [self updateControlStates];
}

- (void)setReport:(NSString *)report {
    _report = [report copy] ?: @"";
    [self updateControlStates];
}

- (void)setLoading:(BOOL)loading {
    _loading = loading;
    if (loading) {
        self.overallSymbolLabel.stringValue = @"…";
        self.overallLabel.stringValue = T(self.language ?: @"en", @"diagnosticsRefreshing");
        self.overallLabel.accessibilityLabel = self.overallLabel.stringValue;
    } else {
        [self applySnapshot:self.snapshot ?: @{}];
    }
    [self updateControlStates];
}

- (void)updateControlStates {
    self.refreshButton.enabled = !self.loading;
    self.copyButton.enabled = !self.loading && self.report.length > 0;
    self.saveButton.enabled = !self.loading && self.report.length > 0;
}

- (void)refreshDiagnostics:(id)sender {
    (void)sender;
    if (self.loading || !self.refreshHandler) return;
    self.loading = YES;
    self.refreshHandler();
}

- (void)copyReport:(id)sender {
    (void)sender;
    if (!self.loading && self.report.length && self.copyHandler) self.copyHandler(self.report);
}

- (void)saveReport:(id)sender {
    (void)sender;
    if (!self.loading && self.report.length && self.saveHandler) self.saveHandler(self.report);
}

- (void)showFeedbackKey:(NSString *)key {
    self.overallLabel.stringValue = T(self.language ?: @"en", key);
    self.overallLabel.accessibilityLabel = self.overallLabel.stringValue;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSGradient *background = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedWhite:0.98 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.87 alpha:1.0]
    ]];
    [background drawInRect:self.bounds angle:-90];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.34] setFill];
    for (CGFloat y = 76.0; y < NSHeight(self.bounds); y += 5.0) {
        NSRectFill(NSMakeRect(0, y, NSWidth(self.bounds), 1.0));
    }
    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.18] setFill];
    for (NSUInteger index = 0; index < 8; index++) {
        CGFloat y = index == 0 ? 118.0 : 126.0 + index * 39.0;
        NSRectFill(NSMakeRect(24.0, y, NSWidth(self.bounds) - 48.0, 1.0));
    }
}

@end
