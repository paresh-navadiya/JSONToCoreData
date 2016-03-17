//
//  JSONToCoreData.m
//  JSONToCoreData
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

//shared instance
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

//JSON structure from NSManagedObject
- (NSDictionary*)dataStructureFromManagedObject:(NSManagedObject*)managedObject
{
    //get all necessary information
    NSEntityDescription *entityDescription = [managedObject entity];
    NSDictionary *attributesByName = [entityDescription attributesByName];
    NSDictionary *relationshipsByName = [entityDescription relationshipsByName];
    
    NSArray *arrAllRelationShipsKey = [relationshipsByName allKeys];
    NSArray *arrAllAttributesKey = [attributesByName allKeys];
    
    //firstly add all attributes
    NSMutableDictionary *valuesDictionary = [[managedObject dictionaryWithValuesForKeys:arrAllAttributesKey] mutableCopy];
    
    //now add all relationship attributes
    for (NSString *relationshipName in arrAllRelationShipsKey) {
        NSRelationshipDescription *description = [relationshipsByName objectForKey:relationshipName];
        
        //check relationship is to many or not
        if (![description isToMany]) {
            NSManagedObject *relationshipObject = [managedObject valueForKey:relationshipName];
            
            //get JSON Structure from relationship
            NSDictionary *dictJSON = [self dataStructureFromManagedObject:relationshipObject];
            
            //set JSON Structure for key
            [valuesDictionary setObject:dictJSON forKey:relationshipName];
            continue;
        }
        
        //relationship has many
        NSSet *relationshipObjects = [managedObject valueForKey:relationshipName];
        //each relationship with many will have one set
        NSMutableArray *relationshipArray = [[NSMutableArray alloc] init];
        //iterate one by one
        for (NSManagedObject *relationshipObject in relationshipObjects) {
            
             //get JSON Structure from relationship
            NSDictionary *dictJSON = [self dataStructureFromManagedObject:relationshipObject];
            //set JSON Structure for key
            [relationshipArray addObject:dictJSON];
        }
        //Now set JSON Structure for relationship with many
        [valuesDictionary setObject:relationshipArray forKey:relationshipName];
    }
    
    //At last provide dictionary
    return valuesDictionary;
}

//JSON structure from NSManagedObject's
- (NSArray*)jsonStructureFromManagedObjects:(NSArray*)managedObjects
{
    //Intialize array to store created JSON Structure from NSManagedObject
    NSMutableArray *mutArrJSON = [[NSMutableArray alloc] init];
    
    //create  JSON Structure from NSManagedObject one by one
    for (id object in managedObjects) {
        
        //check whether array has NSManagedObject or not
        if ([object isKindOfClass:[NSManagedObject class]])
        {
            NSManagedObject *managedObject = (NSManagedObject *)object;
            //get JSON Structure from NSManagedObject
            NSDictionary *dictJSON = [self dataStructureFromManagedObject:managedObject];
            //add JSON Structure in array
            [mutArrJSON addObject:dictJSON];
        }
    }
    return mutArrJSON;
}

#pragma mark -
#pragma mark -JSONTo CoreData (Create)

- (NSArray*)insertManagedObjectsFromJSONStructure:(id)jsonData forEntity:(NSString *)strEntityName withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext;
{
    //Validate
    NSArray *arrJsonData;
    if ([jsonData isKindOfClass:[NSDictionary class]] || [jsonData isKindOfClass:[NSMutableDictionary class]])
        arrJsonData = [NSArray arrayWithObjects:jsonData,nil];
    else if ([jsonData isKindOfClass:[NSArray class]] || [jsonData isKindOfClass:[NSMutableArray class]])
        arrJsonData = jsonData;
    else
        //NSAssert(NO,@"Class : JSONToCoreData | method : managedObjectsFromJSONStructure -> jsonData should be array or dictionary");
        return nil;
    
    //Intialize array to store created object
    NSMutableArray *mutArrAllObjects = [NSMutableArray array];
    
    //insert one by one in coredata
    for (NSDictionary *structureDictionary in arrJsonData) {
        
        //get inserted NSManagedObject but with temparoryID
        NSManagedObject *insertManagedObject = [self insertManagedObjectFromStructure:structureDictionary forEntity:strEntityName withManagedObjectContext:managedObjectContext];
        
        if (insertManagedObject){

            //Obtain permanentID for that object
            NSError *error;
            BOOL hasObtainedPermanentID = [managedObjectContext obtainPermanentIDsForObjects:[NSArray arrayWithObjects:insertManagedObject, nil] error:&error];
            //has obtained permanentID for object or not
            if (hasObtainedPermanentID && error == nil){
                
                //refresh object in context
                [managedObjectContext refreshObject:insertManagedObject mergeChanges:YES];
                
                //check context has changes and is saved in context
                if ([managedObjectContext hasChanges] && [managedObjectContext save:&error]){
                    
                    //add inserted NSManagedObject with permanentID in array
                    [mutArrAllObjects addObject:insertManagedObject];
                }
            }
        }
    }
    
    //return all inserted NSManagedObject in CoreData
    return [mutArrAllObjects copy];
}

- (NSManagedObject*)insertManagedObjectFromStructure:(NSDictionary*)structureDictionary forEntity:(NSString *)strEntityName withManagedObjectContext:(NSManagedObjectContext*)managedObjContext
{
    //Create NSManagedObject
    //NSManagedObject *managedObject = [NSEntityDescription insertNewObjectForEntityForName:strEntityName inManagedObjectContext:managedObjContext];
    
    NSEntityDescription *entity = [NSEntityDescription entityForName:strEntityName inManagedObjectContext:managedObjContext];
    NSManagedObject * managedObject = (NSManagedObject *)[[NSClassFromString(strEntityName) alloc] initWithEntity:entity insertIntoManagedObjectContext:managedObjContext];

    if (managedObject != nil && [managedObject isKindOfClass:[NSManagedObject class]])
    {
        //get all necessary information
        NSDictionary *allAttributes = [entity attributesByName];
        NSDictionary *relationshipsByName = [[managedObject entity] relationshipsByName];
        
        NSArray *arrAllRelationShipsKey = [relationshipsByName allKeys];
        NSArray *arrAllAttributesKey = [allAttributes allKeys];
        
        //Firstly set value of all its attribute
        for (NSString *strKey in arrAllAttributesKey) {
            
            //Expection handling
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
        
        //Now set value of all its relationship
        for (NSString *relationshipName in arrAllRelationShipsKey) {
            
            NSRelationshipDescription *description = [relationshipsByName objectForKey:relationshipName];
            NSEntityDescription *destinationEntity = description.destinationEntity;
            NSString *strDestEntityName = destinationEntity.renamingIdentifier;
            
            //check relationship is to many or not
            if (![description isToMany]) {
                NSDictionary *childStructureDictionary = [structureDictionary objectForKey:relationshipName];
                NSManagedObject *childObject = [self insertManagedObjectFromStructure:childStructureDictionary forEntity:strDestEntityName withManagedObjectContext:managedObjContext];
                
                //Expection handling
                @try {
                    [managedObject setValue:childObject forKey:relationshipName];
                }
                @catch (NSException *exception) {
                    NSLog(@"Exception:%@",exception);
                }
                continue;
            }
            
            //relationship is many
            NSMutableSet *relationshipSet = [managedObject mutableSetValueForKey:relationshipName];
            NSArray *relationshipArray = [structureDictionary objectForKey:relationshipName];
            //iterate one by one
            for (NSDictionary *childStructureDictionary in relationshipArray) {
                NSManagedObject *childObject = [self insertManagedObjectFromStructure:childStructureDictionary forEntity:strDestEntityName withManagedObjectContext:managedObjContext];
                [relationshipSet addObject:childObject];
            }
        }
        
        return managedObject;
    }
    else
    {
        //NSAssert(NO,@"Class : JSONToCoreData | method : insertManagedObjectFromStructure -> needed NSManagedObject was not created");
        return nil;
    }
}


#pragma mark -
#pragma mark -JSONTo CoreData (Update)

//upadate NSManagedObject from JSON structure
- (NSManagedObject *)updateManagedObjectsFromJSONStructure:(NSDictionary *)jsonDict forManagedObject:(NSManagedObject *)managedObject withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext
{
    //validate
    if (managedObject != nil && [managedObject isKindOfClass:[NSManagedObject class]])
    {
        if ([jsonDict isKindOfClass:[NSDictionary class]] && jsonDict.count>0) {
            
            //get all necessary information
            NSDictionary *allAttributes = [managedObject.entity attributesByName];
            NSDictionary *relationshipsByName = [[managedObject entity] relationshipsByName];
            
            NSArray *arrAllRelationShipsKey = [relationshipsByName allKeys];
            NSArray *arrAllAttributesKey = [allAttributes allKeys];

            //Firstly set value of all its attribute
            for (NSString *strKey in arrAllAttributesKey) {
                
                //Expection handling
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
            
            //Now set value of all its relationship
            for (NSString *relationshipName in arrAllRelationShipsKey) {
                NSRelationshipDescription *description = [relationshipsByName objectForKey:relationshipName];
                //NSEntityDescription *destinationEntity = description.destinationEntity;
                //NSString *strDestEntityName = destinationEntity.renamingIdentifier;
                
                 //check relationship is to many or not
                if (![description isToMany]) {
                    NSDictionary *childStructureDictionary = [jsonDict objectForKey:relationshipName];
                    NSManagedObject *childObject = [managedObject valueForKey:relationshipName];
                    childObject = [self updateChildManagedObjectsFromJSONStructure:childStructureDictionary forManagedObject:childObject withManagedObjectContext:managedObjectContext];
                    if (childObject)
                    {
                        //Expection handling
                        @try {
                            [managedObject setValue:childObject forKey:relationshipName];
                        }
                        @catch (NSException *exception) {
                            NSLog(@"Exception:%@",exception);
                        }
                    }
                    continue;
                }
                
                 //relationship is many
                NSMutableSet *relationshipSet = [managedObject mutableSetValueForKey:relationshipName];
                NSArray *relationshipArray = [jsonDict objectForKey:relationshipName];
                
                //get all NSManagedObject for relationship so it can be updated
                NSArray *arrAllObjects = [[managedObject valueForKey:relationshipName] allObjects];
                //iterate one by one
                for (int i = 0; i<[relationshipArray count]; i++)
                {
                    //get child JSON structure for relationship
                    NSDictionary *childStructureDictionary = [relationshipArray objectAtIndex:i];
                    //get NSManagedObject for relationship
                    NSManagedObject *childObject = [arrAllObjects objectAtIndex:i];
                    //Update with JSON Structure
                    childObject = [self updateChildManagedObjectsFromJSONStructure:childStructureDictionary forManagedObject:childObject withManagedObjectContext:managedObjectContext];
                    if (childObject)
                    {
                        //Expection handling
                        @try {
                            [relationshipSet addObject:childObject];
                        }
                        @catch (NSException *exception) {
                            NSLog(@"Exception:%@",exception);
                        }
                    }
                }
            }

            //Refresh NSManagedObject and update
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
            //NSAssert(NO,@"Class : JSONToCoreData | method : updateManagedObjectsFromJSONStructure -> jsonDict should be dictionary and should not be null");
            return nil;
        }
    }
    else
    {
        //NSAssert(NO,@"Class : JSONToCoreData | method : updateChildManagedObjectsFromJSONStructure -> managedObject should not be null");
        return nil;
    }
}

//INTERNAL (update relationship NSManagedObject from JSON structure)
- (NSManagedObject *)updateChildManagedObjectsFromJSONStructure:(NSDictionary *)jsonDict forManagedObject:(NSManagedObject *)managedObject withManagedObjectContext:(NSManagedObjectContext*)managedObjContext
{
    if (managedObject != nil && [managedObject isKindOfClass:[NSManagedObject class]])
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
            
            //return updated relationship NSManagedObject
            return managedObject;
        }
        else
        {
            //NSAssert(NO,@"Class : JSONToCoreData | method : updateChildManagedObjectsFromJSONStructure -> jsonDict should be dictionary and should not be null");
            return nil;
        }
    }
    else
    {
        //NSAssert(NO,@"Class : JSONToCoreData | method : updateChildManagedObjectsFromJSONStructure -> managedObject should not be null");
        return nil;
    }
}

#pragma mark - JSONValueTransformer
//Tranform JSONValue to NSManagedObject's AttributeType
-(id)transformForValue:(id)jsonValue forValueType:(NSString *)strValueType
{
    id transformedValue;
    // but did not find any solution, maybe that's the best idea? (hardly)
    Class sourceClass = [JSONValueTransformer classByResolvingClusterClasses:[jsonValue class]];
    
    //JMLog(@"to type: [%@] from type: [%@] transformer: [%@]", p.type, sourceClass, selectorName);
    
    if ([NSStringFromClass(sourceClass) isEqualToString:strValueType]) {
        transformedValue = jsonValue;
        return transformedValue;
    }
    
    //build a method selector for the property and JSON object classes
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
        
        // it's not aJSONdata type, and there's no transformer for it
        // if property type is not supported - that's a programmer mistake -> exception
        @throw [NSException exceptionWithName:@"Type not allowed"
                                       reason:[NSString stringWithFormat:@"%@ type not supported for %@",strValueType,sourceClass]
                                     userInfo:nil];
        return nil;
    }
}


@end
