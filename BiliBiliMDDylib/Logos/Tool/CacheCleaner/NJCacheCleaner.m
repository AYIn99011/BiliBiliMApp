//
//  NJCacheCleaner.m
//  BiliBiliTweak
//

#import "NJCacheCleaner.h"

@interface NJCacheCleaner ()

+ (NSArray<NSString *> *)preservedCacheEntryNames;
+ (nullable NSString *)cachesDirectory;
+ (NSString *)normalizedDirectoryPath:(NSString *)path;
+ (NSArray<NSString *> *)clearableItemPaths;
+ (BOOL)isPathSafeToDelete:(NSString *)path;
+ (unsigned long long)sizeOfItemAtPath:(NSString *)path
                         fileManager:(NSFileManager *)fm;
+ (unsigned long long)totalClearableSize;
+ (dispatch_queue_t)ioQueue;

@end

@implementation NJCacheCleaner

#pragma mark - Whitelist

/// Top-level entries inside Library/Caches that must never be deleted.
/// - NJCache:          the plugin's own YYCache store (NJSettingCache),
///                     holds every switch / playback-rate setting.
/// - NJCacheShareData: the plugin's own share-data store (NJDiskCache /
///                     NJShareManager).
+ (NSArray<NSString *> *)preservedCacheEntryNames {
    return @[@"NJCache", @"NJCacheShareData"];
}

#pragma mark - Paths

+ (nullable NSString *)cachesDirectory {
    return NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
}

/// Standardizes a directory path and strips any trailing slash so
/// roots and candidates can be prefix-compared reliably.
+ (NSString *)normalizedDirectoryPath:(NSString *)path {
    NSString *normalized = [path stringByStandardizingPath];
    while (normalized.length > 1 && [normalized hasSuffix:@"/"]) {
        normalized = [normalized substringToIndex:normalized.length - 1];
    }
    return normalized;
}

/// Full paths of every clearable top-level item: the non-whitelisted
/// contents of Library/Caches plus the contents of tmp.
+ (NSArray<NSString *> *)clearableItemPaths {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];

    NSString *cachesDir = [self cachesDirectory];
    if (cachesDir.length > 0) {
        NSArray<NSString *> *preserved = [self preservedCacheEntryNames];
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:cachesDir error:nil];
        for (NSString *entry in entries) {
            if ([preserved containsObject:entry]) {
                continue;
            }
            [paths addObject:[cachesDir stringByAppendingPathComponent:entry]];
        }
    }

    NSString *tmpDir = NSTemporaryDirectory();
    if (tmpDir.length > 0) {
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:tmpDir error:nil];
        for (NSString *entry in entries) {
            [paths addObject:[tmpDir stringByAppendingPathComponent:entry]];
        }
    }
    return [paths copy];
}

#pragma mark - Safety

/// A path may only be deleted when it is a direct child of one of the
/// two allowed roots (Library/Caches or tmp) and is neither a root
/// itself nor a whitelisted entry. This is a hard boundary check, not
/// a best-effort filter: anything outside it is refused.
+ (BOOL)isPathSafeToDelete:(NSString *)path {
    if (path.length == 0) {
        return NO;
    }
    NSString *standardized = [path stringByStandardizingPath];
    NSString *cachesDir = [self cachesDirectory];

    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    if (cachesDir.length > 0) {
        [roots addObject:[self normalizedDirectoryPath:cachesDir]];
    }
    NSString *tmpDir = NSTemporaryDirectory();
    if (tmpDir.length > 0) {
        [roots addObject:[self normalizedDirectoryPath:tmpDir]];
    }

    for (NSString *root in roots) {
        if ([standardized isEqualToString:root]) {
            continue;
        }
        NSString *prefix = [root stringByAppendingString:@"/"];
        if (![standardized hasPrefix:prefix]) {
            continue;
        }
        // Only direct children of a root are deletable. Deeper paths
        // are reached by deleting their top-level ancestor, never
        // addressed on their own.
        NSString *relative = [standardized substringFromIndex:prefix.length];
        if ([relative containsString:@"/"]) {
            return NO;
        }
        if (cachesDir.length > 0 &&
            [root isEqualToString:[self normalizedDirectoryPath:cachesDir]] &&
            [[self preservedCacheEntryNames] containsObject:relative]) {
            return NO;
        }
        return YES;
    }
    return NO;
}

#pragma mark - Size

+ (unsigned long long)sizeOfItemAtPath:(NSString *)path
                         fileManager:(NSFileManager *)fm {
    NSDictionary<NSFileAttributeKey, id> *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (attrs == nil) {
        return 0;
    }
    if (![attrs.fileType isEqualToString:NSFileTypeDirectory]) {
        return attrs.fileSize;
    }
    unsigned long long total = 0;
    NSDirectoryEnumerator<NSString *> *enumerator = [fm enumeratorAtPath:path];
    NSString *relativePath = nil;
    while ((relativePath = [enumerator nextObject]) != nil) {
        NSString *fullPath = [path stringByAppendingPathComponent:relativePath];
        NSDictionary<NSFileAttributeKey, id> *fileAttrs =
            [fm attributesOfItemAtPath:fullPath error:nil];
        if ([fileAttrs.fileType isEqualToString:NSFileTypeRegular]) {
            total += fileAttrs.fileSize;
        }
    }
    return total;
}

+ (unsigned long long)totalClearableSize {
    NSFileManager *fm = [NSFileManager defaultManager];
    unsigned long long total = 0;
    for (NSString *path in [self clearableItemPaths]) {
        total += [self sizeOfItemAtPath:path fileManager:fm];
    }
    // NSURLCache is not added on top: its disk store already lives
    // under Library/Caches and is counted by the enumeration above.
    return total;
}

#pragma mark - Queue

+ (dispatch_queue_t)ioQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.njcachecleaner.queue", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

#pragma mark - Public Methods

+ (void)calculateCacheSizeWithCompletion:(void (^)(unsigned long long size))completion {
    dispatch_async([self ioQueue], ^{
        unsigned long long size = [self totalClearableSize];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(size);
            });
        }
    });
}

+ (void)clearCacheWithCompletion:(void (^)(unsigned long long freedSize,
                                           unsigned long long remainingSize))completion {
    dispatch_async([self ioQueue], ^{
        unsigned long long before = [self totalClearableSize];

        [[NSURLCache sharedURLCache] removeAllCachedResponses];

        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *path in [self clearableItemPaths]) {
            if (![self isPathSafeToDelete:path]) {
                NSLog(@"[NJCacheCleaner] refused out-of-scope path: %@", path);
                continue;
            }
            NSError *error = nil;
            if (![fm removeItemAtPath:path error:&error] && error != nil) {
                NSLog(@"[NJCacheCleaner] failed to remove %@: %@", path, error.localizedDescription);
            }
        }

        unsigned long long after = [self totalClearableSize];
        unsigned long long freed = (before > after) ? (before - after) : 0;
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(freed, after);
            });
        }
    });
}

+ (NSString *)formattedSize:(unsigned long long)size {
    return [NSByteCountFormatter stringFromByteCount:(long long)size
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

@end
