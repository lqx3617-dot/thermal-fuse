// ThermalFuse — SpringBoard 侧
// 只挂通知，不 hook 任何私有方法：这里崩的代价是整个安全模式。
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
        TFEvent(@"SB loaded pid=%d", getpid());
    } @catch (NSException *e) {
        NSLog(@"[ThermalFuse] SB 初始化异常: %@", e);
    }

    if (!TFIsSpringBoard()) return;

    if (!TFBool(@"sbEnabled", YES)) {
        NSLog(@"[ThermalFuse] SpringBoard 侧被 sbEnabled 关掉");
        return;
    }

    // 延迟挂通知，避开 SpringBoard 启动最乱的那两秒
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2ull * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        @try {
            NSLog(@"[ThermalFuse] SpringBoard 通知已挂");
            for (NSString *name in @[@"SBApplicationDidBecomeActiveNotification",
                                     @"SBApplicationDidChangeForegroundNotification",
                                     @"UIApplicationDidBecomeActiveNotification"]) {
                [[NSNotificationCenter defaultCenter]
                    addObserverForName:name
                                object:nil
                                 queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *note) {
                    TFHandleAppNote(note);
                }];
            }
        } @catch (NSException *e) {
            NSLog(@"[ThermalFuse] SpringBoard 挂通知异常: %@", e);
        }
    });
}
