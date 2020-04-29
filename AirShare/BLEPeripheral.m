//
//  BLEPeripheral.m
//  Pods
//
//  Created by Christopher Ballinger on 3/4/15.
//
//

#import "BLEPeripheral.h"
#import <CoreBluetooth/CoreBluetooth.h>

@interface BLEPeripheral () <CBPeripheralManagerDelegate>
@property (nonatomic, strong, readonly) CBPeripheralManager *peripheralManager;
@property (nonatomic) BOOL serviceAdded;
@property (nonatomic, strong, readonly) CBMutableService *dataService;
@property (nonatomic, strong, readonly) CBMutableCharacteristic *dataCharacteristic;
@property (nonatomic, strong, readonly) NSMutableDictionary *subscribedCentrals;
@property BOOL shouldStart;

@end

@implementation BLEPeripheral


#pragma mark BLEBluetoothDevice

- (instancetype) initWithDelegate:(id<BLEBluetoothDeviceDelegate>)delegate
                      serviceUUID:(CBUUID*)serviceUUID
               characteristicUUID:(CBUUID*)characteristicUUID
               supportsBackground:(BOOL)supportsBackground
{
    if (self = [super initWithDelegate:delegate serviceUUID:serviceUUID
                    characteristicUUID:characteristicUUID
                    supportsBackground:supportsBackground])
    {
        _subscribedCentrals = [NSMutableDictionary dictionary];
        [self setupCharacteristics];
        [self setupServices];
        [self setupPeripheral];
    }

    return self;
}

- (BOOL) sendData:(NSData*)data
     toIdentifier:(NSString*)identifier
            error:(NSError**)error
{
    CBCentral *central = [self.subscribedCentrals objectForKey:identifier];
    NSUInteger mtu = central ? central.maximumUpdateValueLength : 155;

    [self.dataQueue queueData:data forIdentifier:identifier mtu:mtu];
    if (!central)
    {
        return NO;
    }

    [self writeQueuedDataForCentral:central];

    return YES;
}

- (BOOL) hasSeenIdentifier:(NSString*)identifier
{
    return self.subscribedCentrals[identifier] != nil;
}

- (void) start
{
    self.shouldStart = YES;
    [self broadcastPeripheral];
}

- (void) stop
{
    self.shouldStart = NO;
    if (self.peripheralManager.isAdvertising)
    {
        [self.peripheralManager stopAdvertising];
    }
}


#pragma mark Private Methods

- (void) writeQueuedDataForCentral:(CBCentral*)central
{
    NSString *identifier = central.identifier.UUIDString;
    NSData *data = [self.dataQueue peekDataForIdentifier:identifier];

    if (!data)
    {
        return;
    }
    BOOL success = [self.peripheralManager updateValue:data
                                     forCharacteristic:self.dataCharacteristic
                                  onSubscribedCentrals:@[central]];

    if (success)
    {
        NSLog(@"[AirShare] Wrote %d bytes to central: %@", (int)data.length, central);
        [self.dataQueue popDataForIdentifier:identifier];
        [self writeQueuedDataForCentral:central];
    }
    else {
        NSLog(@"[AirShare] Error writing %d bytes to central: %@", (int)data.length, central);
    }
}

- (void) setupPeripheral
{
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[CBPeripheralManagerOptionShowPowerAlertKey] = @YES;

    if (self.supportsBackground)
    {
        options[CBPeripheralManagerOptionRestoreIdentifierKey] = self.serviceUUID.UUIDString;
    }

    _peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self
                                                                 queue:self.eventQueue
                                                               options:options];
}

- (void) setupCharacteristics
{
    _dataCharacteristic = [[CBMutableCharacteristic alloc]
                           initWithType:self.characteristicUUID
                           properties:CBCharacteristicPropertyRead | CBCharacteristicPropertyWrite | CBCharacteristicPropertyIndicate  value:nil permissions:CBAttributePermissionsReadable | CBAttributePermissionsWriteable];
}

- (void) setupServices
{
    _dataService = [[CBMutableService alloc] initWithType:self.serviceUUID primary:YES];
    _dataService.characteristics = @[self.dataCharacteristic];
}

- (void) broadcastPeripheral
{
    if (self.peripheralManager.state == CBPeripheralManagerStatePoweredOn)
    {
        if (!self.serviceAdded)
        {
            [self.peripheralManager addService:self.dataService];
            self.serviceAdded = YES;
        }
        
        if (!self.peripheralManager.isAdvertising)
        {
            [self.peripheralManager startAdvertising:@{CBAdvertisementDataServiceUUIDsKey: @[self.dataService.UUID],
                                                       CBAdvertisementDataLocalNameKey: @"AirShare"}];
        }
    }
    else {
        NSLog(@"[AirShare] peripheral not powered on");
    }
}

#pragma mark CBPeripheralManagerDelegate

- (void) peripheralManager:(CBPeripheralManager *)peripheral willRestoreState:(NSDictionary *)dict
{
    NSLog(@"[AirShare] peripheralManager:willRestoreState: %@", dict);
//    NSArray *restoredServices = dict[CBPeripheralManagerRestoredStateServicesKey];
//    NSDictionary *restoredAdvertisementDict = dict[CBPeripheralManagerRestoredStateAdvertisementDataKey];
}


- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheralManager
{
    NSLog(@"[AirShare] peripheralManagerDidUpdateState: %@", peripheralManager);

    if (self.shouldStart)
    {
        [self broadcastPeripheral];
    }
}

- (void) peripheralManager:(CBPeripheralManager *)peripheral
                   central:(CBCentral *)central
didSubscribeToCharacteristic:(CBCharacteristic *)characteristic
{
    self.subscribedCentrals[central.identifier.UUIDString] = central;

    NSLog(@"[AirShare] peripheralManager:didSubscribeToCharacteristic: %@ %@", central, characteristic);
    
    dispatch_async(self.delegateQueue, ^{
        [self.delegate device:self
            identifierUpdated:central.identifier.UUIDString
                       status:BLEConnectionStatusConnected
                    extraInfo:nil];
    });
}

- (void) peripheralManager:(CBPeripheralManager *)peripheral
                   central:(CBCentral *)central
didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic
{
    [self.subscribedCentrals removeObjectForKey:central.identifier.UUIDString];
    NSLog(@"[AirShare] peripheralManager:didUnsubscribeFromCharacteristic: %@ %@", central, characteristic);
    
    dispatch_async(self.delegateQueue, ^{
        [self.delegate device:self
            identifierUpdated:central.identifier.UUIDString
                       status:BLEConnectionStatusDisconnected
                    extraInfo:nil];
    });
}

- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral
{
    NSArray *centrals = [self.subscribedCentrals allValues];
    NSLog(@"[AirShare] peripheralManagerIsReadyToUpdateSubscribers: %@", centrals);

    [centrals enumerateObjectsUsingBlock:^(CBCentral *central, NSUInteger idx, BOOL *stop) {
        [self writeQueuedDataForCentral:central];
    }];
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error
{
    NSLog(@"[AirShare] peripheralManagerDidStartAdvertising: %@ %@", peripheral, error);
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
            didAddService:(CBService *)service
                    error:(NSError *)error
{
    NSLog(@"[AirShare] peripheralManager:didAddService: %@ %@", service, error);
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveWriteRequests:(NSArray *)requests
{
    NSLog(@"[AirShare] didReceiveWriteRequests: %@", requests);

    [requests enumerateObjectsUsingBlock:^(CBATTRequest *request, NSUInteger idx, BOOL *stop) {
        NSData *data = request.value;
        NSString *identifier = request.central.identifier.UUIDString;

        NSLog(@"[AirShare] write (%d bytes) %@", (int)data.length, data);

        dispatch_async(self.delegateQueue, ^{
            [self.delegate device:self dataReceived:data fromIdentifier:identifier];
        });

        [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
    }];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveReadRequest:(CBATTRequest *)request
{
    NSLog(@"[AirShare] didReceiveReadRequest: %@", request);

    if (request) {
        [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
    }
}

@end
