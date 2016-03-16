//
//  JSONToCoreData.m
//  Demo
//
//  Created by Paresh on 29/02/16.
//  Copyright © 2016 Paresh. All rights reserved.
//

#import "JSONToCoreData.h"

@implementation JSONToCoreData

+ (JSONToCoreData *)sharedInstance {
    static id sharedObject;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedObject = [[self alloc] init];
    });
    return sharedObject;
}

#pragma mark -
#pragma mark - CoreData To JSON

- (NSDictionary*)dataStructureFromManagedObject:(NSManagedObject*)managedObject
{
    NSEntityDescription *entityDescription = [managedObject entity];
    NSDictionary *attributesByName = [entityDescription attributesByName];
    NSDictionary *relationshipsByName = [entityDescription relationshipsByName];
    NSMutableDictionary *valuesDictionary = [[managedObject dictionaryWithValuesForKeys:[attributesByName allKeys]] mutableCopy];
    //NSLog(@"properties : %@\npropertiesByName : %@\nattributesByName : %@",[entityDescription properties],[entityDescription propertiesByName],[entityDescription attributesByName]);
    //each managedObject has objectID
    //NSManagedObjectID *objectID = [managedObject objectID];
    //[valuesDictionary setObject:objectID forKey:@"objectID"];

    if (relationshipsByName.count>0)
    {
        for (NSString *relationshipName in [relationshipsByName allKeys]) {
            NSRelationshipDescription *description = [relationshipsByName objectForKey:relationshipName];
            if (![description isToMany]) {
                NSManagedObject *relationshipObject = [managedObject valueForKey:relationshipName];
                [valuesDictionary setObject:[self dataStructureFromManagedObject:relationshipObject] forKey:relationshipName];
                continue;
            }
            
            NSSet *relationshipObjects = [managedObject valueForKey:relationshipName];
            NSMutableArray *relationshipArray = [[NSMutableArray alloc] init];
            for (NSManagedObject *relationshipObject in relationshipObjects) {
                [relationshipArray addObject:[self dataStructureFromManagedObject:relationshipObject]];
            }
            [valuesDictionary setObject:relationshipArray forKey:relationshipName];
        }
    }
    
    return valuesDictionary;
}

- (NSArray*)jsonStructureFromManagedObjects:(NSArray*)managedObjects
{
    NSMutableArray *dataArray = [[NSMutableArray alloc] init];
    for (NSManagedObject *managedObject in managedObjects) {
        [dataArray addObject:[self dataStructureFromManagedObject:managedObject]];
    }
    return dataArray;
}

#pragma mark -
#pragma mark - JSON To CoreData (Create)

- (NSArray*)insertManagedObjectsFromJSONStructure:(id)jsonData forEntity:(NSString *)strEntityName withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext andPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    NSArray *arrJsonData;
    if ([jsonData isKindOfClass:[NSDictionary class]] || [jsonData isKindOfClass:[NSMutableDictionary class]])
        arrJsonData = [NSArray arrayWithObjects:jsonData,nil];
    else if ([jsonData isKindOfClass:[NSArray class]] || [jsonData isKindOfClass:[NSMutableArray class]])
        arrJsonData = jsonData;
    else
        NSAssert(NO,@"Class : JSONToCoreData | method : managedObjectsFromJSONStructure -> jsonData should be array or dictionary");
    
    NSMutableArray *mutArrAllObjects = [NSMutableArray array];
    
    for (NSDictionary *structureDictionary in arrJsonData) {
        
        NSManagedObject *insertManagedObject = [self insertManagedObjectFromStructure:structureDictionary forEntity:strEntityName withManagedObjectContext:managedObjectContext];
        //NSURL *managedObjURI = [tempManagedObject.objectID URIRepresentation];
        
        if (insertManagedObject)
        {
            //NSLog(@"Before %@ : %d",insertManagedObject.objectID,insertManagedObject.objectID.isTemporaryID);

            //Obtain permanentID for object 
            NSError *error;
            BOOL hasObtainedPermanentID = [managedObjectContext obtainPermanentIDsForObjects:[NSArray arrayWithObjects:insertManagedObject, nil] error:&error]; //;
            if (hasObtainedPermanentID && error == nil){
                
                //NSLog(@"After %@ : %d",insertManagedObject.objectID,insertManagedObject.objectID.isTemporaryID);
                
                //check context has changes and is saved in context
                if ([managedObjectContext hasChanges] && [managedObjectContext save:&error])
                {
                    [mutArrAllObjects addObject:insertManagedObject];
                }
            }

        }
        
    }
    
    return [mutArrAllObjects copy];
}

- (NSManagedObject*)insertManagedObjectFromStructure:(NSDictionary*)structureDictionary forEntity:(NSString *)strEntityName withManagedObjectContext:(NSManagedObjectContext*)managedObjContext
{
    //NSManagedObject *managedObject = [NSEntityDescription insertNewObjectForEntityForName:strEntityName inManagedObjectContext:managedObjContext];
    
    NSEntityDescription *entity = [NSEntityDescription entityForName:strEntityName inManagedObjectContext:managedObjContext];
    NSManagedObject * managedObject = (NSManagedObject *)[[NSClassFromString(strEntityName) alloc] initWithEntity:entity insertIntoManagedObjectContext:managedObjContext];

    if (managedObject)
    {
        NSDictionary *relationshipsByName = [[managedObject entity] relationshipsByName];
        if (relationshipsByName.count>0)
        {
            NSArray *arrAllRelationShipsKey = [relationshipsByName allKeys];
            
            for (NSString *strKey in [structureDictionary allKeys]) {
                
                if (![arrAllRelationShipsKey containsObject:strKey]) {
                    [managedObject setValue:[structureDictionary objectForKey:strKey] forKey:strKey];
                }
            }
            
            for (NSString *relationshipName in arrAllRelationShipsKey) {
                NSRelationshipDescription *description = [relationshipsByName objectForKey:relationshipName];
                NSEntityDescription *destinationEntity = description.destinationEntity;
                NSString *strDestEntityName = destinationEntity.renamingIdentifier;
                
                if (![description isToMany]) {
                    NSDictionary *childStructureDictionary = [structureDictionary objectForKey:relationshipName];
                    NSManagedObject *childObject = [self insertManagedObjectFromStructure:childStructureDictionary forEntity:strDestEntityName withManagedObjectContext:managedObjContext];
                    [managedObject setValue:childObject forKey:relationshipName];
                    continue;
                }
                
                NSMutableSet *relationshipSet = [managedObject mutableSetValueForKey:relationshipName];
                NSArray *relationshipArray = [structureDictionary objectForKey:relationshipName];
                for (NSDictionary *childStructureDictionary in relationshipArray) {
                    NSManagedObject *childObject = [self insertManagedObjectFromStructure:childStructureDictionary forEntity:strDestEntityName withManagedObjectContext:managedObjContext];
                    [relationshipSet addObject:childObject];
                }
            }
            
        }
        else
        {
            [managedObject setValuesForKeysWithDictionary:structureDictionary];
        }
        
        
        
        return managedObject;
    }
    else
        return nil;
    
}


#pragma mark -
#pragma mark - JSON To CoreData (Update)

//- (NSArray <NSManagedObject*> *)updateManagedObjectsFromJSONStructure:(id)jsonData forManagedObjects:(NSArray <NSManagedObject*> *)managedObjects withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext{
//    NSArray *arrJsonData;
//    if ([jsonData isKindOfClass:[NSDictionary class]] || [jsonData isKindOfClass:[NSMutableDictionary class]])
//        arrJsonData = [NSArray arrayWithObjects:jsonData,nil];
//    else if ([jsonData isKindOfClass:[NSArray class]] || [jsonData isKindOfClass:[NSMutableArray class]])
//        arrJsonData = jsonData;
//    else
//        NSAssert(NO,@"Class : JSONToCoreData | method : updateManagedObjectsFromJSONStructure -> jsonData should be array or dictionary");
//    
//    NSMutableArray *arrAllObjects = [NSMutableArray array];
//    
//    for (NSDictionary *structureDictionary in arrJsonData) {
//        
//        NSArray *arrAllKeys = [structureDictionary allKeys];
//        if ([arrAllKeys containsObject:keyManagedObjectID]) {
//            
//             //[arrAllObjects addObject:[self updateManagedObjectFromStructure:structureDictionary forEntity:strEntityName withManagedObjectContext:managedObjectContext]];
//        }
//        else
//             NSAssert(NO,@"Class : JSONToCoreData | method : updateManagedObjectsFromJSONStructure -> need to get objectid of saved core data object");
//       
//    }
//    return arrAllObjects;
//}

- (NSManagedObject *)updateManagedObjectsFromJSONStructure:(NSDictionary *)jsonDict forManagedObject:(NSManagedObject *)managedObject withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext
{
    if (managedObject != nil)
    {
        if ([jsonDict isKindOfClass:[NSDictionary class]] && jsonDict.count>0) {
            
            NSDictionary *relationshipsByName = [[managedObject entity] relationshipsByName];
            if (relationshipsByName.count>0)
            {
                NSArray *arrAllRelationShipsKey = [relationshipsByName allKeys];
                
                for (NSString *strKey in [jsonDict allKeys]) {
                    
                    if (![arrAllRelationShipsKey containsObject:strKey])
                    {
                        [managedObject setValue:[jsonDict objectForKey:strKey] forKey:strKey];
                    }
                }
                
                for (NSString *relationshipName in arrAllRelationShipsKey) {
                    NSRelationshipDescription *description = [relationshipsByName objectForKey:relationshipName];
                    //NSEntityDescription *destinationEntity = description.destinationEntity;
                    //NSString *strDestEntityName = destinationEntity.renamingIdentifier;
                    
                    if (![description isToMany]) {
                        NSDictionary *childStructureDictionary = [jsonDict objectForKey:relationshipName];
                        NSManagedObject *childObject = [managedObject valueForKey:relationshipName];
                        childObject = [self updateChildManagedObjectsFromJSONStructure:childStructureDictionary forManagedObject:childObject withManagedObjectContext:managedObjectContext];
                        if (childObject)
                            [managedObject setValue:childObject forKey:relationshipName];
                        continue;
                    }
                    
                    NSMutableSet *relationshipSet = [managedObject mutableSetValueForKey:relationshipName];
                    NSArray *relationshipArray = [jsonDict objectForKey:relationshipName];
                    
                    NSArray *arrAllObjects = [[managedObject valueForKey:relationshipName] allObjects];
                    
                    for (int i = 0; i<[relationshipArray count]; i++)
                    {
                        NSDictionary *childStructureDictionary = [relationshipArray objectAtIndex:i];
                        NSManagedObject *childObject = [arrAllObjects objectAtIndex:i];
                        childObject = [self updateChildManagedObjectsFromJSONStructure:childStructureDictionary forManagedObject:childObject withManagedObjectContext:managedObjectContext];
                        if (childObject)
                            [relationshipSet addObject:childObject];
                    }
                }
            }
            else
            {
                [managedObject setValuesForKeysWithDictionary:jsonDict];
            }
            
            if (![managedObject isFault]) {
                [managedObjectContext refreshObject:managedObject mergeChanges:YES];
                NSError *error = nil;
                if([managedObjectContext hasChanges] && [managedObjectContext save:&error])
                {
                    return managedObject;
                }
                else
                    return nil;
            }
            else
                return nil;
        }
        else
        {
            NSAssert(NO,@"Class : JSONToCoreData | method : updateManagedObjectsFromJSONStructure -> jsonDict should be dictionary and should not be null");
            return nil;
        }
    }
    else
        return nil;
}

- (NSManagedObject *)updateChildManagedObjectsFromJSONStructure:(NSDictionary *)jsonDict forManagedObject:(NSManagedObject *)managedObject withManagedObjectContext:(NSManagedObjectContext*)managedObjContext
{
    if (managedObject != nil)
    {
        if ([jsonDict isKindOfClass:[NSDictionary class]] && jsonDict.count>0) {
            
            [managedObject setValuesForKeysWithDictionary:jsonDict];
            
            return managedObject;
        }
        else
        {
            NSAssert(NO,@"Class : JSONToCoreData | method : updateChildManagedObjectsFromJSONStructure -> jsonDict should be dictionary and should not be null");
            return nil;
        }
    }
    else
        return nil;
}


@end
