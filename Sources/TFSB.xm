// ThermalFuse — SpringBoard 侧：只干一件事，把前台 App 的 bundle id 报出去。
// 这里写崩的代价是白苹果，所以全部逻辑压在 @try 里，不碰私有 UI。
#import "TFCore.h"

static void TFReportForeground(NSString *bid) {
    @try {
        NSDictionary *fg = @{
            @"bundle": bid ?: @"",
            @"ts": @([[NSDate date] timeIntervalSince1970]),
        };
        [fg writeToFile:TFPath(@TF_FG_PATH) atomically:YES];
        TFPostNotify(TF_NOTIFY_FG);
        TFLog(@"前台: %@", bid);
    } @catch (NSException *e) {
        TFLog(@"写前台状态异常: %@", e);
    }
}

%group FG
%hook SBApplication

- (void)didBecomeActive {
    %orig;
    @try {
        NSString *bid = [(id)self bundleIdentifier];
        if ([bid isKindOfClass:[NSString class]] && bid.length) {
            TFReportForeground(bid);
        }
    } @catch (NSException *e) {
        TFLog(@"SBApplication 异常: %@", e);
    }
}

- (void)didDeactivate {
    %orig;
    TFReportForeground(@"");
}

%end
%end

%ctor {
    TFReloadPrefs();
    if (!TFBool(@"enabled", YES)) return;
    if (!TFIsSpringBoard()) return;
    if (!objc_getClass("SBApplication")) {
        NSLog(@"[ThermalFuse] 没找到 SBApplication，前台识别不可用");
        return;
    }
    NSLog(@"[ThermalFuse] SpringBoard 侧已加载");
    %init(FG);
}
