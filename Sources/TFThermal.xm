// ThermalFuse — thermalmonitord 侧：档位引擎、定时切档、自检、温控解除
#import "TFCore.h"
#import <objc/runtime.h>

static CommonProduct *gProduct = nil;
static MitigationController *gMitigation = nil;
static TFLevel gLevel = TFLevelAuto;
static int gMaxSeen = 0;
static dispatch_source_t gTickTimer = nil;
static dispatch_source_t gTestTimer = nil;
static NSMutableArray *gSamples = nil;

#pragma mark - 档位计算

static double TFRatio(void) {
    double r = (double)TFLong(@"lowRatio", 40) / 100.0;
    if (r < 0.05) r = 0.05;
    if (r > 1.0) r = 1.0;
    return r;
}

// 不改绝对数值，只做「相对系统自己给出的上限」的放大/缩小，
// 换机型不用重填功率。gMaxSeen 是运行期间见过的最大的 ceiling。
static int TFApplyCeiling(int ceil) {
    if (ceil > gMaxSeen) gMaxSeen = ceil;
    if (gLevel == TFLevelMax) {
        return gMaxSeen > 0 ? gMaxSeen : ceil;
    }
    if (gLevel == TFLevelLow) {
        int base = gMaxSeen > 0 ? gMaxSeen : ceil;
        int v = (int)((double)base * TFRatio());
        return v > 0 ? v : ceil;
    }
    return ceil;
}

static int TFMinutes(NSString *hm) {
    NSArray *p = [hm componentsSeparatedByString:@":"];
    if (p.count < 2) return -1;
    int h = [p[0] intValue];
    int m = [p[1] intValue];
    if (h < 0 || h > 23 || m < 0 || m > 59) return -1;
    return h * 60 + m;
}

// 格式：08:00-22:00=max;23:00-07:00=low
static TFLevel TFLevelForSchedule(void) {
    NSString *s = TFStr(@"schedule", @"");
    if (!s.length) return TFLevelAuto;

    NSDateComponents *c = [[NSCalendar currentCalendar]
        components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
    int now = (int)c.hour * 60 + (int)c.minute;

    for (NSString *item in [s componentsSeparatedByString:@";"]) {
        NSArray *kv = [item componentsSeparatedByString:@"="];
        if (kv.count != 2) continue;
        NSArray *span = [kv[0] componentsSeparatedByString:@"-"];
        if (span.count != 2) continue;
        int a = TFMinutes(span[0]);
        int b = TFMinutes(span[1]);
        if (a < 0 || b < 0) continue;
        BOOL hit = (a <= b) ? (now >= a && now < b) : (now >= a || now < b);
        if (hit) {
            return TFLevelFromString(kv[1]);
        }
    }
    return TFLevelAuto;
}

static NSString *TFForegroundBundle(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:TFPath(@TF_FG_PATH)];
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    double ts = [d[@"ts"] doubleValue];
    if ([[NSDate date] timeIntervalSince1970] - ts > 45) return nil;
    NSString *b = d[@"bundle"];
    return [b isKindOfClass:[NSString class]] ? b : nil;
}

static BOOL TFIsGame(NSString *bid) {
    if (!bid.length) return NO;
    NSString *games = TFStr(@"games", @"");
    if (!games.length) return NO;
    for (NSString *g in [games componentsSeparatedByString:@","]) {
        NSString *t = [g stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length && [bid hasPrefix:t]) return YES;
    }
    return NO;
}

static void TFResolveAndApply(void) {
    TFLevel old = gLevel;
    TFLevel lv = TFLevelFromString(TFStr(@"level", @"auto"));

    TFLevel sched = TFLevelForSchedule();
    if (sched != TFLevelAuto) {
        lv = sched;
    } else if (TFIsGame(TFForegroundBundle())) {
        lv = TFLevelMax;
    }

    gLevel = lv;
    if (old != lv) {
        TFLog(@"档位切换 %@ -> %@", TFLevelName(old), TFLevelName(lv));
        @try {
            if ([gMitigation respondsToSelector:@selector(updateCPU)]) [gMitigation updateCPU];
            if ([gMitigation respondsToSelector:@selector(updateGPU)]) [gMitigation updateGPU];
            if ([gMitigation respondsToSelector:@selector(updatePackage)]) [gMitigation updatePackage];
        } @catch (NSException *e) {
            TFLog(@"触发重算异常: %@", e);
        }
    }
}

#pragma mark - 自检

static void TFSampleOnce(void) {
    if (!gMitigation) return;
    NSMutableDictionary *s = [NSMutableDictionary dictionary];
    @try {
        if ([gMitigation respondsToSelector:@selector(getCurrentCPUPower)])
            s[@"cpu"] = @([gMitigation getCurrentCPUPower]);
        if ([gMitigation respondsToSelector:@selector(getCurrentGPUPower)])
            s[@"gpu"] = @([gMitigation getCurrentGPUPower]);
        if ([gMitigation respondsToSelector:@selector(getCurrentPackagePower)])
            s[@"pkg"] = @([gMitigation getCurrentPackagePower]);
    } @catch (NSException *e) {}
    @try {
        if ([gProduct respondsToSelector:@selector(gasGaugeBatteryTemperature)])
            s[@"batT"] = @([gProduct gasGaugeBatteryTemperature]);
        if ([gProduct respondsToSelector:@selector(arcVirtualTemperature)])
            s[@"socT"] = @([gProduct arcVirtualTemperature]);
    } @catch (NSException *e) {}

    s[@"level"] = TFLevelName(gLevel);
    s[@"t"] = @([[NSDate date] timeIntervalSince1970]);

    if (!gSamples) gSamples = [NSMutableArray array];
    [gSamples addObject:s];
}

static NSDictionary *TFStats(NSArray *samples, NSString *key) {
    long long sum = 0, peak = 0;
    int n = 0;
    for (NSDictionary *s in samples) {
        id v = s[key];
        if (![v isKindOfClass:[NSNumber class]]) continue;
        long long x = [v longLongValue];
        sum += x;
        if (x > peak) peak = x;
        n++;
    }
    if (!n) return @{@"avg": @0, @"peak": @0, @"n": @0};
    return @{@"avg": @(sum / n), @"peak": @(peak), @"n": @(n)};
}

static void TFFinishSelfTest(void) {
    NSArray *arr = [gSamples copy] ?: @[];
    NSDictionary *cpu = TFStats(arr, @"cpu");
    NSDictionary *pkg = TFStats(arr, @"pkg");
    NSDictionary *bat = TFStats(arr, @"batT");

    NSString *verdict = @"数据不足";
    if ([pkg[@"n"] intValue] > 3 && gMaxSeen > 0) {
        double avg = [pkg[@"avg"] doubleValue];
        if (avg < gMaxSeen * 0.5) {
            verdict = @"系统在压功率，建议开满频档";
        } else if (avg > gMaxSeen * 0.9) {
            verdict = @"已接近功率上限，档位正常";
        } else {
            verdict = @"负载中等，功率未触顶";
        }
    }

    NSString *text = [NSString stringWithFormat:
        @"样本 %lu 条｜CPU 平均 %@ 峰值 %@｜包 平均 %@ 峰值 %@｜电池 %@｜档位 %@｜上限 %d｜%@",
        (unsigned long)arr.count, cpu[@"avg"], cpu[@"peak"],
        pkg[@"avg"], pkg[@"peak"], bat[@"avg"],
        TFLevelName(gLevel), gMaxSeen, verdict];

    TFWriteLive(@{
        @"reportText": text,
        @"reportAt": @([[NSDate date] timeIntervalSince1970]),
        @"samples": @(arr.count),
        @"level": TFLevelName(gLevel),
        @"maxSeen": @(gMaxSeen),
    });

    NSLog(@"[ThermalFuse] 自检完成：%@", text);
}

static void TFStartSelfTest(void) {
    if (gTestTimer) {
        dispatch_source_cancel(gTestTimer);
        gTestTimer = nil;
    }
    gSamples = [NSMutableArray array];

    __block int n = 0;
    gTestTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    dispatch_source_set_timer(gTestTimer,
        dispatch_time(DISPATCH_TIME_NOW, 0),
        2ull * NSEC_PER_SEC,
        500ull * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gTestTimer, ^{
        TFSampleOnce();
        n++;
        if (n >= 15) {
            dispatch_source_cancel(gTestTimer);
            gTestTimer = nil;
            TFFinishSelfTest();
            TFPostNotify(TF_NOTIFY_RELOAD);
        }
    });
    dispatch_resume(gTestTimer);
    NSLog(@"[ThermalFuse] 自检开始，30 秒");
}

static void TFStartTick(void) {
    if (gTickTimer) return;
    gTickTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    dispatch_source_set_timer(gTickTimer,
        dispatch_time(DISPATCH_TIME_NOW, 3ull * NSEC_PER_SEC),
        20ull * NSEC_PER_SEC,
        3ull * NSEC_PER_SEC);
    dispatch_source_set_event_handler(gTickTimer, ^{
        TFReloadPrefs();
        TFResolveAndApply();
    });
    dispatch_resume(gTickTimer);
}

static void TFOnNotify(CFNotificationCenterRef center, void *observer,
                       CFStringRef name, const void *object, CFDictionaryRef info) {
    NSString *n = (__bridge NSString *)name;
    TFReloadPrefs();
    if ([n isEqualToString:@TF_NOTIFY_SELFTEST]) {
        TFStartSelfTest();
    }
    TFResolveAndApply();
}

#pragma mark - ThermalMonitor 配置改写

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

#pragma mark - 温控解除

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

- (int64_t)thermalPressureLevel {
    return 0;
}

- (void)setThermalState:(int)a3 {
    %orig(0);
}

%end
%end

%group Sensors
%hook HidSensors

- (void)handleTemperatureEvent:(int)a3 service:(id)a4 {
    TFLog(@"传感器事件 type=%d 已吞", a3);
}

%end
%end

%group Mitigation
%hook MitigationController

- (void)setCPUPowerCeiling:(int)a3 fromDecisionSource:(int)a4 {
    gMitigation = self;
    %orig(TFApplyCeiling(a3), a4);
}

- (void)setGPUPowerCeiling:(int)a3 fromDecisionSource:(int)a4 {
    gMitigation = self;
    %orig(TFApplyCeiling(a3), a4);
}

- (void)setPackagePowerCeiling:(int)a3 fromDecisionSource:(int)a4 {
    gMitigation = self;
    %orig(TFApplyCeiling(a3), a4);
}

- (void)setMaxPackagePower:(int)a3 {
    gMitigation = self;
    %orig(TFApplyCeiling(a3));
}

- (void)setCPMSMitigationsEnabled:(BOOL)a3 {
    %orig(TFBool(@"blockMitigation", NO) ? NO : a3);
}

%end
%end

%ctor {
    TFReloadPrefs();
    NSLog(@"[ThermalFuse] 1.1.0 loaded in %@", [[NSProcessInfo processInfo] processName]);

    if (!TFIsThermalmonitord()) return;
    if (!TFBool(@"enabled", YES)) return;

    %init(Core);

    if (TFBool(@"blockSensorEvents", YES)) {
        %init(Sensors);
    }

    %init(Mitigation);

    if (TFBool(@"patchThermalPlist", YES)) {
        TFInstallDictHook();
    }

    TFStartTick();

    if (TFBool(@"selfTestOnStart", YES)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6ull * NSEC_PER_SEC),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            TFStartSelfTest();
        });
    }

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL, TFOnNotify,
                                    CFSTR(TF_NOTIFY_RELOAD), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL, TFOnNotify,
                                    CFSTR(TF_NOTIFY_SELFTEST), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
