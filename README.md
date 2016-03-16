# JSONToCoreData
JSON mapping to its respective object into coredata with so easy

#####How a basic mapping looks like: For example, we have JSON:
```bash
  {
    "name": "Paresh",
    "email": "paresh@gmail.com",
  }
```
#####CorrespondingCoreData-generated classes:
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
#####Update existing NSManagedObject with JSON Structure
```bash
NSManagedObject *updatedManagedObj = [[JSONToCoreData sharedInstance] updateManagedObjectsFromJSONStructure:dictJson forManagedObject:tempManagedObj withManagedObjectContext:appDelegate.managedObjectContext];
```
#####Serialize NSManagedObjects to JSON Structure
```bash
NSArray *arrJson = [[JSONToCoreData sharedInstance] jsonStructureFromManagedObjects:arrAllManagedObjects];
NSLog(@"\nCore Data to JSON ---> arrJson : %@ ",arrJson);
```
