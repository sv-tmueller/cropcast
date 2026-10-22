// The only file in the repository that touches the private CGVirtualDisplay API.
//
// Rules (see CGVirtualDisplayPrivate.h):
//  - Classes are looked up with NSClassFromString only. A direct class
//    reference would be a hard link-time dependency and the app would not
//    start at all if macOS removed the class.
//  - Every selector is checked before it is sent.
//  - Calls are wrapped in @try/@catch because Swift cannot catch ObjC exceptions.

#if !__has_feature(objc_arc)
#error "CVirtualDisplayShim.m must be compiled with ARC (-fobjc-arc)"
#endif

#import "CVirtualDisplayShim.h"
#import "CGVirtualDisplayPrivate.h"

NSErrorDomain const CVDShimErrorDomain = @"CVDShimErrorDomain";

// Fixed identity so macOS does not remember a new display on every run.
static const unsigned int kVendorID = 0xC0C0;
static const unsigned int kProductID = 0xCA57;
static const unsigned int kSerialNum = 0x0001;
// A 27 inch 16:9 panel, about 109 ppi at 2560x1440.
static const CGFloat kPanelWidthMM = 597.0;
static const CGFloat kPanelHeightMM = 336.0;

static BOOL Fail(NSError **error, CVDShimErrorCode code, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:CVDShimErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

static BOOL ClassRespondsToAll(Class cls, NSArray<NSString *> *selectors) {
    for (NSString *name in selectors) {
        if (![cls instancesRespondToSelector:NSSelectorFromString(name)]) {
            return NO;
        }
    }
    return YES;
}

@implementation CVDVirtualDisplayShim {
    // Strong reference: releasing it removes the display from the system.
    id _display;
    // The descriptor's callback queue. The display owns it too; keeping it here
    // makes the shim's lifetime the single owner story.
    dispatch_queue_t _queue;
    uint32_t _displayID;
}

+ (nullable instancetype)createWithName:(NSString *)name
                                  width:(uint32_t)width
                                 height:(uint32_t)height
                            refreshRate:(double)refreshRate
                                  error:(NSError **)error {
    return [self createWithName:name
                          width:width
                         height:height
                    refreshRate:refreshRate
               displayClassName:@"CGVirtualDisplay"
            descriptorClassName:@"CGVirtualDisplayDescriptor"
                  modeClassName:@"CGVirtualDisplayMode"
              settingsClassName:@"CGVirtualDisplaySettings"
                          error:error];
}

+ (nullable instancetype)createWithName:(NSString *)name
                                  width:(uint32_t)width
                                 height:(uint32_t)height
                            refreshRate:(double)refreshRate
                       displayClassName:(NSString *)displayClassName
                    descriptorClassName:(NSString *)descriptorClassName
                          modeClassName:(NSString *)modeClassName
                      settingsClassName:(NSString *)settingsClassName
                                  error:(NSError **)error {
    Class displayClass = NSClassFromString(displayClassName);
    Class descriptorClass = NSClassFromString(descriptorClassName);
    Class modeClass = NSClassFromString(modeClassName);
    Class settingsClass = NSClassFromString(settingsClassName);

    if (!displayClass || !descriptorClass || !modeClass || !settingsClass) {
        Fail(error, CVDShimErrorApiUnavailable,
             @"Private CGVirtualDisplay classes are not present on this macOS version");
        return nil;
    }

    BOOL selectorsOK =
        ClassRespondsToAll(displayClass, @[@"initWithDescriptor:", @"applySettings:", @"displayID"]) &&
        ClassRespondsToAll(modeClass, @[@"initWithWidth:height:refreshRate:"]) &&
        ClassRespondsToAll(descriptorClass,
                           @[@"setName:", @"setMaxPixelsWide:", @"setMaxPixelsHigh:",
                             @"setSizeInMillimeters:", @"setVendorID:", @"setProductID:",
                             @"setSerialNum:", @"setRedPrimary:", @"setGreenPrimary:",
                             @"setBluePrimary:", @"setWhitePoint:", @"setQueue:"]) &&
        ClassRespondsToAll(settingsClass, @[@"setHiDPI:", @"setModes:"]);
    if (!selectorsOK) {
        Fail(error, CVDShimErrorApiUnavailable,
             @"Private CGVirtualDisplay API has an unexpected shape on this macOS version");
        return nil;
    }

    // Declared outside @try so @catch can release it: ARC does not release
    // locals when an exception unwinds past them (no -fobjc-arc-exceptions), and
    // a leaked display would stay on screen after start() reported failure.
    CGVirtualDisplay *display = nil;
    @try {
        CGVirtualDisplayDescriptor *descriptor = [[descriptorClass alloc] init];
        if (!descriptor) {
            Fail(error, CVDShimErrorCreationFailed, @"Could not allocate the display descriptor");
            return nil;
        }
        dispatch_queue_t queue = dispatch_queue_create("cropcast.virtualdisplay", DISPATCH_QUEUE_SERIAL);
        descriptor.name = name;
        descriptor.vendorID = kVendorID;
        descriptor.productID = kProductID;
        descriptor.serialNum = kSerialNum;
        descriptor.maxPixelsWide = width;
        descriptor.maxPixelsHigh = height;
        descriptor.sizeInMillimeters = CGSizeMake(kPanelWidthMM, kPanelHeightMM);
        descriptor.redPrimary = CGPointMake(0.64, 0.33);
        descriptor.greenPrimary = CGPointMake(0.30, 0.60);
        descriptor.bluePrimary = CGPointMake(0.15, 0.06);
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        descriptor.queue = queue;

        display = [[displayClass alloc] initWithDescriptor:descriptor];
        if (!display) {
            Fail(error, CVDShimErrorCreationFailed,
                 @"The system refused to create the virtual display");
            return nil;
        }

        CGVirtualDisplayMode *mode = [[modeClass alloc] initWithWidth:width
                                                               height:height
                                                          refreshRate:refreshRate];
        CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
        if (!mode || !settings) {
            Fail(error, CVDShimErrorCreationFailed, @"Could not allocate the display mode or settings");
            return nil;
        }
        settings.hiDPI = 0;
        settings.modes = @[mode];
        if (![display applySettings:settings]) {
            Fail(error, CVDShimErrorSettingsRejected,
                 @"The system rejected the virtual display settings");
            return nil;
        }

        CVDVirtualDisplayShim *shim = [[CVDVirtualDisplayShim alloc] initPrivate];
        shim->_display = display;
        shim->_queue = queue;
        shim->_displayID = display.displayID;
        return shim;
    } @catch (NSException *exception) {
        display = nil;  // remove a half-configured display
        Fail(error, CVDShimErrorCreationFailed,
             [NSString stringWithFormat:@"Objective-C exception while creating the display: %@",
                                        exception.reason ?: exception.name]);
        return nil;
    }
}

- (instancetype)initPrivate {
    return [super init];
}

- (uint32_t)displayID {
    return _displayID;
}

@end
