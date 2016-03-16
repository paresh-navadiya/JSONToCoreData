//
//  JSONToCoreData.m
//  Demo
//
//  Created by Paresh on 29/02/16.
//  Copyright © 2016 Paresh. All rights reserved.
//

#import <objc/runtime.h>
#import <objc/message.h>

#import "JSONToCoreData.h"
#import "JSONValueTransformer.h"

static JSONValueTransformer* valueTransformer = nil;

@implementation JSONToCoreData

+ (JSONToCoreData *)sharedInstance {
    static id sharedObject;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedObject = [[self alloc] init];
        valueTransformer = [[JSONValueTransformer alloc] init];
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

    if (relationshipsByName.count>0){
        
        for (NSString *relationshipName in [relationshipsByName allKeys]) {
            NSRelationshipDescription *description = [relationshipsByName objectForKey:relationshipName];
            if (![description isToMany]) {
                NSManagedObject *relationshipObject = [managedObject valueForKey:relationshipName];
                NSDictionary *dictJSON = [self dataStructureFromManagedObject:relationshipObject];
                [valuesDictionary setObject:dictJSON forKey:relationshipName];
                continue;
            }
            
            NSSet *relationshipObjects = [managedObject valueForKey:relationshipName];
            NSMutableArray *relationshipArray = [[NSMutableArray alloc] init];
            for (NSManagedObject *relationshipObject in relationshipObjects) {
                NSDictionary *dictJSON = [self dataStructureFromManagedObject:relationshipObject];
                [relationshipArray addObject:dictJSON];
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

- (NSArray*)insertManagedObjectsFromJSONStructure:(id)jsonData forEntity:(NSString *)strEntityName withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext;
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
        
        if (insertManagedObject){

            //Obtain permanentID for object 
            NSError *error;
            BOOL hasObtainedPermanentID = [managedObjectContext obtainPermanentIDsForObjects:[NSArray arrayWithObjects:insertManagedObject, nil] error:&error]; //;
            if (hasObtainedPermanentID && error == nil){
                
                //check context has changes and is saved in context
                if ([managedObjectContext hasChanges] && [managedObjectContext save:&error]){
                    
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
        NSDictionary *allAttributes = [entity attributesByName];
        NSDictionary *relationshipsByName = [[managedObject entity] relationshipsByName];
        
        if (relationshipsByName.count>0)
        {

            NSArray *arrAllRelationShipsKey = [relationshipsByName allKeys];
            
            for (NSString *strKey in [structureDictionary allKeys]) {
                
                if (![arrAllRelationShipsKey containsObject:strKey]) {
                    
                    @try {
                        
                        id jsonValue = [structureDictionary objectForKey:strKey];
                        if (!isNull(jsonValue)) {
                            NSString *strValueType = [[allAttributes objectForKey:strKey] attributeValueClassName];
                            id transformedValue = [self transformForValue:jsonValue forValueType:strValueType];
                            if(transformedValue)
                                [managedObject setValue:transformedValue forKey:strKey];
                        }
                    }
                    @catch (NSException *exception) {
                        NSLog(@"Exception:%@",exception);
                    }
                }
            }
            
            for (NSString *relationshipName in arrAllRelationShipsKey) {
                NSRelationshipDescription *description = [relationshipsByName objectForKey:relationshipName];
                NSEntityDescription *destinationEntity = description.destinationEntity;
                NSString *strDestEntityName = destinationEntity.renamingIdentifier;
                
                if (![description isToMany]) {
                    NSDictionary *childStructureDictionary = [structureDictionary objectForKey:relationshipName];
                    NSManagedObject *childObject = [self insertManagedObjectFromStructure:childStructureDictionary forEntity:strDestEntityName withManagedObjectContext:managedObjContext];
                    @try {
                        [managedObject setValue:childObject forKey:relationshipName];
                    }
                    @catch (NSException *exception) {
                        NSLog(@"Exception:%@",exception);
                    }
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
            for (NSString *strKey in [structureDictionary allKeys]) {
                @try {
                    id jsonValue = [structureDictionary objectForKey:strKey];
                    if (!isNull(jsonValue)) {
                        NSString *strValueType = [[allAttributes objectForKey:strKey] attributeValueClassName];
                        id transformedValue = [self transformForValue:jsonValue forValueType:strValueType];
                        if(transformedValue)
                            [managedObject setValue:transformedValue forKey:strKey];
                    }
                }
                @catch (NSException *exception) {
                    NSLog(@"Exception:%@",exception);
                }
            }
            //[managedObject setValuesForKeysWithDictionary:structureDictionary];
        }
        
        return managedObject;
    }
    else
        return nil;
}


#pragma mark -
#pragma mark - JSON To CoreData (Update)

- (NSManagedObject *)updateManagedObjectsFromJSONStructure:(NSDictionary *)jsonDict forManagedObject:(NSManagedObject *)managedObject withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext
{
    if (managedObject != nil)
    {
        if ([jsonDict isKindOfClass:[NSDictionary class]] && jsonDict.count>0) {
            
            NSDictionary *allAttributes = [managedObject.entity attributesByName];
            NSDictionary *relationshipsByName = [[managedObject entity] relationshipsByName];
            if (relationshipsByName.count>0)
            {
                NSArray *arrAllRelationShipsKey = [relationshipsByName allKeys];
                
                for (NSString *strKey in [jsonDict allKeys]) {
                    
                    if (![arrAllRelationShipsKey containsObject:strKey])
                    {
                        @try {
                            
                            id jsonValue = [jsonDict objectForKey:strKey];
                            if (!isNull(jsonValue)) {
                                NSString *strValueType = [[allAttributes objectForKey:strKey] attributeValueClassName];
                                id transformedValue = [self transformForValue:jsonValue forValueType:strValueType];
                                if(transformedValue)
                                    [managedObject setValue:transformedValue forKey:strKey];
                            }
                        }
                        @catch (NSException *exception) {
                            NSLog(@"Exception:%@",exception);
                        }
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
                        {
                            @try {
                                [managedObject setValue:childObject forKey:relationshipName];
                            }
                            @catch (NSException *exception) {
                                NSLog(@"Exception:%@",exception);
                            }
                        }
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
                        {
                            @try {
                                [relationshipSet addObject:childObject];
                            }
                            @catch (NSException *exception) {
                                NSLog(@"Exception:%@",exception);
                            }
                        }
                    }
                }
            }
            else
            {
                for (NSString *strKey in [jsonDict allKeys]) {
                    @try {
                        id jsonValue = [jsonDict objectForKey:strKey];
                        if (!isNull(jsonValue)) {
                            NSString *strValueType = [[allAttributes objectForKey:strKey] attributeValueClassName];
                            id transformedValue = [self transformForValue:jsonValue forValueType:strValueType];
                            if(transformedValue)
                                [managedObject setValue:transformedValue forKey:strKey];
                        }
                    }
                    @catch (NSException *exception) {
                        NSLog(@"Exception:%@",exception);
                    }
                }
                //[managedObject setValuesForKeysWithDictionary:jsonDict];
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
            
            NSDictionary *allAttributes = [managedObject.entity attributesByName];
            for (NSString *strKey in [jsonDict allKeys]) {
                @try {
                    id jsonValue = [jsonDict objectForKey:strKey];
                    if (!isNull(jsonValue)) {
                        NSString *strValueType = [[allAttributes objectForKey:strKey] attributeValueClassName];
                        id transformedValue = [self transformForValue:jsonValue forValueType:strValueType];
                        if(transformedValue)
                            [managedObject setValue:transformedValue forKey:strKey];
                    }
                }
                @catch (NSException *exception) {
                    NSLog(@"Exception:%@",exception);
                }
            }
            //[managedObject setValuesForKeysWithDictionary:jsonDict];
            
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

#pragma mark - JSONValueTransformer

-(id)transformForValue:(id)jsonValue forValueType:(NSString *)strValueType
{
    id transformedValue;
    // searched around the web how to do this better
    // but did not find any solution, maybe that's the best idea? (hardly)
    Class sourceClass = [JSONValueTransformer classByResolvingClusterClasses:[jsonValue class]];
    
    //JMLog(@"to type: [%@] from type: [%@] transformer: [%@]", p.type, sourceClass, selectorName);
    
    if ([NSStringFromClass(sourceClass) isEqualToString:strValueType]) {
        transformedValue = jsonValue;
        return transformedValue;
    }
    
    //build a method selector for the property and json object classes
    NSString* selectorName = [NSString stringWithFormat:@"%@From%@:",
                              strValueType, //target name
                              sourceClass]; //source name
    SEL selector = NSSelectorFromString(selectorName);
    
    //check for custom transformer
    BOOL foundCustomTransformer = NO;
    if ([valueTransformer respondsToSelector:selector]) {
        foundCustomTransformer = YES;
    } else {
        //try for hidden custom transformer
        selectorName = [NSString stringWithFormat:@"__%@",selectorName];
        selector = NSSelectorFromString(selectorName);
        if ([valueTransformer respondsToSelector:selector]) {
            foundCustomTransformer = YES;
        }
    }
    
    //check if there's a transformer with that name
    if (foundCustomTransformer) {
        
        //it's OK, believe me...
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        //transform the value
        transformedValue = [valueTransformer performSelector:selector withObject:jsonValue];
#pragma clang diagnostic pop
        return transformedValue;
        
    } else {
        
        // it's not a JSON data type, and there's no transformer for it
        // if property type is not supported - that's a programmer mistake -> exception
        @throw [NSException exceptionWithName:@"Type not allowed"
                                       reason:[NSString stringWithFormat:@"%@ type not supported for %@",strValueType,sourceClass]
                                     userInfo:nil];
        return nil;
    }
}


@end
