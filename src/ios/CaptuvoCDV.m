
#import "CaptuvoCDV.h"


@implementation CaptuvoCDV

- (void)pluginInitialize {
    [super pluginInitialize];
    
    self.device = [Captuvo sharedCaptuvoDevice];
    [self.device addCaptuvoDelegate:self];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dispose {
    
    [self.device removeCaptuvoDelegate:self];
    [self.device stopDecoderHardware];
    [self.device stopPMHardware];
    [self.device stopMSRHardware];
    
    [super dispose];
}


- (void) onDidEnterBackground {
    Captuvo *device = self.device;
    if (device.isDecoderRunning)
        [device stopDecoderHardware];
    if (device.isMSRRunning)
        [device stopMSRHardware];
    if (self.isMonitoringBattery)
        [device stopPMHardware];
}

- (void) onDidBecomeActive {
    if (self.isMonitoringScanner)
        [self.device startDecoderHardware];
    if (self.isMonitoringMSR)
        [self.device startMSRHardware];
    if (self.isMonitoringBattery)
        [self.device startPMHardware];
}

-(void)captuvoConnected{
    NSLog(@"Captuvo connected");
    [self.commandDelegate evalJs:@"captuvo.captuvoConnected();"];
    [self onDidBecomeActive];
}

-(void)captuvoDisconnected{
    NSLog(@"Captuvo disconnected");
    [self.commandDelegate evalJs:@"captuvo.captuvoDisconnected();"];
}

- (void) decoderDataReceived:(NSString*)data {
    CDVPluginResult *result = [CDVPluginResult
                               resultWithStatus:CDVCommandStatus_OK
                               messageAsString:data];
    
    [result setKeepCallbackAsBool:YES];
    
    [self.commandDelegate sendPluginResult:result callbackId:self.scannerCallbackId];
}

//CORDOVA CALLBACKS
- (void) registerScannerCallback:(CDVInvokedUrlCommand *)command {
    BOOL beepOnStartup = false;
    if (command.arguments.count > 0) {
        beepOnStartup = (BOOL) [command.arguments objectAtIndex:0];
    }
    self.scannerCallbackId = command.callbackId;
    self.isMonitoringScanner = true;
    
    [self.device enableDecoderPowerUpBeep:beepOnStartup];
    ProtocolConnectionStatus status =[self.device startDecoderHardware];
    [self logConnectionStatus:status];
    
}

- (void)unregisterScanner:(CDVInvokedUrlCommand *)command {
    self.scannerCallbackId = nil;
    self.isMonitoringScanner = false;
    [self.device stopDecoderHardware];
}

- (void)startScanning:(CDVInvokedUrlCommand *)command {
    [self.device startDecoderScanning];
}

-(void)stopScanning:(CDVInvokedUrlCommand *)command{
    [self.device stopDecoderScanning];
}
- (void)decoderReady{
    NSLog(@"Captuvo Decoder Ready");
    [self.commandDelegate evalJs:@"captuvo.decoderReady();"];
}

/**
 * Pass in params to setup beeps 
 */
- (void)configureScanner:(CDVInvokedUrlCommand*)command {
    /*
    NSError* error;
    id params =  [NSJSONSerialization
                             JSONObjectWithData: [command argumentAtIndex:0]
                             options:kNilOptions
                             error:&error];*/
    BOOL startupBeep = [[command argumentAtIndex:0] boolValue];
    BOOL successBeep = [[command argumentAtIndex:1] boolValue];
    BOOL triggerClick = [[command argumentAtIndex:2] boolValue];
    
    [self.device enableDecoderPowerUpBeep:startupBeep];
    [self.device enableDecoderBeeperForGoodRead:successBeep persistSetting:true];
    [self.device enableDecoderTriggerClick:triggerClick persistSetting:true];
}

//MSR
- (void)unregisterMagstripe:(CDVInvokedUrlCommand*)command{
    self.isMonitoringMSR = false;
    self.msrCallbackId = nil;
    [self.device disableMSRReader];
    [self.device stopMSRHardware];
}

- (void)registerMagstripeCallback:(CDVInvokedUrlCommand*)command{
    NSLog(@"Registering MSR");
    self.msrCallbackId = command.callbackId;
    self.isMonitoringMSR = true;
    ProtocolConnectionStatus status =[self.device startMSRHardware];
    [self.device enableMSRReader];
    [self.device setMSRTrackSelection:TrackSelectionAnyTrack];
    [self logConnectionStatus:status];
    
}
-(void)msrStringDataReceived:(NSString *)data validData:(BOOL)status{
    NSLog(@"Got MSR Data");
    CDVPluginResult *result = [CDVPluginResult
                               resultWithStatus: status ? CDVCommandStatus_OK : CDVCommandStatus_ERROR
                               messageAsString:data];
    
    [self.commandDelegate sendPluginResult:result callbackId:self.msrCallbackId];
}
-(void)msrReady{
    NSLog(@"Captuvo Magstripe Reader Ready");
    [self.commandDelegate evalJs:@"captuvo.msrReady();"];
}

-(int) getBatteryStatusValue:(BatteryStatus)batteryStatus {
    switch (batteryStatus) {
        case BatteryStatusPowerSourceConnected:
            return -1; // |*AC*|
        case BatteryStatus4Of4Bars:
            return 4;
        case BatteryStatus3Of4Bars:
            return 3;
        case BatteryStatus2Of4Bars:
            return 2;
        case BatteryStatus1Of4Bars:
            return 1;
        case BatteryStatus0Of4Bars:
            return 0;
        default:
            return -2; // Unknown
    }
}

-(void) publishBatteryStatus:(BatteryStatus)batteryStatus {
    if (self.batteryCallbackId) {
        int status = [self getBatteryStatusValue:batteryStatus];
        
        //if didn't read status, send an error
        BOOL didRead = batteryStatus != BatteryStatusUndefined;
        
        CDVPluginResult *result = [CDVPluginResult
                                   resultWithStatus: didRead ? CDVCommandStatus_OK : CDVCommandStatus_ERROR
                                   messageAsInt:status];
        [result setKeepCallbackAsBool:YES];
        
        [self.commandDelegate sendPluginResult:result callbackId:self.batteryCallbackId];
    }
}

//Battery
-(void)pmBatteryStatusChange:(BatteryStatus)newBatteryStatus {
    [self publishBatteryStatus:newBatteryStatus];
}

- (void)registerBatteryCallback:(CDVInvokedUrlCommand*)command{
    [self.device startPMHardware];
    self.batteryCallbackId = command.callbackId;
    self.isMonitoringBattery = true;
    
    if(self.device != nil) {
        [self.device startPMHardware];
        BatteryStatus batteryStatus = [self.device getBatteryStatus];
        [self publishBatteryStatus:batteryStatus];
    }
}

-(void)logConnectionStatus:(ProtocolConnectionStatus) connectionStatus {
    switch (connectionStatus) {
        case ProtocolConnectionStatusConnected:
        case ProtocolConnectionStatusAlreadyConnected:
            NSLog(@"Connected!");
            break;
        case ProtocolConnectionStatusBatteryDepleted:
            NSLog(@"Battery depleted!");
            break;
        case ProtocolConnectionStatusUnableToConnect:
            NSLog(@"Error connecting!");
            break;
        case ProtocolConnectionStatusUnableToConnectIncompatiableSledFirmware:
            NSLog(@"Incompatible firmware!");
            break;
        default:
            NSLog(@"Unknown connection status");
            break;
    }
}

@end
