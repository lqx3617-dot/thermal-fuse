// ThermalFuse 共享层实现
#import "TFCore.h"

#if __has_include(<roothide.h>)
#import <roothide.h>
#elif __has_include(<rootless.h>)
#import <rootless.h>
#endif

BOOL gVerbose = NO;
static NSDictionary *gPrefs = nil;

NSString *TFPath(NSString *p) {
    if (!p.length) return p;
#if __has_include(<roothide.h>)
    return [NSString stringWithUTF8String:jbroot(p.UTF8String)];
#elif __has_include(<rootless.h>)
    return [NSString stringWithUTF8String:ROOT_PATH(p.UTF8String)];
#else
    return p;
#endif
}

void TFReloadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:TFPath(@TF_PREFS_PATH)];
    gPrefs = [d isKindOfClass:[NSDictionary class]] ? d : @{};
    gVerbose = [gPrefs[@"verbose"] boolValue];
}

NSDictionary *TFPrefs(void) {
    if (!gPrefs) TFReloadPrefs();
    return gPrefs ?: @{};
}

BOOL TFBool(NSString *key, BOOL def) {
    id v = TFPrefs()[key];
    if (!v) return def;
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v lowercaseString];
        return [s isEqualToString:@"1"] || [s isEqualToString:@"true"] || [s isEqualToString:@"yes"];
    }
    return [v boolValue];
}

long TFLong(NSString *key, long def) {
    id v = TFPrefs()[key];
    if ([v isKindOfClass:[NSNumber class]]) return [v longValue];
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return s.length ? (long)[s longLongValue] : def;
    }
    return def;
}

NSString *TFStr(NSString *key, NSString *def) {
    id v = TFPrefs()[key];
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return def;
}

void TFWriteLive(NSDictionary *d) {
    if (![d isKindOfClass:[NSDictionary class]]) return;
    [d writeToFile:TFPath(@TF_LIVE_PATH) atomically:YES];
}

void TFPostNotify(const char *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)[NSString stringWithUTF8String:name],
                                         NULL, NULL, true);
}

BOOL TFIsSpringBoard(void) {
    return [[[NSProcessInfo processInfo] processName] isEqualToString:@"SpringBoard"];
}

BOOL TFIsThermalmonitord(void) {
    return [[[NSProcessInfo processInfo] processName] isEqualToString:@"thermalmonitord"];
}

TFLevel TFLevelFromString(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return TFLevelAuto;
    NSString *t = [[s stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([t isEqualToString:@"max"] || [t isEqualToString:@"performance"] ||
        [t isEqualToString:@"high"]) return TFLevelMax;
    if ([t isEqualToString:@"low"] || [t isEqualToString:@"powersave"] ||
        [t isEqualToString:@"eco"]) return TFLevelLow;
    return TFLevelAuto;
}

NSString *TFLevelName(TFLevel l) {
    switch (l) {
        case TFLevelMax: return @"max";
        case TFLevelLow: return @"low";
        default: return @"auto";
    }
}
