#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GDTBackupNotificationPolicy : NSObject

+ (NSDictionary<NSString *, NSString *> * _Nullable)
    decisionForConfig:(NSDictionary<NSString *, NSString *> *)config
               summary:(NSDictionary<NSString *, NSString *> *)summary
                status:(NSString *)status
                   now:(NSDate *)now
              calendar:(NSCalendar *)calendar;

+ (NSArray<NSString *> *)failureNotificationIdentifiersForProfileID:(NSString *)profileID
                                                candidateIdentifiers:
                                                    (NSArray<NSString *> *)candidateIdentifiers;

+ (NSArray<NSString *> *)failureNotificationIdentifiersForProfileID:(NSString *)profileID
                                 throughIssueOriginTimestamp:(NSTimeInterval)cutoff
                                      candidateNotifications:
                                          (NSArray<NSDictionary<NSString *, id> *> *)candidates;

@end

@interface GDTAutomaticRetryPolicy : NSObject

+ (NSDictionary<NSString *, NSString *> * _Nullable)
    decisionForConfig:(NSDictionary<NSString *, NSString *> *)config
               summary:(NSDictionary<NSString *, NSString *> *)summary
                status:(NSString *)status
                   now:(NSDate *)now;

@end

NS_ASSUME_NONNULL_END
