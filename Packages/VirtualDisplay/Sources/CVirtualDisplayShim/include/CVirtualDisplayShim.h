// Public surface of the CGVirtualDisplay shim.
//
// This header deliberately exposes no private types. All use of the private
// CGVirtualDisplay classes lives in CVirtualDisplayShim.m and goes through
// NSClassFromString, so nothing links against those classes directly. If a
// future macOS removes them, creation fails with a typed error instead of the
// process dying at launch with "Symbol not found".

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const CVDShimErrorDomain;

typedef NS_ERROR_ENUM(CVDShimErrorDomain, CVDShimErrorCode) {
    /// A private class or selector is missing on this macOS version.
    CVDShimErrorApiUnavailable = 1,
    /// The classes exist but the display could not be created.
    CVDShimErrorCreationFailed = 2,
    /// The display was created but the system rejected its mode settings.
    CVDShimErrorSettingsRejected = 3,
};

/// Owns one virtual display. Releasing the last reference removes the display.
NS_SWIFT_NAME(VirtualDisplayShim)
@interface CVDVirtualDisplayShim : NSObject

/// Creates a non-HiDPI display with a single mode, using the real class names.
+ (nullable instancetype)createWithName:(NSString *)name
                                  width:(uint32_t)width
                                 height:(uint32_t)height
                            refreshRate:(double)refreshRate
                                  error:(NSError **)error;

/// Same, with the private class names injected so tests can exercise the
/// failure paths without creating a real display.
+ (nullable instancetype)createWithName:(NSString *)name
                                  width:(uint32_t)width
                                 height:(uint32_t)height
                            refreshRate:(double)refreshRate
                       displayClassName:(NSString *)displayClassName
                    descriptorClassName:(NSString *)descriptorClassName
                          modeClassName:(NSString *)modeClassName
                      settingsClassName:(NSString *)settingsClassName
                                  error:(NSError **)error;

/// The CGDirectDisplayID of the created display.
@property (nonatomic, readonly) uint32_t displayID;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
