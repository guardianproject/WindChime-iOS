//
//  BLESessionMessage.h
//  Pods
//
//  Created by Christopher Ballinger on 3/2/15.
//
//

#import <Foundation/Foundation.h>

/** abstract class */
@interface BLESessionMessage : NSObject

// Prefix
@property (nonatomic) uint8_t version;
@property (nonatomic) uint16_t headerLength;

// Derived from values in header
@property (nonatomic, strong) NSString *identifer;
@property (nonatomic) NSUInteger payloadLength;
@property (nonatomic, strong) NSString *type;

@property (nonatomic, strong) NSData *payloadHash;

/** outgoing */
- (instancetype) initWithIdentifier:(NSString*)identifier;

/** incoming */
- (instancetype) initWithVersion:(uint8_t)version headers:(NSDictionary*)headers;

+ (NSString*) type;

@end

@interface BLESessionMessage (Serialization)

- (NSMutableDictionary*) headers;
- (NSData*) serializedPrefixData;
- (NSData*) serializedHeaderData;
- (NSData*) serializedPrefixAndHeaderData;
- (void) clearSerializationCache;


/** serializes full message (only works if payload fits in memory) */
- (NSData*) serializedData;

@end

@interface BLESessionMessage (Deserialization)

- (void) parseHeaders:(NSDictionary *)headers;
- (void) parsePrefixData:(NSData*)prefixData;

+ (uint8_t) versionFromPrefixData:(NSData*)prefixData;
+ (uint16_t) headerLengthFromPrefixData:(NSData*)prefixData;
+ (NSDictionary*) headersFromData:(NSData*)data version:(uint8_t)version error:(NSError**)error;

@end

extern const NSUInteger kBLESessionMessagePrefixLength;

extern NSString * const kBLESessionMessageHeaderTypeKey;
extern NSString * const kBLESessionMessageHeaderPayloadLengthKey;
extern NSString * const kBLESessionMessageHeaderIdentifierKey;

