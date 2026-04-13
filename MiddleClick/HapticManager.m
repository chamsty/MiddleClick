#import "HapticManager.h"

#import <IOKit/IOReturn.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <os/log.h>

static const int64_t kMiddleClickHapticDelayNanos = 50 * NSEC_PER_MSEC;
static NSString * const kHapticActuationIDDefaultsKey = @"hapticActuationID";
static NSString * const kHapticUnknown2DefaultsKey = @"hapticUnknown2";
static NSString * const kHapticUnknown3DefaultsKey = @"hapticUnknown3";
static const int32_t kDefaultPrivateTrackpadActuationID = 4;
static const float kDefaultPrivateTrackpadUnknown2 = 0.0f;
static const float kDefaultPrivateTrackpadUnknown3 = 0.05f;

typedef CFMutableArrayRef (*MTDeviceCreateListFn)(void);
typedef CFTypeRef (*MTDeviceGetMTActuatorFn)(CFTypeRef device);
typedef IOReturn (*MTActuatorRequestHostClickControlFn)(CFTypeRef actuator);
typedef IOReturn (*MTActuatorHandoffHostClickControlFn)(CFTypeRef actuator);
typedef IOReturn (*MTActuatorReclaimHostClickControlFn)(CFTypeRef actuator);
typedef IOReturn (*MTActuatorOpenFn)(CFTypeRef actuator);
typedef IOReturn (*MTActuatorCloseFn)(CFTypeRef actuator);
typedef IOReturn (*MTActuatorActuateFn)(
  CFTypeRef actuator, int32_t actuationID, uint32_t unknown1, float unknown2, float unknown3
);

typedef struct {
  MTDeviceCreateListFn createDeviceList;
  MTDeviceGetMTActuatorFn getActuator;
  MTActuatorRequestHostClickControlFn requestHostClickControl;
  MTActuatorHandoffHostClickControlFn handoffHostClickControl;
  MTActuatorReclaimHostClickControlFn reclaimHostClickControl;
  MTActuatorOpenFn open;
  MTActuatorCloseFn close;
  MTActuatorActuateFn actuate;
  bool isResolved;
  bool canUsePrivateActuator;
} PrivateActuatorAPI;

static PrivateActuatorAPI privateActuatorAPI;
static os_log_t hapticLog;

// These private actuator controls are empirical tuning values discovered by local testing.
static NSInteger integerPreference(NSString *key, NSInteger defaultValue) {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  return [defaults objectForKey:key] == nil ? defaultValue : [defaults integerForKey:key];
}

static float floatPreference(NSString *key, float defaultValue) {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  return [defaults objectForKey:key] == nil ? defaultValue : [defaults floatForKey:key];
}

static int32_t currentPrivateTrackpadActuationID(void) {
  NSInteger rawValue = integerPreference(
    kHapticActuationIDDefaultsKey,
    kDefaultPrivateTrackpadActuationID
  );
  rawValue = MAX(1, MIN(16, rawValue));
  return (int32_t)rawValue;
}

static float currentPrivateTrackpadUnknown2(void) {
  float rawValue = floatPreference(kHapticUnknown2DefaultsKey, kDefaultPrivateTrackpadUnknown2);
  return MAX(0.0f, MIN(1.0f, rawValue));
}

static float currentPrivateTrackpadUnknown3(void) {
  float rawValue = floatPreference(kHapticUnknown3DefaultsKey, kDefaultPrivateTrackpadUnknown3);
  return MAX(0.0f, MIN(1.0f, rawValue));
}

static void initializeHapticLog(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *subsystem = NSBundle.mainBundle.bundleIdentifier ?: @"MiddleClick";
    hapticLog = os_log_create(subsystem.UTF8String, "haptics");
  });
}

static void resolvePrivateActuatorAPI(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    privateActuatorAPI.createDeviceList =
      (MTDeviceCreateListFn)dlsym(RTLD_DEFAULT, "MTDeviceCreateList");
    privateActuatorAPI.getActuator =
      (MTDeviceGetMTActuatorFn)dlsym(RTLD_DEFAULT, "MTDeviceGetMTActuator");
    privateActuatorAPI.requestHostClickControl =
      (MTActuatorRequestHostClickControlFn)dlsym(RTLD_DEFAULT, "MTActuatorRequestHostClickControl");
    privateActuatorAPI.handoffHostClickControl =
      (MTActuatorHandoffHostClickControlFn)dlsym(RTLD_DEFAULT, "MTActuatorHandoffHostClickControl");
    privateActuatorAPI.reclaimHostClickControl =
      (MTActuatorReclaimHostClickControlFn)dlsym(RTLD_DEFAULT, "MTActuatorReclaimHostClickControl");
    privateActuatorAPI.open = (MTActuatorOpenFn)dlsym(RTLD_DEFAULT, "MTActuatorOpen");
    privateActuatorAPI.close = (MTActuatorCloseFn)dlsym(RTLD_DEFAULT, "MTActuatorClose");
    privateActuatorAPI.actuate = (MTActuatorActuateFn)dlsym(RTLD_DEFAULT, "MTActuatorActuate");
    privateActuatorAPI.isResolved = true;
    privateActuatorAPI.canUsePrivateActuator =
      privateActuatorAPI.createDeviceList != NULL &&
      privateActuatorAPI.getActuator != NULL &&
      privateActuatorAPI.open != NULL &&
      privateActuatorAPI.close != NULL &&
      privateActuatorAPI.actuate != NULL;
  });
}

static bool tryPrivateActuatorPulse(void) {
  initializeHapticLog();
  resolvePrivateActuatorAPI();

  if (!privateActuatorAPI.canUsePrivateActuator) {
    os_log_debug(hapticLog, "Private actuator symbols are unavailable.");
    return false;
  }

  CFMutableArrayRef devices = privateActuatorAPI.createDeviceList();
  if (!devices) {
    os_log_debug(hapticLog, "No multitouch devices available for private actuator pulse.");
    return false;
  }

  bool didActuate = false;
  CFIndex deviceCount = CFArrayGetCount(devices);
  int32_t actuationID = currentPrivateTrackpadActuationID();
  float unknown2 = currentPrivateTrackpadUnknown2();
  float unknown3 = currentPrivateTrackpadUnknown3();

  for (CFIndex index = 0; index < deviceCount; index++) {
    CFTypeRef device = (CFTypeRef)CFArrayGetValueAtIndex(devices, index);
    if (!device) { continue; }

    CFTypeRef actuator = privateActuatorAPI.getActuator(device);
    if (!actuator) { continue; }

    bool requestedHostClickControl = false;
    if (privateActuatorAPI.requestHostClickControl != NULL) {
      IOReturn requestError = privateActuatorAPI.requestHostClickControl(actuator);
      requestedHostClickControl = requestError == kIOReturnSuccess;
    }

    IOReturn openError = privateActuatorAPI.open(actuator);
    if (openError != kIOReturnSuccess) {
      os_log_debug(
        hapticLog,
        "Private actuator open failed with error %{public}d.",
        openError
      );

      if (requestedHostClickControl) {
        if (privateActuatorAPI.handoffHostClickControl != NULL) {
          privateActuatorAPI.handoffHostClickControl(actuator);
        } else if (privateActuatorAPI.reclaimHostClickControl != NULL) {
          privateActuatorAPI.reclaimHostClickControl(actuator);
        }
      }

      continue;
    }

    IOReturn actuationError = privateActuatorAPI.actuate(
      actuator,
      actuationID,
      0,
      unknown2,
      unknown3
    );
    IOReturn closeError = privateActuatorAPI.close(actuator);

    if (requestedHostClickControl) {
      if (privateActuatorAPI.handoffHostClickControl != NULL) {
        privateActuatorAPI.handoffHostClickControl(actuator);
      } else if (privateActuatorAPI.reclaimHostClickControl != NULL) {
        privateActuatorAPI.reclaimHostClickControl(actuator);
      }
    }

    if (closeError != kIOReturnSuccess) {
      os_log_debug(
        hapticLog,
        "Private actuator close returned error %{public}d.",
        closeError
      );
    }

    if (actuationError == kIOReturnSuccess) {
      didActuate = true;
      break;
    }

    os_log_debug(
      hapticLog,
      "Private actuator pulse failed with error %{public}d.",
      actuationError
    );
  }

  CFRelease(devices);
  return didActuate;
}

void triggerHapticForMiddleClick(void) {
  dispatch_after(
    dispatch_time(DISPATCH_TIME_NOW, kMiddleClickHapticDelayNanos),
    dispatch_get_main_queue(), ^{
      tryPrivateActuatorPulse();
    }
  );
}
