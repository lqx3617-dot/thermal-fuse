// ThermalFuse 设置面板
// 自绘 UITableView（insetGrouped），不依赖 Preferences 私有头，
// 视觉全部走系统语义色与动态字体，深色模式自动适配。
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "TFPrefsRootListController.h"

#pragma mark - 偏好读写

static NSString *const kDomain   = @"com.lqx3617.thermalfuse";
static NSString *const kLivePath = @"/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.live.plist";

static id TFRead(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)kDomain);
    return v ? CFBridgingRelease(v) : nil;
}

static void TFWrite(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFTypeRef)value,
                             (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
}

static BOOL TFBool(NSString *key, BOOL def) {
    id v = TFRead(key);
    return v ? [v boolValue] : def;
}

static NSString *TFString(NSString *key, NSString *def) {
    id v = TFRead(key);
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return def;
}

static void TFNotify(const char *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)[NSString stringWithUTF8String:name], NULL, NULL, true);
}

static void TFApplyNow(void) {
    TFNotify("com.lqx3617.thermalfuse/reload");
}

static NSDictionary *TFLive(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kLivePath];
    return [d isKindOfClass:[NSDictionary class]] ? d : nil;
}

static NSString *TFLevelText(NSString *raw) {
    if ([raw isEqualToString:@"max"]) return @"满频";
    if ([raw isEqualToString:@"low"]) return @"低功耗";
    return @"智能";
}

static UIColor *TFLevelColor(NSString *raw) {
    if ([raw isEqualToString:@"max"]) return UIColor.systemOrangeColor;
    if ([raw isEqualToString:@"low"]) return UIColor.systemGreenColor;
    return UIColor.systemBlueColor;
}

static CGFloat TFLevelRatio(NSString *raw) {
    if ([raw isEqualToString:@"max"]) return 1.0;
    if ([raw isEqualToString:@"low"]) {
        long r = [TFString(@"lowRatio", @"40") integerValue];
        return MAX(0.05, MIN(1.0, r / 100.0));
    }
    return 0.6;
}

@interface TFLogController : UIViewController
@property (nonatomic, strong) UITextView *textView;
@end

#pragma mark - 状态卡片

@interface TFCardCell : UITableViewCell
@property (nonatomic, strong) UILabel *levelLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *reportLabel;
@property (nonatomic, strong) UIView *track;
@property (nonatomic, strong) UIView *fill;
@property (nonatomic, assign) CGFloat ratio;
@end

@implementation TFCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

    _levelLabel = [UILabel new];
    _levelLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
    _levelLabel.adjustsFontForContentSizeCategory = YES;

    _metaLabel = [UILabel new];
    _metaLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _metaLabel.textColor = UIColor.secondaryLabelColor;
    _metaLabel.adjustsFontForContentSizeCategory = YES;
    _metaLabel.textAlignment = NSTextAlignmentRight;

    _track = [UIView new];
    _track.backgroundColor = UIColor.tertiarySystemFillColor;
    _track.layer.cornerRadius = 4;
    _track.clipsToBounds = YES;

    _fill = [UIView new];
    [_track addSubview:_fill];

    _reportLabel = [UILabel new];
    _reportLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _reportLabel.textColor = UIColor.secondaryLabelColor;
    _reportLabel.numberOfLines = 0;
    _reportLabel.adjustsFontForContentSizeCategory = YES;

    for (UIView *v in @[_levelLabel, _metaLabel, _track, _reportLabel]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:v];
    }

    UILayoutGuide *g = self.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_levelLabel.topAnchor constraintEqualToAnchor:g.topAnchor constant:6],
        [_levelLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [_metaLabel.firstBaselineAnchor constraintEqualToAnchor:_levelLabel.firstBaselineAnchor],
        [_metaLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_levelLabel.trailingAnchor constant:12],
        [_metaLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [_track.topAnchor constraintEqualToAnchor:_levelLabel.bottomAnchor constant:12],
        [_track.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [_track.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [_track.heightAnchor constraintEqualToConstant:8],
        [_reportLabel.topAnchor constraintEqualToAnchor:_track.bottomAnchor constant:10],
        [_reportLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [_reportLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [_reportLabel.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-6],
    ]];
    return self;
}

- (void)setRatio:(CGFloat)ratio {
    _ratio = MAX(0, MIN(1, ratio));
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.track.bounds.size.height;
    CGFloat w = self.track.bounds.size.width * self.ratio;
    self.fill.frame = CGRectMake(0, 0, w, h);
    self.fill.layer.cornerRadius = h / 2;
}

@end

#pragma mark - 档位分段

@interface TFSegmentCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, copy) void (^onChange)(NSInteger index);
@end

@implementation TFSegmentCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _titleLabel.adjustsFontForContentSizeCategory = YES;

    _seg = [[UISegmentedControl alloc] initWithItems:@[@"智能", @"低功耗", @"满频"]];
    [_seg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];

    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _seg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_titleLabel];
    [self.contentView addSubview:_seg];

    UILayoutGuide *g = self.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.topAnchor constraintEqualToAnchor:g.topAnchor constant:10],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [_seg.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:10],
        [_seg.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [_seg.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [_seg.heightAnchor constraintEqualToConstant:32],
        [_seg.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-10],
    ]];
    return self;
}

- (void)segChanged {
    if (self.onChange) self.onChange(self.seg.selectedSegmentIndex);
}

@end

#pragma mark - 开关行

@interface TFSwitchCell : UITableViewCell
@property (nonatomic, strong) UISwitch *sw;
@property (nonatomic, copy) void (^onToggle)(BOOL on);
@end

@implementation TFSwitchCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    _sw = [UISwitch new];
    [_sw addTarget:self action:@selector(toggled) forControlEvents:UIControlEventValueChanged];
    self.accessoryView = _sw;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    return self;
}

- (void)toggled {
    if (self.onToggle) self.onToggle(self.sw.isOn);
}

@end

@implementation TFPrefsRootListController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"温控解除";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = UITableViewAutomaticDimension;
    self.table.estimatedRowHeight = 60;
    self.table.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self buildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self buildSections];
    [self.table reloadData];
}

- (void)buildSections {
    self.sections = @[
        @{@"rows": @[@{@"type": @"card"}]},
        @{@"header": @"档位",
          @"footer": @"满频 = 按系统给过的最高功率上限跑；低功耗 = 按比例压；智能 = 不干预，只受下面的场景规则影响。",
          @"rows": @[
              @{@"type": @"segment"},
              @{@"type": @"value", @"title": @"低功耗比例", @"key": @"lowRatio", @"unit": @"%", @"numeric": @YES},
          ]},
        @{@"header": @"场景",
          @"footer": @"游戏按 bundle id 前缀匹配，多个用英文逗号隔开。时间表写法 08:00-22:00=max;23:00-07:00=low，留空不启用。",
          @"rows": @[
              @{@"type": @"value", @"title": @"游戏 bundle 前缀", @"key": @"games"},
              @{@"type": @"value", @"title": @"定时时间表", @"key": @"schedule"},
          ]},
        @{@"header": @"自检",
          @"footer": @"采样 15 次共 30 秒，统计功率与温度，结论写在下面的卡片里。",
          @"rows": @[
              @{@"type": @"button", @"title": @"立即自检", @"action": @"selftest"},
              @{@"type": @"switch", @"title": @"启动后自动自检", @"key": @"selfTestOnStart", @"def": @YES},
          ]},
        @{@"footer": @"温控解除的每一项都能单独关，出问题先来这里排查。",
          @"rows": @[
              @{@"type": @"nav", @"title": @"运行日志", @"action": @"log"},
              @{@"type": @"nav", @"title": @"高级设置", @"action": @"advanced"},
          ]},
    ];
}

#pragma mark 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *rows = self.sections[section][@"rows"];
    return rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"header"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.sections[section][@"footer"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSString *type = row[@"type"];

    if ([type isEqualToString:@"card"]) {
        static NSString *cid = @"card";
        TFCardCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell) cell = [[TFCardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];

        NSString *level = TFString(@"level", @"auto");
        NSDictionary *live = TFLive();
        NSNumber *maxSeen = live[@"maxSeen"];

        cell.levelLabel.text = TFLevelText(level);
        cell.levelLabel.textColor = TFLevelColor(level);
        cell.metaLabel.text = maxSeen ? [NSString stringWithFormat:@"上限 %@", maxSeen] : @"上限学习中";
        cell.fill.backgroundColor = TFLevelColor(level);
        cell.ratio = TFLevelRatio(level);
        cell.reportLabel.text = live[@"reportText"] ?: @"还没有自检数据，跑一次或重启 thermalmonitord。";
        return cell;
    }

    if ([type isEqualToString:@"segment"]) {
        static NSString *cid = @"segment";
        TFSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell) cell = [[TFSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];

        NSString *level = TFString(@"level", @"auto");
        cell.seg.selectedSegmentIndex = [level isEqualToString:@"max"] ? 2 : ([level isEqualToString:@"low"] ? 1 : 0);

        __weak typeof(self) weakSelf = self;
        cell.onChange = ^(NSInteger index) {
            NSString *v = index == 2 ? @"max" : (index == 1 ? @"low" : @"auto");
            TFWrite(@"level", v);
            TFApplyNow();
            [weakSelf.table reloadData];
        };
        return cell;
    }

    if ([type isEqualToString:@"switch"]) {
        static NSString *cid = @"switch";
        TFSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell) cell = [[TFSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];

        UIListContentConfiguration *cfg = [UIListContentConfiguration cellConfiguration];
        cfg.text = row[@"title"];
        cell.contentConfiguration = cfg;

        NSString *key = row[@"key"];
        BOOL def = [row[@"def"] boolValue];
        cell.sw.on = TFBool(key, def);

        __weak typeof(self) weakSelf = self;
        cell.onToggle = ^(BOOL on) {
            TFWrite(key, @(on));
            TFApplyNow();
            [weakSelf.table reloadData];
        };
        return cell;
    }

    if ([type isEqualToString:@"button"]) {
        static NSString *cid = @"button";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];

        UIListContentConfiguration *cfg = [UIListContentConfiguration cellConfiguration];
        cfg.text = row[@"title"];
        cfg.textProperties.color = UIColor.linkColor;
        cfg.textProperties.alignment = UIListContentTextAlignmentCenter;
        cell.contentConfiguration = cfg;
        return cell;
    }

    // value / nav
    static NSString *cid = @"value";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];

    if ([type isEqualToString:@"value"]) {
        UIListContentConfiguration *cfg = [UIListContentConfiguration valueCellConfiguration];
        cfg.text = row[@"title"];
        NSString *key = row[@"key"];
        NSString *val = TFString(key, @"");
        if (row[@"unit"]) {
            val = val.length ? [NSString stringWithFormat:@"%@%@", val, row[@"unit"]] : @"默认";
        }
        cfg.secondaryText = val.length ? val : @"未设置";
        cell.contentConfiguration = cfg;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        UIListContentConfiguration *cfg = [UIListContentConfiguration cellConfiguration];
        cfg.text = row[@"title"];
        cell.contentConfiguration = cfg;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

#pragma mark 交互

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSString *type = row[@"type"];
    NSString *action = row[@"action"];

    if ([type isEqualToString:@"button"] && [action isEqualToString:@"selftest"]) {
        [self runSelfTest];
        return;
    }

    if ([type isEqualToString:@"nav"] && [action isEqualToString:@"log"]) {
        [self.navigationController pushViewController:[TFLogController new] animated:YES];
        return;
    }

    if ([type isEqualToString:@"nav"] && [action isEqualToString:@"advanced"]) {
        TFAdvancedController *vc = [TFAdvancedController new];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    if ([type isEqualToString:@"value"]) {
        NSString *key = row[@"key"];
        BOOL numeric = [row[@"numeric"] boolValue];
        NSString *hint = numeric ? @"只填数字" : (row[@"unit"] ? @"只填数字" : @"英文逗号分隔");
        [self editKey:key title:row[@"title"] hint:hint numeric:numeric];
    }
}

- (void)editKey:(NSString *)key title:(NSString *)title hint:(NSString *)hint numeric:(BOOL)numeric {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = TFString(key, @"");
        tf.placeholder = hint;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        if (numeric) tf.keyboardType = UIKeyboardTypeNumberPad;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *v = alert.textFields.firstObject.text ?: @"";
        TFWrite(key, v);
        TFApplyNow();
        [weakSelf.table reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)runSelfTest {
    TFNotify("com.lqx3617.thermalfuse/selftest");

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"自检已开始"
                                                               message:@"30 秒后回到这个页面，卡片里会显示结论。"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 32ull * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [weakSelf.table reloadData];
    });
}

@end

#pragma mark - 高级设置实现

@implementation TFAdvancedController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"高级设置";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.dataSource = self;
    table.delegate = self;
    table.rowHeight = UITableViewAutomaticDimension;
    table.estimatedRowHeight = 56;
    table.backgroundColor = UIColor.systemGroupedBackgroundColor;
    table.tag = 100;
    [self.view addSubview:table];

    [NSLayoutConstraint activateConstraints:@[
        [table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (UITableView *)table {
    return (UITableView *)[self.view viewWithTag:100];
}

- (NSArray *)rows {
    return @[
        @{@"type": @"switch", @"title": @"启用插件", @"key": @"enabled", @"def": @YES},
        @{@"type": @"switch", @"title": @"强制 nominal 模拟模式", @"key": @"forceNominal", @"def": @YES},
        @{@"type": @"switch", @"title": @"屏蔽温度传感器上报", @"key": @"blockSensorEvents", @"def": @YES},
        @{@"type": @"switch", @"title": @"改写 ThermalMonitor 配置", @"key": @"patchThermalPlist", @"def": @YES},
        @{@"type": @"switch", @"title": @"关闭 CPMS 缓解（激进）", @"key": @"blockMitigation", @"def": @NO},
        @{@"type": @"switch", @"title": @"档位引擎（实验）", @"key": @"engineEnabled", @"def": @NO},
        @{@"type": @"switch", @"title": @"SpringBoard 侧（游戏识别）", @"key": @"sbEnabled", @"def": @YES},
        @{@"type": @"switch", @"title": @"输出日志", @"key": @"verbose", @"def": @NO},
        @{@"type": @"value", @"title": @"背光功率上限", @"key": @"cpuMaxPower", @"numeric": @YES},
    ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"前四项是温控解除的核心，全关就等于装了个空壳。档位引擎要动 MitigationController 的功率 setter，默认关着；确认温控解除稳定后再开。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.rows[indexPath.row];
    NSString *type = row[@"type"];

    if ([type isEqualToString:@"switch"]) {
        static NSString *cid = @"aswitch";
        TFSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell) cell = [[TFSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];

        UIListContentConfiguration *cfg = [UIListContentConfiguration cellConfiguration];
        cfg.text = row[@"title"];
        cell.contentConfiguration = cfg;

        NSString *key = row[@"key"];
        cell.sw.on = TFBool(key, [row[@"def"] boolValue]);

        UITableView *t = tableView;
        cell.onToggle = ^(BOOL on) {
            TFWrite(key, @(on));
            TFApplyNow();
            [t reloadData];
        };
        return cell;
    }

    static NSString *vid = @"avalue";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:vid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:vid];

    UIListContentConfiguration *cfg = [UIListContentConfiguration valueCellConfiguration];
    cfg.text = row[@"title"];
    NSString *val = TFString(row[@"key"], @"");
    cfg.secondaryText = val.length ? val : @"不改写";
    cell.contentConfiguration = cfg;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.rows[indexPath.row];
    if ([row[@"type"] isEqualToString:@"value"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:row[@"title"]
                                                                      message:@"数字，单位跟系统 plist 一致；留空不改写。"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.text = TFString(row[@"key"], @"");
            tf.keyboardType = UIKeyboardTypeNumberPad;
        }];
        UITableView *t = tableView;
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            TFWrite(row[@"key"], alert.textFields.firstObject.text ?: @"");
            TFApplyNow();
            [t reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end


#pragma mark - 运行日志页

@implementation TFLogController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"运行日志";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.textView = [UITextView new];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable = NO;
    self.textView.alwaysBounceVertical = YES;
    self.textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    self.textView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.textView.layer.cornerRadius = 12;
    self.textView.clipsToBounds = YES;
    [self.view addSubview:self.textView];

    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
    ]];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                      target:self
                                                      action:@selector(shareLog)];
    [self reloadLog];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadLog];
}

- (NSString *)logPath {
    return @"/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.log";
}

- (void)reloadLog {
    NSString *text = [NSString stringWithContentsOfFile:[self logPath]
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    if (!text.length) {
        self.textView.text = @"还没有日志。\n\n装上后没动过的话，日志里只有启动那几行；"
                              "把高级设置里的「输出日志」打开，用一会儿再回来。";
        return;
    }
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    if (lines.count > 400) {
        lines = [lines subarrayWithRange:NSMakeRange(lines.count - 400, 400)];
    }
    self.textView.text = [lines componentsJoinedByString:@"\n"];
    [self.textView scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)shareLog {
    NSString *path = [self logPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"还没有日志文件"
                                                                   message:@"用一会儿再来"
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    // 顺手把偏好和自检结果塞进同目录，导出的东西一次看全
    NSMutableString *extra = [NSMutableString string];
    [extra appendString:@"\n===== prefs =====\n"];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.plist"];
    [extra appendFormat:@"%@\n", prefs ?: @{}];
    [extra appendString:@"\n===== live =====\n"];
    NSDictionary *live = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.live.plist"];
    [extra appendFormat:@"%@\n", live ?: @{}];

    NSString *bundleText = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *full = [bundleText stringByAppendingString:extra];

    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ThermalFuse-日志.txt"];
    [full writeToFile:tmp atomically:YES encoding:NSUTF8StringEncoding error:nil];

    UIActivityViewController *vc = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:tmp]] applicationActivities:nil];
    vc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:vc animated:YES completion:nil];
}

@end
