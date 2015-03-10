//
//  BLEDataMessage.m
//  Pods
//
//  Created by Christopher Ballinger on 3/3/15.
//
//

#import "BLEDataMessage.h"

@interface BLEDataMessage()
@property (nonatomic, strong) NSMutableData *serializedMessage;
@end

@implementation BLEDataMessage

- (instancetype) initWithData:(NSData*)data {
    NSParameterAssert(data != nil);
    if (self = [super init]) {
        _data = data;
        self.payloadLength = data.length;
    }
    return self;
}

- (NSData*) serializedData {
    if (!self.serializedMessage) {
        NSData *prefixData = [self serializedPrefixData];
        NSParameterAssert(prefixData.length > 0);
        NSData *headerData = [self serializedHeaderData];
        NSParameterAssert(headerData.length > 0);
        NSUInteger totalLength = prefixData.length + headerData.length + self.data.length;
        self.serializedMessage = [[NSMutableData alloc] initWithCapacity:totalLength];
        [self.serializedMessage appendData:prefixData];
        [self.serializedMessage appendData:headerData];
        [self.serializedMessage appendData:self.data];
    }
    return self.serializedMessage;
}

+ (NSString*) type {
    return @"DataTransferMessage";
}

@end
