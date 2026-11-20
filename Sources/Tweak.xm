// ThermalFuse —— 解除 iOS 温控降频
// 注入 thermalmonitord，不改内核，全靠 hook 这个守护进程的判定链。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "TFPrivate.h"

#if __has_include(<roothide.h>)
#import <roothide.h>
#define TF_ROOT(p) jbroot(p)
#elif __has_include(<rootless.h>)
#import <rootless.h>
#define TF_ROOT(p) ROOT_PATH(p)
#else
#define TF_ROOT(p) (p)
#endif

#define TF_DOMAIN "com.lqx3617.thermalfuse"
#define TF_NOTIFY "com.lqx3617.thermalfuse/reload"

static NSDictionary *gPrefs = nil;
static BOOL gVerbose = NO;
static CommonProduct *gProduct = nil;

#define TFLog(fmt, ...) \
    do { if (gVerbose) NSLog(@"[ThermalFuse] " fmt, ##__VA_ARGS__); } while (0)

static NSString *TFPath(const char *p) {
    return [NSString stringWithUTF8String:TF_ROOT(p)];
}

static void TFReloadPrefs(void) {
    NSString *path = TFPath("/var/mobile/Library/Preferences/" TF_DOMAIN ".plist");
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
    gPrefs = d ?: @{};
    gVerbose = [gPrefs[@"verbose"] boolValue];
}

static BOOL TFBool(NSString *key, BOOL def) {
    id v = gPrefs[key];
    if (!v) return def;
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v lowercaseString];
        return [s isEqualToString:@"1"] || [s isEqualToString:@"true"] ||
               [s isEqualToString:@"yes"];
    }
    return [v boolValue];
}

static long TFLong(NSString *key, long def) {
    id v = gPrefs[key];
    if ([v isKindOfClass:[NSNumber class]]) return [v longValue];
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return s.length ? (long)[s longLongValue] : def;
    }
    return def;
}

// ---- ThermalMonitor 配置改写 ----
// 系统从 /System/Library/ThermalMonitor/*.plist 读背光功率与 CPMS 参数，
// 把 BacklightBrightness / BacklightPower 的整条曲线拉平到第一档，
// 等于告诉系统「任何温度下背光都用最低功耗」，它就不会靠降频来省电了。
static id TFPatchedPlist(NSDictionary *src) {
    NSMutableDictionary *dict = [src mutableCopy];
    NSDictionary *bc = dict[@"backlightComponentControl"];
    if (![bc isKindOfClass:[NSDictionary class]]) {
        TFLog(@"plist 里没有 backlightComponentControl，跳过改写");
        return dict;
    }

    NSMutableDictionary *m = [bc mutableCopy];
    for (NSString *key in @[@"BacklightBrightness", @"BacklightPower"]) {
        NSArray *arr = m[key];
        if ([arr isKindOfClass:[NSArray class]] && arr.count > 1) {
            NSMutableArray *a = [arr mutableCopy];
            id first = a.firstObject;
            for (NSUInteger i = 1; i < a.count; i++) a[i] = first;
            m[key] = a;
            TFLog(@"%@ 曲线拉平，共 %lu 档", key, (unsigned long)a.count);
        }
    }

    m[@"expectsCPMSSupport"] = @0;

    long power = TFLong(@"cpuMaxPower", 0);
    if (power > 0) {
        m[@"maxThermalPower"] = @(power);
        m[@"minThermalPower"] = @(power);
        TFLog(@"maxThermalPower/minThermalPower = %ld", power);
    }

    dict[@"backlightComponentControl"] = m;
    return dict;
}

static id (*tf_origDictWithContents)(id, SEL, NSString *);

static id tf_dictWithContents(id self, SEL _cmd, NSString *path) {
    id result = tf_origDictWithContents(self, _cmd, path);
    if ([path isKindOfClass:[NSString class]] &&
        [path rangeOfString:@"/System/Library/ThermalMonitor/"].location != NSNotFound &&
        [result isKindOfClass:[NSDictionary class]]) {
        TFLog(@"拦截 ThermalMonitor 配置：%@", path);
        return TFPatchedPlist(result);
    }
    return result;
}

static void TFInstallDictHook(void) {
    Class meta = object_getClass((id)objc_getClass("NSDictionary"));
    if (!meta) return;
    MSHookMessageEx(meta, @selector(dictionaryWithContentsOfFile:),
                    (IMP)tf_dictWithContents,
                    (IMP *)&tf_origDictWithContents);
    TFLog(@"NSDictionary 类方法 hook 已装");
}

// ---- 主 hook：thermalmonitord 的判定链 ----
%group Core
%hook CommonProduct

- (id)initProduct:(id)arg1 {
    id r = %orig;
    if (r) {
        gProduct = r;
        if (TFBool(@"forceNominal", YES)) {
            [(CommonProduct *)r putDeviceInThermalSimulationMode:@"nominal"];
            TFLog(@"initProduct 后强制 nominal 模拟模式");
        }
    }
    return r;
}

// 这四个是降频的执行动作，留空等于让它算完不落地
- (void)tryTakeAction {
    TFLog(@"tryTakeAction 拦下");
}

- (void)simulateLightThermalPressure {
    TFLog(@"simulateLightThermalPressure 拦下");
}

- (void)updatePowerzoneTelemetry {
}

- (void)handleMCSThermalPressure {
}

// 上报给系统的压力等级永远最小
- (int64_t)thermalPressureLevel {
    return 0;
}

// 写内核的热状态永远是 0（nominal）
- (void)setThermalState:(int)a3 {
    %orig(0);
}

%end
%end

%group Sensors
%hook HidSensors

// 温度传感器的上报通道，堵住之后 thermalmonitord 收不到新温度
- (void)handleTemperatureEvent:(int)a3 service:(id)a4 {
    TFLog(@"传感器事件 pid=%d 已吞", a3);
}

%end
%end

%group Mitigation
%hook MitigationController

- (void)setCPMSMitigationsEnabled:(BOOL)a3 {
    %orig(NO);
}

- (void)updateCPU {
}

- (void)updateGPU {
}

%end
%end

static void TFOnReload(CFNotificationCenterRef center, void *observer,
                       CFStringRef name, const void *object, CFDictionaryRef info) {
    TFReloadPrefs();
    TFLog(@"偏好已重载");
}

%ctor {
    TFReloadPrefs();

    NSLog(@"[ThermalFuse] v1.0.0 loaded in thermalmonitord, enabled=%d",
          TFBool(@"enabled", YES));

    if (!TFBool(@"enabled", YES)) return;

    %init(Core);

    if (TFBool(@"blockSensorEvents", YES)) {
        %init(Sensors);
    }
    if (TFBool(@"blockMitigation", NO)) {
        %init(Mitigation);
    }
    if (TFBool(@"patchThermalPlist", YES)) {
        TFInstallDictHook();
    }

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL, TFOnReload,
                                    CFSTR(TF_NOTIFY), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
