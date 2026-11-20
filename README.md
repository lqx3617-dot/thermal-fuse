# ThermalFuse · 温控解除 + 智能档位

注入 `thermalmonitord`（温控守护进程）和 `SpringBoard`（前台 App 感知），
把热压力判定链掐掉，并按档位接管 CPU/GPU 功率上限。
纯 Objective-C + Logos，不依赖 Orion / Swift runtime。

目标环境：iOS 16.6.1 + Relaxin（RootHide），roothide scheme 打包。

## 当前版本 1.1.0 做了什么

**解除温控（v1.0 已有）**

| 位置 | 动作 |
|---|---|
| `CommonProduct -initProduct:` | 建实例立刻 `putDeviceInThermalSimulationMode:"nominal"` |
| `tryTakeAction` / `simulateLightThermalPressure` / `updatePowerzoneTelemetry` / `handleMCSThermalPressure` | 留空，降频动作不落地 |
| `-thermalPressureLevel` / `-setThermalState:` | 固定 0 |
| `HidSensors -handleTemperatureEvent:service:` | 留空，传感器数据进不来 |
| `NSDictionary +dictionaryWithContentsOfFile:` | 改写 `/System/Library/ThermalMonitor/*.plist` 的背光功率曲线 |

**档位引擎（v1.1 新增）**

接管 `MitigationController` 的 `setCPUPowerCeiling:fromDecisionSource:`、
`setGPUPowerCeiling:…`、`setPackagePowerCeiling:…`、`setMaxPackagePower:`，
按当前档位放大或压缩系统给的上限。

不复用硬编码功率值，用「运行期间见过的最大的 ceiling」当基准（`gMaxSeen`），
所以换机型不用重新填参数。三档：

- `auto` 不干预
- `low` 压到 `gMaxSeen × lowRatio`（默认 40%）
- `max` 顶到 `gMaxSeen`

**游戏识别**：SpringBoard 侧监听前台 App 通知，把 bundle id 写进
`thermalfuse.fg.plist`；thermalmonitord 每 20 秒读一次，命中 `games`
里的前缀就切 `max`，退出回落。

**定时切档**：`schedule` 里写 `08:00-22:00=max;23:00-07:00=low`，
优先级高于游戏识别。

**自检**：启动后 6 秒开始，2 秒采一次共 15 次（30 秒），统计 CPU / 包功率 /
电池温度的平均与峰值，给出「系统在压功率 / 已接近上限」的判定，结果写
`thermalfuse.live.plist` 的 `reportText` 并打一行 syslog。

## 三个共享文件

| 文件 | 作用 |
|---|---|
| `com.lqx3617.thermalfuse.plist` | 偏好，设置面板写的 |
| `com.lqx3617.thermalfuse.live.plist` | 自检报告（`reportText` / `maxSeen` / `level`） |
| `com.lqx3617.thermalfuse.fg.plist` | 前台 bundle id + 时间戳（45 秒过期） |

跨进程只走文件 + darwin 通知（`com.lqx3617.thermalfuse/reload`），不开 XPC。

## 开关一览

| 键 | 默认 | 作用 |
|---|---|---|
| `enabled` | true | 总开关 |
| `forceNominal` | true | 强制 nominal 模拟模式 |
| `blockSensorEvents` | true | 屏蔽传感器上报 |
| `patchThermalPlist` | true | 改写 ThermalMonitor 配置 |
| `blockMitigation` | false | 连 CPMS 缓解一起关 |
| `level` | auto | 常驻档位 auto/low/max |
| `lowRatio` | 40 | 低功耗档百分比 |
| `games` | 常见游戏前缀 | 逗号分隔的 bundle id 前缀 |
| `schedule` | 空 | 定时表 |
| `cpuMaxPower` | 空 | 背光功率上限，0 = 不改 |
| `selfTestOnStart` | true | 启动后自动自检 |
| `verbose` | false | syslog 详细日志 |

## 装

Sileo 里点 deb 装最稳（RootHide 的 dpkg 在 jbroot 里）：

```sh
/var/jb/usr/bin/dpkg -i /var/mobile/Downloads/ThermalFuse-1.1.0.deb
killall -9 thermalmonitord; killall -9 SpringBoard
```

## 验证

```sh
# 注入是否成功
idevicesyslog | grep ThermalFuse

# 该看到：
# [ThermalFuse] 1.1.0 loaded in thermalmonitord
# [ThermalFuse] SpringBoard 侧加载
# [ThermalFuse] 自检完成：样本 15 条｜CPU 平均 …｜包 平均 …｜…

# 前台识别是否工作（verbose 打开后）
idevicesyslog | grep "前台:"

# 自检报告原文
cat /var/mobile/Library/Preferences/com.lqx3617.thermalfuse.live.plist
```

手动再跑一次自检（终端里）：

```sh
launchctl post-notification com.lqx3617.thermalfuse/selftest
# 或者用 trollstore 里的快捷指令 / 任意发 darwin 通知的工具
```

## 注意

- SpringBoard 侧只注册了三个 NSNotification，不 hook 任何私有方法 —— 崩不了。
- `MitigationController` 的方法签名取自 iOS 16 的类结构，换大版本要重新对。
- `gMaxSeen` 是运行时学习的，刚装完的第一次自检 `maxSeen` 可能是 0，
  跑一会儿再看才有意义。

## 构建

```sh
export THEOS=~/theos          # roothide/theos fork
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

产物 `packages/com.lqx3617.thermalfuse_<版本>_iphoneos-arm64e.deb`。
Architecture 必须是 `iphoneos-arm64e`、包内路径不能写 `/var/jb` 前缀 ——
这是 roothide 的约定，RootHide 的 dpkg 靠它做 jbroot 重映射。

CI 用 `ubuntu-22.04` + theos 官方 Linux 工具链（macOS runner 在这个账号上分配不到）。
