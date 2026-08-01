#import "BackupProgressSupport.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

static BOOL GDTProgressValueIsSafe(NSString *value, NSUInteger maximumLength) {
    if (![value isKindOfClass:NSString.class] || value.length > maximumLength) {
        return NO;
    }
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if (character == 0 || character == '\r' || character == '\n') return NO;
    }
    return YES;
}

static BOOL GDTParseUnsignedInteger(NSString *value, unsigned long long *result) {
    if (!value.length ||
        [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:
            @"0123456789"].invertedSet].location != NSNotFound) {
        return NO;
    }
    errno = 0;
    char *end = NULL;
    unsigned long long number = strtoull(value.UTF8String, &end, 10);
    if (errno == ERANGE || !end || *end != '\0') {
        return NO;
    }
    if (result) *result = number;
    return YES;
}

static BOOL GDTMatchesPattern(NSString *value, NSString *pattern) {
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:pattern options:0 error:nil];
    NSRange entireValue = NSMakeRange(0, value.length);
    return [expression firstMatchInString:value options:0 range:entireValue] != nil;
}

static BOOL GDTValidProgressPhase(NSString *phase) {
    if (!GDTMatchesPattern(phase, @"^[1-9][0-9]*/[1-9][0-9]*$")) return NO;
    NSArray<NSString *> *parts = [phase componentsSeparatedByString:@"/"];
    unsigned long long current = 0;
    unsigned long long total = 0;
    return parts.count == 2 &&
        GDTParseUnsignedInteger(parts[0], &current) &&
        GDTParseUnsignedInteger(parts[1], &total) &&
        current <= total && total <= 9999;
}

static BOOL GDTValidProgressDetail(NSString *detail) {
    if (!GDTProgressValueIsSafe(detail, 256)) return NO;
    return GDTMatchesPattern(detail,
        @"^[0-9]+([.][0-9]+)? ([KMGTPE]i)?B / [0-9]+([.][0-9]+)? ([KMGTPE]i)?B, [0-9]+([.][0-9]+)? ([KMGTPE]i)?B/s, ETA (-|[0-9]+[dhms]([0-9]+[dhms])*)$");
}

static NSData *GDTReadPrivateProgressData(NSString *path) {
    if (!path.length) return nil;
    int descriptor = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (descriptor < 0) return nil;

    struct stat attributes;
    if (fstat(descriptor, &attributes) != 0 ||
        !S_ISREG(attributes.st_mode) ||
        attributes.st_uid != getuid() ||
        (attributes.st_mode & (S_IRWXG | S_IRWXO)) != 0) {
        close(descriptor);
        return nil;
    }

    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096];
    for (;;) {
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count > 0) {
            [data appendBytes:buffer length:(NSUInteger)count];
            continue;
        }
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) {
            close(descriptor);
            return nil;
        }
        break;
    }
    close(descriptor);
    return data;
}

NSString *GDTBackupProgressPathForSummaryPath(NSString *summaryPath) {
    return [[summaryPath stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"current-progress.status"];
}

NSDictionary<NSString *, NSString *> *GDTReadBackupProgressAtPath(NSString *path) {
    NSData *data = GDTReadPrivateProgressData(path);
    if (!data.length) return nil;
    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!content.length || [content rangeOfString:@"\r"].location != NSNotFound) {
        return nil;
    }
    for (NSUInteger index = 0; index < content.length; index++) {
        if ([content characterAtIndex:index] == 0) return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    NSArray<NSString *> *lines = [content componentsSeparatedByString:@"\n"];
    for (NSUInteger index = 0; index < lines.count; index++) {
        NSString *line = lines[index];
        if (!line.length && index == lines.count - 1) continue;
        NSRange separator = [line rangeOfString:@"="];
        if (!line.length || separator.location == NSNotFound || separator.location == 0) {
            return nil;
        }
        NSString *key = [line substringToIndex:separator.location];
        NSString *value = [line substringFromIndex:NSMaxRange(separator)];
        if (values[key] || !GDTProgressValueIsSafe(value, 512)) return nil;
        values[key] = value;
    }

    for (NSString *key in @[@"protocol", @"profile_id", @"pid", @"started_at",
                              @"trigger", @"updated_at"]) {
        if (!values[key]) return nil;
    }
    if (![values[@"status"] isEqualToString:@"finished"] && !values[@"label"]) {
        return nil;
    }
    return values;
}

NSDictionary<NSString *, NSString *> *GDTValidatedBackupProgressForValues(
    NSDictionary<NSString *, NSString *> *progress,
    NSDictionary<NSString *, NSString *> *summary,
    NSString *summaryStatus,
    NSString *profileID,
    NSTimeInterval nowTimestamp) {
    for (NSString *key in @[@"protocol", @"profile_id", @"pid", @"started_at",
                              @"trigger", @"label", @"updated_at"]) {
        if (!GDTProgressValueIsSafe(progress[key], 512)) return nil;
    }
    for (NSString *key in @[@"protocol", @"pid", @"started_at", @"trigger"]) {
        if (!GDTProgressValueIsSafe(summary[key], 512)) return nil;
    }
    if (![summaryStatus isEqualToString:@"running"] ||
        ![progress[@"protocol"] isEqualToString:@"1"] ||
        ![summary[@"protocol"] isEqualToString:@"1"] ||
        ![progress[@"profile_id"] isEqualToString:profileID] ||
        ![progress[@"pid"] isEqualToString:summary[@"pid"]] ||
        ![progress[@"started_at"] isEqualToString:summary[@"started_at"]] ||
        ![progress[@"trigger"] isEqualToString:summary[@"trigger"]]) {
        return nil;
    }

    NSString *summaryRetry = summary[@"retry_attempt"];
    NSString *progressRetry = progress[@"retry_attempt"];
    if ((summaryRetry || progressRetry) &&
        (!GDTProgressValueIsSafe(summaryRetry, 512) ||
         !GDTProgressValueIsSafe(progressRetry, 512) ||
         ![summaryRetry isEqualToString:progressRetry])) {
        return nil;
    }

    unsigned long long pid = 0;
    unsigned long long startedAt = 0;
    unsigned long long updatedAt = 0;
    if (!GDTParseUnsignedInteger(progress[@"pid"], &pid) || pid == 0 || pid > INT_MAX ||
        !GDTParseUnsignedInteger(progress[@"started_at"], &startedAt) || startedAt == 0 ||
        !GDTParseUnsignedInteger(progress[@"updated_at"], &updatedAt)) {
        return nil;
    }
    errno = 0;
    if (kill((pid_t)pid, 0) != 0 && errno != EPERM) return nil;
    NSTimeInterval updateTimestamp = (NSTimeInterval)updatedAt;
    if (updateTimestamp > nowTimestamp + 1 || nowTimestamp - updateTimestamp > 60) {
        return nil;
    }

    NSString *label = progress[@"label"];
    NSSet<NSString *> *labels = [NSSet setWithArray:
        @[@"preparing", @"My Drive", @"Shared with me", @"Shared Drive"]];
    if (![labels containsObject:label]) return nil;
    NSString *phase = progress[@"phase"];
    if ([label isEqualToString:@"preparing"]) {
        if (phase && !GDTValidProgressPhase(phase)) return nil;
    } else if (!GDTProgressValueIsSafe(phase, 512) || !GDTValidProgressPhase(phase)) {
        return nil;
    }

    NSString *percent = progress[@"percent"];
    if (percent) {
        unsigned long long number = 0;
        if (!GDTProgressValueIsSafe(percent, 512) ||
            !GDTParseUnsignedInteger(percent, &number) || number > 100) {
            return nil;
        }
    }
    NSString *detail = progress[@"detail"];
    if (detail && !GDTValidProgressDetail(detail)) return nil;
    return progress;
}
