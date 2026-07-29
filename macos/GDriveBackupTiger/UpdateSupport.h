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

NS_ASSUME_NONNULL_END
