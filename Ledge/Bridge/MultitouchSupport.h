// Private MultitouchSupport.framework: raw finger data from every Apple trackpad,
// plus the Force Touch actuator. Linked against the .tbd stub in the macOS SDK.
#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTVector;

// 96 bytes. Normalized coordinates run 0…1, x left→right, y bottom→top.
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;      // stable id for one finger while it stays down
    int32_t state;          // 3 = make touch, 4 = touching, 5 = break touch
    int32_t fingerID;
    int32_t handID;
    MTVector normalized;
    float zTotal;           // contact size
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;      // millimetres
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

typedef void *MTDeviceRef;
typedef void (*MTContactCallbackFunction)(MTDeviceRef device,
                                          const MTTouch *touches,
                                          int32_t numTouches,
                                          double timestamp,
                                          int32_t frame);

CFMutableArrayRef MTDeviceCreateList(void) CF_RETURNS_RETAINED;
void MTRegisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void MTUnregisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
int32_t MTDeviceStart(MTDeviceRef device, int32_t mode);
int32_t MTDeviceStop(MTDeviceRef device);
bool MTDeviceIsRunning(MTDeviceRef device);
bool MTDeviceIsBuiltIn(MTDeviceRef device);
// Hundredths of a millimetre.
int32_t MTDeviceGetSensorSurfaceDimensions(MTDeviceRef device, int32_t *width, int32_t *height);
int32_t MTDeviceGetFamilyID(MTDeviceRef device, int32_t *familyID);
int32_t MTDeviceGetDeviceID(MTDeviceRef device, uint64_t *deviceID);

typedef CFTypeRef MTActuatorRef;
MTActuatorRef MTActuatorCreateFromDeviceID(uint64_t deviceID) CF_RETURNS_RETAINED;
IOReturn MTActuatorOpen(MTActuatorRef actuator);
IOReturn MTActuatorClose(MTActuatorRef actuator);
bool MTActuatorIsOpen(MTActuatorRef actuator);
IOReturn MTActuatorActuate(MTActuatorRef actuator, int32_t actuationID, uint32_t unknown1, float unknown2, float unknown3);
