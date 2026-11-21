// ThermalFuse 共享层：偏好、路径、档位、跨进程状态
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "TFPrivate.h"

#define TF_DOMAIN   "com.lqx3617.thermalfuse"
#define TF_PREFS_PATH "/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.plist"
#define TF_LIVE_PATH  "/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.live.plist"
#define TF_FG_PATH    "/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.fg.plist"
#define TF_LOG_PATH   "/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.log"

#define TF_NOTIFY_RELOAD  "com.lqx3617.thermalfuse/reload"
#define TF_NOTIFY_FG      "com.lqx3617.thermalfuse/foreground"
#define TF_NOTIFY_SELFTEST "com.lqx3617.thermalfuse/selftest"

typedef NS_ENUM(NSInteger, TFLevel) {
    TFLevelAuto = 0,
    TFLevelLow  = 1,
    TFLevelMax  = 2,
};

#ifdef __cplusplus
extern "C" {
#endif

extern BOOL gVerbose;


// 关键事件：始终写日志文件 + syslog
void TFLogWrite(NSString *msg);
#define TFEvent(fmt, ...) TFLogWrite([NSString stringWithFormat:fmt, ##__VA_ARGS__])

// 高频细节：只在 verbose 打开时才记
#define TFLog(fmt, ...) \
    do { if (gVerbose) { NSLog(@"[ThermalFuse] " fmt, ##__VA_ARGS__); \
         TFLogWrite([NSString stringWithFormat:fmt, ##__VA_ARGS__]); } } while (0)

NSString *TFPath(NSString *p);
void TFReloadPrefs(void);
NSDictionary *TFPrefs(void);
BOOL TFBool(NSString *key, BOOL def);
long TFLong(NSString *key, long def);
NSString *TFStr(NSString *key, NSString *def);
void TFWriteLive(NSDictionary *d);
void TFPostNotify(const char *name);

BOOL TFIsSpringBoard(void);
BOOL TFIsThermalmonitord(void);

TFLevel TFLevelFromString(NSString *s);
NSString *TFLevelName(TFLevel l);

#ifdef __cplusplus
}
#endif
