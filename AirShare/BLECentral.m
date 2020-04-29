//
//  BLECentral.m
//  Pods
//
//  Created by Christopher Ballinger on 3/4/15.
//
//

#import "BLECentral.h"
#import <CoreBluetooth/CoreBluetooth.h>

@interface BLECentral () <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, strong, readonly) NSMutableDictionary *allDiscoveredPeripherals;
@property (nonatomic, strong, readonly) NSMutableDictionary *connectedPeripherals;
@property (nonatomic, strong, readonly) CBCentralManager *centralManager;
@property (nonatomic, strong, readonly) NSMutableDictionary *peripheralDataCharacteristics;
@property BOOL shouldStart;

@end

@implementation BLECentral


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
        _allDiscoveredPeripherals = [NSMutableDictionary dictionary];
        _connectedPeripherals = [NSMutableDictionary dictionary];
        _peripheralDataCharacteristics = [NSMutableDictionary dictionary];

        [self setupCentral];
    }

    return self;
}

- (BOOL) sendData:(NSData*)data
     toIdentifier:(NSString*)identifier
            error:(NSError**)error
{
    [self.dataQueue queueData:data forIdentifier:identifier mtu:155];

    CBPeripheral *periperal = [self.connectedPeripherals objectForKey:identifier];
    BLEConnectionStatus status = [self connectionStatusForPeripheral:periperal];

    if (status == BLEConnectionStatusConnected) {
        [self sendQueuedDataForConnectedPeripheral:periperal];
    }
    else if (status == BLEConnectionStatusDisconnected) {
        if (periperal) {
            [self.centralManager connectPeripheral:periperal options:nil];
        }
    }

    return YES;
}

- (BOOL) hasSeenIdentifier:(NSString*)identifier
{
    return self.allDiscoveredPeripherals[identifier] != nil;
}

- (void) start
{
    self.shouldStart = YES;

    [self scanForPeripherals];
}

- (void) stop
{
    self.shouldStart = NO;

    if (@available(iOS 9.0, *)) {
        if (self.centralManager.isScanning)
        {
            [self.centralManager stopScan];
        }
    }
    else {
        [self.centralManager stopScan];
    }
}


#pragma mark Private Methods

- (void) sendQueuedDataForConnectedPeripheral:(CBPeripheral*)peripheral
{
    NSData *data = [self.dataQueue peekDataForIdentifier:peripheral.identifier.UUIDString];
    CBCharacteristic *characteristic = [self dataCharacteristicForPeripheral:peripheral];

    if (!data || !characteristic)
    {
        return;
    }

    [peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
    NSLog(@"[AirShare] Writing %d bytes to peripheral: %@", (int)data.length, peripheral);
}


- (CBCharacteristic*) dataCharacteristicForPeripheral:(CBPeripheral*)peripheral
{
    return self.peripheralDataCharacteristics[peripheral.identifier.UUIDString];
}

- (void) scanForPeripherals
{
    if (self.centralManager.state == CBCentralManagerStatePoweredOn)
    {
        [self.centralManager
         scanForPeripheralsWithServices:@[self.serviceUUID]
         options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
    }
    else {
        NSLog(@"[AirShare] central not powered on");
    }
}

- (void) setupCentral
{
    NSMutableDictionary *options = [NSMutableDictionary dictionary];

    if (self.supportsBackground)
    {
        options[CBCentralManagerOptionRestoreIdentifierKey] = @"AirShareCentralManager";
        options[CBPeripheralManagerOptionRestoreIdentifierKey] = self.serviceUUID.UUIDString;
    }

    _centralManager = [[CBCentralManager alloc] initWithDelegate:self
                                                           queue:self.eventQueue
                                                         options:options];
}


#pragma mark CBCentralManagerDelegate

- (void) centralManager:(CBCentralManager *)central willRestoreState:(NSDictionary *)dict
{
    NSLog(@"[AirShare] centralManager:willRestoreState: %@", dict);

    NSArray *peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey];

    [peripherals enumerateObjectsUsingBlock:^(CBPeripheral *peripheral, NSUInteger idx, BOOL *stop) {
        self.allDiscoveredPeripherals[peripheral.identifier.UUIDString] = peripheral;

        if (peripheral.state == CBPeripheralStateConnected) {
            self.connectedPeripherals[peripheral.identifier.UUIDString] = peripheral;
        }
    }];
}

- (void) centralManagerDidUpdateState:(CBCentralManager *)centralManager
{
    NSLog(@"[AirShare] centralManagerDidUpdateState: %@", centralManager);

    if (self.shouldStart)
    {
        [self scanForPeripherals];
    }
}

- (BLEConnectionStatus) connectionStatusForPeripheral:(CBPeripheral*)peripheral
{
    if (peripheral.state == CBPeripheralStateDisconnected)
    {
        return BLEConnectionStatusDisconnected;
    }
    else if (peripheral.state == CBPeripheralStateConnecting)
    {
        return BLEConnectionStatusConnecting;
    }
    else if (peripheral.state == CBPeripheralStateConnected)
    {
        if (self.connectedPeripherals[peripheral.identifier.UUIDString] != nil)
        {
            return BLEConnectionStatusConnected;
        }
        else {
            return BLEConnectionStatusConnecting;
        }
    }

    return BLEConnectionStatusDisconnected;
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData
                  RSSI:(NSNumber *)RSSI
{
    NSLog(@"[AirShare] didDiscoverPeripheral: %@ %@ %@", peripheral, advertisementData, RSSI);

    CBPeripheral *previouslySeenPeripheral = self.allDiscoveredPeripherals[peripheral.identifier.UUIDString];
    BLEConnectionStatus status = [self connectionStatusForPeripheral:peripheral];

    dispatch_async(self.delegateQueue, ^{
        [self.delegate device:self identifierUpdated:peripheral.identifier.UUIDString status:status extraInfo:@{@"RSSI": RSSI}];
    });

    CBCharacteristic *characteristic = [self dataCharacteristicForPeripheral:peripheral];

    // previouslySeenPeripheral may be set because of centralManager:willRestoreState:,
    // but if characteristics are not loaded, sendQueuedDataForConnectedPeripheral:
    // will fail, so re-connect anyway to trigger service and characteristics discovery.
    if (!previouslySeenPeripheral || !characteristic) {
        [self.allDiscoveredPeripherals setObject:peripheral forKey:peripheral.identifier.UUIDString];
        peripheral.delegate = self;
        [central connectPeripheral:peripheral options:nil];

        dispatch_async(self.delegateQueue, ^{
            [self.delegate device:self identifierUpdated:peripheral.identifier.UUIDString
                           status:BLEConnectionStatusConnecting extraInfo:nil];
        });
    }
}

- (void) centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"[AirShare] didConnectPeripheral: %@", peripheral);

    [peripheral discoverServices:@[self.serviceUUID]];

    dispatch_async(self.delegateQueue, ^{
        [self.delegate device:self identifierUpdated:peripheral.identifier.UUIDString
                       status:BLEConnectionStatusConnecting extraInfo:nil];
    });
}

- (void) centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                  error:(NSError *)error
{
    dispatch_async(self.delegateQueue, ^{
        [self.delegate device:self identifierUpdated:peripheral.identifier.UUIDString
                       status:BLEConnectionStatusDisconnected extraInfo:nil];
    });
}

- (void) centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)peripheral
                  error:(NSError *)error
{
    dispatch_async(self.delegateQueue, ^{
        [self.delegate device:self identifierUpdated:peripheral.identifier.UUIDString
                       status:BLEConnectionStatusDisconnected extraInfo:nil];
    });
}


#pragma mark CBPeripheralDelegate

- (void) peripheral:(CBPeripheral *)peripheral
didWriteValueForCharacteristic:(CBCharacteristic *)characteristic
              error:(NSError *)error
{
    NSString *identifier = peripheral.identifier.UUIDString;
    NSData *data = nil;

    if (error)
    {
        data = [self.dataQueue peekDataForIdentifier:identifier];
    }
    else {
        data = [self.dataQueue popDataForIdentifier:identifier];
    }

    NSLog(@"[AirShare] didWriteValueForCharacteristic %@ %@", data, error);

    dispatch_async(self.delegateQueue, ^{
        [self.delegate device:self dataSent:data toIdentifier:identifier error:error];
    });

    [self sendQueuedDataForConnectedPeripheral:peripheral];
}

- (void) peripheral:(CBPeripheral *)peripheral
didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
              error:(NSError *)error
{
    if (error) {
        NSLog(@"[AirShare] didUpdateValueForCharacteristic error %@", error);
        return;
    }

    NSString *identifier = peripheral.identifier.UUIDString;
    NSData *data = characteristic.value;

    dispatch_async(self.delegateQueue, ^{
        [self.delegate device:self dataReceived:data fromIdentifier:identifier];
    });

    NSLog(@"[AirShare] didUpdateValueForCharacteristic %@", characteristic.value);
}

- (void)peripheral:(CBPeripheral *)peripheral
didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic
             error:(NSError *)error
{
    NSLog(@"[AirShare] didUpdateNotificationStateForCharacteristic %@ %@", characteristic, error);

    if ([characteristic.UUID isEqual:self.characteristicUUID] && !error)
    {
        [self.connectedPeripherals setObject:peripheral forKey:peripheral.identifier.UUIDString];

        dispatch_async(self.delegateQueue, ^{
            [self.delegate device:self identifierUpdated:peripheral.identifier.UUIDString
                           status:BLEConnectionStatusConnected extraInfo:nil];
        });
    }
}

- (void) peripheral:(CBPeripheral *)peripheral
didDiscoverCharacteristicsForService:(CBService *)service
              error:(NSError *)error
{
    if (error)
    {
        NSLog(@"[AirShare] didDiscoverCharacteristicsForService error %@" ,error);
        return;
    }
    else {
        NSLog(@"[AirShare] didDiscoverCharacteristicsForService: %@", service.characteristics);
    }

    NSArray *characteristics = service.characteristics;
    NSUInteger characteristicIndex = [characteristics indexOfObjectPassingTest:^BOOL(CBCharacteristic *characteristic, NSUInteger idx, BOOL *stop) {
        if ([characteristic.UUID isEqual:self.characteristicUUID])
        {
            *stop = YES;
            return YES;
        }

        return NO;
    }];

    if (characteristicIndex == NSNotFound)
    {
        NSLog(@"[AirShare] Characteristic not found");
        return;
    }

    CBCharacteristic *characteristic = characteristics[characteristicIndex];
    if (!characteristic)
    {
        NSLog(@"[AirShare] Characteristic not found");
        return;
    }

    self.peripheralDataCharacteristics[peripheral.identifier.UUIDString] = characteristic;

    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
}

- (void) peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    NSLog(@"[AirShare] didDiscoverServices: %@", peripheral.services);

    if (peripheral.services.count == 0)
    {
        return;
    }

    NSUInteger serviceIndex = [peripheral.services indexOfObjectPassingTest:^BOOL(CBService *service, NSUInteger idx, BOOL *stop) {
        if ([service.UUID isEqual:self.serviceUUID])
        {
            *stop = YES;
            return YES;
        }

        return NO;
    }];

    if (serviceIndex == NSNotFound)
    {
        NSLog(@"[AirShare] Data service not found");
        return;
    }

    [peripheral discoverCharacteristics:@[self.characteristicUUID]
                             forService:peripheral.services[serviceIndex]];
}

- (void)peripheral:(CBPeripheral *)peripheral didModifyServices:(NSArray<CBService *> *)invalidatedServices
{
    NSLog(@"[AirShare] didModifyServices: %@", invalidatedServices);
}

@end
