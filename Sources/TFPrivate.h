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
@end

@interface HidSensors : NSObject
- (void)handleTemperatureEvent:(int)a3 service:(id)a4;
@end

@interface MitigationController : NSObject
- (void)setCPMSMitigationsEnabled:(BOOL)a3;
- (void)setPackagePowerCeiling:(int)a3 fromDecisionSource:(int)a4;
- (void)updateCPU;
- (void)updateGPU;
@end
