//
//  NJCacheCleaner.h
//  BiliBiliTweak
//
//  One-click cache cleaning for the host app.
//  Scope is intentionally narrow: only the contents of Library/Caches
//  (minus the plugin's own stores) and tmp, plus NSURLCache.
//  Offline downloads, account state, Preferences and Documents are
//  never touched.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NJCacheCleaner : NSObject

/// Asynchronously calculates the total size of the clearable cache.
/// The completion block is called on the main queue.
+ (void)calculateCacheSizeWithCompletion:(void (^)(unsigned long long size))completion;

/// Asynchronously clears the cache.
/// The completion block is called on the main queue with the number of
/// bytes freed and the number of bytes remaining in the clearable scope.
+ (void)clearCacheWithCompletion:(void (^)(unsigned long long freedSize,
                                           unsigned long long remainingSize))completion;

/// Formats a byte count, e.g. 0 B / 12.3 MB / 1.2 GB.
+ (NSString *)formattedSize:(unsigned long long)size;

@end

NS_ASSUME_NONNULL_END
