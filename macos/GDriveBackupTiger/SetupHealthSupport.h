#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^GDTSetupCommandAvailability)(NSString *command);
typedef NSDictionary<NSString *, id> * _Nonnull (^GDTSetupCommandRunner)(NSString *command,
                                                                          NSArray<NSString *> *arguments);

@interface GDTSetupHealthChecker : NSObject

@property(nonatomic, copy, nullable) GDTSetupCommandAvailability commandAvailability;
@property(nonatomic, copy, nullable) GDTSetupCommandRunner commandRunner;
@property(nonatomic, strong) NSFileManager *fileManager;

+ (instancetype)productionChecker;
- (NSDictionary<NSString *, id> *)snapshotForConfig:(NSDictionary<NSString *, NSString *> *)config;

@end

NS_ASSUME_NONNULL_END
