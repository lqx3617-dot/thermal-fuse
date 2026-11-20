// ThermalFuse — SpringBoard 侧：只干一件事，把前台 App 的 bundle id 报出去。
// 不 hook 任何 SB 私有方法，只挂通知，最坏情况是功能失效而不是白苹果。
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
    TFReloadPrefs();
    if (!TFBool(@"enabled", YES)) return;
    if (!TFIsSpringBoard()) return;

    NSLog(@"[ThermalFuse] SpringBoard 侧加载");

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
}
