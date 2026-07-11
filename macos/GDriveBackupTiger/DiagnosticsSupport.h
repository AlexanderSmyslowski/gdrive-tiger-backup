#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GDTDiagnosticsBuilder : NSObject

+ (NSDictionary<NSString *, id> *)snapshotForConfig:(NSDictionary<NSString *, NSString *> *)config
                                              summary:(NSDictionary<NSString *, NSString *> *)summary
                                          setupHealth:(NSDictionary<NSString *, id> *)setupHealth
                                              appInfo:(NSDictionary<NSString *, id> *)appInfo
                                         serviceState:(NSDictionary<NSString *, id> *)serviceState
                                          scriptState:(NSDictionary<NSString *, id> *)scriptState;
+ (NSString *)reportForSnapshot:(NSDictionary<NSString *, id> *)snapshot;

@end
NS_ASSUME_NONNULL_END
