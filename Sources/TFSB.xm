// ThermalFuse — SpringBoard 侧：只干一件事，把前台 App 的 bundle id 报出去。
// 不 hook 任何 SB 私有方法，只挂通知，最坏情况是功能失效而不是白苹果。
#define TF_PROBE 1

#import "TFCore.h"

static void TFReportForeground(NSString *bid) {
    @try {
        NSDictionary *fg = @{
            @"bundle": bid ?: @"",
            @"ts": @([[NSDate date] timeIntervalSince1970]),
        };
        [fg writeToFile:TFPath(@TF_FG_PATH) atomically:YES];
        TFPostNotify(TF_NOTIFY_FG);
        TFLog(@"前台: %@", bid.length ? bid : @"(无)");
    } @catch (NSException *e) {
        TFLog(@"写前台状态异常: %@", e);
    }
}

static void TFHandleAppNote(NSNotification *note) {
    @try {
        id app = note.object;
        NSString *bid = nil;
        if ([app isKindOfClass:[NSDictionary class]]) {
            bid = app[@"bundleIdentifier"];
        } else if (app) {
            bid = [app valueForKey:@"bundleIdentifier"];
        }
        if ([bid isKindOfClass:[NSString class]] && bid.length) {
            TFReportForeground(bid);
        }
    } @catch (NSException *e) {
        TFLog(@"通知处理异常: %@", e);
    }
}

%ctor {
    @try {
        TFReloadPrefs();
        TFWriteHeartbeat();
    } @catch (NSException *e) {
        TFEvent(@"SB 读偏好异常: %@", e);
    }

    if (!TFIsSpringBoard()) return;

#if TF_PROBE
    TFEvent(@"PROBE sb loaded pid=%d", getpid());
    return;
#endif

    // 总闸：万一 SpringBoard 侧把系统搞进安全模式，先关这里，不用卸载
    if (!TFBool(@"sbEnabled", YES)) {
        TFEvent(@"SpringBoard 侧被 sbEnabled 关掉了");
        return;
    }

    // 启动期不做任何事，延迟 2 秒再挂通知，避开 SpringBoard 初始化最乱的那段
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2ull * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        @try {
            TFEvent(@"SpringBoard 侧加载");
            for (NSString *name in @[@"SBApplicationDidBecomeActiveNotification",
                                     @"SBApplicationDidChangeForegroundNotification",
                                     @"UIApplicationDidBecomeActiveNotification"]) {
                [[NSNotificationCenter defaultCenter]
                    addObserverForName:name
                                object:nil
                                 queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *note) {
                    @try {
                        TFHandleAppNote(note);
                    } @catch (NSException *e) {
                        TFLog(@"通知处理异常: %@", e);
                    }
                }];
            }
        } @catch (NSException *e) {
            TFEvent(@"SpringBoard 初始化异常: %@", e);
        }
    });
}
