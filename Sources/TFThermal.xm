// ThermalFuse — thermalmonitord 侧：档位引擎、定时切档、自检、温控解除
#define TF_PROBE 1

#import "TFCore.h"
#import <substrate.h>
#import <objc/runtime.h>

static CommonProduct *gProduct = nil;
static MitigationController *gMitigation = nil;
static TFLevel gLevel = TFLevelAuto;
static int gMaxSeen = 0;
static int gSwitchCount = 0;
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
        // 不主动调 updateCPU/updateGPU：那些方法有线程约束，跨线程调用会 SIGBUS。
        // 档位会在系统下一次设置 ceiling 时自然生效。
        TFLog(@"档位切换 %@ -> %@", TFLevelName(old), TFLevelName(lv));
    }
}

#pragma mark - 自检

// 只用本进程自己记下来的状态，不主动调任何私有 getter：
// 那些方法在守护进程里的线程约束不明，跨线程调用是 SIGBUS 的常见来源。
static void TFSampleOnce(void) {
    NSMutableDictionary *s = [NSMutableDictionary dictionary];
    s[@"ceiling"] = @(gMaxSeen);
    s[@"level"] = TFLevelName(gLevel);
    s[@"switches"] = @(gSwitchCount);
    s[@"pid"] = @(getpid());
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
    NSDictionary *ceil = TFStats(arr, @"ceiling");

    NSString *verdict = @"系统还没给过功率上限，多用一会儿再自检";
    if (gMaxSeen > 0) {
        verdict = gSwitchCount > 0
            ? [NSString stringWithFormat:@"已拦截 %d 次功率上限设置", gSwitchCount]
            : @"hook 已挂上，但系统还没调整过功率";
    }

    NSString *text = [NSString stringWithFormat:
        @"样本 %lu 条｜档位 %@｜系统上限 %d（均值 %.0f）｜拦截 %d 次｜%@",
        (unsigned long)arr.count, TFLevelName(gLevel), gMaxSeen,
        [ceil[@"avg"] doubleValue], gSwitchCount, verdict];

    TFWriteLive(@{
        @"reportText": text,
        @"reportAt": @([[NSDate date] timeIntervalSince1970]),
        @"samples": @(arr.count),
        @"level": TFLevelName(gLevel),
        @"maxSeen": @(gMaxSeen),
        @"switchCount": @(gSwitchCount),
    });

    TFEvent(@"自检完成：%@", text);
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
    TFEvent(@"自检开始，30 秒");
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
    if (!tf_origDictWithContents) return nil;
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
    Class cls = objc_getClass("NSDictionary");
    if (!cls) return;
    Class meta = object_getClass((id)cls);
    SEL s = sel_registerName("dictionaryWithContentsOfFile:");
    if (!meta || !class_getClassMethod(cls, s)) {
        TFEvent(@"类方法 dictionaryWithContentsOfFile: 找不到，跳过");
        return;
    }
    MSHookMessageEx(meta, s, (IMP)tf_dictWithContents, (IMP *)&tf_origDictWithContents);
    if (!tf_origDictWithContents) {
        TFEvent(@"类方法 hook 失败，orig 为空，后续调用会崩，立刻撤退");
        return;
    }
    TFEvent(@"hooked NSDictionary.dictionaryWithContentsOfFile:");
}

#pragma mark - 温控解除


#pragma mark - 手动 hook：拿得到 orig 指针，能判空，缺方法就跳过

typedef void (*TFVoidFn)(id, SEL);
typedef void (*TFVoidIntFn)(id, SEL, int);
typedef void (*TFVoidIntIdFn)(id, SEL, int, id);
typedef int64_t (*TFInt64Fn)(id, SEL);
typedef id (*TFInitProductFn)(id, SEL, id);
typedef void (*TFSetIntIntFn)(id, SEL, int, int);
typedef void (*TFSetIntFn)(id, SEL, int);
typedef void (*TFSetBoolFn)(id, SEL, BOOL);

static TFInitProductFn tfOrigInitProduct = NULL;
static TFSetIntIntFn tfOrigCPUCeil = NULL;
static TFSetIntIntFn tfOrigGPUCeil = NULL;
static TFSetIntIntFn tfOrigPkgCeil = NULL;
static TFSetIntFn tfOrigMaxPkg = NULL;
static TFSetBoolFn tfOrigCPMS = NULL;

static id tf_initProduct(id self, SEL _cmd, id arg) {
    if (!tfOrigInitProduct) return nil;
    id r = tfOrigInitProduct(self, _cmd, arg);
    if (r) {
        gProduct = r;
        if (TFBool(@"forceNominal", YES)) {
            @try {
                [(CommonProduct *)r putDeviceInThermalSimulationMode:@"nominal"];
                TFLog(@"initProduct 后强制 nominal 模拟模式");
            } @catch (NSException *e) {
                TFLog(@"nominal 设置异常: %@", e);
            }
        }
    }
    return r;
}

static void tf_setCPUCeil(id self, SEL _cmd, int v, int src) {
    gMitigation = self;
    gSwitchCount++;
    if (tfOrigCPUCeil) tfOrigCPUCeil(self, _cmd, TFApplyCeiling(v), src);
}

static void tf_setGPUCeil(id self, SEL _cmd, int v, int src) {
    gMitigation = self;
    gSwitchCount++;
    if (tfOrigGPUCeil) tfOrigGPUCeil(self, _cmd, TFApplyCeiling(v), src);
}

static void tf_setPkgCeil(id self, SEL _cmd, int v, int src) {
    gMitigation = self;
    gSwitchCount++;
    if (tfOrigPkgCeil) tfOrigPkgCeil(self, _cmd, TFApplyCeiling(v), src);
}

static void tf_setMaxPkg(id self, SEL _cmd, int v) {
    gMitigation = self;
    gSwitchCount++;
    if (tfOrigMaxPkg) tfOrigMaxPkg(self, _cmd, TFApplyCeiling(v));
}

static void tf_setCPMS(id self, SEL _cmd, BOOL v) {
    if (tfOrigCPMS) tfOrigCPMS(self, _cmd, TFBool(@"blockMitigation", NO) ? NO : v);
}

static void TFInstallManualHooks(void) {
    Class prod = objc_getClass("CommonProduct");
    SEL initSel = sel_registerName("initProduct:");
    if (prod && class_getInstanceMethod(prod, initSel)) {
        MSHookMessageEx(prod, initSel, (IMP)tf_initProduct, (IMP *)&tfOrigInitProduct);
        TFEvent(@"hooked CommonProduct.initProduct:");
    } else {
        TFEvent(@"缺 CommonProduct.initProduct:，跳过");
    }

    Class c = objc_getClass("MitigationController");
    if (!c) {
        TFEvent(@"没有 MitigationController，档位引擎不生效");
        return;
    }

    SEL s1 = sel_registerName("setCPUPowerCeiling:fromDecisionSource:");
    if (class_getInstanceMethod(c, s1)) {
        MSHookMessageEx(c, s1, (IMP)tf_setCPUCeil, (IMP *)&tfOrigCPUCeil);
        TFEvent(@"hooked setCPUPowerCeiling");
    } else {
        TFEvent(@"缺 setCPUPowerCeiling");
    }

    SEL s2 = sel_registerName("setGPUPowerCeiling:fromDecisionSource:");
    if (class_getInstanceMethod(c, s2)) {
        MSHookMessageEx(c, s2, (IMP)tf_setGPUCeil, (IMP *)&tfOrigGPUCeil);
        TFEvent(@"hooked setGPUPowerCeiling");
    } else {
        TFEvent(@"缺 setGPUPowerCeiling");
    }

    SEL s3 = sel_registerName("setPackagePowerCeiling:fromDecisionSource:");
    if (class_getInstanceMethod(c, s3)) {
        MSHookMessageEx(c, s3, (IMP)tf_setPkgCeil, (IMP *)&tfOrigPkgCeil);
        TFEvent(@"hooked setPackagePowerCeiling");
    } else {
        TFEvent(@"缺 setPackagePowerCeiling");
    }

    SEL s4 = sel_registerName("setMaxPackagePower:");
    if (class_getInstanceMethod(c, s4)) {
        MSHookMessageEx(c, s4, (IMP)tf_setMaxPkg, (IMP *)&tfOrigMaxPkg);
        TFEvent(@"hooked setMaxPackagePower");
    } else {
        TFEvent(@"缺 setMaxPackagePower");
    }

    SEL s5 = sel_registerName("setCPMSMitigationsEnabled:");
    if (class_getInstanceMethod(c, s5)) {
        MSHookMessageEx(c, s5, (IMP)tf_setCPMS, (IMP *)&tfOrigCPMS);
        TFEvent(@"hooked setCPMSMitigationsEnabled");
    } else {
        TFEvent(@"缺 setCPMSMitigationsEnabled");
    }
}

#pragma mark - 温控解除 hook（手动安装，类或方法缺失就跳过，绝不 MSHookMessageEx(NULL)）

static TFVoidFn tfOrigTryAction = NULL;
static TFVoidFn tfOrigSimLight = NULL;
static TFVoidFn tfOrigUpdatePZ = NULL;
static TFVoidFn tfOrigHandleMCS = NULL;
static TFInt64Fn tfOrigPressure = NULL;
static TFVoidIntFn tfOrigSetState = NULL;
static TFVoidIntIdFn tfOrigHandleTemp = NULL;

static void tf_tryTakeAction(id self, SEL _cmd) {
    TFLog(@"tryTakeAction 拦下");
}

static void tf_simLight(id self, SEL _cmd) {
    TFLog(@"simulateLightThermalPressure 拦下");
}

static void tf_updatePZ(id self, SEL _cmd) {
}

static void tf_handleMCS(id self, SEL _cmd) {
}

static int64_t tf_pressure(id self, SEL _cmd) {
    return 0;
}

static void tf_setState(id self, SEL _cmd, int st) {
    // 故意不调原实现：原方法往内核写热状态
    (void)st;
}

static void tf_handleTemp(id self, SEL _cmd, int type, id svc) {
    (void)type;
    (void)svc;
    TFLog(@"温度事件已吞");
}

// 类存在才动，方法存在就 hook，不存在就补一个空实现
static void TFHookOrAdd(Class c, const char *selName, IMP imp, const char *types, IMP *origOut) {
    if (!c) return;
    SEL s = sel_registerName(selName);
    if (class_getInstanceMethod(c, s)) {
        IMP dummy = NULL;
        MSHookMessageEx(c, s, imp, origOut ? origOut : &dummy);
        TFEvent(@"hooked %s", selName);
    } else if (types) {
        class_addMethod(c, s, imp, types);
        TFEvent(@"补方法 %s", selName);
    } else {
        TFEvent(@"缺 %s，跳过", selName);
    }
}

static void TFInstallClassHooks(void) {
    Class prod = objc_getClass("CommonProduct");
    if (!prod) {
        TFEvent(@"没有 CommonProduct，温控解除不生效");
    } else {
        SEL initSel = sel_registerName("initProduct:");
        if (class_getInstanceMethod(prod, initSel)) {
            MSHookMessageEx(prod, initSel, (IMP)tf_initProduct, (IMP *)&tfOrigInitProduct);
            TFEvent(@"hooked CommonProduct.initProduct:");
        } else {
            TFEvent(@"缺 initProduct:，跳过");
        }

        TFHookOrAdd(prod, "tryTakeAction", (IMP)tf_tryTakeAction, "v@:", (IMP *)&tfOrigTryAction);
        TFHookOrAdd(prod, "simulateLightThermalPressure", (IMP)tf_simLight, "v@:", (IMP *)&tfOrigSimLight);
        TFHookOrAdd(prod, "updatePowerzoneTelemetry", (IMP)tf_updatePZ, "v@:", (IMP *)&tfOrigUpdatePZ);
        TFHookOrAdd(prod, "handleMCSThermalPressure", (IMP)tf_handleMCS, "v@:", (IMP *)&tfOrigHandleMCS);
        TFHookOrAdd(prod, "thermalPressureLevel", (IMP)tf_pressure, "q@:", (IMP *)&tfOrigPressure);
        TFHookOrAdd(prod, "setThermalState:", (IMP)tf_setState, "v@:i", (IMP *)&tfOrigSetState);
    }

    Class hid = objc_getClass("HidSensors");
    if (!hid) {
        TFEvent(@"没有 HidSensors，传感器屏蔽不生效");
    } else {
        TFHookOrAdd(hid, "handleTemperatureEvent:service:", (IMP)tf_handleTemp, "v@:i@", (IMP *)&tfOrigHandleTemp);
    }
}

%ctor {
    NSLog(@"[ThermalFuse] MINIMAL probe loaded in %@ pid=%d",
          [[NSProcessInfo processInfo] processName], getpid());
}
