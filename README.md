# JSONToCoreData
JSON mapping to its respective object into coredata easily

#####How a basic mapping looks like: For example, we have JSON:
```bash
  {
    "name": "Paresh",
    "email": "paresh@gmail.com",
  }
```
#####Corresponding CoreData-generated classes:
```bash
@interface Person : NSManagedObject
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *email;
@end
``` 
#####Now we can deserialize JSON to NSManagedObject so easily:
```bash
NSArray <NSManagedObject *> *arrAllManagedObjects = [[JSONToCoreData sharedInstance] insertManagedObjectsFromJSONStructure:dictJson forEntity:@"Person" withManagedObjectContext:appDelegate.managedObjectContext];
```
Note : It will transform JSON Value if necessary to map to NSManagedObject's AttributeType
```bash
-(id)transformForValue:(id)jsonValue forValueType:(NSString *)strValueType
```
#####Update existing NSManagedObject with JSON Structure
```bash
NSManagedObject *updatedManagedObject = [[JSONToCoreData sharedInstance] updateManagedObjectsFromJSONStructure:dictJson forManagedObject:updatingManagedObject withManagedObjectContext:appDelegate.managedObjectContext];
```
#####Serialize NSManagedObjects to JSON Structure
```bash
NSArray *arrJSON = [[JSONToCoreData sharedInstance] jsonStructureFromManagedObjects:arrAllManagedObjects];
NSLog(@"\nCore Data to JSON ---> arrJson : %@ ",arrJSON);
```
