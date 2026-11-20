# ThermalFuse · 温控解除

注入 `thermalmonitord`，把热压力判定链掐掉，解掉过热降频。
纯 Objective-C + Logos，不依赖 Orion / Swift runtime，CI 一次编好。

目标环境：iOS 16.6.1 + Relaxin（RootHide 架构），roothide scheme 打包。

## 它改了什么

`thermalmonitord` 是系统的热管理守护进程，判定顺序大致是：
传感器上报 → `CommonProduct` 算热压力 → `MitigationController` 压 CPU/GPU 功率上限 →
必要时 `setThermalState:` 往内核写热状态，App 收到 `NSProcessInfo.thermalState` 变热，
系统同时降亮度、限频。

ThermalFuse 在四个位置动手：

| 位置 | 动作 | 效果 |
|---|---|---|
| `CommonProduct -initProduct:` | 建实例后立刻 `putDeviceInThermalSimulationMode:"nominal"` | 让它一直按「温度正常」算 |
| `tryTakeAction` / `simulateLightThermalPressure` / `updatePowerzoneTelemetry` / `handleMCSThermalPressure` | 留空 | 降频动作算完不落地 |
| `-thermalPressureLevel` / `-setThermalState:` | 固定 0 | 上报给系统的压力等级恒为最小 |
| `HidSensors -handleTemperatureEvent:service:` | 留空 | 温度传感器的新数据进不来 |

另外改写 `/System/Library/ThermalMonitor/*.plist`：把 `backlightComponentControl` 里
`BacklightBrightness` / `BacklightPower` 的整条曲线拉平到第一档，`expectsCPMSSupport` 置 0，
可选把 `maxThermalPower` / `minThermalPower` 钉成你填的值。系统以为背光本来就省电，
少了降频的理由。

## 和 be-huge/insulation 的关系

思路参考了 [insulation](https://github.com/be-huge/insulation)（那是 Swift + Orion 写的，
同一个 hook 面）。这边重写成纯 Objective-C：

- 不用 Orion，不用 Swift 交叉模块，CI 少一层依赖
- 全部开关走偏好文件，能单独关，方便定位是哪个 hook 起作用
- 偏好面板是纯 plist bundle，不需要编译 PrefLoader 代码
- 类方法 hook 走 `MSHookMessageEx`，不赌 Logos 的类方法支持

## 装

```sh
sileo   # 或 dpkg -i
dpkg -i ThermalFuse_1.0.0_iphoneos-arm64.deb
killall -9 thermalmonitord     # 或重启用户空间
```

Sileo 里直接点 deb 也行。装完「设置」里会多一项「温控解除」。

## 开关（`/var/mobile/Library/Preferences/com.lqx3617.thermalfuse.plist`）

| 键 | 默认 | 作用 |
|---|---|---|
| `enabled` | true | 总开关，false 时什么都不 hook |
| `forceNominal` | true | 强制 nominal 模拟模式 |
| `blockSensorEvents` | true | 屏蔽传感器上报 |
| `patchThermalPlist` | true | 改写 ThermalMonitor 配置 |
| `blockMitigation` | false | 连 `MitigationController` 的 CPMS 缓解一起关，更激进 |
| `cpuMaxPower` | 空 | 背光功率上限，0 或空 = 不改写 |
| `verbose` | false | 往 syslog 打每一步 |

命令行改完发一条通知即可重载：

```sh
killall -9 thermalmonitord
```

## 验证有没有生效

```sh
# 1. 确认注入成功（verbose 打开后）
idevicesyslog | grep ThermalFuse

# 2. 看进程还在、插件已加载
ps aux | grep thermalmonitord

# 3. 跑分前看频率
#    TrollStore 里装 Filza → /var/jb/usr/bin/... 或直接看 CPU 频率监测 App
```

## 排查

| 现象 | 可能原因 |
|---|---|
| 设置里没有「温控解除」 | 没装 PreferenceLoader；或 bundle 路径不在 jbroot 里 |
| syslog 完全没有 ThermalFuse | dylib 没注入：Check Filter 的 Executables、RootHide 的注入开关 |
| 有日志但照样降频 | 系统还有别的路径（如 `powermanagementd`），看 verbose 日志确认哪个 hook 触发 |
| 装了直接重启 | 方法签名和 iOS 16.6.1 不符，看崩溃日志里 Last Exception Backtrace |

## 构建

本机（Ubuntu / macOS 都行）：

```sh
export THEOS=~/theos          # roothide/theos fork
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

产物：`packages/com.lqx3617.thermalfuse_<版本>_iphoneos-arm64e.deb`。

注意两个 roothide 特有的点：

1. Architecture 是 `iphoneos-arm64e`，不是 `iphoneos-arm64`。这是 roothide 的约定
   （`vendor/mod/roothide/package/deb.mk` 里写死的），RootHide 的 dpkg 靠这个字段
   认出「这是 jbroot 的包」再做路径重映射，改成 arm64 反而装不上。
2. 包内路径写成 `Library/MobileSubstrate/...`，没有 `/var/jb` 前缀。同样是故意的，
   前缀由 RootHide 安装时补，写死前缀会让重映射错位。

## CI

GitHub Actions 用 `ubuntu-22.04` + theos 官方 Linux 工具链编（macOS runner 在这个
账号上分配不到，job 会秒 cancelled）。流程：apt 依赖 → roothide/theos →
`iOSToolchain-x86_64` → sparse checkout 只取 iPhoneOS16.5.sdk → make package。
打了 `v*` tag 会自动发 Release。
