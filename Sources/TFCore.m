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
    const char *r = jbroot(p.UTF8String);
    if (!r) {
        NSLog(@"[ThermalFuse] jbroot 返回 NULL，退回原路径");
        return p;
    }
    return [NSString stringWithUTF8String:r];
#elif __has_include(<rootless.h>)
    return [NSString stringWithUTF8String:ROOT_PATH(p.UTF8String)];
#else
    return p;
#endif
}

void TFReloadPrefs(void) {
    @try {
    NSMutableDictionary *merged = [NSMutableDictionary dictionary];

    // RootHide 里那份（tweak 写的）
    NSDictionary *inJb = [NSDictionary dictionaryWithContentsOfFile:TFPath(@TF_PREFS_PATH)];
    if ([inJb isKindOfClass:[NSDictionary class]]) [merged addEntriesFromDictionary:inJb];

    // 设置面板经 cfprefsd 写的真实路径那份，优先
    NSDictionary *real = [NSDictionary dictionaryWithContentsOfFile:@TF_PREFS_PATH];
    if ([real isKindOfClass:[NSDictionary class]]) [merged addEntriesFromDictionary:real];

    gPrefs = merged;
    gVerbose = [gPrefs[@"verbose"] boolValue];
    } @catch (NSException *e) {
        NSLog(@"[ThermalFuse] 偏好读取异常: %@", e);
        gPrefs = @{};
        gVerbose = NO;
    }
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
    NSString *jb = TFPath(@TF_LIVE_PATH);
    [d writeToFile:jb atomically:YES];
    // 设置面板在沙盒里看不到 jbroot，真实路径也写一份
    if (![jb isEqualToString:@TF_LIVE_PATH]) {
        [d writeToFile:@TF_LIVE_PATH atomically:YES];
    }
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

#pragma mark - 日志文件

static dispatch_queue_t gLogQueue = NULL;
static NSDateFormatter *gLogFormatter = nil;

static NSString *TFLogTimestamp(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gLogFormatter = [[NSDateFormatter alloc] init];
        gLogFormatter.dateFormat = @"MM-dd HH:mm:ss";
    });
    @synchronized (gLogFormatter) {
        return [gLogFormatter stringFromDate:[NSDate date]];
    }
}

static void TFAppendToFile(NSString *path, NSString *line) {
    if (!path.length) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (attrs && [attrs fileSize] > 200 * 1024) {
        NSData *d = [NSData dataWithContentsOfFile:path];
        if (d.length > 100 * 1024) {
            d = [d subdataWithRange:NSMakeRange(d.length - 100 * 1024, 100 * 1024)];
        }
        [d writeToFile:path atomically:YES];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    @try {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } @catch (NSException *e) {
        NSLog(@"[ThermalFuse] 写日志失败: %@", e);
    }
}

void TFLogWrite(NSString *msg) {
    if (![msg isKindOfClass:[NSString class]] || !msg.length) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gLogQueue = dispatch_queue_create("com.lqx3617.thermalfuse.log", DISPATCH_QUEUE_SERIAL);
    });
    NSString *line = [NSString stringWithFormat:@"%@  %@\n", TFLogTimestamp(), msg];
    NSString *jb = TFPath(@TF_LOG_PATH);
    NSString *real = @TF_LOG_PATH;
    dispatch_async(gLogQueue, ^{
        TFAppendToFile(jb, line);
        if (![jb isEqualToString:real]) {
            TFAppendToFile(real, line);
        }
    });
}
