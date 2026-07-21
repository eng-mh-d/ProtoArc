#include "ProtoArcTouchpadDriver.h"
#include <HIDDriverKit/IOHIDDigitizerStructs.h>
#include <os/log.h>

#define Log(fmt, ...) os_log(OS_LOG_DEFAULT, "ProtoArcTouchpadDriver: " fmt, ##__VA_ARGS__)

// The report ID that contains the multitouch data based on the prompt
#define PROTOARC_TOUCH_REPORT_ID 2

// Max dimensions from the descriptor
#define MAX_X 3200
#define MAX_Y 2000

// Define the packed struct to map the raw HID report.
#pragma pack(push, 1)

struct ProtoArcContact {
    uint8_t tipSwitch:1;
    uint8_t inRange:1;
    uint8_t contactID:6;
    uint16_t x;
    uint16_t y;
};

struct ProtoArcTouchReport {
    uint8_t reportID;      
    uint8_t timestamp;     
    ProtoArcContact contacts[4];
    uint8_t contactCount;  
};

#pragma pack(pop)

bool ProtoArcTouchpadDriver::init()
{
    Log("init()");
    if (!super::init()) {
        return false;
    }
    return true;
}

void ProtoArcTouchpadDriver::free()
{
    Log("free()");
    super::free();
}

kern_return_t ProtoArcTouchpadDriver::Start(IOService *provider)
{
    Log("Start()");
    kern_return_t ret = super::Start(provider);
    if (ret != kIOReturnSuccess) {
        Log("super::Start failed");
        return ret;
    }
    return kIOReturnSuccess;
}

kern_return_t ProtoArcTouchpadDriver::Stop(IOService *provider)
{
    Log("Stop()");
    return super::Stop(provider);
}

void ProtoArcTouchpadDriver::handleReport(
    uint64_t timestamp,
    uint8_t *report,
    uint32_t reportLength,
    IOHIDReportType type,
    uint32_t reportID)
{
    // Pass standard reports back to the system
    if (reportID != PROTOARC_TOUCH_REPORT_ID) {
        super::handleReport(timestamp, report, reportLength, type, reportID);
        return;
    }

    // Intercept our multitouch report ID 2
    DispatchDigitizerEvents(timestamp, report, reportLength);
}

void ProtoArcTouchpadDriver::DispatchDigitizerEvents(uint64_t timestamp, uint8_t *report, uint32_t reportLength)
{
    // Basic bounds checking
    if (reportLength < sizeof(ProtoArcTouchReport)) {
        Log("Report too short: %u bytes", reportLength);
        return;
    }

    ProtoArcTouchReport *touchReport = (ProtoArcTouchReport *)report;

    // Safety check on contact count
    uint8_t actualCount = touchReport->contactCount;
    if (actualCount > 4) { actualCount = 4; }
    if (actualCount == 0) {
        // DriverKit's dispatchDigitizerTouchEvent expects an array.
        // We can pass an empty array to indicate all fingers lifted,
        // or a single touch data with touch=0.
        // It's safer to pass one invalid touch to update state.
        IOHIDDigitizerTouchData touchData = {};
        dispatchDigitizerTouchEvent(timestamp, &touchData, 0);
        return;
    }

    IOHIDDigitizerTouchData touches[4] = {};

    for (int i = 0; i < actualCount; i++) {
        ProtoArcContact *c = &touchReport->contacts[i];
        
        touches[i].identifier = c->contactID;
        // DriverKit API expects 16.16 fixed point for coordinates.
        // Some systems expect values between 0.0 and 1.0 (scaled by logical max).
        // Let's pass the raw values as 16.16 first. If scaling is wrong, we would
        // scale them here: IOFixed x = (IOFixed)(((float)c->x / MAX_X) * 65536.0f);
        touches[i].x = (c->x << 16); 
        touches[i].y = (c->y << 16);
        touches[i].inRange = c->inRange;
        touches[i].touch = c->tipSwitch;
        touches[i].touchValid = 1;
        
        // Force the OS to process this as an update
        touches[i].touchChanged = 1;
        touches[i].positionChanged = 1;
        touches[i].rangeChanged = 1;
    }

    // Dispatch to the OS using DriverKit API
    dispatchDigitizerTouchEvent(timestamp, touches, actualCount);
}
