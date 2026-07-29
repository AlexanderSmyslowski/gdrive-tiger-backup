#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface GDTDiagnosticsView : NSView

@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSDictionary<NSString *, id> *snapshot;
@property(nonatomic, copy) NSString *report;
@property(nonatomic) BOOL loading;
@property(nonatomic, copy, nullable) void (^refreshHandler)(void);
@property(nonatomic, copy, nullable) void (^copyHandler)(NSString *report);
@property(nonatomic, copy, nullable) void (^saveHandler)(NSString *report);

@property(nonatomic, copy, readonly) NSArray<NSTextField *> *rowTitleLabels;
@property(nonatomic, copy, readonly) NSArray<NSTextField *> *rowDetailLabels;
@property(nonatomic, copy, readonly) NSArray<NSTextField *> *rowSymbolLabels;
@property(nonatomic, strong, readonly) NSButton *refreshButton;
- (NSButton *)copyButton __attribute__((objc_method_family(none)));
@property(nonatomic, strong, readonly) NSButton *copyButton;
@property(nonatomic, strong, readonly) NSButton *saveButton;
@property(nonatomic, strong, readonly) NSTextField *privacyLabel;
@property(nonatomic, strong, readonly) NSTextField *overallLabel;

- (void)applySnapshot:(NSDictionary<NSString *, id> *)snapshot;
- (void)showFeedbackKey:(NSString *)key;

@end
NS_ASSUME_NONNULL_END
