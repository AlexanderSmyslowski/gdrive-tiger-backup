#import <Foundation/Foundation.h>

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static void Write(NSURL *url, NSString *value) {
    [value writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static NSArray<NSDictionary<NSString *, id> *> *CallList(id object,
                                                          NSString *selectorName,
                                                          NSString *relativePath,
                                                          NSError **error) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }
    typedef NSArray *(*ListMethod)(id, SEL, NSString *, NSError **);
    ListMethod method = (ListMethod)[object methodForSelector:selector];
    return method(object, selector, relativePath, error);
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-restore-%@", NSUUID.UUID.UUIDString]
                             isDirectory:YES];
        NSURL *myDrive = [root URLByAppendingPathComponent:@"My Drive" isDirectory:YES];
        NSURL *versions = [root URLByAppendingPathComponent:@".gdrive-versions" isDirectory:YES];
        NSURL *collisionArchive = [root
            URLByAppendingPathComponent:@".gdrive-collisions" isDirectory:YES];
        NSString *olderRun = @"2026-07-09T08-00-00+0200-11111111-1111-1111-1111-111111111111";
        NSString *newerRun = @"2026-07-10T20-00-00+0200-22222222-2222-2222-2222-222222222222";
        NSURL *olderDrive = [[versions URLByAppendingPathComponent:olderRun isDirectory:YES]
            URLByAppendingPathComponent:@"My Drive" isDirectory:YES];
        NSURL *newerDrive = [[versions URLByAppendingPathComponent:newerRun isDirectory:YES]
            URLByAppendingPathComponent:@"My Drive" isDirectory:YES];
        NSURL *retiredDrive = [[[versions URLByAppendingPathComponent:@".retention-trash" isDirectory:YES]
            URLByAppendingPathComponent:@"retired-run" isDirectory:YES]
            URLByAppendingPathComponent:@"My Drive" isDirectory:YES];
        NSURL *outside = [[root URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"outside-%@.txt", NSUUID.UUID.UUIDString]];
        NSURL *linkedRoot = [[root URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"linked-root-%@", NSUUID.UUID.UUIDString]];
        NSURL *output = [[root URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-restored-%@", NSUUID.UUID.UUIDString]
                             isDirectory:YES];
        NSURL *codecRoot = [[root URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-codec-%@", NSUUID.UUID.UUIDString]
                             isDirectory:YES];
        NSURL *codecOutput = [[root URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"gdrive-codec-output-%@", NSUUID.UUID.UUIDString]
                             isDirectory:YES];

        for (NSURL *directory in @[
                myDrive, olderDrive, newerDrive, retiredDrive, collisionArchive, output
             ]) {
            [fileManager createDirectoryAtURL:directory
                  withIntermediateDirectories:YES attributes:nil error:nil];
        }
        Write([myDrive URLByAppendingPathComponent:@"current-only.txt"], @"current");
        Write([myDrive URLByAppendingPathComponent:@"shared.txt"], @"live shared");
        Write([olderDrive URLByAppendingPathComponent:@"shared.txt"], @"older shared");
        Write([newerDrive URLByAppendingPathComponent:@"shared.txt"], @"newer shared");
        Write([newerDrive URLByAppendingPathComponent:@"historical-only.txt"], @"deleted later");
        Write([retiredDrive URLByAppendingPathComponent:@"retired.txt"], @"retired");
        Write(outside, @"outside");
        [fileManager createSymbolicLinkAtURL:[myDrive URLByAppendingPathComponent:@"unsafe-link.txt"]
                         withDestinationURL:outside error:nil];
        [fileManager createSymbolicLinkAtURL:linkedRoot withDestinationURL:root error:nil];

        Class catalogClass = NSClassFromString(@"GDTRestoreCatalog");
        Class copierClass = NSClassFromString(@"GDTRestoreCopier");
        Assert(catalogClass != Nil && copierClass != Nil,
               @"restore catalog and verified copier are available");

        if (catalogClass && copierClass) {
            SEL catalogInitSelector = NSSelectorFromString(@"initWithBackupRootURL:fileManager:");
            typedef id (*CatalogInitMethod)(id, SEL, NSURL *, NSFileManager *);
            CatalogInitMethod catalogInit = (CatalogInitMethod)[catalogClass
                instanceMethodForSelector:catalogInitSelector];
            id catalog = catalogInit([catalogClass alloc], catalogInitSelector, root, fileManager);

            NSError *error = nil;
            NSArray<NSDictionary<NSString *, id> *> *rootChildren =
                CallList(catalog, @"childrenAtRelativePath:error:", @"", &error);
            NSSet *rootNames = [NSSet setWithArray:[rootChildren valueForKey:@"name"]];
            Assert(!error && [rootNames containsObject:@"My Drive"] &&
                   ![rootNames containsObject:@".gdrive-versions"] &&
                   ![rootNames containsObject:@".gdrive-collisions"],
                   @"browser starts at backup areas without exposing internal backup stores");

            NSArray<NSDictionary<NSString *, id> *> *children =
                CallList(catalog, @"childrenAtRelativePath:error:", @"My Drive", &error);
            NSSet *childNames = [NSSet setWithArray:[children valueForKey:@"name"]];
            Assert(!error && [childNames containsObject:@"current-only.txt"] &&
                   [childNames containsObject:@"shared.txt"] &&
                   [childNames containsObject:@"historical-only.txt"],
                   @"browser merges current and retained per-file versions lazily");
            Assert(![childNames containsObject:@"unsafe-link.txt"] &&
                   ![childNames containsObject:@"retired.txt"],
                   @"browser excludes symbolic links and retired quarantine data");

            NSArray<NSDictionary<NSString *, id> *> *sharedVersions =
                CallList(catalog, @"versionsForRelativePath:error:", @"My Drive/shared.txt", &error);
            Assert(sharedVersions.count == 3 &&
                   [sharedVersions[0][@"kind"] isEqualToString:@"current"] &&
                   [sharedVersions[1][@"runID"] isEqualToString:newerRun] &&
                   [sharedVersions[2][@"runID"] isEqualToString:olderRun] &&
                   [[NSSet setWithArray:[sharedVersions valueForKey:@"name"]]
                       isEqualToSet:[NSSet setWithObject:@"shared.txt"]],
                   @"file versions show current first and history newest first");

            error = nil;
            NSArray *unsafeTraversal =
                CallList(catalog, @"childrenAtRelativePath:error:", @"../private", &error);
            Assert(unsafeTraversal.count == 0 && error != nil,
                   @"catalog rejects traversal outside the backup root");

            NSArray<NSDictionary<NSString *, id> *> *historicalVersions =
                CallList(catalog, @"versionsForRelativePath:error:", @"My Drive/historical-only.txt", &error);
            NSURL *historicalSource = historicalVersions.firstObject[@"sourceURL"];
            Write([output URLByAppendingPathComponent:@"historical-only.txt"], @"keep existing");

            SEL copierInitSelector = NSSelectorFromString(@"initWithBackupRootURL:fileManager:");
            typedef id (*CopierInitMethod)(id, SEL, NSURL *, NSFileManager *);
            CopierInitMethod copierInit = (CopierInitMethod)[copierClass
                instanceMethodForSelector:copierInitSelector];
            id copier = copierInit([copierClass alloc], copierInitSelector, root, fileManager);
            SEL restoreSelector = NSSelectorFromString(@"restoreSourceURL:toDirectoryURL:error:");
            typedef NSDictionary *(*RestoreMethod)(id, SEL, NSURL *, NSURL *, NSError **);
            RestoreMethod restore = (RestoreMethod)[copier methodForSelector:restoreSelector];
            SEL namedRestoreSelector =
                NSSelectorFromString(@"restoreSourceURL:name:toDirectoryURL:error:");
            typedef NSDictionary *(*NamedRestoreMethod)(
                id, SEL, NSURL *, NSString *, NSURL *, NSError **
            );

            error = nil;
            NSDictionary<NSString *, id> *result = restore(copier, restoreSelector,
                                                            historicalSource, output, &error);
            NSURL *restoredURL = result[@"destinationURL"];
            NSString *restoredContent = restoredURL
                ? [NSString stringWithContentsOfURL:restoredURL encoding:NSUTF8StringEncoding error:nil]
                : nil;
            Assert(!error && [restoredURL.lastPathComponent isEqualToString:@"historical-only restored.txt"] &&
                   [restoredContent isEqualToString:@"deleted later"] &&
                   [result[@"sha256"] length] == 64,
                   @"verified restore preserves an existing file and returns its SHA-256 proof");

            __block NSInteger digestCalls = 0;
            id mismatchProvider = [^NSString *(NSURL *url, NSError **digestError) {
                (void)url;
                (void)digestError;
                digestCalls++;
                return digestCalls == 1 ? @"aaaaaaaa" : @"bbbbbbbb";
            } copy];
            [copier setValue:mismatchProvider forKey:@"digestProvider"];
            NSUInteger beforeCount = [fileManager contentsOfDirectoryAtURL:output
                                                includingPropertiesForKeys:nil options:0 error:nil].count;
            error = nil;
            NSDictionary *mismatchResult = restore(copier, restoreSelector,
                                                     historicalSource, output, &error);
            NSUInteger afterCount = [fileManager contentsOfDirectoryAtURL:output
                                               includingPropertiesForKeys:nil options:0 error:nil].count;
            Assert(!mismatchResult && error != nil && beforeCount == afterCount,
                   @"checksum mismatch never publishes an unverified restored file");

            error = nil;
            NSDictionary *outsideResult = restore(copier, restoreSelector, outside, output, &error);
            Assert(!outsideResult && error != nil,
                   @"restore copier rejects sources outside the configured backup");

            error = nil;
            NSDictionary *insideResult = restore(copier, restoreSelector,
                                                  historicalSource, myDrive, &error);
            Assert(!insideResult && error != nil,
                   @"restore destination cannot modify the independent backup tree");

            id linkedCatalog = catalogInit([catalogClass alloc], catalogInitSelector,
                                            linkedRoot, fileManager);
            error = nil;
            NSArray *linkedRootChildren =
                CallList(linkedCatalog, @"childrenAtRelativePath:error:", @"", &error);
            Assert(linkedRootChildren.count == 0,
                   @"symbolic-link backup roots are never browsed as trusted copies");

            NSString *codecRun = @"2026-07-10T20-00-00+0200-33333333-3333-3333-3333-333333333333";
            NSURL *codecCurrentParent = [[codecRoot URLByAppendingPathComponent:@"My Drive"
                                                                   isDirectory:YES]
                URLByAppendingPathComponent:@"node_modules" isDirectory:YES];
            NSURL *codecCurrentBin = [codecCurrentParent
                URLByAppendingPathComponent:@"__gdt0__dotbin_000" isDirectory:YES];
            NSURL *codecCurrentCollision = [codecCurrentParent
                URLByAppendingPathComponent:@"__gdt0____gdt0__dotbin_000" isDirectory:YES];
            NSURL *codecCurrentUpperBin = [[codecRoot
                URLByAppendingPathComponent:@"My Drive/case-variant" isDirectory:YES]
                URLByAppendingPathComponent:@"__gdt0__dotbin_111" isDirectory:YES];
            NSURL *codecHistoricalParent = [[[[codecRoot
                URLByAppendingPathComponent:@".gdrive-versions" isDirectory:YES]
                URLByAppendingPathComponent:codecRun isDirectory:YES]
                URLByAppendingPathComponent:@"My Drive" isDirectory:YES]
                URLByAppendingPathComponent:@"node_modules" isDirectory:YES];
            NSURL *codecHistoricalBin = [codecHistoricalParent
                URLByAppendingPathComponent:@"__gdt0____gdt0__dotbin_000" isDirectory:YES];
            NSURL *codecHistoricalCollision = [codecHistoricalParent
                URLByAppendingPathComponent:@"__gdt0____gdt0____gdt0__dotbin_000"
                                 isDirectory:YES];
            NSURL *codecHistoricalUpperBin = [[[[codecRoot
                URLByAppendingPathComponent:@".gdrive-versions" isDirectory:YES]
                URLByAppendingPathComponent:codecRun isDirectory:YES]
                URLByAppendingPathComponent:@"My Drive/case-variant" isDirectory:YES]
                URLByAppendingPathComponent:@"__gdt0____gdt0__dotbin_111"
                                 isDirectory:YES];
            NSURL *codecSharedDrive = [[codecRoot
                URLByAppendingPathComponent:@"Shared Drives" isDirectory:YES]
                URLByAppendingPathComponent:@"__gdt0__Team (drive-1)" isDirectory:YES];
            NSURL *codecSharedDriveBin = [codecSharedDrive
                URLByAppendingPathComponent:@"__gdt0__dotbin_000" isDirectory:YES];
            NSURL *codecCurrentMarkerFile = [[codecRoot
                URLByAppendingPathComponent:@"My Drive" isDirectory:YES]
                URLByAppendingPathComponent:@"__gdt0____GDT0__Marker.txt"];
            NSURL *codecHistoricalMarkerFile = [[[[codecRoot
                URLByAppendingPathComponent:@".gdrive-versions" isDirectory:YES]
                URLByAppendingPathComponent:codecRun isDirectory:YES]
                URLByAppendingPathComponent:@"My Drive" isDirectory:YES]
                URLByAppendingPathComponent:
                    @"__gdt0____gdt0____GDT0__Marker.txt"];
            NSURL *codecMalformedBin = [[[[[codecRoot
                URLByAppendingPathComponent:@".gdrive-versions" isDirectory:YES]
                URLByAppendingPathComponent:codecRun isDirectory:YES]
                URLByAppendingPathComponent:@"My Drive" isDirectory:YES]
                URLByAppendingPathComponent:@"malformed" isDirectory:YES]
                URLByAppendingPathComponent:@"__gdt0__dotbin_000" isDirectory:YES];
            for (NSURL *directory in @[
                    codecCurrentBin, codecCurrentCollision, codecHistoricalBin,
                    codecHistoricalCollision, codecCurrentUpperBin,
                    codecHistoricalUpperBin, codecSharedDriveBin,
                    codecMalformedBin, codecOutput
                 ]) {
                [fileManager createDirectoryAtURL:directory
                      withIntermediateDirectories:YES attributes:nil error:nil];
            }
            Write([codecRoot URLByAppendingPathComponent:@".gdrive-name-codec"],
                  @"protocol=1\ncodec=nas-path-v1\nprefix=__gdt0__\n"
                   "dot_bin_prefix=__gdt0__dotbin_\ncurrent_layers=1\nversion_layers=2\n");
            Write([codecCurrentBin URLByAppendingPathComponent:@"tool"], @"current tool");
            Write([codecCurrentCollision URLByAppendingPathComponent:@"collision.txt"],
                  @"collision directory");
            Write([codecHistoricalBin URLByAppendingPathComponent:@"tool"], @"historical tool");
            Write([codecHistoricalCollision URLByAppendingPathComponent:@"collision.txt"],
                  @"historical collision directory");
            Write([codecCurrentUpperBin URLByAppendingPathComponent:@"upper-tool"],
                  @"current upper tool");
            Write([codecHistoricalUpperBin URLByAppendingPathComponent:@"upper-tool"],
                  @"historical upper tool");
            Write([codecSharedDriveBin URLByAppendingPathComponent:@"shared-tool"],
                  @"shared drive tool");
            Write(codecCurrentMarkerFile, @"current marker file");
            Write(codecHistoricalMarkerFile, @"historical marker file");

            id codecCatalog = catalogInit([catalogClass alloc], catalogInitSelector,
                                           codecRoot, fileManager);
            error = nil;
            NSArray<NSDictionary<NSString *, id> *> *codecChildren =
                CallList(codecCatalog, @"childrenAtRelativePath:error:",
                         @"My Drive/node_modules", &error);
            NSSet *codecNames = [NSSet setWithArray:[codecChildren valueForKey:@"name"]];
            Assert(!error && [codecNames containsObject:@".bin"] &&
                   [codecNames containsObject:@"__gdt0__dotbin_000"] &&
                   codecNames.count == 2,
                   @"NAS codec decodes .bin without colliding with a real marker-like directory");

            error = nil;
            NSArray<NSDictionary<NSString *, id> *> *codecBinChildren =
                CallList(codecCatalog, @"childrenAtRelativePath:error:",
                         @"My Drive/node_modules/.bin", &error);
            Assert(!error && codecBinChildren.count == 1 &&
                   [codecBinChildren.firstObject[@"name"] isEqualToString:@"tool"],
                   @"NAS codec navigates encoded current and historical .bin directories");

            error = nil;
            NSArray<NSDictionary<NSString *, id> *> *codecVersions =
                CallList(codecCatalog, @"versionsForRelativePath:error:",
                         @"My Drive/node_modules/.bin/tool", &error);
            Assert(!error && codecVersions.count == 2 &&
                   [codecVersions[0][@"kind"] isEqualToString:@"current"] &&
                   [codecVersions[1][@"runID"] isEqualToString:codecRun],
                   @"NAS codec resolves one current layer and two version-history layers");

            error = nil;
            NSArray<NSDictionary<NSString *, id> *> *codecUpperChildren =
                CallList(codecCatalog, @"childrenAtRelativePath:error:",
                         @"My Drive/case-variant", &error);
            NSArray<NSDictionary<NSString *, id> *> *codecUpperVersions =
                CallList(codecCatalog, @"versionsForRelativePath:error:",
                         @"My Drive/case-variant/.BIN/upper-tool", &error);
            Assert(!error && codecUpperChildren.count == 1 &&
                   [codecUpperChildren.firstObject[@"name"] isEqualToString:@".BIN"] &&
                   codecUpperVersions.count == 2,
                   @"NAS codec round-trips the uppercase .BIN case variant");

            error = nil;
            NSArray<NSDictionary<NSString *, id> *> *codecCollisionVersions =
                CallList(codecCatalog, @"versionsForRelativePath:error:",
                         @"My Drive/node_modules/__gdt0__dotbin_000/collision.txt", &error);
            Assert(!error && codecCollisionVersions.count == 2,
                   @"NAS codec resolves a real marker-like directory in current and history");

            error = nil;
            NSArray<NSDictionary<NSString *, id> *> *codecMarkerVersions =
                CallList(codecCatalog, @"versionsForRelativePath:error:",
                         @"My Drive/__GDT0__Marker.txt", &error);
            Assert(!error && codecMarkerVersions.count == 2 &&
                   [[NSSet setWithArray:[codecMarkerVersions valueForKey:@"name"]]
                       isEqualToSet:[NSSet setWithObject:@"__GDT0__Marker.txt"]],
                   @"NAS codec keeps the logical name for encoded regular-file versions");

            error = nil;
            NSArray *malformedCodecChildren =
                CallList(codecCatalog, @"childrenAtRelativePath:error:",
                         @"My Drive/malformed", &error);
            Assert(malformedCodecChildren.count == 0 && error != nil,
                   @"NAS codec rejects a physical name with the wrong history layer count");

            error = nil;
            NSArray<NSDictionary<NSString *, id> *> *sharedDriveRoots =
                CallList(codecCatalog, @"childrenAtRelativePath:error:",
                         @"Shared Drives", &error);
            Assert(!error && sharedDriveRoots.count == 1 &&
                   [sharedDriveRoots.firstObject[@"name"]
                       isEqualToString:@"__gdt0__Team (drive-1)"],
                   @"NAS codec keeps the raw Shared Drive destination component browseable");

            error = nil;
            NSArray<NSDictionary<NSString *, id> *> *sharedDriveChildren =
                CallList(codecCatalog, @"childrenAtRelativePath:error:",
                         @"Shared Drives/__gdt0__Team (drive-1)", &error);
            Assert(!error && sharedDriveChildren.count == 1 &&
                   [sharedDriveChildren.firstObject[@"name"] isEqualToString:@".bin"],
                   @"NAS codec starts decoding below the raw Shared Drive destination");

            id codecCopier = copierInit([copierClass alloc], copierInitSelector,
                                         codecRoot, fileManager);
            error = nil;
            NSDictionary *codecRestore = codecVersions.count > 1
                ? restore(codecCopier, restoreSelector, codecVersions[1][@"sourceURL"],
                          codecOutput, &error)
                : nil;
            NSString *codecRestored = codecRestore[@"destinationURL"]
                ? [NSString stringWithContentsOfURL:codecRestore[@"destinationURL"]
                                           encoding:NSUTF8StringEncoding error:nil]
                : nil;
            Assert(!error && [codecRestored isEqualToString:@"historical tool"],
                   @"NAS codec restores the original file from encoded version history");

            error = nil;
            BOOL supportsNamedRestore = [codecCopier respondsToSelector:namedRestoreSelector];
            NamedRestoreMethod namedRestore = supportsNamedRestore
                ? (NamedRestoreMethod)[codecCopier methodForSelector:namedRestoreSelector] : NULL;
            NSDictionary *markerRestore = supportsNamedRestore && codecMarkerVersions.count > 1
                ? namedRestore(codecCopier, namedRestoreSelector,
                               codecMarkerVersions[1][@"sourceURL"],
                               codecMarkerVersions[1][@"name"], codecOutput, &error)
                : nil;
            Assert(!error && markerRestore &&
                   [[(NSURL *)markerRestore[@"destinationURL"] lastPathComponent]
                       isEqualToString:@"__GDT0__Marker.txt"],
                   @"NAS codec restores a regular file under its logical original name");

            error = nil;
            NSArray<NSDictionary<NSString *, id> *> *codecRootChildren =
                CallList(codecCatalog, @"childrenAtRelativePath:error:", @"", &error);
            NSSet *codecRootNames = [NSSet setWithArray:[codecRootChildren valueForKey:@"name"]];
            Assert(!error && ![codecRootNames containsObject:@".gdrive-name-codec"],
                   @"restore browser hides the NAS codec manifest");

            Write([codecRoot URLByAppendingPathComponent:@".gdrive-name-codec"],
                  @"protocol=999\ncodec=unknown\n");
            id invalidCodecCatalog = catalogInit([catalogClass alloc], catalogInitSelector,
                                                  codecRoot, fileManager);
            error = nil;
            NSArray *invalidCodecChildren =
                CallList(invalidCodecCatalog, @"childrenAtRelativePath:error:", @"", &error);
            Assert(invalidCodecChildren.count == 0 && error != nil,
                   @"restore browser fails closed for an unknown NAS codec manifest");
        }

        [fileManager trashItemAtURL:root resultingItemURL:nil error:nil];
        [fileManager trashItemAtURL:outside resultingItemURL:nil error:nil];
        [fileManager trashItemAtURL:output resultingItemURL:nil error:nil];
        [fileManager trashItemAtURL:linkedRoot resultingItemURL:nil error:nil];
        [fileManager trashItemAtURL:codecRoot resultingItemURL:nil error:nil];
        [fileManager trashItemAtURL:codecOutput resultingItemURL:nil error:nil];
    }

    if (failures > 0) {
        printf("%d restore support test(s) failed.\n", failures);
        return 1;
    }
    printf("All restore support tests passed.\n");
    return 0;
}
