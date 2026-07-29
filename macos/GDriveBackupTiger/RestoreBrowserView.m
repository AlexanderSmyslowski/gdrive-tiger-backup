#import "RestoreBrowserView.h"

#import "Localization.h"

@interface GDTRestoreBrowserView ()
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *subtitleLabel;
@property(nonatomic, strong) NSTextField *pathLabel;
@property(nonatomic, strong) NSTextField *itemsHeadingLabel;
@property(nonatomic, strong) NSTextField *versionsHeadingLabel;
@property(nonatomic, strong, readwrite) NSTableView *itemsTable;
@property(nonatomic, strong, readwrite) NSTableView *versionsTable;
@property(nonatomic, strong) NSScrollView *itemsScrollView;
@property(nonatomic, strong) NSScrollView *versionsScrollView;
@property(nonatomic, strong, readwrite) NSButton *backButton;
@property(nonatomic, strong, readwrite) NSButton *openButton;
@property(nonatomic, strong, readwrite) NSButton *restoreButton;
@property(nonatomic, strong, readwrite) NSButton *revealButton;
@property(nonatomic, strong, readwrite) NSTextField *statusLabel;
@property(nonatomic, strong) NSURL *verifiedDestinationURL;
@end

@implementation GDTRestoreBrowserView

- (BOOL)isFlipped {
    return YES;
}

- (NSTextField *)labelWithFrame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = YES;
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
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

- (NSScrollView *)scrollViewForTable:(NSTableView *)table {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSBezelBorder;
    scrollView.documentView = table;
    return scrollView;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) {
        return nil;
    }
    self.wantsLayer = YES;
    NSColor *ink = [NSColor colorWithCalibratedWhite:0.13 alpha:1.0];
    NSColor *muted = [NSColor colorWithCalibratedWhite:0.36 alpha:1.0];
    self.titleLabel = [self labelWithFrame:NSZeroRect
                                      font:[NSFont boldSystemFontOfSize:21] color:ink];
    self.titleLabel.selectable = NO;
    [self addSubview:self.titleLabel];
    self.subtitleLabel = [self labelWithFrame:NSZeroRect
                                         font:[NSFont systemFontOfSize:12] color:muted];
    self.subtitleLabel.selectable = NO;
    [self addSubview:self.subtitleLabel];
    self.pathLabel = [self labelWithFrame:NSZeroRect
                                     font:[NSFont boldSystemFontOfSize:12] color:ink];
    [self addSubview:self.pathLabel];
    self.itemsHeadingLabel = [self labelWithFrame:NSZeroRect
                                             font:[NSFont boldSystemFontOfSize:11] color:muted];
    self.itemsHeadingLabel.selectable = NO;
    [self addSubview:self.itemsHeadingLabel];
    self.versionsHeadingLabel = [self labelWithFrame:NSZeroRect
                                                font:[NSFont boldSystemFontOfSize:11] color:muted];
    self.versionsHeadingLabel.selectable = NO;
    [self addSubview:self.versionsHeadingLabel];

    self.itemsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.itemsTable.headerView = [[NSTableHeaderView alloc] initWithFrame:NSZeroRect];
    self.itemsTable.rowHeight = 24;
    self.itemsTable.usesAlternatingRowBackgroundColors = YES;
    self.itemsTable.allowsMultipleSelection = NO;
    self.itemsTable.delegate = self;
    self.itemsTable.dataSource = self;
    self.itemsTable.accessibilityRole = NSAccessibilityTableRole;
    NSTableColumn *filesColumn = [[NSTableColumn alloc] initWithIdentifier:@"files"];
    filesColumn.resizingMask = NSTableColumnAutoresizingMask;
    [self.itemsTable addTableColumn:filesColumn];
    self.itemsTable.doubleAction = @selector(openSelectedFolder:);
    self.itemsTable.target = self;
    self.itemsScrollView = [self scrollViewForTable:self.itemsTable];
    [self addSubview:self.itemsScrollView];

    self.versionsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.versionsTable.headerView = [[NSTableHeaderView alloc] initWithFrame:NSZeroRect];
    self.versionsTable.rowHeight = 24;
    self.versionsTable.usesAlternatingRowBackgroundColors = YES;
    self.versionsTable.allowsMultipleSelection = NO;
    self.versionsTable.delegate = self;
    self.versionsTable.dataSource = self;
    self.versionsTable.accessibilityRole = NSAccessibilityTableRole;
    NSTableColumn *versionColumn = [[NSTableColumn alloc] initWithIdentifier:@"version"];
    versionColumn.width = 220;
    versionColumn.minWidth = 180;
    versionColumn.resizingMask = NSTableColumnAutoresizingMask;
    NSTableColumn *sizeColumn = [[NSTableColumn alloc] initWithIdentifier:@"size"];
    sizeColumn.width = 90;
    sizeColumn.minWidth = 70;
    [self.versionsTable addTableColumn:versionColumn];
    [self.versionsTable addTableColumn:sizeColumn];
    self.versionsScrollView = [self scrollViewForTable:self.versionsTable];
    [self addSubview:self.versionsScrollView];

    self.statusLabel = [self labelWithFrame:NSZeroRect
                                       font:[NSFont systemFontOfSize:11] color:muted];
    [self addSubview:self.statusLabel];
    self.backButton = [self buttonWithAction:@selector(goBack:)];
    self.openButton = [self buttonWithAction:@selector(openSelectedFolder:)];
    self.restoreButton = [self buttonWithAction:@selector(restoreSelectedVersion:)];
    self.restoreButton.keyEquivalent = @"\r";
    self.revealButton = [self buttonWithAction:@selector(revealRestoredFile:)];
    self.revealButton.hidden = YES;
    for (NSButton *button in @[self.backButton, self.openButton, self.revealButton, self.restoreButton]) {
        [self addSubview:button];
    }
    self.backButton.nextKeyView = self.itemsTable;
    self.itemsTable.nextKeyView = self.openButton;
    self.openButton.nextKeyView = self.versionsTable;
    self.versionsTable.nextKeyView = self.restoreButton;
    self.restoreButton.nextKeyView = self.backButton;

    self.entries = @[];
    self.versions = @[];
    self.currentRelativePath = @"";
    self.language = @"en";
    return self;
}

- (void)layout {
    [super layout];
    CGFloat width = NSWidth(self.bounds);
    CGFloat height = NSHeight(self.bounds);
    CGFloat margin = 20.0;
    CGFloat gap = 12.0;
    CGFloat tablesTop = 142.0;
    CGFloat footerHeight = 82.0;
    CGFloat tablesHeight = MAX(180.0, height - tablesTop - footerHeight);
    CGFloat availableWidth = width - margin * 2.0 - gap;
    CGFloat itemsWidth = floor(availableWidth * 0.56);
    CGFloat versionsWidth = availableWidth - itemsWidth;
    self.titleLabel.frame = NSMakeRect(margin + 4.0, 18.0, width - margin * 2.0, 28.0);
    self.subtitleLabel.frame = NSMakeRect(margin + 5.0, 50.0, width - margin * 2.0, 20.0);
    self.pathLabel.frame = NSMakeRect(margin + 4.0, 92.0, width - margin * 2.0, 20.0);
    self.itemsHeadingLabel.frame = NSMakeRect(margin + 4.0, 118.0, itemsWidth - 8.0, 18.0);
    self.versionsHeadingLabel.frame = NSMakeRect(margin + itemsWidth + gap + 4.0,
                                                 118.0, versionsWidth - 8.0, 18.0);
    self.itemsScrollView.frame = NSMakeRect(margin, tablesTop, itemsWidth, tablesHeight);
    self.versionsScrollView.frame = NSMakeRect(margin + itemsWidth + gap, tablesTop,
                                               versionsWidth, tablesHeight);
    self.statusLabel.frame = NSMakeRect(margin + 4.0, height - 64.0,
                                       MAX(240.0, width - 490.0), 22.0);

    CGFloat backWidth = MAX(84.0, ceil(self.backButton.cell.cellSize.width + 18.0));
    CGFloat openWidth = MAX(116.0, ceil(self.openButton.cell.cellSize.width + 18.0));
    CGFloat restoreWidth = MAX(138.0, ceil(self.restoreButton.cell.cellSize.width + 18.0));
    CGFloat revealWidth = MAX(130.0, ceil(self.revealButton.cell.cellSize.width + 18.0));
    CGFloat y = height - 38.0;
    self.backButton.frame = NSMakeRect(margin, y, backWidth, 30.0);
    self.openButton.frame = NSMakeRect(NSMaxX(self.backButton.frame) + 8.0, y, openWidth, 30.0);
    self.restoreButton.frame = NSMakeRect(width - margin - restoreWidth, y, restoreWidth, 30.0);
    self.revealButton.frame = NSMakeRect(NSMinX(self.restoreButton.frame) - 8.0 - revealWidth,
                                         y, revealWidth, 30.0);
}

- (void)setLanguage:(NSString *)language {
    _language = [language copy] ?: @"en";
    self.titleLabel.stringValue = T(_language, @"restoreTitle");
    self.subtitleLabel.stringValue = T(_language, @"restoreSubtitle");
    self.itemsTable.tableColumns[0].title = T(_language, @"restoreFilesColumn");
    self.versionsTable.tableColumns[0].title = T(_language, @"restoreVersionsColumn");
    self.versionsTable.tableColumns[1].title = T(_language, @"restoreSizeColumn");
    self.itemsHeadingLabel.stringValue = T(_language, @"restoreFilesColumn");
    self.versionsHeadingLabel.stringValue = T(_language, @"restoreVersionsColumn");
    self.itemsHeadingLabel.accessibilityLabel = self.itemsHeadingLabel.stringValue;
    self.versionsHeadingLabel.accessibilityLabel = self.versionsHeadingLabel.stringValue;
    self.backButton.title = T(_language, @"restoreBack");
    self.openButton.title = T(_language, @"restoreOpenFolder");
    self.restoreButton.title = T(_language, @"restoreAction");
    self.revealButton.title = T(_language, @"restoreShowInFinder");
    for (NSButton *button in @[self.backButton, self.openButton, self.restoreButton, self.revealButton]) {
        button.accessibilityLabel = button.title;
    }
    self.titleLabel.accessibilityLabel = self.titleLabel.stringValue;
    self.subtitleLabel.accessibilityLabel = self.subtitleLabel.stringValue;
    [self setCurrentRelativePath:self.currentRelativePath ?: @""];
    if (!self.statusText.length) {
        [self setStatusText:T(_language, @"restoreEmpty")];
    }
    [self setNeedsLayout:YES];
}

- (void)setCurrentRelativePath:(NSString *)currentRelativePath {
    _currentRelativePath = [currentRelativePath copy] ?: @"";
    self.pathLabel.stringValue = _currentRelativePath.length ? _currentRelativePath : @"Backup";
    self.pathLabel.toolTip = self.pathLabel.stringValue;
    self.pathLabel.accessibilityLabel = self.pathLabel.stringValue;
    [self updateControlStates];
}

- (void)setEntries:(NSArray<NSDictionary<NSString *,id> *> *)entries {
    _entries = [entries copy] ?: @[];
    [self.itemsTable reloadData];
    [self.itemsTable deselectAll:nil];
    self.openButton.enabled = NO;
    if (!_entries.count && !self.loading) {
        self.statusText = T(self.language ?: @"en", @"restoreEmpty");
    }
}

- (void)setVersions:(NSArray<NSDictionary<NSString *,id> *> *)versions {
    _versions = [versions copy] ?: @[];
    [self.versionsTable reloadData];
    [self.versionsTable deselectAll:nil];
    self.restoreButton.enabled = NO;
    if (!_versions.count && self.itemsTable.selectedRow >= 0 && !self.loading) {
        self.statusText = T(self.language ?: @"en", @"restoreNoVersions");
    }
}

- (void)setStatusText:(NSString *)statusText {
    _statusText = [statusText copy] ?: @"";
    self.statusLabel.stringValue = _statusText;
    self.statusLabel.toolTip = _statusText;
    self.statusLabel.accessibilityLabel = _statusText;
}

- (void)setLoading:(BOOL)loading {
    _loading = loading;
    if (loading) {
        self.statusText = T(self.language ?: @"en", @"restoreLoading");
    }
    [self updateControlStates];
}

- (void)updateControlStates {
    NSInteger itemRow = self.itemsTable.selectedRow;
    BOOL selectedDirectory = itemRow >= 0 && itemRow < (NSInteger)self.entries.count &&
        [self.entries[(NSUInteger)itemRow][@"kind"] isEqualToString:@"directory"];
    self.backButton.enabled = !self.loading && self.currentRelativePath.length > 0;
    self.openButton.enabled = !self.loading && selectedDirectory;
    self.restoreButton.enabled = !self.loading && self.versionsTable.selectedRow >= 0;
    self.itemsTable.enabled = !self.loading;
    self.versionsTable.enabled = !self.loading;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return tableView == self.itemsTable ? (NSInteger)self.entries.count : (NSInteger)self.versions.count;
}

- (nullable id)tableView:(NSTableView *)tableView
 objectValueForTableColumn:(nullable NSTableColumn *)tableColumn
                      row:(NSInteger)row {
    if (row < 0) {
        return @"";
    }
    if (tableView == self.itemsTable) {
        if (row >= (NSInteger)self.entries.count) return @"";
        NSDictionary *entry = self.entries[(NSUInteger)row];
        NSString *prefix = [entry[@"kind"] isEqualToString:@"directory"] ? @"▸  " : @"";
        return [prefix stringByAppendingString:entry[@"name"] ?: @""];
    }
    if (row >= (NSInteger)self.versions.count) return @"";
    NSDictionary *version = self.versions[(NSUInteger)row];
    return [tableColumn.identifier isEqualToString:@"size"]
        ? (version[@"displaySize"] ?: @"")
        : (version[@"displayDate"] ?: @"");
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == self.itemsTable) {
        NSInteger row = self.itemsTable.selectedRow;
        self.versions = @[];
        if (row >= 0 && row < (NSInteger)self.entries.count) {
            NSDictionary *entry = self.entries[(NSUInteger)row];
            if ([entry[@"kind"] isEqualToString:@"file"] && self.fileSelectionHandler) {
                self.fileSelectionHandler(entry[@"relativePath"] ?: @"");
            }
        }
    }
    [self updateControlStates];
}

- (void)goBack:(id)sender {
    (void)sender;
    if (!self.loading && self.backHandler) {
        self.backHandler();
    }
}

- (void)openSelectedFolder:(id)sender {
    (void)sender;
    NSInteger row = self.itemsTable.selectedRow;
    if (self.loading || row < 0 || row >= (NSInteger)self.entries.count) {
        return;
    }
    NSDictionary *entry = self.entries[(NSUInteger)row];
    if ([entry[@"kind"] isEqualToString:@"directory"] && self.browseHandler) {
        self.browseHandler(entry[@"relativePath"] ?: @"");
    }
}

- (void)restoreSelectedVersion:(id)sender {
    (void)sender;
    NSInteger row = self.versionsTable.selectedRow;
    if (self.loading || row < 0 || row >= (NSInteger)self.versions.count || !self.restoreHandler) {
        return;
    }
    self.restoreHandler(self.versions[(NSUInteger)row]);
}

- (void)revealRestoredFile:(id)sender {
    (void)sender;
    if (self.verifiedDestinationURL && self.revealHandler) {
        self.revealHandler(self.verifiedDestinationURL);
    }
}

- (void)showVerifiedDestinationURL:(NSURL *)destinationURL sha256:(NSString *)sha256 {
    self.loading = NO;
    self.verifiedDestinationURL = destinationURL;
    self.revealButton.hidden = NO;
    NSString *message = [NSString stringWithFormat:@"%@ %@",
        T(self.language ?: @"en", @"restoreVerified"), destinationURL.path];
    self.statusText = message;
    self.statusLabel.accessibilityLabel = [NSString stringWithFormat:@"%@ SHA-256: %@",
        message, sha256 ?: @""];
    self.statusLabel.toolTip = self.statusLabel.accessibilityLabel;
}

- (void)showRestoreError:(NSString *)message {
    self.loading = NO;
    self.revealButton.hidden = YES;
    self.verifiedDestinationURL = nil;
    self.statusText = message.length ? message : T(self.language ?: @"en", @"restoreIntegrityFailed");
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSGradient *background = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedWhite:0.98 alpha:1.0],
        [NSColor colorWithCalibratedWhite:0.87 alpha:1.0]
    ]];
    [background drawInRect:self.bounds angle:-90];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.34] setFill];
    for (CGFloat y = 78.0; y < NSHeight(self.bounds); y += 5.0) {
        NSRectFill(NSMakeRect(0, y, NSWidth(self.bounds), 1.0));
    }
    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.26] setFill];
    NSRectFill(NSMakeRect(0, 76.0, NSWidth(self.bounds), 1.0));
}

@end
