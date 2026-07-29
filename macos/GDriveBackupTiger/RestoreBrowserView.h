#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface GDTRestoreBrowserView : NSView <NSTableViewDataSource, NSTableViewDelegate>

@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSString *currentRelativePath;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *entries;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *versions;
@property(nonatomic) BOOL loading;
@property(nonatomic, copy) NSString *statusText;
@property(nonatomic, copy, nullable) void (^backHandler)(void);
@property(nonatomic, copy, nullable) void (^browseHandler)(NSString *relativePath);
@property(nonatomic, copy, nullable) void (^fileSelectionHandler)(NSString *relativePath);
@property(nonatomic, copy, nullable) void (^restoreHandler)(NSDictionary<NSString *, id> *version);
@property(nonatomic, copy, nullable) void (^revealHandler)(NSURL *destinationURL);

@property(nonatomic, strong, readonly) NSTableView *itemsTable;
@property(nonatomic, strong, readonly) NSTableView *versionsTable;
@property(nonatomic, strong, readonly) NSButton *backButton;
@property(nonatomic, strong, readonly) NSButton *openButton;
@property(nonatomic, strong, readonly) NSButton *restoreButton;
@property(nonatomic, strong, readonly) NSButton *revealButton;
@property(nonatomic, strong, readonly) NSTextField *statusLabel;

- (void)showVerifiedDestinationURL:(NSURL *)destinationURL sha256:(NSString *)sha256;
- (void)showRestoreError:(NSString *)message;

@end
NS_ASSUME_NONNULL_END
