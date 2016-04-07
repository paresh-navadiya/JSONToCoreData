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
            
            if ([self isValidManagedObject:relationshipObject])
            {
                //get JSON Structure from relationship
                NSDictionary *dictJSON = [self dataStructureFromManagedObject:relationshipObject];
                
                //set JSON Structure for key
                if ([self isValidDictionaryWithData:dictJSON])
                    [valuesDictionary setObject:dictJSON forKey:relationshipName];
                
                continue;
            }
            
        }
        
        //relationship has many
        NSSet *relationshipObjects = [managedObject valueForKey:relationshipName];
        //each relationship with many will have one set
        NSMutableArray *relationshipArray = [[NSMutableArray alloc] init];
        //iterate one by one
        for (NSManagedObject *relationshipObject in relationshipObjects) {
            
            if ([self isValidManagedObject:relationshipObject])
            {
                //get JSON Structure from relationship
                NSDictionary *dictJSON = [self dataStructureFromManagedObject:relationshipObject];
                //set JSON Structure for relationship key after validating
                if ([self isValidDictionaryWithData:dictJSON])
                    [relationshipArray addObject:dictJSON];
            }
        }
        //Now set JSON Structure for relationship with many
        [valuesDictionary setObject:relationshipArray forKey:relationshipName];
    }
    
    //At last provide dictionary
    return valuesDictionary;
}

//JSON structure from NSManagedObject's
- (NSArray*)jsonStructureFromManagedObjects:(NSArray*)arrManagedObjects
{
    //Intialize array to store created JSON Structure from NSManagedObject
    NSMutableArray *mutArrJSON = [[NSMutableArray alloc] init];
    
     if ([self isValidArrayWithData:arrManagedObjects])
     {
         //create  JSON Structure from NSManagedObject one by one
         for (id object in arrManagedObjects) {
             
             //check whether array has NSManagedObject or not
             if ([self isValidManagedObject:object])
             {
                 NSManagedObject *managedObject = (NSManagedObject *)object;
                 //get JSON Structure from NSManagedObject
                 NSDictionary *dictJSON = [self dataStructureFromManagedObject:managedObject];
                 //add JSON Structure in array after validating
                 if ([self isValidDictionaryWithData:dictJSON])
                     [mutArrJSON addObject:dictJSON];
             }
         }
         return [mutArrJSON copy];
     }
    else
        return nil;
      
}

#pragma mark -
#pragma mark -JSONTo CoreData (Create)

- (NSArray*)insertManagedObjectsFromJSONStructure:(id)jsonData forEntity:(NSString *)strEntityName withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext;
{
    //Need to convert json to array if necessary so we can iterate multiple objects
    //Consider it can be NSDictionary or NSArray so need to maintain only one NSArray
    //Also it can be validated here that it accepts only NSDictionary or NSArray
    NSArray *arrJsonData = [self createJSONDataToArrayIfNecessary:jsonData];
    
    //Validation
    if (![self isValidArrayWithData:arrJsonData])
        return nil;
    else if (![self isValidStringWithData:strEntityName])
        return nil;
    else if (![self isValidManagedObjectContext:managedObjectContext])
        return nil;
    else
    {
        //Intialize array to store created object
        NSMutableArray *mutArrAllObjects = [NSMutableArray array];
        
        //insert one by one in coredata
        for (NSDictionary *structureDictionary in arrJsonData) {
            
            if ([self isValidDictionaryWithData:structureDictionary])
            {
                //get inserted NSManagedObject but with temparoryID
                NSManagedObject *insertManagedObject = [self insertManagedObjectFromStructure:structureDictionary forEntity:strEntityName withManagedObjectContext:managedObjectContext];
                
                if ([self isValidManagedObject:insertManagedObject])
                {
                    //Obtain permanentID for that object
                    NSError *error;
                    BOOL hasObtainedPermanentID = [managedObjectContext obtainPermanentIDsForObjects:[NSArray arrayWithObjects:insertManagedObject, nil] error:&error];
                    //has obtained permanentID for object or not
                    if (hasObtainedPermanentID && error == nil){
                        
                        //refresh object in context
                        [managedObjectContext refreshObject:insertManagedObject mergeChanges:YES];
                        
                        //add inserted NSManagedObject with permanentID in array
                        [mutArrAllObjects addObject:insertManagedObject];
                    }
                }
            }
        }
        
        //check context has changes and is saved in context
        if ([managedObjectContext hasChanges]) {
            
            NSError *error = nil;
            BOOL isSaved = [managedObjectContext save:&error];
            if (error && isSaved) {
                //return all inserted NSManagedObject in CoreData
                return [mutArrAllObjects copy];
            }
            else
                return nil;
        }
        else
            return nil;
    }
}


- (NSManagedObject*)insertManagedObjectFromStructure:(NSDictionary*)structureDictionary forEntity:(NSString *)strEntityName withManagedObjectContext:(NSManagedObjectContext*)managedObjContext
{
    //Create NSManagedObject
    //NSManagedObject *managedObject = [NSEntityDescription insertNewObjectForEntityForName:strEntityName inManagedObjectContext:managedObjContext];
    
    NSEntityDescription *entity = [NSEntityDescription entityForName:strEntityName inManagedObjectContext:managedObjContext];
    
    //get all necessary information
    NSDictionary *allAttributes = [entity attributesByName];
    NSDictionary *relationshipsByName = [entity relationshipsByName];
    
    NSArray *arrAllRelationShipsKey = [relationshipsByName allKeys];
    NSArray *arrAllAttributesKey = [allAttributes allKeys];
    
    NSManagedObject * managedObject = (NSManagedObject *)[[NSClassFromString(strEntityName) alloc] initWithEntity:entity insertIntoManagedObjectContext:managedObjContext];
    
    if ([self isValidManagedObject:managedObject])
    {
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
                
                if ([self isValidDictionaryWithData:childStructureDictionary])
                {
                    NSManagedObject *childObject = [self insertManagedObjectFromStructure:childStructureDictionary forEntity:strDestEntityName withManagedObjectContext:managedObjContext];
                    
                    if ([self isValidManagedObject:childObject])
                    {
                        //Expection handling
                        @try {
                            [managedObject setValue:childObject forKey:relationshipName];
                        }
                        @catch (NSException *exception) {
                            NSLog(@"Exception:%@",exception);
                        }
                    }

                }
                
                continue;
            }
            
            //relationship is many
            NSMutableSet *relationshipSet = [managedObject mutableSetValueForKey:relationshipName];
            NSArray *relationshipArray = [structureDictionary objectForKey:relationshipName];
            //iterate one by one
            for (NSDictionary *childStructureDictionary in relationshipArray) {
                
                if ([self isValidDictionaryWithData:childStructureDictionary])
                {
                    NSManagedObject *childObject = [self insertManagedObjectFromStructure:childStructureDictionary forEntity:strDestEntityName withManagedObjectContext:managedObjContext];
                    
                    if ([self isValidManagedObject:childObject])
                        [relationshipSet addObject:childObject];
                }
                
            }
        }
        
        return managedObject;
    }
    else
        return nil;
   
}


#pragma mark -
#pragma mark -JSONTo CoreData (Update)

//upadate NSManagedObject from JSON structure
- (NSManagedObject *)updateManagedObjectsFromJSONStructure:(NSDictionary *)jsonDict forManagedObject:(NSManagedObject *)managedObject withManagedObjectContext:(NSManagedObjectContext*)managedObjectContext
{
    //validation
    if (![self isValidDictionaryWithData:jsonDict])
        return nil;
    else if (![self isValidManagedObject:managedObject])
        return nil;
    else if (![self isValidManagedObjectContext:managedObjectContext])
        return nil;
    else {
        
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
                
                if ([self isValidDictionaryWithData:childStructureDictionary])
                {
                    NSManagedObject *tempChildObject = [managedObject valueForKey:relationshipName];
                    
                    if ([self isValidManagedObject:tempChildObject])
                    {
                        //Update NSManagedObject with JSON Structure
                        NSManagedObject *childObject = [self updateChildManagedObjectsFromJSONStructure:childStructureDictionary forManagedObject:tempChildObject withManagedObjectContext:managedObjectContext];
                        
                        if ([self isValidManagedObject:childObject])
                        {
                            //Expection handling
                            @try {
                                [managedObject setValue:childObject forKey:relationshipName];
                            }
                            @catch (NSException *exception) {
                                NSLog(@"Exception:%@",exception);
                            }
                        }
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
                
                if ([self isValidDictionaryWithData:childStructureDictionary])
                {
                    //get NSManagedObject for relationship
                    NSManagedObject *tempChildObject = [arrAllObjects objectAtIndex:i];
                    
                    if ([self isValidManagedObject:tempChildObject])
                    {
                        //Update NSManagedObject with JSON Structure
                        NSManagedObject *childObject = [self updateChildManagedObjectsFromJSONStructure:childStructureDictionary forManagedObject:tempChildObject withManagedObjectContext:managedObjectContext];
                        if ([self isValidManagedObject:childObject])
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
}

//INTERNAL (update relationship NSManagedObject from JSON structure)
- (NSManagedObject *)updateChildManagedObjectsFromJSONStructure:(NSDictionary *)jsonDict forManagedObject:(NSManagedObject *)managedObject withManagedObjectContext:(NSManagedObjectContext*)managedObjContext
{
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

#pragma mark - Validation

-(NSArray *)createJSONDataToArrayIfNecessary:(id)jsonData
{
    NSArray *arrJsonData = nil;
    if (jsonData) {
        if ([jsonData isKindOfClass:[NSDictionary class]] || [jsonData isKindOfClass:[NSMutableDictionary class]]){
            arrJsonData = [NSArray arrayWithObjects:jsonData,nil];
            return arrJsonData;
        }
        else if ([jsonData isKindOfClass:[NSArray class]] || [jsonData isKindOfClass:[NSMutableArray class]]){
            arrJsonData = jsonData;
            return arrJsonData;
        }
        else //Diffent kind of jsonData Object which is not expected
            return arrJsonData;
    }
    else
        return arrJsonData;
}

-(BOOL)isValidStringWithData:(id)string
{
    if (string && ![string isKindOfClass:[NSNull class]]) {
        if ([string isKindOfClass:[NSString class]]) {
            NSString *strData = (NSString *)string;
            if (strData.length>0)
                return YES;
            else
                return NO;
        }
        return NO;
    }
    else
        return NO;
}

-(BOOL)isValidDictionaryWithData:(id)json
{
    if (json)
    {
        if ([json isKindOfClass:[NSDictionary class]] || [json isKindOfClass:[NSMutableDictionary class]]) {
            
            NSDictionary *dictJSONData = (NSDictionary *)json;
            if (dictJSONData.count == 0)
                return NO;
            else
                return YES;
        }
        else
            return NO;
    }
    else
        return NO;
}

-(BOOL)isValidArrayWithData:(id)json
{
    if (json)
    {
        if ([json isKindOfClass:[NSArray class]] || [json isKindOfClass:[NSMutableArray class]]) {
            
            NSArray *arrJSONData = (NSArray *)json;
            if (arrJSONData.count == 0)
                return NO;
            else
                return YES;
        }
        else
            return NO;
    }
    else
        return NO;
}

-(BOOL)isValidManagedObject:(id)managedObject
{
    if (managedObject)
    {
        if ([managedObject isKindOfClass:[NSManagedObject class]])
            return YES;
        else
            return NO;
    }
    else
        return NO;
}

-(BOOL)isValidManagedObjectContext:(id)managedObjectContext
{
    if (managedObjectContext)
    {
        if ([managedObjectContext isKindOfClass:[NSManagedObjectContext class]])
            return YES;
        else
            return NO;
    }
    else
        return NO;
}


@end
