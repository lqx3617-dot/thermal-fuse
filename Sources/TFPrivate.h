// ThermalFuse 私有类声明（按 thermalmonitord 实际方法签名写，改签名会 hook 失败）
#import <Foundation/Foundation.h>
#include <stdint.h>

@interface CommonProduct : NSObject
- (id)initProduct:(id)arg1;
- (void)putDeviceInThermalSimulationMode:(id)arg1;
- (void)putDeviceInLowTempSimulationMode:(id)arg1;
- (void)tryTakeAction;
- (void)simulateLightThermalPressure;
- (void)updatePowerzoneTelemetry;
- (void)handleMCSThermalPressure;
- (void)setThermalState:(int)a3;
- (int64_t)thermalPressureLevel;
- (int)arcVirtualTemperature;
- (int)arcModuleTemperature;
- (int)gasGaugeBatteryTemperature;
- (int)getFrontDisplayCenterTemperature;
@end

@interface HidSensors : NSObject
- (void)handleTemperatureEvent:(int)a3 service:(id)a4;
@end

@interface MitigationController : NSObject
- (void)setCPMSMitigationsEnabled:(BOOL)a3;
- (int)CPULevel;
- (int)CPUPower;
- (int)GPUPower;
- (int)getCPUTargetPower;
- (int)getGPUTargetPower;
- (int)getCurrentCPUPower;
- (int)getCurrentGPUPower;
- (int)getCurrentPackagePower;
- (int)getPackageTargetPower;
- (int)getPackagePowerZoneMetric;
- (void)setCPUPowerCeiling:(int)a3 fromDecisionSource:(int)a4;
- (void)setCPUPowerFloor:(int)a3 fromDecisionSource:(int)a4;
- (void)setGPUPowerCeiling:(int)a3 fromDecisionSource:(int)a4;
- (void)setPackagePowerCeiling:(int)a3 fromDecisionSource:(int)a4;
- (void)setPackagePowerFloor:(int)a3 fromDecisionSource:(int)a4;
- (void)setMaxPackagePower:(int)a3;
- (void)setMaxGraphicsDrivePowerTarget:(int)a3;
- (void)setCPUPowerZoneTarget:(int)a3;
- (void)setGPUPowerZoneTarget:(int)a3;
- (void)setPackagePowerZoneTarget;
- (void)updateCPU;
- (void)updateGPU;
- (void)updatePackage;
@end

@interface CPMSHelper : NSObject
+ (id)sharedInstance;
- (unsigned)getMaxPowerForComponent:(int)a3;
- (unsigned)getMinPowerForComponent:(int)a3;
@end
