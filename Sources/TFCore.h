// ThermalFuse 共享层：偏好、路径、档位、跨进程状态
#import <Foundation/Foundation.h>
#import "TFPrivate.h"

#define TF_DOMAIN   "com.lqx3617.thermalfuse"
#define TF_PREFS_PATH "/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.plist"
#define TF_LIVE_PATH  "/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.live.plist"
#define TF_FG_PATH    "/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.fg.plist"

#define TF_NOTIFY_RELOAD  "com.lqx3617.thermalfuse/reload"
#define TF_NOTIFY_FG      "com.lqx3617.thermalfuse/foreground"
#define TF_NOTIFY_SELFTEST "com.lqx3617.thermalfuse/selftest"

typedef NS_ENUM(NSInteger, TFLevel) {
    TFLevelAuto = 0,
    TFLevelLow  = 1,
    TFLevelMax  = 2,
};

extern BOOL gVerbose;

#define TFLog(fmt, ...) \
    do { if (gVerbose) NSLog(@"[ThermalFuse] " fmt, ##__VA_ARGS__); } while (0)

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
