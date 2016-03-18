//
//  JSONToCoreData.h
//  JSONToCoreData
//
//  Created by Paresh on 29/02/16.
//  Copyright © 2016 Paresh. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@interface JSONToCoreData : NSObject

//shared instance
+ (JSONToCoreData *)sharedInstance;
//JSON structure from NSManagedObject
- (NSArray*)jsonStructureFromManagedObjects:(NSArray <NSManagedObject*> *)arrManagedObjects;
//update NSManagedObject from JSON structure
- (NSManagedObject *)updateManagedObjectsFromJSONStructure:(NSDictionary *)jsonDict forManagedObject:(NSManagedObject *)managedObject withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext;
//create NSManagedObject from JSON structure
- (NSArray <NSManagedObject*> *)insertManagedObjectsFromJSONStructure:(id)jsonData forEntity:(NSString *)strEntityName withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext;
@end
