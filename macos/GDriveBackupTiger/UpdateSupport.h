#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^GDTUpdateDataCompletion)(NSData * _Nullable data,
                                        NSURLResponse * _Nullable response,
                                        NSError * _Nullable error);
typedef void (^GDTUpdateDataLoader)(NSURLRequest *request,
                                    GDTUpdateDataCompletion completion);

@interface GDTUpdateChecker : NSObject <NSURLSessionTaskDelegate>

@property(nonatomic, copy) GDTUpdateDataLoader dataLoader;

+ (NSDictionary<NSString *, NSString *> *)resultForResponseData:(NSData *)data
                                                    responseURL:(NSURL *)responseURL
                                                 currentVersion:(NSString *)currentVersion;
- (void)checkCurrentVersion:(NSString *)currentVersion
                 completion:(void (^)(NSDictionary<NSString *, NSString *> *result))completion;

@end

// All policy calls and state callbacks run on the controller's main thread.
@interface GDTAutomaticUpdatePolicy : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults checker:(GDTUpdateChecker *)checker
                   currentVersion:(NSString *)version;
@property(nonatomic, copy) NSDate *(^clock)(void);
@property(nonatomic, copy, nullable) void (^stateChanged)(void);
@property(nonatomic, readonly) BOOL answered;
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly, nullable) NSString *availableVersion;
@property(nonatomic, readonly) NSString *generation;
- (void)setEnabled:(BOOL)enabled;
- (void)checkIfDue;
- (nullable NSString *)claimNoticeVersion;
- (BOOL)acceptsNoticeVersion:(NSString *)version generation:(NSString *)generation;
- (NSArray<NSString *> *)takeObsoleteNoticeIdentifiers;
@end

NS_ASSUME_NONNULL_END
