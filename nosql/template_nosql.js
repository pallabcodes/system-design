// START HERE: https://www.mongodb.com/docs/manual/introduction/

// # Insert : if the collection doesn't exist, it will be created
db.inventory.insertOne({
    item: "journal",
    qty: 25,
    tags: ["writing", "stationery"],
    size: { h: 14, w: 21, uom: "cm" }
  });
  
  db.inventory.insertMany([
    {
      item: "notebook",
      qty: 50,
      tags: ["writing", "school"],
      size: { h: 14, w: 9, uom: "cm" }
    },
    {
      item: "paper",
      qty: 100,
      tags: ["writing", "office"],
      size: { h: 20, w: 30, uom: "cm" }
    },
    {
      item: "eraser",
      qty: 30,
      tags: ["stationery"],
      size: { h: 2, w: 5, uom: "cm" }
    }
  ]);
  
  db.inventory.updateOne(
    { item: "journal" },          // Filter
    { $set: { qty: 55 } }         // Update
  );
  
  db.inventory.updateMany(
    { tags: "writing" },          // Filter
    { $inc: { qty: 10 } }         // Update
  );
  
  db.inventory.replaceOne(
    { item: "notebook" },         // Filter
    { item: "spiral notebook", qty: 45, tags: ["school", "stationery"] } // New document but since no value provided for size so size will be empty
  );
  
  db.inventory.findOneAndUpdate(
    { item: "paper" },            // Filter
    { $set: { qty: 120 } },       // Update
    { returnDocument: "after" }   // Options: return updated document
  );
  
  db.inventory.deleteOne({ item: "spiral notebook" }); // acknowledge: true, deletedCount: 1 (or 0 if already deleted)
  db.inventory.deleteMany({ tags: "stationery" });
  db.inventory.findOneAndDelete({ item: "paper" }); // deleted document but if already deleted or doesn't exist then null
  
  
  
  db.inventory.findOneAndUpdate({item: 'stencil'}, {$set: {
      item: "stencil",
      qty: 10,
      tags: ["stationery"],
      size: { h: 2, w: 5, uom: "cm" }
    }}, {upsert: true});
  
  db.inventory.findOneAndReplace(
    { item: "whiteboard" },         // Filter
    { item: "whiteboard", qty: 10 }, // Replacement document
    { upsert: true, returnDocument: "after" } // Upsert and return updated doc
  );
  
  // bulkWrite allows to perform insert, update and deletion at the same time
  db.inventory.bulkWrite([
    { insertOne: { document: { item: "marker", qty: 50 } } },
    { updateOne: { filter: { item: "pen" }, update: { $inc: { qty: 10 } }, upsert: true } },
    { deleteOne: { filter: { item: "eraser" } } }
  ]);
  
  db.inventory.insertMany([
    {
      item: 'journal',
      qty: 25,
      size: { h: 14, w: 21, uom: 'cm' },
      status: 'A'
    },
    {
      item: 'notebook',
      qty: 50,
      size: { h: 8.5, w: 11, uom: 'in' },
      status: 'A'
    },
    {
      item: 'paper',
      qty: 100,
      size: { h: 8.5, w: 11, uom: 'in' },
      status: 'D'
    },
    {
      item: 'planner',
      qty: 75,
      size: { h: 22.85, w: 30, uom: 'cm' },
      status: 'D'
    },
    {
      item: 'postcard',
      qty: 45,
      size: { h: 10, w: 15.25, uom: 'cm' },
      status: 'A'
    }
  ]);
  
  db.inventory.find(); // db.inventory.find({});
  
  db.inventory.find({status: 'A'});
  db.inventory.find({status: 'A', qty: {$gt: 30}});
  db.inventory.find({$or: [{status: 'A'}, {qty: {$lt: 30}}]});
  db.inventory.find({$and: [{status: 'A'}, {qty: {$lte: 50}}]});
  db.inventory.find({status: 'A', $or: [{qty: 30},{item: {$regex: '^p'}}]});
  db.inventory.find({status: {$in: ['A', 'D']}});
  
  // ## Querying on embedded / nested documents
  db.inventory.updateOne(
    { "item": "marker" },          // Filter documents with size.uom equal to "cm"
    { $set: { "size.uom": "in" } }, // Update size.uom to "in",
    {upsert: true}
  );
  
  //db.inventory.updateMany(
  //  { "size.uom": "cm" },
  //  { $set: { "size.uom": "in" } }
  //);
  
  db.inventory.find({status: 'A', 'size.uom': 'cm', 'size.h': {$lt: 15}});
  
  db.inventory.find({
    size: {
      h: NumberInt(14),
      w: NumberInt(21),
      uom: "cm"
    }
  });
  
  // ## queryng on array
  db.inventory.find();
  
  db.inventory.find({tags: ['school']}); // find documents where tags exactly 'school' so it won't pick document(s) like ['school', 'office']
  // The following  queries for all documents where tags is an array that contains the string "red" as one of its elements:
  db.inventory.find({tags: 'school'});
  db.inventory.find({tags: {$all: ['school']}}); // does same as the above
  
  db.inventory.find().forEach(doc => {
    const randomDim = [Math.floor(Math.random() * 50) + 1, Math.floor(Math.random() * 50) + 1]; // Random numbers between 1 and 50
    db.inventory.updateOne(
      { _id: doc._id },
      { $set: { dim_cm: randomDim } }
    );
  });
  
  db.inventory.find({dim_cm: {$gt: 15, $lt: 20}});
  
  // find dim_cm array where dim_cm array contains at least one element that is both greater than ($gt) 22 and less than ($lt) 30:
  db.inventory.find({dim_cm: {$elemMatch: {$gt: 15, $lt: 20}}  });
  
  // find from dim_cm array where its second element greater then 25
  db.inventory.find({'dim_cm.1': {$gt: 20}  });
  
  // find from tags array where tags size is 2
  db.inventory.find({tags: {$size: 2}  });
  
  db.inventory.updateMany(
  {},
  {$set: {instock: [
    { warehouse: 'A', qty: 5 },
    { warehouse: 'C', qty: 15 }
  ]
  }}
  );
  db.inventory.find();
  
  db.inventory.find({ instock: { warehouse: 'A', qty: 5 } });
  db.inventory.find({ instock: { warehouse: 'A', qty: {$gte: 15} } });
  
  // select all documents where the instock array has at least one embedded document or element that contains the field qty whose value is less than or equal to 20
  db.inventory.find({
    'instock.qty': {$gte: 20}
  });
  // select all documents where the instock array's first embedded document or element that contains the field qty whose value is less than or equal to 20
  db.inventory.find({
    'instock.0.qty': { $lte: 20 }
  });
  
  // queries for documents where the instock array has at least one embedded document that contains both the field qty equal to 5 and the field warehouse equal to A:
  
  db.inventory.find({
    instock: { $elemMatch: { qty: 5, warehouse: 'A' } }
  });
  
  // queries for documents where the instock array has "at least one embedded document that contains the field qty that is greater than 10 and less than or equal to 20"
  db.inventory.find({instock: { $elemMatch: { qty: {$gte: 5, $lte: 20}} }});
  
  db.inventory.find({
    'instock.qty': { $gt: 10, $lte: 20 }
  });
  
  db.inventory.find({
    $and: [
      { "instock.warehouse": 'A' },   // Condition for warehouse
      { "instock.qty": { $gte: 50 } } // Condition for qty greater than or equal to 50
    ]
  });
  
  
  db.inventory.find({status: 'A'}).projection({item: 1, status: 1});
  db.inventory.find({status: 'A'}).projection({item: 1, status: 1, _id: 0});
  db.inventory.find({status: 'A'}).projection({item: 1, status: 1, _id: 0, 'size.uom': 1});
  // since, it includes projection exclude so this projection only handle exclude so to include just chain like below
  db.inventory.find({status: 'A'}).projection({'size.uom': 0}).projection({status: 1});
  db.inventory.find({status: 'A'}).projection({'size.uom': 0}).projection({status: 1, item: 1, 'instoack.qty': 1});
  
  //-- during projection, only these operators allowde on a field i.e array $elemMatch, $slice and $
  
  db.inventory.find({ status: 'A' }).projection({ item: 1, status: 1, instock: { $slice: -1 } });
  // #### find all and project some field as usual and and some conditionally
  db.inventory.find(
     { },
     // so when projection, some fields from collection whereas some fields could be coumputed like below
     {
        _id: 0,
        item: 1,
        status: {
           $switch: {
              branches: [
                 {
                    case: { $eq: [ "$status", "A" ] },
                    then: "Available"
                 },
                 {
                    case: { $eq: [ "$status", "D" ] },
                    then: "Discontinued"
                 },
              ],
              default: "No status found"
           }
        },
        area: {
           $concat: [
              { $toString: { $multiply: [ "$size.h", "$size.w" ] } },
              " ",
              "$size.uom"
           ]
        },
        reportNumber: { $literal: 1 }
     }
  );
  
  // #### query for null or missing fields
  db.inventory.insertMany([{  _id: new ObjectId(), item: null }, { _id: new ObjectId() }]);
  
  db.inventory.find({item: null});
  db.inventory.find({item: {$exists: false}});
  
  db.inventory.find({item: {$ne: null}});
  db.inventory.find({item: {$exists: true}});
  
  //#### query timeouts: if the query doesn't return a result within the given time, then stop
  db.inventory.find({ qty: 50 }).maxTimeMS(5000);
  
  db.inventory.aggregate([
    { $match: { item: { $ne: null } } }, // Filter out documents where 'item' is null
    {
      $group: {
        _id: "$qty", // Group by the 'qty' field
        count: { $sum: 1 } // Count the number of documents in each group
      }
    }
  ]).maxTimeMS(5000); // Specify a 5-second timeout
  
  
  // update with aggregation pipeline
  
  db.students.insertMany([
     { _id: 1, test1: 95, test2: 92, test3: 90, modified: new Date("2020-01-05") },
     { _id: 2, test1: 98, test2: 100, test3: 102, modified: new Date("2020-01-05") },
     { _id: 3, test1: 95, test2: 110, modified: new Date("2020-01-31") }
  ]);
  
  db.students.updateOne( { _id: 3 }, [ { $set: { "test3": 98, modified: "$$NOW"} } ] );
  db.students.find();
  
  db.students2.insertMany( [
     { "_id" : 1, quiz1: 8, test2: 100, quiz2: 9, modified: new Date("2020-05-01") },
     { "_id" : 2, quiz2: 5, test1: 80, test2: 89, modified: new Date("2020-05-01") },
  ] );
  
  // updateMayn with the $replaceRoot and $mergeObjects
  db.students2.updateMany({},
    [
      // $$ROOT represent the og object or array so far in the pipeline, now using $replaceRoot, it could be overwritten as instructed below
      // so, $mergeObject will over each document and then it will do what spread or Object.assign(value_from_current_document, given_value_below) does
      {$replaceRoot: {newRoot: {$mergeObjects: [{ quiz1: 0, quiz2: 0, test2: 0 }, "$$ROOT"] }}},
      { $set: { modified: "$$NOW"}  }
    ]
  );
  
  db.students3.insertMany([
     { "_id" : 1, "tests" : [ 95, 92, 90 ], "modified" : ISODate("2019-01-01T00:00:00Z") },
     { "_id" : 2, "tests" : [ 94, 88, 90 ], "modified" : ISODate("2019-01-01T00:00:00Z") },
     { "_id" : 3, "tests" : [ 70, 75, 82 ], "modified" : ISODate("2019-01-01T00:00:00Z") }
  ]);
  
  
  // updateMany with the $set
  db.students3.updateMany(
     { },
     [
       // created average attribute that wasn't already exist, so here it uses an exsiting field i.e. "tests" and the calcualted value will be assinged to the average
       { $set: { average : { $trunc: [ { $avg: "$tests" }, 0 ] }, modified: "$$NOW" } },
       // now, here creating grade based on the existing field from table or it could be an exiting computed filed created here (which is here average)
       // and then just using switch case to conditionally assing value to this computed property i.e. grade
       { $set: { grade: { $switch: {
                             branches: [
                                 { case: { $gte: [ "$average", 90 ] }, then: "A" },
                                 { case: { $gte: [ "$average", 80 ] }, then: "B" },
                                 { case: { $gte: [ "$average", 70 ] }, then: "C" },
                                 { case: { $gte: [ "$average", 60 ] }, then: "D" }
                             ],
                             default: "F"
       } } } }
     ]
  );
  
  db.students3.find();
  
  db.students4.insertMany( [
    { "_id" : 1, "quizzes" : [ 4, 6, 7 ] },
    { "_id" : 2, "quizzes" : [ 5 ] },
    { "_id" : 3, "quizzes" : [ 10, 10, 10 ] }
  ] );
  
  db.students4.updateOne( { _id: 2 },
    // it is like using es6 map on array and only when _id = 2, then concat to current item or element 8, 6
    [ { $set: { quizzes: { $concatArrays: [ "$quizzes", [ 8, 6 ]  ] } } } ]
  );
  
  db.students4.find();
  
  db.temperatures.insertMany( [
    { "_id" : 1, "date" : ISODate("2019-06-23"), "tempsC" : [ 4, 12, 17 ] },
    { "_id" : 2, "date" : ISODate("2019-07-07"), "tempsC" : [ 14, 24, 11 ] },
    { "_id" : 3, "date" : ISODate("2019-10-30"), "tempsC" : [ 18, 6, 8 ] }
  ] );
  
  db.temperatures.updateMany(
    { }, // Match all documents in the collection
    [
      // so, creating a new computed field i.e. 'tempsF' based on existing field (but a new field could be created from arbitrary or arbirarry + existing filed or such as well)
      // Add a new field 'tempsF' to each document
      {
        $addFields: {
          "tempsF": {
            $map: {
              input: "$tempsC", // 'tempsC' is the existing field that holds an array of temperatures in Celsius
              as: "celsius", // Assigning a variable 'celsius' to each element in the 'tempsC' array
              in: {
                $add: [
                  { $multiply: ["$$celsius", 9/5 ] }, // Convert Celsius to Fahrenheit by multiplying by 9/5 so e.g. (4 * 9 / 5) + 32
                  32 // Adding 32 to the result to complete the Fahrenheit conversion formula
                ]
              } // Resulting value will be the converted temperature in Fahrenheit
            }
          }
        }
      }
    ]
  );
  
  db.temperatures.find();
  
  db.cakeFlavors.insertMany([
     { _id: 1, flavor: "chocolate" },
     { _id: 2, flavor: "strawberry" },
     { _id: 3, flavor: "cherry" }
  ]);
  
  db.cakeFlavors.find()
  
  db.cakeFlavors.updateOne(
    {
      flavor: "cherry"  // Match documents where the flavor is 'cherry'
    },
    [
      {
        $set: {
          flavor: "orange"  // Set the new flavor to 'orange'
        }
      }
    ]
  );
  
  db.cakeFlavors.updateOne(
    {
      flavor: "cherry"  // Match documents where the flavor is 'cherry'
    },
    [
      {
        $set: {
          flavor: "orange"  // Set the new flavor to 'orange'
        }
      }
    ]
  );
  
  db.cakeFlavors.find();
  
  db.inventory.deleteMany({});
  
  db.inventory.deleteMany({ status: 'A' });
  
  db.pizzas.insertMany([
     { _id: 0, type: "pepperoni", size: "small", price: 4 },
     { _id: 1, type: "cheese", size: "medium", price: 7 },
     { _id: 2, type: "vegan", size: "large", price: 8 }
  ]);
  
  db.pizzas.find();
  
  // #### bulkWrite
  try {
     db.pizzas.bulkWrite([
        { insertOne: { document: { _id: 3, type: "beef", size: "medium", price: 6 } } },
        { insertOne: { document: { _id: 4, type: "sausage", size: "large", price: 10 } } },
        { updateOne: {
           filter: { type: "cheese" },  // filter for cheese type
           update: { $set: { price: 8 } }  // update price to 8
        } },
        { deleteOne: { filter: { type: "pepperoni" } } },  // delete document with pepperoni
        { replaceOne: {
           filter: { type: "vegan" },  // filter for vegan type
           replacement: { type: "tofu", size: "small", price: 4 }  // replace with tofu
        }}
     ] );
  } catch (error) {
     print(error);
  }
  
  db.pizzas.find({ type: "cheese" });
  db.pizzas.find({ type: "pepperoni" });
  
  
  // #### Geospatial querties
  
  db.places.insertMany([
     {
        name: "Central Park",
        location: { type: "Point", coordinates: [ -73.97, 40.77 ] },
        category: "Parks"
     },
     {
        name: "Sara D. Roosevelt Park",
        location: { type: "Point", coordinates: [ -73.9928, 40.7193 ] },
        category: "Parks"
     },
     {
        name: "Polo Grounds",
        location: { type: "Point", coordinates: [ -73.9375, 40.8303 ] },
        category: "Stadiums"
     }
  ]);
  
  // The following operation creates a 2dsphere index on the location field:
  db.places.createIndex( { location: "2dsphere" } );
  
  db.places.find();
  
  // The following query uses the $near operator to return documents that are at least 1000 meters from and at most 5000 meters from the specified GeoJSON point, sorted in order from nearest to farthest:
  db.places.find(
     {
       location:
         { $near:
            {
              $geometry: { type: "Point",  coordinates: [ -73.9667, 40.78 ] },
              $minDistance: 1000,
              $maxDistance: 5000
            }
         }
     }
  );
  
  // The following operation uses the $geoNear aggregation operation to return documents that match the query filter { category: "Parks" }, sorted in order of nearest to farthest to the specified GeoJSON point:
  
  db.places.aggregate( [
     {
        $geoNear: {
           near: { type: "Point", coordinates: [ -73.9667, 40.78 ] },
           spherical: true,
           query: { category: "Parks" },
           distanceField: "calcDistance"
        }
     }
  ]);
  
  // Determine the user's current neighborhood using $geoIntersects,
  
  // Show the number of restaurants in that neighborhood using $geoWithin, and
  
  // Find restaurants within a specified distance of the user using $nearSphere.
  
  db.restaurants.createIndex({ location: "2dsphere" })
  db.neighborhoods.createIndex({ geometry: "2dsphere" })
  
  db.restaurants.findOne();
  
  // Suppose the user is located at -73.93414657 longitude and 40.82302903 latitude. To find the current neighborhood, you will specify a point using the special $geometry field in GeoJSON format:
  db.neighborhoods.findOne({ geometry: { $geoIntersects: { $geometry: { type: "Point", coordinates: [ -73.93414657, 40.82302903 ] } } } });
  
  // Find all Restaurants in the Neighborhood
  var neighborhood = db.neighborhoods.findOne( { geometry: { $geoIntersects: { $geometry: { type: "Point", coordinates: [ -73.93414657, 40.82302903 ] } } } } )
  db.restaurants.find( { location: { $geoWithin: { $geometry: neighborhood.geometry } } } ).count();
  
  // The following will find all restaurants within five miles of the user:
  
  db.restaurants.find({ location: { $geoWithin: { $centerSphere: [ [ -73.93414657, 40.82302903 ], 5 / 3963.2 ] } } });
  
  // You may also use $nearSphere and specify a $maxDistance term in meters. This will return all restaurants within five miles of the user in sorted order from nearest to farthest:
  
  var METERS_PER_MILE = 1609.34
  db.restaurants.find({ location: { $nearSphere: { $geometry: { type: "Point", coordinates: [ -73.93414657, 40.82302903 ] }, $maxDistance: 5 * METERS_PER_MILE } } })
  
  // #### Aggregation operations
  
  db.orders.insertMany([
     { _id: 0, name: "Pepperoni", size: "small", price: 19,
       quantity: 10, date: ISODate( "2021-03-13T08:14:30Z" ) },
     { _id: 1, name: "Pepperoni", size: "medium", price: 20,
       quantity: 20, date : ISODate( "2021-03-13T09:13:24Z" ) },
     { _id: 2, name: "Pepperoni", size: "large", price: 21,
       quantity: 30, date : ISODate( "2021-03-17T09:22:12Z" ) },
     { _id: 3, name: "Cheese", size: "small", price: 12,
       quantity: 15, date : ISODate( "2021-03-13T11:21:39.736Z" ) },
     { _id: 4, name: "Cheese", size: "medium", price: 13,
       quantity:50, date : ISODate( "2022-01-12T21:23:13.331Z" ) },
     { _id: 5, name: "Cheese", size: "large", price: 14,
       quantity: 10, date : ISODate( "2022-01-12T05:08:13Z" ) },
     { _id: 6, name: "Vegan", size: "small", price: 17,
       quantity: 10, date : ISODate( "2021-01-13T05:08:13Z" ) },
     { _id: 7, name: "Vegan", size: "medium", price: 18,
       quantity: 10, date : ISODate( "2021-01-13T05:10:13Z" ) }
  ]);
  
  db.orders.aggregate( [
  
     // Stage 1: Filter pizza order documents by pizza size
     {
        $match: { size: "medium" }
     },
  
     // Stage 2: Group remaining documents by pizza name and calculate total quantity
     {
        $group: { _id: "$name", totalQuantity: { $sum: "$quantity" } }
     }
  ]);
  
  db.orders.aggregate( [
  
     // Stage 1: Filter pizza order documents by date range
     {
        $match:
        {
           "date": { $gte: new ISODate( "2020-01-30" ), $lt: new ISODate( "2022-01-30" ) } // YYYY-MM-DD
        }
     },
  
     // Stage 2: Group remaining documents by date and calculate results
     {
        $group:
        {
           // so, here created or computed property `dateToString` based on $date field from collection but again value could come be computed too
           // based on the computed property , groupping is done, so here groupping is date wise ($dateToString is an operator)
           _id: { $dateToString: { format: "%Y-%m-%d", date: "$date" } },
           // now, what to do on the existing fields and also if needed create some computed fields as done below i.e. totalOrderValue
           totalOrderValue: { $sum: { $multiply: [ "$price", "$quantity" ] } },
           averageOrderQuantity: { $avg: "$quantity" }
        }
     },
  
     // Stage 3: Sort documents by totalOrderValue in descending order
     {
        $sort: { totalOrderValue: -1 }
     }
   ]);
  
  db.products.insertMany([
     { item: "journal", instock: [ { warehouse: "A"}, { warehouse: "C" } ] },
     { item: "notebook", instock: [ { warehouse: "C" } ] },
     { item: "paper", instock: [ { warehouse: "A" }, { warehouse: "B" } ] },
     { item: "planner", instock: [ { warehouse: "A" }, { warehouse: "B" } ] },
     { item: "postcard", instock: [ { warehouse: "B" }, { warehouse: "C" } ] }
  ]);
  
  // ####
  db.products.aggregate([
     {
        $project: {
           item: 1,
           warehouses: "$instock.warehouse"
        }
     }
  ]);
  
  db.fruits.insertOne(
     {
        _id: ObjectId("5ba53172ce6fa2fcfc58e0ac"),
        inventory: [
           {
              apples: [
                 "macintosh",
                 "golden delicious",
              ]
           },
           {
              oranges: [
                 "mandarin",
              ]
           },
           {
              apples: [
                 "braeburn",
                 "honeycrisp",
              ]
           }
        ]
     }
  );
  
  db.fruits.aggregate( [
     { $project:
        { all_apples: "$inventory.apples" } }
  ]);
  
  // The following aggregation operation returns the average populations for cities in each state:
  //db.zipcodes.aggregate([
  //   { $group: { _id: { state: "$state", city: "$city" }, pop: { $sum: "$pop" } } },
  //   { $group: { _id: "$_id.state", avgCityPop: { $avg: "$pop" } } }
  //]);
  
  // The following aggregation operation returns the smallest and largest cities by population for each state:
  
  // db.zipcodes.aggregate( [
  //    {
  //      $group: {
  //        _id: { state: "$state", city: "$city" },
  //        pop: { $sum: "$pop" }
  //    }
  //   },
  //   { $sort: { pop: 1 } },
  //   { $group: {
  //        _id : "$_id.state",
  //        biggestCity:  { $last: "$_id.city" },
  //        biggestPop:   { $last: "$pop" },
  //        smallestCity: { $first: "$_id.city" },
  //        smallestPop:  { $first: "$pop" }
  //      }
  //   },
  //
  //  // the following $project is optional, and
  //  // modifies the output format.
  //
  //  {
  //  $project: {
  //      _id: 0,
  //      state: "$_id",
  //      biggestCity:  { name: "$biggestCity",  pop: "$biggestPop" },
  //      smallestCity: { name: "$smallestCity", pop: "$smallestPop" }
  //    }
  //  }
  //]);
  
  db.members.insertMany([
     {
        _id: "jane",
        joined: ISODate("2011-03-02"),
        likes: ["golf", "racquetball"]
     },
     {
        _id: "joe",
        joined: ISODate("2012-07-02"),
        likes: ["tennis", "golf", "swimming"]
     },
     {
        _id: "ruth",
        joined: ISODate("2012-01-14"),
        likes: ["golf", "racquetball"]
     },
     {
        _id: "harold",
        joined: ISODate("2012-01-21"),
        likes: ["handball", "golf", "racquetball"]
     },
     {
        _id: "kate",
        joined: ISODate("2012-01-14"),
        likes: ["swimming", "tennis"]
     }
  ]);
  
  db.members.aggregate([ { $project: { _id: 1 } }]);
  
  db.members.aggregate(
    [
      { $project: { name: { $toUpper: "$_id" }, _id: 0 } },
      { $sort: { name: 1 } }
    ]
  );
  
  db.members.aggregate( [
      {
        $project: {
           month_joined: { $month: "$joined" },
           name: "$_id",
           _id: 0
         }
      },
      { $sort: { month_joined: 1 } }
  ]);
  
  db.members.aggregate( [
     { $project: { month_joined: { $month: "$joined" } } } ,
     { $group: { _id: { month_joined: "$month_joined" } , number: { $sum: 1 } } },
     { $sort: { "_id.month_joined": 1 } }
  ]);
  
  db.members.aggregate(
    [
      { $unwind: "$likes" },
      { $group: { _id: "$likes" , number: { $sum: 1 } } },
      { $sort: { number: -1 } },
      { $limit: 5 }
    ]
  );
  
  // #### Aggregation stages
  
  // #### $addFields: add computed fields, update and remove fields
  
  db.scores.insertMany( [
     {
        _id: 1,
        student: "Maya",
        homework: [ 10, 5, 10 ],
        quiz: [ 10, 8 ],
        extraCredit: 0
     },
     {
        _id: 2,
        student: "Ryan",
        homework: [ 5, 6, 5 ],
        quiz: [ 8, 8 ],
        extraCredit: 8
     }
  ]);
  
  // The following operation uses two $addFields stages to include three new fields in the output documents:
  db.scores.aggregate( [
     {
       $addFields: {
         totalHomework: { $sum: "$homework" } ,
         totalQuiz: { $sum: "$quiz" }
       }
     },
     {
       $addFields: {
         totalScore: { $add: [ "$totalHomework", "$totalQuiz", "$extraCredit" ] } }
     }
  ]);
  
  // Adding Fields to an Embedded Document
  db.vehicles.insertMany( [
        { _id: 1, type: "car", specs: { doors: 4, wheels: 4 } },
        { _id: 2, type: "motorcycle", specs: { doors: 0, wheels: 2 } },
        { _id: 3, type: "jet ski" }
  ]);
  
  // Here, it added fuel_type to each documents but off course it just during the aggregation it won't affect the original documents
  db.vehicles.aggregate( [
     { $addFields: { "specs.fuel_type": "unleaded" } }
  ]);
  
  // ovewriting an exisitng filed
  
  db.animals.insertOne(
     { _id: 1, dogs: 10, cats: 15 }
  );
  
  db.animals.aggregate( [
    {
      $addFields: { cats: 20 }
    }
  ]);
  
  // It is possible to replace one field with another. In the following example the item field substitutes for the _id field.
  
  db.fruit.insertMany( [
     { _id: 1, item: "tangerine", type: "citrus" },
     { _id: 2, item: "lemon", type: "citrus" },
     { _id: 3, item: "grapefruit", type: "citrus" }
  ]);
  
  db.fruit.aggregate( [
    {
      $addFields: {
        _id : "$item",
        item: "fruit"
      }
    }
  ]);
  
  // so, find the document with _id: 1 and then updated its homework array by concatenating 7
  db.scores.aggregate([
     { $match: { _id: 1 } },
     { $addFields: { homework: { $concatArrays: [ "$homework", [ 7 ] ] } } }
  ]);
  
  db.labReadings.insertMany( [
     {
        date: ISODate("2024-10-09"),
        temperature: 80
     },
     {
        date: null,
        temperature: 83
     },
     {
        date: ISODate("2024-12-09"),
        temperature: 85
     }
  ]);
  
  
  // To remove the date field from the labReadings documents, use $addFields with the $$REMOVE variable:
  db.labReadings.aggregate( [
     {
        $addFields: { date: "$$REMOVE" }
     }
  ]);
  
  // The following aggregation removes the date field from documents where date is null:
  db.labReadings.aggregate([
     {
        $addFields:
           {
              date: {
                 $ifNull: [ "$date", "$$REMOVE" ]
              }
           }
     }
  ]);
  
  db.labReadings.find();
  
  // #### $bucket: categorizes incoming documents into groups, called buckets, based on a specified expression and bucket boundaries and outputs a document per each bucket.
  
  db.artists.insertMany([
    { "_id" : 1, "last_name" : "Bernard", "first_name" : "Emil", "year_born" : 1868, "year_died" : 1941, "nationality" : "France" },
    { "_id" : 2, "last_name" : "Rippl-Ronai", "first_name" : "Joszef", "year_born" : 1861, "year_died" : 1927, "nationality" : "Hungary" },
    { "_id" : 3, "last_name" : "Ostroumova", "first_name" : "Anna", "year_born" : 1871, "year_died" : 1955, "nationality" : "Russia" },
    { "_id" : 4, "last_name" : "Van Gogh", "first_name" : "Vincent", "year_born" : 1853, "year_died" : 1890, "nationality" : "Holland" },
    { "_id" : 5, "last_name" : "Maurer", "first_name" : "Alfred", "year_born" : 1868, "year_died" : 1932, "nationality" : "USA" },
    { "_id" : 6, "last_name" : "Munch", "first_name" : "Edvard", "year_born" : 1863, "year_died" : 1944, "nationality" : "Norway" },
    { "_id" : 7, "last_name" : "Redon", "first_name" : "Odilon", "year_born" : 1840, "year_died" : 1916, "nationality" : "France" },
    { "_id" : 8, "last_name" : "Diriks", "first_name" : "Edvard", "year_born" : 1855, "year_died" : 1930, "nationality" : "Norway" }
  ]);
  
  // The following operation groups the documents into buckets according to the year_born field and filters based on the count of documents in the buckets:
  // N.B: bucket has a limit of 100 mb
  db.artists.aggregate([
    // First Stage
    {
      $bucket: {
        groupBy: "$year_born",                        // Field to group by
         // For example, an array of [ 0, 5, 10 ] creates two buckets:
         // [0, 5) with inclusive lower bound 0 and exclusive upper bound 5.
         // [5, 10) with inclusive lower bound 5 and exclusive upper bound 10.
        boundaries: [ 1840, 1850, 1860, 1870, 1880 ], // Boundaries for the buckets
        default: "Other",                             // Bucket ID for documents which do not fall into a bucket
        output: {                                     // Output for each bucket
          "count": { $sum: 1 },
          "artists" :
            {
              $push: {
                "name": { $concat: [ "$first_name", " ", "$last_name"] },
                "year_born": "$year_born"
              }
            }
        }
      }
    },
    // Second Stage
    {
      $match: { count: {$gt: 3} }
    }
  ]);
  
  // [1840, 1850) with inclusive lowerbound 1840 and exclusive upper bound 1850
  // [1850, 1860) with inclusive lowerbound 1850 and exclusive upper bound 1860
  // [1860, 1870) with inclusive lowerbound 1860 and exclusive upper bound 1870.
  // [1870, 1880) with inclusive lowerbound 1870 and exclusive upper bound 1880.
  
  // Use $bucket with $facet to Bucket by Multiple Fields
  
  db.artwork.insertMany([
    { "_id" : 1, "title" : "The Pillars of Society", "artist" : "Grosz", "year" : 1926,
        "price" : NumberDecimal("199.99") },
    { "_id" : 2, "title" : "Melancholy III", "artist" : "Munch", "year" : 1902,
        "price" : NumberDecimal("280.00") },
    { "_id" : 3, "title" : "Dancer", "artist" : "Miro", "year" : 1925,
        "price" : NumberDecimal("76.04") },
    { "_id" : 4, "title" : "The Great Wave off Kanagawa", "artist" : "Hokusai",
        "price" : NumberDecimal("167.30") },
    { "_id" : 5, "title" : "The Persistence of Memory", "artist" : "Dali", "year" : 1931,
        "price" : NumberDecimal("483.00") },
    { "_id" : 6, "title" : "Composition VII", "artist" : "Kandinsky", "year" : 1913,
        "price" : NumberDecimal("385.00") },
    { "_id" : 7, "title" : "The Scream", "artist" : "Munch", "year" : 1893
        /* No price*/ },
    { "_id" : 8, "title" : "Blue Flower", "artist" : "O'Keefe", "year" : 1918,
        "price" : NumberDecimal("118.42") }
  ]);
  
  // The following operation uses two $bucket stages within a $facet stage to create two groupings, one by price and the other by year:
  
  db.artwork.aggregate([
    {
      $facet: {                               // Top-level $facet stage
        "price": [                            // Output field 1
          {
            $bucket: {
                groupBy: "$price",            // Field to group by
                boundaries: [ 0, 200, 400 ],  // Boundaries for the buckets
                default: "Other",             // Bucket ID for documents which do not fall into a bucket boundaries above 0-199, 200-399
                output: {                     // Output for each bucket
                  "count": { $sum: 1 },
                  "artwork" : { $push: { "title": "$title", "price": "$price" } },
                  "averagePrice": { $avg: "$price" }
                }
            }
          }
        ],
        "year": [                                      // Output field 2
          {
            $bucket: {
              groupBy: "$year",                        // Field to group by
              boundaries: [ 1890, 1910, 1920, 1940 ],  // Boundaries for the buckets
              default: "Unknown",                      // Bucket ID for documents which do not fall into a bucket
              output: {                                // Output for each bucket
                "count": { $sum: 1 },
                "artwork": { $push: { "title": "$title", "year": "$year" } }
              }
            }
          }
        ]
      }
    }
  ]);
  
  // In the following operation, input documents are grouped (automatically) into four buckets according to the values in the price field
  db.artwork.aggregate([
     {
       $bucketAuto: {
           groupBy: "$price",
           buckets: 4
       }
     }
  ]);
  
  // The following aggregation pipeline groups the documents from the artwork collection into buckets based on price, year, and the calculated area:
  
  db.artwork.aggregate( [
    {
      $facet: {
        "price": [
          {
            $bucketAuto: {
              groupBy: "$price",
              buckets: 4
            }
          }
        ],
        "year": [
          {
            $bucketAuto: {
              groupBy: "$year",
              buckets: 3,
              output: {
                "count": { $sum: 1 },
                "years": { $push: "$year" }
              }
            }
          }
        ],
        "area": [
          {
            $bucketAuto: {
              groupBy: {
                $multiply: [ "$dimensions.height", "$dimensions.width" ]
              },
              buckets: 4,
              output: {
                "count": { $sum: 1 },
                "titles": { $push: "$title" }
              }
            }
          }
        ]
      }
    }
  ]);
  
  // #### $count
  db.getCollection('scores').drop();
  
  db.scores.insertMany([
     { "subject" : "History", "score" : 88 },
     { "subject" : "History", "score" : 92 },
     { "subject" : "History", "score" : 97 },
     { "subject" : "History", "score" : 100 },
     { "subject" : "History", "score" : 79 },
     { "subject" : "History", "score" : 150 }
  ]);
  
  db.scores.aggregate([
     { $match: { score: { $gt: 99 } } },
     { $count: "passing_scores" }
  ]);
  
  db.scores.aggregate([
     { $match: { score: { $gt: 99 } } },
     { $count: "high_scores" }
  ]);
  
  // #### $densify
  
  db.weather.insertMany( [
     {
         "metadata": { "sensorId": 5578, "type": "temperature" },
         "timestamp": ISODate("2021-05-18T00:00:00.000Z"),
         "temp": 12
     },
     {
         "metadata": { "sensorId": 5578, "type": "temperature" },
         "timestamp": ISODate("2021-05-18T04:00:00.000Z"),
         "temp": 11
     },
     {
         "metadata": { "sensorId": 5578, "type": "temperature" },
         "timestamp": ISODate("2021-05-18T08:00:00.000Z"),
         "temp": 11
     },
     {
         "metadata": { "sensorId": 5578, "type": "temperature" },
         "timestamp": ISODate("2021-05-18T12:00:00.000Z"),
         "temp": 12
     }
  ]);
  
  db.weather.aggregate( [
     {
        $densify: {
           field: "timestamp",
           range: {
              step: 1,
              unit: "hour",
              bounds:[ ISODate("2021-05-18T00:00:00.000Z"), ISODate("2021-05-18T08:00:00.000Z") ]
           }
        }
     }
  ]);
  
  
  db.coffee.insertMany( [
     {
        "altitude": 600,
        "variety": "Arabica Typica",
        "score": 68.3
     },
     {
        "altitude": 750,
        "variety": "Arabica Typica",
        "score": 69.5
     },
     {
        "altitude": 950,
        "variety": "Arabica Typica",
        "score": 70.5
     },
     {
        "altitude": 1250,
        "variety": "Gesha",
        "score": 88.15
     },
     {
       "altitude": 1700,
       "variety": "Gesha",
       "score": 95.5,
       "price": 1029
     }
  ]);
  
  //The example aggregation:
  //Partitions the documents by variety to create one grouping for Arabica Typica and one for Gesha coffee.
  //Specifies a full range, meaning that the data is densified across the full range of existing documents for each partition.
  //Specifies a step of 200, meaning new documents are created at altitude intervals of 200.
  //The aggregation outputs the following documents:
  db.coffee.aggregate( [
     {
        $densify: {
           field: "altitude",
           partitionByFields: [ "variety" ],
           range: {
              bounds: "full",
              step: 200
           }
        }
     }
  ]);
  
  //The example aggregation:
  //Partitions the documents by variety to create one grouping for Arabica Typica and one for Gesha coffee.
  //Specifies a partition range, meaning that the data is densified within each partition.
  //For the Arabica Typica partition, the range is 600-950.
  //For the Gesha partition, the range is 1250-1700.
  //Specifies a step of 200, meaning new documents are created at altitude intervals of 200.
  
  db.coffee.aggregate([
     {
        $densify: {
           field: "altitude",
           partitionByFields: [ "variety" ],
           range: {
              bounds: "partition",
              step: 200
           }
        }
     }
  ]);
  
  // #### $facet : Processes multiple aggregation pipelines within a single stage on the same set of input documents. Each sub-pipeline has its own field in the output document where its results are stored as an array of documents.
  
  db.artwork.aggregate( [
    {
      $facet: {
        "categorizedByTags": [
          { $unwind: "$tags" }, // unwind the tags array
          { $sortByCount: "$tags" }
        ],
        "categorizedByPrice": [
          // Filter out documents without a price e.g., _id: 7
          { $match: { price: { $exists: 1 } } },
          {
            $bucket: {
              groupBy: "$price",
              boundaries: [  0, 150, 200, 300, 400 ],
              default: "Other",
              output: {
                "count": { $sum: 1 },
                "titles": { $push: "$title" }
              }
            }
          }
        ],
        "categorizedByYears(Auto)": [
          {
            $bucketAuto: {
              groupBy: "$year",
              buckets: 4
            }
          }
        ]
      }
    }
  ]);
  
  // #### $fill
  
  db.dailySales.insertMany( [
     {
        "date": ISODate("2022-02-02"),
        "bootsSold": 10,
        "sandalsSold": 20,
        "sneakersSold": 12
     },
     {
        "date": ISODate("2022-02-03"),
        "bootsSold": 7,
        "sneakersSold": 18
     },
     {
        "date": ISODate("2022-02-04"),
        "sneakersSold": 5
     }
  ]);
  
  // The following example uses $fill to set the quantities sold to 0 for the missing shoe types for each day's sales:
  
  db.dailySales.aggregate( [
     {
        $fill:
           {
              output:
                 {
                    "bootsSold": { value: 0 },
                    "sandalsSold": { value: 0 },
                    "sneakersSold": { value: 0 }
                 }
           }
     }
  ]);
  
  db.stock.insertMany( [
     {
        time: ISODate("2021-03-08T09:00:00.000Z"),
        price: 500
     },
     {
        time: ISODate("2021-03-08T10:00:00.000Z"),
     },
     {
        time: ISODate("2021-03-08T11:00:00.000Z"),
        price: 515
     },
     {
        time: ISODate("2021-03-08T12:00:00.000Z")
     },
     {
        time: ISODate("2021-03-08T13:00:00.000Z")
     },
     {
        time: ISODate("2021-03-08T14:00:00.000Z"),
        price: 485
     }
  ]);
  
  db.stock.aggregate( [
     {
        $fill:
           {
              sortBy: { time: 1 },
              output:
                 {
                    "price": { method: "linear" }
                 }
           }
     }
  ]);
  
  db.restaurantReviews.insertMany( [
     {
        date: ISODate("2021-03-08"),
        score: 90
     },
     {
        date: ISODate("2021-03-09"),
        score: 92
     },
     {
        date: ISODate("2021-03-10")
     },
     {
        date: ISODate("2021-03-11")
     },
     {
        date: ISODate("2021-03-12"),
        score: 85
     },
     {
        date: ISODate("2021-03-13")
     }
  ]);
  
  db.restaurantReviews.aggregate( [
     {
        $fill:
           {
              sortBy: { date: 1 },
              output:
                 {
                    "score": { method: "locf" }
                 }
           }
     }
  ]);
  
  db.restaurantReviewsMultiple.insertMany( [
     {
        date: ISODate("2021-03-08"),
        restaurant: "Joe's Pizza",
        score: 90
     },
     {
        date: ISODate("2021-03-08"),
        restaurant: "Sally's Deli",
        score: 75
     },
     {
        date: ISODate("2021-03-09"),
        restaurant: "Joe's Pizza",
        score: 92
     },
     {
        date: ISODate("2021-03-09"),
        restaurant: "Sally's Deli"
     },
     {
        date: ISODate("2021-03-10"),
        restaurant: "Joe's Pizza"
     },
     {
        date: ISODate("2021-03-10"),
        restaurant: "Sally's Deli",
        score: 68
     },
     {
        date: ISODate("2021-03-11"),
        restaurant: "Joe's Pizza",
        score: 93
     },
     {
        date: ISODate("2021-03-11"),
        restaurant: "Sally's Deli"
     }
  ]);
  
  db.restaurantReviewsMultiple.aggregate( [
     {
        $fill:
           {
              sortBy: { date: 1 },
              partitionBy: { "restaurant": "$restaurant" },
              output:
                 {
                    "score": { method: "locf" }
                 }
           }
     }
  ]);
  
  db.restaurantReviews.insertMany( [
     {
        date: ISODate("2021-03-08"),
        score: 90
     },
     {
        date: ISODate("2021-03-09"),
        score: 92
     },
     {
        date: ISODate("2021-03-10")
     },
     {
        date: ISODate("2021-03-11")
     },
     {
        date: ISODate("2021-03-12"),
        score: 85
     },
     {
        date: ISODate("2021-03-13")
     }
  ]);
  
  db.restaurantReviews.aggregate( [
     {
        $set: {
           "valueExisted": {
              "$ifNull": [
                 { "$toBool": { "$toString": "$score" } },
                 false
              ]
           }
        }
     },
     {
        $fill: {
           sortBy: { date: 1 },
           output:
              {
                 "score": { method: "locf" }
              }
        }
     }
  ]);
  
  // #### $redact : Restricts entire documents or content within documents from being outputted based on information stored in the documents themselves
  
  db.forecasts.insertMany([
  {
    _id: 1,
    title: "123 Department Report",
    tags: [ "G", "STLW" ],
    year: 2014,
    subsections: [
      {
        subtitle: "Section 1: Overview",
        tags: [ "SI", "G" ],
        content:  "Section 1: This is the content of section 1."
      },
      {
        subtitle: "Section 2: Analysis",
        tags: [ "STLW" ],
        content: "Section 2: This is the content of section 2."
      },
      {
        subtitle: "Section 3: Budgeting",
        tags: [ "TK" ],
        content: {
          text: "Section 3: This is the content of section 3.",
          tags: [ "HCS" ]
        }
      }
    ]
  }
  ]);
  
  //A user has access to view information with either the tag "STLW" or "G". To run a query on all documents with year 2014 for this user, include a $redact stage as in the following:
  var userAccess = [ "STLW", "G" ];
  db.forecasts.aggregate(
     [
       { $match: { year: 2014 } },
       { $redact: {
          $cond: {
             if: { $gt: [ { $size: { $setIntersection: [ "$tags", userAccess ] } }, 0 ] },
             then: "$$DESCEND",
             else: "$$PRUNE"
           }
         }
       }
     ]
  );
  
  // {
  //  _id: 1,
  //  title: "123 Department Report",
  //  tags: [ "G", "STLW" ],
  //  year: 2014,
  //  subsections: [
  //    {
  //      subtitle: "Section 1: Overview",
  //      tags: [ "SI", "G" ],
  //      content:  "Section 1: This is the content of section 1."
  //    },
  //    {
  //      subtitle: "Section 2: Analysis",
  //      tags: [ "STLW" ],
  //      content: "Section 2: This is the content of section 2."
  //    },
  //    {
  //      subtitle: "Section 3: Budgeting",
  //      tags: [ "TK" ],
  //      content: {
  //        text: "Section 3: This is the content of section 3.",
  //        tags: [ "HCS" ]
  //      }
  //    }
  //  ]
  // }
  
  // SO FROM ABOVE AS SEEN, IN THE YEAR 2014 THERE ARE 2 DOCUMENTS THAT HAS EITHER 'G' OR 'STLW' SO ONLY THOSE 2 DOCUMENTS ARE PICKED AS OUTPUT
  
  db.accounts.insertMany([{
    level: 1,
    acct_id: "xyz123",
    cc: {
      level: 5, // when needed set this value to 4 to test the below $redact
      type: "yy",
      num: 000000000000,
      exp_date: ISODate("2015-11-01T00:00:00.000Z"),
      billing_addr: {
        level: 5,
        addr1: "123 ABC Street",
        city: "Some City"
      },
      shipping_addr: [
        {
          level: 3,
          addr1: "987 XYZ Ave",
          city: "Some City"
        },
        {
          level: 3,
          addr1: "PO Box 0123",
          city: "Some City"
        }
      ]
    },
    status: "A"
  }]);
  
  //db.getCollection('accounts').drop();
  
  //db.accounts.find();
  
  //To run a query on all documents with status A and "exclude all fields contained in a document/embedded document at level 5", include a $redact stage that specifies the system variable "$$PRUNE" in the then field:
  // simply meaning, any embedded document in the accounts colleciton to be excluded if it has status 5 and since cc has level: 5 so it's excluded
  db.accounts.aggregate(
    [
      { $match: { status: "A" } },
      {
        $redact: {
          $cond: {
            if: { $eq: [ "$level", 5 ] },
            then: "$$PRUNE",
            else: "$$DESCEND"
          }
        }
      }
    ]
  );
  
  // #### $replaceRoot
  
  db.students_test.insertMany([
     {
        "_id" : 1,
        "grades" : [
           { "test": 1, "grade" : 80, "mean" : 75, "std" : 6 },
           { "test": 2, "grade" : 85, "mean" : 90, "std" : 4 },
           { "test": 3, "grade" : 95, "mean" : 85, "std" : 6 }
        ]
     },
     {
        "_id" : 2,
        "grades" : [
           { "test": 1, "grade" : 90, "mean" : 75, "std" : 6 },
           { "test": 2, "grade" : 87, "mean" : 90, "std" : 3 },
           { "test": 3, "grade" : 91, "mean" : 85, "std" : 4 }
        ]
     }
  ]);
  //The following operation promotes the embedded document(s) with the grade field greater than or equal to 90 to the top level:
  db.students_test.aggregate( [
     { $unwind: "$grades" },
     { $match: { "grades.grade" : { $gte: 90 } } },
     { $replaceRoot: { newRoot: "$grades" } }
  ]);
  
  db.contacts.insertMany([
  { "_id" : 1, "first_name" : "Gary", "last_name" : "Sheffield", "city" : "New York" },
  { "_id" : 2, "first_name" : "Nancy", "last_name" : "Walker", "city" : "Anaheim" },
  { "_id" : 3, "first_name" : "Peter", "last_name" : "Sumner", "city" : "Toledo" }
  ]);
  
  db.contacts.aggregate([
     {
        $replaceRoot: {
           newRoot: {
              full_name: {
                 $concat : [ "$first_name", " ", "$last_name" ]
              }
           }
        }
     }
  ]);
  
  db.getCollection('contacts').drop();
  
  db.contacts.insertMany([
     { "_id" : 1, name: "Fred", email: "fred@example.net" },
     { "_id" : 2, name: "Frank N. Stine", cell: "012-345-9999" },
     { "_id" : 3, name: "Gren Dell", home: "987-654-3210", email: "beo@example.net" }
  ]);
  
  db.contacts.aggregate( [
     { $replaceRoot:
        { newRoot:
           { $mergeObjects:
               [
                  { _id: "", name: "", email: "", cell: "", home: "" },
                  "$$ROOT"
               ]
            }
        }
     }
  ]);
  
  // #### $replaceWith
  
  db.people.insertMany([
     { "_id" : 1, "name" : "Arlene", "age" : 34, "pets" : { "dogs" : 2, "cats" : 1 } },
     { "_id" : 2, "name" : "Sam", "age" : 41, "pets" : { "cats" : 1, "fish" : 3 } },
     { "_id" : 3, "name" : "Maria", "age" : 25 }
  ]);
  
  // as $replaceWith iterates on each document of the collection, if exist use it else the fallback value given below and return output should have below mentioned 4 fields
  db.people.aggregate( [
     { $replaceWith: { $mergeObjects:  [ { dogs: 0, cats: 0, birds: 0, fish: 0 }, "$pets" ] } }
  ]);
  
  db.sales.insertMany([
     { "_id" : 1, "item" : "butter", "price" : 10, "quantity": 2, date: ISODate("2019-03-01T08:00:00Z"), status: "C" },
     { "_id" : 2, "item" : "cream", "price" : 20, "quantity": 1, date: ISODate("2019-03-01T09:00:00Z"), status: "A" },
     { "_id" : 3, "item" : "jam", "price" : 5, "quantity": 10, date: ISODate("2019-03-15T09:00:00Z"), status: "C" },
     { "_id" : 4, "item" : "muffins", "price" : 5, "quantity": 10, date: ISODate("2019-03-15T09:00:00Z"), status: "C" }
  ]);
  
  //Assume that for reporting purposes, you want to calculate for each completed sale, the total amount as of the current report run time. The following operation finds all the sales with status C and creates new documents using the $replaceWith stage. The $replaceWith calculates the total amount as well as uses the variable NOW to get the current time.
  // so, by today i.e. asOfDate: "$$NOW" , select the document that has status: "Complete" and then return it as mentioned within $replaceWith
  db.sales.aggregate([
     { $match: { status: "C" } },
     { $replaceWith: { _id: "$_id", item: "$item", amount: { $multiply: [ "$price", "$quantity"]}, status: "Complete", asofDate: "$$NOW" } }
  ]);
  
  db.reportedsales.insertMany( [
     { _id: 1, quarter: "2019Q1", region: "A", qty: 400 },
     { _id: 2, quarter: "2019Q1", region: "B", qty: 550 },
     { _id: 3, quarter: "2019Q1", region: "C", qty: 1000 },
     { _id: 4, quarter: "2019Q2", region: "A", qty: 660 },
     { _id: 5, quarter: "2019Q2", region: "B", qty: 500 },
     { _id: 6, quarter: "2019Q2", region: "C", qty: 1200 }
  ]);
  
  db.reportedsales.aggregate([
     // as it goes over each doument in the collection, creates an object that has obj whose value is an object
     { $addFields: { obj:  { k: "$region", v: "$qty" } } },
     // group and what to after it
     { $group: { _id: "$quarter", items: { $push: "$obj" } } },
     // so, iterate on the each document and so create a field named items2 where iteratete on current iterated document's "items" field and push its element to items and then repeat the same for another document in the next itearation
     { $project: { items2: { $concatArrays: [ [ { "k": "_id", "v": "$_id" } ], "$items" ] } } },
     { $replaceWith: { $arrayToObject: "$items2" } }
  ]);
  
  db.contacts.insertMany( [
     { "_id" : 1, name: "Fred", email: "fred@example.net" },
     { "_id" : 2, name: "Frank N. Stine", cell: "012-345-9999" },
     { "_id" : 3, name: "Gren Dell", cell: "987-654-3210", email: "beo@example.net" }
  ]);
  
  db.contacts.aggregate( [
     { $replaceWith:
        { $mergeObjects:
           [
              { _id: "", name: "", email: "", cell: "", home: "" },
              "$$ROOT"
           ]
        }
     }
  ]);
  
  // #### $set
  db.scores2.insertMany( [
     { _id: 1, student: "Maya", homework: [ 10, 5, 10 ], quiz: [ 10, 8 ], extraCredit: 0 },
     { _id: 2, student: "Ryan", homework: [ 5, 6, 5 ], quiz: [ 8, 8 ], extraCredit: 8 }
  ]);
  // The following operation uses two $set stages to include three new fields in the output documents:
  db.scores.aggregate( [
     {
       $set: {
          totalHomework: { $sum: "$homework" },
          totalQuiz: { $sum: "$quiz" }
       }
     },
     {
       $set: {
          totalScore: { $add: [ "$totalHomework", "$totalQuiz", "$extraCredit" ] } }
     }
  ]);
  
  // so, here $set will add this on each document's embedded spces
  db.vehicles.aggregate([
     { $set: { "specs.fuel_type": "unleaded" } }
  ]);
  
  db.fruits.insertMany([
     { _id: 1, item: "tangerine", type: "citrus" },
     { _id: 2, item: "lemon", type: "citrus" },
     { _id: 3, item: "grapefruit", type: "citrus" }
  ]);
  
  // ovewrtie each document from fruits as below ( item: "fruit" is hard-coded)
  db.fruits.aggregate([
    { $set: { _id: "$item", item: "fruit" } }
  ]);
  
  // find the document where _id = 1 and update its homework field that is an array by concatenating 7
  db.scores2.aggregate([
     { $match: { _id: 1 } },
     { $set: { homework: { $concatArrays: [ "$homework", [ 7 ] ] } } }
  ]);
  
  // so, here it creates a new fileds from $quiz field
  db.scores2.aggregate( [
     {
        $set: {
           quizAverage: { $avg: "$quiz" }
        }
     }
  ]);
  
  // #### $setWindowField
  
  db.cakeSales.insertMany( [
     { _id: 0, type: "chocolate", orderDate: new Date("2010-05-18T14:10:30Z"),
       state: "CA", price: 13, quantity: 120 },
     { _id: 1, type: "chocolate", orderDate: new Date("2021-03-20T11:30:05Z"),
       state: "WA", price: 14, quantity: 140 },
     { _id: 2, type: "vanilla", orderDate: new Date("2021-01-11T06:31:15Z"),
       state: "CA", price: 12, quantity: 145 },
     { _id: 3, type: "vanilla", orderDate: new Date("2020-02-08T13:13:23Z"),
       state: "WA", price: 13, quantity: 104 },
     { _id: 4, type: "strawberry", orderDate: new Date("2019-05-18T16:09:01Z"),
       state: "CA", price: 41, quantity: 162 },
     { _id: 5, type: "strawberry", orderDate: new Date("2019-01-08T06:12:03Z"),
       state: "WA", price: 43, quantity: 134 }
  ]);
  
  //db.getCollection('cakeSales').drop();
  //db.cakeSales.find();
  
  db.cakeSales.aggregate([
     {
        $setWindowFields: {
          // step 1: it will partition or divide all documents by "$state" so here CA, WA (now it could be assumed as groupBy: null so no documents will be merged into one as of yet, all document will be there)
           partitionBy: "$state",
          // step 2: now, sort within each partition by orderDate ASC
           sortBy: { orderDate: 1 },
           output: {
              cumulativeQuantityForState: {
                 // what to do on each partition ?
                 $sum: "$quantity",
                 // range : unbounded (from beginning) to current date time
                 window: {
                    documents: [ "unbounded", "current" ]
                 }
              }
           }
        }
     }
  ]);
  
  
  /* 1. Partition by Year:
  
  -- The $setWindowFields groups the data by year (using the partitionBy key with the year extracted from orderDate).
  -- For example, all orders in 2019 form one group, 2020 another, and 2021 another.
  
  2. Sort by Date:
  
  -- Inside each year group, documents are sorted by orderDate in ascending order (sortBy: { orderDate: 1 }).
  
  3. Calculate Moving Average:
  
  -- The averageQuantity is calculated using the $avg operator, but only within a specific "window" of documents.
  -- The window is defined as the document before the current one (-1) and the current document (0).
  
  This means:
  
  For the first document in a year, the average is just its quantity (no prior document exists).
  For other documents, the average includes the current document and the one immediately before it.
  
  #### Example Data:
  -- Here’s the input data grouped by year and sorted by date:
  
  2019:
  _id	  Type	       Quantity	    CumulativeQuantityForYear	                           OrderDate
  5	  Strawberry	134	        134	                                                   2019-01-08T06:12:03Z
  4	  Strawberry	162	        296                                                    2019-05-18T16:09:01Z
  
  2020:
  _id	  Type	       Quantity	    CumulativeQuantityForYear	                           OrderDate
  3	  Vanilla	    104	        104	                                                   2020-02-08T13:13:23Z
  0	  Chocolate	    120	        224                                                    2020-05-18T14:10:30Z
  
  2021:
  _id	  Type	       Quantity	    CumulativeQuantityForYear	                           OrderDate
  2	  Vanilla	    145	        145	                                                   2021-01-11T06:31:15Z
  1	  Chocolate	    140	        285                                                    2021-03-20T11:30:05Z
  
  ## Calculations:
  Using the window of [-1, 0]:
  
  2019:
  
  Document 1: Avg = (134) = 134 (no previous document)
  Document 2: Avg = (134 + 162) / 2 = 148
  2020:
  
  Document 1: Avg = (104) = 104 (no previous document)
  Document 2: Avg = (104 + 120) / 2 = 112
  2021:
  
  Document 1: Avg = (145) = 145 (no previous document)
  Document 2: Avg = (145 + 140) / 2 = 142.5
  
  ## Output Data:
  
  _id	Type	      Quantity	        AverageQuantity	            OrderDate
  5	Strawberry	  134	                134                     2019-01-08T06:12:03Z
  4	Strawberry	  162                   148                     2019-05-18T16:09:01Z
  3	Vanilla	104   104                   104                     2020-02-08T13:13:23Z
  0	Chocolate	  120                   112                     2020-05-18T14:10:30Z
  2	Vanilla	145	  145	                145                     2021-01-11T06:31:15Z
  1	Chocolate	  140	               142.5                    2021-03-20T11:30:05Z
  
  ## Visual Representation of the Collection: Here’s a diagram showing the partition and calculation flow:
  
  2019 Partition:
      (134) --> 134
      (134 + 162) / 2 --> 148
  
  2020 Partition:
      (104) --> 104
      (104 + 120) / 2 --> 112
  
  2021 Partition:
      (145) --> 145
      (145 + 140) / 2 --> 142.5
  
  
  */
  
  db.cakeSales.aggregate([
     {
        $setWindowFields: {
           partitionBy: { $year: "$orderDate" },
           sortBy: { orderDate: 1 },
           output: {
              averageQuantity: {
                 $avg: "$quantity",
                 window: {
                    documents: [ -1, 0 ]
                 }
              }
           }
        }
     }
  ]);
  
  // Use Documents Window to Obtain Cumulative and Maximum Quantity for Each Year
  db.cakeSales.aggregate( [
     {
        $setWindowFields: {
           partitionBy: { $year: "$orderDate" },
           sortBy: { orderDate: 1 },
           output: {
              cumulativeQuantityForYear: {
                 $sum: "$quantity",
                 window: {
                    //  cumulative quantity for the documents between the beginning of the partition and the current document.
                    documents: [ "unbounded", "current" ]
                 }
              },
              maximumQuantityForYear: {
                 $max: "$quantity",
                 window: {
                    // The window contains documents between an unbounded lower and upper limit. This means $max returns the maximum quantity for the documents in the partition.
                    documents: [ "unbounded", "unbounded" ]
                 }
              }
           }
        }
     }
  ]);
  
  // #### $unionWith : combines two aggregations into a single result set. $unionWith outputs the combined result set (including duplicates) to the next stage.
  
  db.suppliers.insertMany([
    { _id: 1, supplier: "Aardvark and Sons", state: "Texas" },
    { _id: 2, supplier: "Bears Run Amok.", state: "Colorado"},
    { _id: 3, supplier: "Squid Mark Inc. ", state: "Rhode Island" },
  ]);
  
  db.warehouses.insertMany([
    { _id: 1, warehouse: "A", region: "West", state: "California" },
    { _id: 2, warehouse: "B", region: "Central", state: "Colorado"},
    { _id: 3, warehouse: "C", region: "East", state: "Florida" },
  ]);
  
  db.suppliers.aggregate([
     { $project: { state: 1, _id: 0 } },
     { $unionWith: { coll: "warehouses", pipeline: [ { $project: { state: 1, _id: 0 } } ]} }
  ]);
  
  db.suppliers.aggregate([
     { $project: { state: 1, _id: 0 } },
     { $unionWith: { coll: "warehouses", pipeline: [ { $project: { state: 1, _id: 0 } } ]} },
     { $group: { _id: "$state" } }
  ]);
  
  db.sales_2017.insertMany([
    { store: "General Store", item: "Chocolates", quantity: 150 },
    { store: "ShopMart", item: "Chocolates", quantity: 50 },
    { store: "General Store", item: "Cookies", quantity: 100 },
    { store: "ShopMart", item: "Cookies", quantity: 120 },
    { store: "General Store", item: "Pie", quantity: 10 },
    { store: "ShopMart", item: "Pie", quantity: 5 }
  ]);
  
  db.sales_2018.insertMany([
    { store: "General Store", item: "Cheese", quantity: 30 },
    { store: "ShopMart", item: "Cheese", quantity: 50 },
    { store: "General Store", item: "Chocolates", quantity: 125 },
    { store: "ShopMart", item: "Chocolates", quantity: 150 },
    { store: "General Store", item: "Cookies", quantity: 200 },
    { store: "ShopMart", item: "Cookies", quantity: 100 },
    { store: "ShopMart", item: "Nuts", quantity: 100 },
    { store: "General Store", item: "Pie", quantity: 30 },
    { store: "ShopMart", item: "Pie", quantity: 25 }
  ]);
  
  db.sales_2019.insertMany([
    { store: "General Store", item: "Cheese", quantity: 50 },
    { store: "ShopMart", item: "Cheese", quantity: 20 },
    { store: "General Store", item: "Chocolates", quantity: 125 },
    { store: "ShopMart", item: "Chocolates", quantity: 150 },
    { store: "General Store", item: "Cookies", quantity: 200 },
    { store: "ShopMart", item: "Cookies", quantity: 100 },
    { store: "General Store", item: "Nuts", quantity: 80 },
    { store: "ShopMart", item: "Nuts", quantity: 30 },
    { store: "General Store", item: "Pie", quantity: 50 },
    { store: "ShopMart", item: "Pie", quantity: 75 }
  ]);
  
  db.sales_2020.insertMany( [
    { store: "General Store", item: "Cheese", quantity: 100, },
    { store: "ShopMart", item: "Cheese", quantity: 100},
    { store: "General Store", item: "Chocolates", quantity: 200 },
    { store: "ShopMart", item: "Chocolates", quantity: 300 },
    { store: "General Store", item: "Cookies", quantity: 500 },
    { store: "ShopMart", item: "Cookies", quantity: 400 },
    { store: "General Store", item: "Nuts", quantity: 100 },
    { store: "ShopMart", item: "Nuts", quantity: 200 },
    { store: "General Store", item: "Pie", quantity: 100 },
    { store: "ShopMart", item: "Pie", quantity: 100 }
  ]);
  
  //Report 1: All Sales by Year and Stores and Items
  db.sales_2017.aggregate([
     // A $set stage to update the _id field to contain the year.
     { $set: { _id: "2017" } },
     // A sequence of $unionWith stages to combine all documents from the four collections, each also using the $set stage on its documents.
     { $unionWith: { coll: "sales_2018", pipeline: [ { $set: { _id: "2018" } } ] } },
     { $unionWith: { coll: "sales_2019", pipeline: [ { $set: { _id: "2019" } } ] } },
     { $unionWith: { coll: "sales_2020", pipeline: [ { $set: { _id: "2020" } } ] } },
     // A $sort stage to sort by the _id (the year), the store, and item.
     { $sort: { _id: 1, store: 1, item: 1 } }
  ]);
  
  db.sales_2017.aggregate([
     { $unionWith: "sales_2018" },
     { $unionWith: "sales_2019" },
     { $unionWith: "sales_2020" },
     { $group: { _id: "$item", total: { $sum: "$quantity" } } },
     { $sort: { total: -1 } }
  ]);
  
  db.cakeFlavors.insertMany([
     { _id: 1, flavor: "chocolate" },
     { _id: 2, flavor: "strawberry" },
     { _id: 3, flavor: "cherry" }
  ]);
  
  db.cakeFlavors.find();
  
  db.cakeFlavors.aggregate( [
     {
        $unionWith: {
           pipeline: [
              {
                 $documents: [
                    { _id: 4, flavor: "orange" },
                    { _id: 5, flavor: "vanilla", price: 20 }
                 ]
              }
           ]
        }
     }
  ]);
  
  // #### $unset
  db.books.insertMany([
     { "_id" : 1, title: "Antelope Antics", isbn: "0001122223334", author: { last:"An", first: "Auntie" }, copies: [ { warehouse: "A", qty: 5 }, { warehouse: "B", qty: 15 } ] },
     { "_id" : 2, title: "Bees Babble", isbn: "999999999333", author: { last:"Bumble", first: "Bee" }, copies: [ { warehouse: "A", qty: 2 }, { warehouse: "B", qty: 5 } ] }
  ]);
  
  // remove the copies field from books collections
  db.books.aggregate([ { $unset: "copies" } ]); // db.books.aggregate([ { $unset: [ "copies" ] } ])
  db.books.aggregate([
     { $unset: [ "isbn", "copies" ] }
  ]);
  
  // remove the embedded fields
  db.books.aggregate([
     { $unset: [ "isbn", "author.first", "copies.warehouse" ] }
  ]);
  
  db.clothing.insertMany([
    { "_id" : 1, "item" : "Shirt", "sizes": [ "S", "M", "L"] },
    { "_id" : 2, "item" : "Shorts", "sizes" : [ ] },
    { "_id" : 3, "item" : "Hat", "sizes": "M" },
    { "_id" : 4, "item" : "Gloves" },
    { "_id" : 5, "item" : "Scarf", "sizes" : null }
  ]);
  
  db.clothing.aggregate( [ { $unwind: "$sizes" } ] ); // db.clothing.aggregate( [ { $unwind: { path: "$sizes" } } ] )
  
  db.inventory2.insertMany([
     { "_id" : 1, "item" : "ABC", price: NumberDecimal("80"), "sizes": [ "S", "M", "L"] },
     { "_id" : 2, "item" : "EFG", price: NumberDecimal("120"), "sizes" : [ ] },
     { "_id" : 3, "item" : "IJK", price: NumberDecimal("160"), "sizes": "M" },
     { "_id" : 4, "item" : "LMN" , price: NumberDecimal("10") },
     { "_id" : 5, "item" : "XYZ", price: NumberDecimal("5.75"), "sizes" : null }
  ]);
  
  // The following $unwind operation uses the preserveNullAndEmptyArrays option to include documents whose sizes field is null, missing, or an empty array.
  
  db.inventory2.aggregate([
     { $unwind: { path: "$sizes", preserveNullAndEmptyArrays: true } }
  ]);
  
  db.inventory2.aggregate( [
    {
      $unwind:
        {
          path: "$sizes",
          includeArrayIndex: "arrayIndex"
        }
     }]);
  
  db.inventory2.aggregate( [
     // First Stage
     {
       $unwind: { path: "$sizes", preserveNullAndEmptyArrays: true }
     },
     // Second Stage
     {
       $group:
         {
           _id: "$sizes",
           averagePrice: { $avg: "$price" }
         }
     },
     // Third Stage
     {
       $sort: { "averagePrice": -1 }
     }
  ]);
  
  db.sales2.insertMany([
    {
      _id: "1",
      "items" : [
       {
        "name" : "pens",
        "tags" : [ "writing", "office", "school", "stationary" ],
        "price" : NumberDecimal("12.00"),
        "quantity" : NumberInt("5")
       },
       {
        "name" : "envelopes",
        "tags" : [ "stationary", "office" ],
        "price" : NumberDecimal("19.95"),
        "quantity" : NumberInt("8")
       }
      ]
    },
    {
      _id: "2",
      "items" : [
       {
        "name" : "laptop",
        "tags" : [ "office", "electronics" ],
        "price" : NumberDecimal("800.00"),
        "quantity" : NumberInt("1")
       },
       {
        "name" : "notepad",
        "tags" : [ "stationary", "school" ],
        "price" : NumberDecimal("14.95"),
        "quantity" : NumberInt("3")
       }
      ]
    }
  ]);
  
  db.sales2.aggregate([
    // First Stage
    { $unwind: "$items" },
  
    // Second Stage
    { $unwind: "$items.tags" },
  
    // Third Stage
    {
      $group:
        {
          _id: "$items.tags",
          totalSalesAmount:
            {
              $sum: { $multiply: [ "$items.price", "$items.quantity" ] }
            }
        }
    }
  ]);
  
  // ## Mongodb operators
  
  // $zip
  db.matrices.insertMany([
    { matrix: [[1, 2], [2, 3], [3, 4]] },
    { matrix: [[8, 7], [7, 6], [5, 4]] },
  ]);
  
  db.matrices.aggregate([{
    $project: {
      _id: false,
      transposed: {
        $zip: {
          inputs: [
            { $arrayElemAt: [ "$matrix", 0 ] },
            { $arrayElemAt: [ "$matrix", 1 ] },
            { $arrayElemAt: [ "$matrix", 2 ] },
          ]
        }
      }
    }
  }]);
  
  db.pages.insertOne( {
    "category": "unix",
    "pages": [
      { "title": "awk for beginners", reviews: 5 },
      { "title": "sed for newbies", reviews: 0 },
      { "title": "grep made simple", reviews: 2 },
  ] });
  
  // The following aggregation pipeline will first zip the elements of the pages array together with their index, and then filter out only the pages with at least one review:
  db.pages.aggregate([{
    $project: {
      _id: false,
      pages: {
        //
        $filter: {
          input: {
            $zip: {
              // $pages array, the index array, which is created using $range with the range of indices from 0 to the size of the pages array ({ $size: "$pages" }).
              inputs: [ "$pages", { $range: [0, { $size: "$pages" }] } ]
            }
            // zip returns a matrix
            /*
            [
            [{ "title": "awk for beginners", "reviews": 5 }, 0],
            [{ "title": "sed for newbies", "reviews": 0 }, 1],
            [{ "title": "grep made simple", "reviews": 2 }, 2]
            ]
            */
  
          },
          // pageWithIndex refers to the zipped page and its index i.e. basically zipped result which is mentioned above (i.e. matrix)
          as: "pageWithIndex",
          cond: {
            // The condition inside $let ensures that only pages with reviews >= 1 are kept.
            $let: {
              vars: {
  
                // Here, the $arrayElemAt is applied or iterates on each individual element of the $$pageWithIndex array. and when it iterates it will pick its 0th element as instructed
                page: { $arrayElemAt: [ "$$pageWithIndex", 0 ] }
              },
              // and now, on $$page.reviews cehck whether reviews field >= 1 and only then accept it
              in: { $gte: [ "$$page.reviews", 1 ] }
            }
          }
        }
      }
    }
  }]);
  
  // $arrayElemAt
  
  db.some_flavours.insertMany([
  { "_id" : 1, "name" : "dave123", favorites: [ "chocolate", "cake", "butter", "apples" ] },
  { "_id" : 2, "name" : "li", favorites: [ "apples", "pudding", "pie" ] },
  { "_id" : 3, "name" : "ahn", favorites: [ "pears", "pecans", "chocolate", "cherries" ] },
  { "_id" : 4, "name" : "ty", favorites: [ "ice cream" ] }
  ]);
  
  db.some_flavours.aggregate([
    {$project: {
      name: 1,
      // so, as it iterates on each document, from the current iteration's document it will picke first and last item from favourites e.g. 'apples', 'pie'
      first: {$arrayElemAt: ["$favorites", 0]},
      first: {$arrayElemAt: ["$favorites", -1]}
    }}
  ]);
  
  // $arrayToObject:
  
  db.inventory.insertMany([
   { "_id" : 1, "item" : "ABC1",  dimensions: [ { "k": "l", "v": 25} , { "k": "w", "v": 10 }, { "k": "uom", "v": "cm" } ] },
   { "_id" : 2, "item" : "ABC2",  dimensions: [ [ "l", 50 ], [ "w",  25 ], [ "uom", "cm" ] ] },
   { "_id" : 3, "item" : "ABC3",  dimensions: [ [ "l", 25 ], [ "l",  "cm" ], [ "l", 50 ] ] }
  ]);
  
  
  db.inventory.aggregate(
     [
        {
           $project: {
              item: 1,
              // from the dimensions array, it pics the first item and assign to dimensions
              dimensions: { $arrayToObject: "$dimensions" }
           }
        }
     ]
  );
  
  // $objectToArray:
  
  db.inventory.aggregate(
     [
        {
           $project: {
              item: 1,
              // it will simply iterate on this "$dimesionsions" field i.e. an array and each field from "$dimension" array will be as below
              /*
              [
              {
              "_id": 1,
              "item": "ABC1",
              "dimensions": [
                { "k": "l", "v": 25 },
                  { "k": "w", "v": 10 },
                  { "k": "uom", "v": "cm" }
                 ]
               },
               {
               "_id": 2,
               "item": "ABC2",
               "dimensions": [
                 { "k": "l", "v": 50 },
                   { "k": "w", "v": 25 },
                     { "k": "uom", "v": "cm" }
                     ]
               },
               {
               "_id": 3,
               "item": "XYZ1",
               "dimensions": [
                 { "k": "l", "v": 70 },
                   { "k": "w", "v": 75 },
                     { "k": "uom", "v": "cm" }
                     ]
                     }
                ]
              */
              dimensions: { $objectToArray: "$dimensions" }
           }
        }
     ]
  );
  
  
  //{ "_id": 1, "item": "ABC1", "instock": { "warehouse1": 2500, "warehouse2": 500 } }
  //{ "_id": 2, "item": "ABC2", "instock": { "warehouse2": 500, "warehouse3": 200 } }
  
  
  db.inventory.aggregate([
     { $project: { warehouses: { $objectToArray: "$instock" } } },
     { $unwind: "$warehouses" },
     { $group: { _id: "$warehouses.k", total: { $sum: "$warehouses.v" } } }
  ]);
  
  // The following aggregation pipeline operation calculates the total in stock for each item and adds to the instock document:
  
  db.inventory.aggregate( [
     { $addFields: { instock: { $objectToArray: "$instock" } } },
     { $addFields: { instock: { $concatArrays: [ "$instock", [ { "k": "total", "v": { $sum: "$instock.v" } } ] ] } } } , // $sum will simply sum up all "$instock.v" from the current iteration's current document
     { $addFields: { instock: { $arrayToObject: "$instock" } } }
  ] )
  
  
  // $mergeObjects
  
  db.orders2.insertMany([
    { "_id" : 1, "item" : "abc", "price" : 12, "ordered" : 2 },
    { "_id" : 2, "item" : "jkl", "price" : 20, "ordered" : 1 }
  ]);
  
  db.orders2.aggregate([
     {
        $lookup: {
           from: "items",
           localField: "item",    // field in the orders collection
           foreignField: "item",  // field in the items collection
           as: "fromItems"
        }
     },
     {
        $replaceRoot: { newRoot: { $mergeObjects: [ { $arrayElemAt: [ "$fromItems", 0 ] }, "$$ROOT" ] } }
     },
     { $project: { fromItems: 0 } }
  ]);
  
  db.items.insertMany([
    { "_id" : 1, "item" : "abc", description: "product 1", "instock" : 120 },
    { "_id" : 2, "item" : "def", description: "product 2", "instock" : 80 },
    { "_id" : 3, "item" : "jkl", description: "product 3", "instock" : 60 }
  ]);
  
  db.sales3.insertMany( [
     { _id: 1, year: 2017, item: "A", quantity: { "2017Q1": 500, "2017Q2": 500 } },
     { _id: 2, year: 2016, item: "A", quantity: { "2016Q1": 400, "2016Q2": 300, "2016Q3": 0, "2016Q4": 0 } } ,
     { _id: 3, year: 2017, item: "B", quantity: { "2017Q1": 300 } },
     { _id: 4, year: 2016, item: "B", quantity: { "2016Q3": 100, "2016Q4": 250 } }
  ]);
  
  // $mergeObjects as an accumulator
  db.sales3.aggregate([
     // so, it will group by "$item" and then create a new filed named "mergedSales" and its value will be an object as see below
     // and within the object, it will include each document's quantity (for better understanding, run below query)
     { $group: { _id: "$item", mergedSales: { $mergeObjects: "$quantity" } } }
  ]);
  
  // $or, $and
  db.inventory.aggregate(
     [
       {
         $project:
            {
              item: 1,
              result: { $or: [ { $gt: [ "$qty", 250 ] }, { $lt: [ "$qty", 200 ] } ] }
            }
       }
     ]
  );
  
  db.inventory.aggregate(
     [
       {
         $project:
            {
              item: 1,
              qty: 1,
              result: { $and: [ { $gt: [ "$qty", 100 ] }, { $lt: [ "$qty", 250 ] } ] }
            }
       }
     ]
  );
  
  // $addToSet
  db.sales4.insertMany([{ "_id" : 1, "item" : "abc", "price" : 10, "quantity" : 2, "date" : ISODate("2014-01-01T08:00:00Z") },
  { "_id" : 2, "item" : "jkl", "price" : 20, "quantity" : 1, "date" : ISODate("2014-02-03T09:00:00Z") },
  { "_id" : 3, "item" : "xyz", "price" : 5, "quantity" : 5, "date" : ISODate("2014-02-03T09:05:00Z") },
  { "_id" : 4, "item" : "abc", "price" : 10, "quantity" : 10, "date" : ISODate("2014-02-15T08:00:00Z") },
  { "_id" : 5, "item" : "xyz", "price" : 5, "quantity" : 10, "date" : ISODate("2014-02-15T09:12:00Z") }]);
  
  db.sales4.aggregate(
     [
       {
         $group:
           {
             _id: { day: { $dayOfYear: "$date"}, year: { $year: "$date" } },
             itemsSold: { $addToSet: "$item" }
           }
       }
     ]
  );
  
  db.cakeSales.aggregate([
     {
        $setWindowFields: {
           partitionBy: "$state",
           sortBy: { orderDate: 1 },
           output: {
              cakeTypesForState: {
                 $addToSet: "$type",
                 window: {
                    documents: [ "unbounded", "current" ]
                 }
              }
           }
        }
     }
  ]);
  
  // $reduce
  db.events.insertMany([
     { _id : 1, type : "die", experimentId :"r5", description : "Roll a 5", eventNum : 1, probability : 0.16666666666667 },
     { _id : 2, type : "card", experimentId :"d3rc", description : "Draw 3 red cards", eventNum : 1, probability : 0.5 },
     { _id : 3, type : "card", experimentId :"d3rc", description : "Draw 3 red cards", eventNum : 2, probability : 0.49019607843137 },
     { _id : 4, type : "card", experimentId :"d3rc", description : "Draw 3 red cards", eventNum : 3, probability : 0.48 },
     { _id : 5, type : "die", experimentId :"r16", description : "Roll a 1 then a 6", eventNum : 1, probability : 0.16666666666667 },
     { _id : 6, type : "die", experimentId :"r16", description : "Roll a 1 then a 6", eventNum : 2, probability : 0.16666666666667 },
     { _id : 7, type : "card", experimentId :"dak", description : "Draw an ace, then a king", eventNum : 1, probability : 0.07692307692308 },
     { _id : 8, type : "card", experimentId :"dak", description : "Draw an ace, then a king", eventNum : 2, probability : 0.07843137254902 }
  ]);
  
  db.events.aggregate([
    {
      $group: {
        _id: "$experimentId",
        probabilityArr: { $push: "$probability" }
      }
    },
    {
      $project: {
        description: 1,
        results: {
          $reduce: {
            input: "$probabilityArr", // input: The array being processed (probabilityArr)
            initialValue: 1, // the initital value for this reduce is 1
            in: { $multiply: ["$$value", "$$this"] } // Multiplies the current cumulative value ($$value) with the current array element ($$this) i.e. like accumulator in a reduce fn
          }
        }
      }
    }
  ]);
  
  
  db.clothes.insertMany( [
     { _id : 1, productId : "ts1", description : "T-Shirt", color : "black", size : "M", price : 20, discounts : [ 0.5, 0.1 ] },
     { _id : 2, productId : "j1", description : "Jeans", color : "blue", size : "36", price : 40, discounts : [ 0.25, 0.15, 0.05 ] },
     { _id : 3, productId : "s1", description : "Shorts", color : "beige", size : "32", price : 30, discounts : [ 0.15, 0.05 ] },
     { _id : 4, productId : "ts2", description : "Cool T-Shirt", color : "White", size : "L", price : 25, discounts : [ 0.3 ] },
     { _id : 5, productId : "j2", description : "Designer Jeans", color : "blue", size : "30", price : 80, discounts : [ 0.1, 0.25 ] }
  ]);
  
  db.clothes.aggregate(
    [
      {
        $project: {
          discountedPrice: {
            $reduce: {
              input: "$discounts",
              initialValue: "$price",
              in: { $multiply: [ "$$value", { $subtract: [ 1, "$$this" ] } ] }
            }
          }
        }
      }
    ]
  );
  
  db.people.find();
  
  db.people.aggregate(
     [
       // Filter to return only non-empty arrays
       { $match: { "hobbies": { $gt: [ ] } } },
       {
         $project: {
           name: 1,
           bio: {
             $reduce: {
               input: "$hobbies",
               initialValue: "My hobbies include:",
               in: {
                 $concat: [
                   "$$value",
                   {
                     $cond: {
                       if: { $eq: [ "$$value", "My hobbies include:" ] },
                       then: " ",
                       else: ", "
                     }
                   },
                   "$$this"
                 ]
               }
             }
           }
         }
       }
     ]
  );
  
  db.arrayconcat.insertMany( [
     { _id : 1, arr : [ [ 24, 55, 79 ], [ 14, 78, 35 ], [ 84, 90, 3 ], [ 50, 89, 70 ] ] },
     { _id : 2, arr : [ [ 39, 32, 43, 7 ], [ 62, 17, 80, 64 ], [ 17, 88, 11, 73 ] ] },
     { _id : 3, arr : [ [ 42 ], [ 26, 59 ], [ 17 ], [ 72, 19, 35 ] ] },
     { _id : 4 }
  ]);
  
  db.arrayconcat.aggregate(
    [
      {
        $project: {
          collapsed: {
            $reduce: {
              input: "$arr",
              initialValue: [ ],
              in: { $concatArrays: [ "$$value", "$$this" ] }
            }
          }
        }
      }
    ]
  );
  
  
  db.arrayconcat.aggregate(
    [
      {
        $project: {
          results: {
            $reduce: {
              input: "$arr",
              initialValue: [ ],
              in: {
                collapsed: {
                  $concatArrays: [ "$$value.collapsed", "$$this" ]
                },
                firstValues: {
                  $concatArrays: [ "$$value.firstValues", { $slice: [ "$$this", 1 ] } ]
                }
              }
            }
          }
        }
      }
    ]
  );
  
  
  // $avg: https://www.mongodb.com/docs/manual/reference/operator/aggregation/avg/
  
  // $cond: https://www.mongodb.com/docs/manual/reference/operator/aggregation/cond/
  
  // $dateAdd: https://www.mongodb.com/docs/manual/reference/operator/aggregation/dateAdd/
  
  // $dateDiff: https://www.mongodb.com/docs/manual/reference/operator/aggregation/dateDiff/
  
  // $dateFromString: https://www.mongodb.com/docs/manual/reference/operator/aggregation/dateFromString/
  
  // $dateToParts: https://www.mongodb.com/docs/manual/reference/operator/aggregation/dateSubtract/
  
  // $dateToString: https://www.mongodb.com/docs/manual/reference/operator/aggregation/dateToString/
  
  // $dateTrunc: https://www.mongodb.com/docs/manual/reference/operator/aggregation/dateTrunc/
  
  // $dayOfMonth: https://www.mongodb.com/docs/manual/reference/operator/aggregation/dayOfMonth/
  
  // $dayOfWeek: https://www.mongodb.com/docs/manual/reference/operator/aggregation/dayOfWeek/
  
  // $dayOfYear: https://www.mongodb.com/docs/manual/reference/operator/aggregation/dayOfYear/
  
  // $divide: https://www.mongodb.com/docs/manual/reference/operator/aggregation/divide/
  
  // $eq: https://www.mongodb.com/docs/manual/reference/operator/aggregation/eq/
  
  // $exp: https://www.mongodb.com/docs/manual/reference/operator/aggregation/exp/
  
  // $filter
  
  db.sales2.aggregate([
     {
        $project: {
           items: {
              $filter: {
                 input: "$items",
                 as: "item",
                 cond: { $gte: [ "$$item.price", 12.00 ] }
              }
           }
        }
     }
  ]);
  
  db.sales2.aggregate( [
     {
        $project: {
           items: {
              $filter: {
                 input: "$items",
                 as: "item",
                 cond: { $gte: [ "$$item.price", 100 ] },
                 limit: 1
              }
           }
        }
     }
  ]);
  
  db.sales2.aggregate( [
     {
        $project: {
           items: {
              $filter: {
                 input: "$items",
                 as: "item",
                 cond: { $gte: [ "$$item.price", 100] },
                 limit: 5
              }
           }
        }
     }
  ]);
  
  db.sales2.aggregate([
     {
        $project: {
           items: {
              $filter: {
                 input: "$items",
                 as: "item",
                 cond: { $eq: [ "$$item.name", "pen"] }
              }
           }
        }
     }
  ]);
  
  db.sales2.aggregate( [
     {
        $project: {
           items: {
              $filter: {
                 input: "$items",
                 as: "item",
                 cond: {
                    $regexMatch: { input: "$$item.name", regex: /^p/ }
                 }
              }
           }
        }
     }
  ]);
  
  
  // $function : https://www.mongodb.com/docs/manual/reference/operator/aggregation/function/
  
  // $ifNull: https://www.mongodb.com/docs/manual/reference/operator/aggregation/ifNull/
  
  // $in: https://www.mongodb.com/docs/manual/reference/operator/aggregation/in/
  
  // $isArray: https://www.mongodb.com/docs/manual/reference/operator/aggregation/isArray/
  
  // $isoDayOfWeek: https://www.mongodb.com/docs/manual/reference/operator/aggregation/isoDayOfWeek/
  
  // $isoWeek: https://www.mongodb.com/docs/manual/reference/operator/aggregation/isoWeek/
  
  // $isoWeekYear: https://www.mongodb.com/docs/manual/reference/operator/aggregation/isoWeekYear/
  
  // $setField: Adds, updates, or removes a specified field in a document
  db.inventory2.insertMany([
     { "_id" : 1, "item" : "sweatshirt", price: 45.99, qty: 300 },
     { "_id" : 2, "item" : "winter coat", price: 499.99, qty: 200 },
     { "_id" : 3, "item" : "sun dress", price: 199.99, qty: 250 },
     { "_id" : 4, "item" : "leather boots", price: 249.99, qty: 300 },
     { "_id" : 5, "item" : "bow tie", price: 9.99, qty: 180 }
  ]);
  
  // The following operation uses the $replaceWith pipeline stage and the $setField operator to add a new field to each document, "price.usd". The value of "price.usd" will equal the value of "price" in each document. Finally, the operation uses the $unset pipeline stage to remove the "price" field.
  db.inventory2.aggregate( [
     { $replaceWith: {
          $setField: {
             field: "price.usd", // new field name i.e. created during each iteration
             input: "$$ROOT",   // to allow or make it able to iterate on each document
             value: "$price"   // value to pass onto "price.usd" from each iteration
     } } },
     { $unset: "price" }
  ]);
  
  // exactly same as the above except The value of "$price" will equal the value of "price" in each document. Finally, the operation uses the $unset pipeline stage to remove the "price" field.
  
  db.inventory2.aggregate( [
     { $replaceWith: {
          $setField: {
             field: { $literal: "$price" }, // during the each iteration, take the "$price" and add it to this newly created "price" i.e. what literal means
             input: "$$ROOT", // refer to the entire or all documents being processed
             value: "$price" // during each iteration, take "$price" from current document which will be assigned to "price" i.e. being created here
     } } },
     { $unset: "price" }
  ]);
  
  
  db.inventory.aggregate( [
     { $match: { _id: 1 } }, // find this very document by _id
     { $replaceWith: {
          $setField: {
             field: "price.usd", // new field is being created i.e. 'price.usd'
             input: "$$ROOT", // refer to entire or all documents being processed
             value: 49.99 // this value i.e. hard-coded will be assigned to the field being created i.e. 'price.usd'
      } } }
  ]);
  
  // so, find the _id: 1 and update its price as below
  db.inventory2.aggregate( [
     { $match: { _id: 1 } },
     { $replaceWith: {
          $setField: {
             field: { $literal: "$price" },
             input: "$$ROOT",
             value: 1049.99
     } } }
  ]);
  
  // The following operation uses the $replaceWith pipeline stage and the $setField operator and $$REMOVE to remove the "price.usd" field from each document:
  db.inventory2.aggregate( [
     { $replaceWith:  {
          $setField: {
             field: "price.usd", // during iteration take this field
             input: "$$ROOT", // refers to entire or all documents being processed
             value: "$$REMOVE" // whichever field is selected , is going to be removed during each iteration
     } } }
  ]);
  
  // does same as the above
  
  db.inventory2.aggregate( [
     { $replaceWith:  {
          $unsetField: {
             field: "price.usd",
             input: "$$ROOT"
     } } }
  ]);
  
  // The following operation uses the $replaceWith pipeline stage, the $setField and $literal operators, and $$REMOVE to remove the "$price" field from each document:
  
  db.inventory2.aggregate([
     { $replaceWith: {
          $setField: {
             field: { $literal: "$price" },
             input: "$$ROOT",
             value: "$$REMOVE"
     } } }
  ]);
  
  
  // $setDifference
  db.flowers.aggregate(
     [
       { $project: { flowerFieldA: 1, flowerFieldB: 1, inBOnly: { $setDifference: [ "$flowerFieldB", "$flowerFieldA" ] }, _id: 0 } }
     ]
  );
  
  // $replaceAll, $replaceOne
  
  db.inventory2.aggregate([
     {
       $project:
        {
           item: { $replaceAll: { input: "$item", find: "winter coat", replacement: "winter hoodie" } }
        }
     }
  ]);
  
  db.inventory2.aggregate([
     {
       $project:
        {
           item: { $replaceAll: { input: "$item", find: "winter coat", replacement: "winter hoodie" } }
        }
     }
  ]);
  
  db.inventory2.aggregate([
     {
       $project:
        {
           item: { $replaceOne: { input: "$item", find: "leather boots", replacement: "leather shoes" } }
        }
     }
  ]);
  
  // $setInteraction: Takes two or more arrays and returns an array that contains the elements that appear in every input array
  db.flowers.aggregate(
     [
       { $project: { flowerFieldA: 1, flowerFieldB: 1, commonToBoth: { $setIntersection: [ "$flowerFieldA", "$flowerFieldB" ] }, _id: 0 } }
     ]
  );
  
  db.budget.insertMany( [
     {
        _id: 0,
        allowedRoles: [ "Marketing" ],
        comment: "For marketing team",
        yearlyBudget: 15000
     },
     {
        _id: 1,
        allowedRoles: [ "Sales" ],
        comment: "For sales team",
        yearlyBudget: 17000,
        salesEventsBudget: 1000
     },
     {
        _id: 2,
        allowedRoles: [ "Operations" ],
        comment: "For operations team",
        yearlyBudget: 19000,
        cloudBudget: 12000
     },
     {
        _id: 3,
        allowedRoles: [ "Development" ],
        comment: "For development team",
        yearlyBudget: 27000
     }
  ]);
  
  db.budget.aggregate( [ {
     $match: {
        $expr: {
           $not: {
              $eq: [ { $setIntersection: [ "$allowedRoles", "$$USER_ROLES.role" ] }, [] ]
           }
        }
     }
  } ] );
  
  // $setIsSubset: Takes two arrays and returns true when the first array is a subset of the second, including when the first array equals the second array, and false otherwise
  db.flowers.aggregate(
     [
       { $project: { flowerFieldA:1, flowerFieldB: 1, AisSubset: { $setIsSubset: [ "$flowerFieldA", "$flowerFieldB" ] }, _id:0 } }
     ]
  );
  
  // $setUnion: Takes two or more arrays and returns an array containing the elements that appear in any input array
  
  db.flowers.insertMany([
     { "_id" : 1, "flowerFieldA" : [ "rose", "orchid" ], "flowerFieldB" : [ "rose", "orchid" ] },
     { "_id" : 2, "flowerFieldA" : [ "rose", "orchid" ], "flowerFieldB" : [ "orchid", "rose", "orchid" ] },
     { "_id" : 3, "flowerFieldA" : [ "rose", "orchid" ], "flowerFieldB" : [ "rose", "orchid", "jasmine" ] },
     { "_id" : 4, "flowerFieldA" : [ "rose", "orchid" ], "flowerFieldB" : [ "jasmine", "rose" ] },
     { "_id" : 5, "flowerFieldA" : [ "rose", "orchid" ], "flowerFieldB" : [ ] },
     { "_id" : 6, "flowerFieldA" : [ "rose", "orchid" ], "flowerFieldB" : [ [ "rose" ], [ "orchid" ] ] },
     { "_id" : 7, "flowerFieldA" : [ "rose", "orchid" ], "flowerFieldB" : [ [ "rose", "orchid" ] ] },
     { "_id" : 8, "flowerFieldA" : [ ], "flowerFieldB" : [ ] },
     { "_id" : 9, "flowerFieldA" : [ ], "flowerFieldB" : [ "rose" ] }
  ]);
  
  db.flowers.aggregate(
     [
       { $project: { flowerFieldA:1, flowerFieldB: 1, allValues: { $setUnion: [ "$flowerFieldA", "$flowerFieldB" ] }, _id: 0 } }
     ]
  );
  
  // $shift
  db.cakeSales.aggregate([
     {
        $setWindowFields: {
           /*
           // so, first `partitionBy: "$state"` will group the available document as below, then sort each document within each partition qty desc
  
           // CA partition
           [
           { "_id": 4, "quantity": 162 },
           { "_id": 2, "quantity": 145 },
           { "_id": 0, "quantity": 120 }
           ]
  
           // WA partition
           [
           { "_id": 1, "quantity": 140 },
           { "_id": 5, "quantity": 134 },
           { "_id": 3, "quantity": 104 }
           ]
           */
           partitionBy: "$state",
           sortBy: { quantity: -1 },
           output: {
              shiftQuantityForState: {
                 // For each document, shiftQuantityForState contains the quantity value of the next document in the partition. If no next document exists, "Not available" is assigned.
             /*
                 // CA i.e. california parition would be like this
                 [
                 { "_id": 4, "quantity": 162, "shiftQuantityForState": 145 },
                 { "_id": 2, "quantity": 145, "shiftQuantityForState": 120 },
                 { "_id": 0, "quantity": 120, "shiftQuantityForState": "Not available" }
                 ]
  
                 // WA i.e washington output
                 [
                 { "_id": 1, "quantity": 140, "shiftQuantityForState": 134 },
                 { "_id": 5, "quantity": 134, "shiftQuantityForState": 104 },
                 { "_id": 3, "quantity": 104, "shiftQuantityForState": "Not available" }
                 ]
             */
                // The shift operation retrieves the quantity from the next document (based on sorting) in the partition as shown in the example above
                 $shift: {
                    output: "$quantity",
                    by: 1,
                    default: "Not available"
                 }
              }
           }
        }
     }
  ]);
  
  // just like above query, but instead of using value from next document within each partition, it uses prev value each document within a partition
  
  db.cakeSales.aggregate( [
     {
        $setWindowFields: {
           partitionBy: "$state",
           sortBy: { quantity: -1 },
           output: {
              shiftQuantityForState: {
                 $shift: {
                    output: "$quantity",
                    by: -1,
                    default: "Not available"
                 }
              }
           }
        }
     }
  ]);
  
  // $slice
  db.some_flavours.aggregate([
     // so, it will iterate on each document and then from favourites starting from 0 (inclusive) to 3 (exclusive)
     { $project: { name: 1, threeFavorites: { $slice: [ "$favorites", 3 ] } } }
  ]);
  
  // $split
  db.deliveries.insertMany([
     { _id: 1, city: "Berkeley, CA", qty: 648 },
     { _id: 2, city: "Bend, OR", qty: 491 },
     { _id: 3, city: "Kensington, CA", qty: 233 },
     { _id: 4, city: "Eugene, OR", qty: 842 },
     { _id: 5, city: "Reno, NV", qty: 655 },
     { _id: 6, city: "Portland, OR", qty: 408 },
     { _id: 7, city: "Sacramento, CA", qty: 574 }
  ]);
  
  db.deliveries.aggregate([
    { $project: { city_state: { $split: ["$city", ", "] }, qty: 1 } },
    { $unwind: "$city_state" },
    { $match: { city_state: /[A-Z]{2}/ } },
    { $group: { _id: { state: "$city_state" }, total_qty: { $sum: "$qty" } } },
    { $sort: { total_qty: -1 } }
  ]);
  
  // $rank
  db.cakeSales.aggregate([
     {
        $setWindowFields: {
           partitionBy: "$state",
           sortBy: { quantity: -1 },
           // This specifies the field to be added to each document in the pipeline. In this case, it adds a new field called rankQuantityForState to each document, which contains the rank of that document within its state partition.
           // $rank: {}: This operator assigns a rank to each document within its partition based on the order specified by sortBy. The document with the highest quantity will get rank 1, the next will get rank 2, and so on.
  
           output: {
              rankQuantityForState: {
                 $rank: {} // it just assigns the rank (starting from the 1) to each document within each partition e.g. CA, WA
              }
           }
        }
     }
  ]);
  
  
  db.cakeSales.aggregate([
     {
        $setWindowFields: {
           partitionBy: "$state",
           sortBy: { orderDate: 1 },
           output: {
              rankOrderDateForState: {
                 $rank: {}
              }
           }
        }
     }
  ]);
  
  db.cakeSalesWithDuplicates.insertMany([
     { _id: 0, type: "chocolate", orderDate: new Date("2020-05-18T14:10:30Z"),
       state: "CA", price: 13, quantity: 120 },
     { _id: 1, type: "chocolate", orderDate: new Date("2021-03-20T11:30:05Z"),
       state: "WA", price: 14, quantity: 140 },
     { _id: 2, type: "vanilla", orderDate: new Date("2021-01-11T06:31:15Z"),
       state: "CA", price: 12, quantity: 145 },
     { _id: 3, type: "vanilla", orderDate: new Date("2020-02-08T13:13:23Z"),
       state: "WA", price: 13, quantity: 104 },
     { _id: 4, type: "strawberry", orderDate: new Date("2019-05-18T16:09:01Z"),
       state: "CA", price: 41, quantity: 162 },
     { _id: 5, type: "strawberry", orderDate: new Date("2019-01-08T06:12:03Z"),
       state: "WA", price: 43, quantity: 134 },
     { _id: 6, type: "strawberry", orderDate: new Date("2020-01-08T06:12:03Z"),
       state: "WA", price: 41, quantity: 134 },
     { _id: 7, type: "strawberry", orderDate: new Date("2020-01-01T06:12:03Z"),
       state: "WA", price: 34, quantity: 134 },
     { _id: 8, type: "strawberry", orderDate: new Date("2020-01-02T06:12:03Z"),
       state: "WA", price: 40, quantity: 134 },
     { _id: 9, type: "strawberry", orderDate: new Date("2020-05-11T16:09:01Z"),
       state: "CA", price: 39, quantity: 162 },
     { _id: 10, type: "strawberry", orderDate: new Date("2020-05-11T16:09:01Z"),
       state: "CA", price: 39, quantity: null },
     { _id: 11, type: "strawberry", orderDate: new Date("2020-05-11T16:09:01Z"),
       state: "CA", price: 39 }
  ]);
  
  db.cakeSalesWithDuplicates.aggregate([
     {
        $setWindowFields: {
           partitionBy: "$state",
           sortBy: { quantity: -1 },
           output: {
              rankQuantityForState: {
                 $rank: {}
              }
           }
        }
     }
  ]);
  
  // $distances:
  db.distances.insertMany([
     { _id: 0, city: "San Jose", distance: 42 },
     { _id: 1, city: "Sacramento", distance: 88 },
     { _id: 2, city: "Reno", distance: 218 },
     { _id: 3, city: "Los Angeles", distance: 383 }
  ]);
  
  // A bicyclist is planning to ride from San Francisco to each city listed in the collection and wants to stop and rest every 25 miles. The following aggregation pipeline operation uses the $range operator to determine the stopping points for each trip
  db.distances.aggregate([{
      $project: {
          _id: 0,
          city: 1,
          // so, when iteratin on each document, start from 0 and increment by 25 upto current document's distance
          // so, on the 1st iteration, it will 0, 25 (and then if it increments again it will be 50 which will be wrong), similarly on subsequent iterations
          "rest_stops": { $range: [ 0, "$distance", 25 ] }
      }
  }]);
  
  // $sum
  
  db.sales2.aggregate(
     [
       {
         $group:
           {
             _id: { day: { $dayOfYear: "$date"}, year: { $year: "$date" } },
             totalAmount: { $sum: { $multiply: [ "$price", "$quantity" ] } },
             count: { $sum: 1 }
           }
       }
     ]
  );
  
  db.sales2.aggregate(
     [
       {
         $group:
           {
             _id: { day: { $dayOfYear: "$date"}, year: { $year: "$date" } },
             totalAmount: { $sum: "$qty" },
             count: { $sum: 1 }
           }
       }
     ]
  );
  
  db.students.aggregate([
     {
       $project: {
         quizTotal: { $sum: "$quizzes"},
         labTotal: { $sum: "$labs" },
         examTotal: { $sum: [ "$final", "$midterm" ] }
       }
     }
  ]);
  
  db.cakeSales.aggregate( [
     {
        $setWindowFields: {
           partitionBy: "$state",
           sortBy: { orderDate: 1 },
           output: {
              sumQuantityForState: {
                 $sum: "$quantity",
                 window: {
                    documents: [ "unbounded", "current" ]
                 }
              }
           }
        }
     }
  ]);
  
  // $switch
  
  db.grades.insertMany([{ "_id" : 1, "name" : "Susan Wilkes", "scores" : [ 87, 86, 78 ] },
  { "_id" : 2, "name" : "Bob Hanna", "scores" : [ 71, 64, 81 ] },
  { "_id" : 3, "name" : "James Torrelio", "scores" : [ 91, 84, 97 ] }]);
  
  db.grades.aggregate( [
    {
      $project:
        {
          "name" : 1,
          "summary" :
          {
            $switch:
              {
                branches: [
                  {
                    case: { $gte : [ { $avg : "$scores" }, 90 ] },
                    then: "Doing great!"
                  },
                  {
                    case: { $and : [ { $gte : [ { $avg : "$scores" }, 80 ] },
                                     { $lt : [ { $avg : "$scores" }, 90 ] } ] },
                    then: "Doing pretty well."
                  },
                  {
                    case: { $lt : [ { $avg : "$scores" }, 80 ] },
                    then: "Needs improvement."
                  }
                ],
                default: "No scores found."
              }
           }
        }
     }
  ] );
  
  
  // $year, $week
  
  db.sales.aggregate(
     [
       {
         $project:
           {
             year: { $year: "$date" },
             month: { $month: "$date" },
             day: { $dayOfMonth: "$date" },
             hour: { $hour: "$date" },
             minutes: { $minute: "$date" },
             seconds: { $second: "$date" },
             milliseconds: { $millisecond: "$date" },
             dayOfYear: { $dayOfYear: "$date" },
             dayOfWeek: { $dayOfWeek: "$date" },
             week: { $week: "$date" }
           }
       }
     ]
  );
  
  // $unsetField
  db.inventory2.find();
  
  db.inventory2.aggregate( [
     { $replaceWith: {
          $unsetField: {
             field: { $literal: "price" },
             input: "$$ROOT"
     } } }
  ]);
  
  // $getField
  db.inventory3.insertMany( [
     { _id: 1, item: "sweatshirt", qty: 300, "price": {"usd":45.99, "euro": 38.77 } },
     { _id: 2, item: "winter coat", qty: 200, "price": { "usd": 499.99, "euro": 420.51 } },
     { _id: 3, item: "sun dress", qty: 250, "price": { "usd": 199.99, "euro": 167.70 } },
     { _id: 4, item: "leather boots", qty: 300, "price": { "usd": 249.99, "euro": 210.68 } },
     { _id: 5, item: "bow tie", qty: 180, "price": { "usd": 9.99, "euro": 8.42 } }
   ]);
  
   db.inventory3.aggregate( [
     { $replaceWith: {
          $setField: {
             field: "price",
             input: "$$ROOT",
             value: {
                $unsetField: {
                   field: "euro",
                   input: { $getField: "price" }
     } } } } }
  ]);
  
  // $type
  db.coll.insertMany([
  { _id: 0, a : 8 },
  { _id: 1, a : [ 41.63, 88.19 ] },
  { _id: 2, a : { a : "apple", b : "banana", c: "carrot" } },
  { _id: 3, a :  "caribou" },
  { _id: 4, a : NumberLong(71) },
  { _id: 5 }
  ]);
  
  db.coll.aggregate([{
      $project: {
         a : { $type: "$a" }
      }
  }]);
  
  // $substr
  
  db.inventory4.insertMany([
  { "_id" : 1, "item" : "ABC1", quarter: "13Q1", "description" : "product 1" },
  { "_id" : 2, "item" : "ABC2", quarter: "13Q4", "description" : "product 2" },
  { "_id" : 3, "item" : "XYZ1", quarter: "14Q2", "description" : null }
  ]);
  
  db.inventory4.aggregate(
     [
       {
         $project:
            {
              item: 1,
              yearSubstring: { $substr: [ "$quarter", 0, 2 ] },
              quarterSubtring: { $substr: [ "$quarter", 2, -1 ] }
            }
        }
     ]
  );
  
  
  // $topN, $top
  
  db.gamescores.insertMany([
     { playerId: "PlayerA", gameId: "G1", score: 31 },
     { playerId: "PlayerB", gameId: "G1", score: 33 },
     { playerId: "PlayerC", gameId: "G1", score: 99 },
     { playerId: "PlayerD", gameId: "G1", score: 1 },
     { playerId: "PlayerA", gameId: "G2", score: 10 },
     { playerId: "PlayerB", gameId: "G2", score: 14 },
     { playerId: "PlayerC", gameId: "G2", score: 66 },
     { playerId: "PlayerD", gameId: "G2", score: 80 }
  ]);
  
  // Find the three highest scores
  db.gamescores.aggregate( [
     {
        $match : { gameId : "G1" }
     },
     {
        $group:
           {
              _id: "$gameId",
              playerId:
                 {
                    $topN:
                    {
                       output: ["$playerId", "$score"],
                       sortBy: { "score": -1 },
                       n:3
                    }
                 }
           }
     }
  ] );
  
  
  //SELECT T3.GAMEID,T3.PLAYERID,T3.SCORE FROM GAMESCORES AS GS
  //JOIN (SELECT TOP 3 GAMEID,PLAYERID,SCORE FROM GAMESCORES WHERE GAMEID = 'G1' ORDER BY SCORE DESC) AS T3 ON GS.GAMEID = T3.GAMEID
  //GROUP BY T3.GAMEID,T3.PLAYERID,T3.SCORE ORDER BY T3.SCORE DESC
  
  
  // Finding the Three Highest Score Documents Across Multiple Games
  
  db.gamescores.aggregate( [
        {
           $group: {
           _id: "$gameId",
           playerId: {
                 $topN:
                    {
                       output: [ "$playerId","$score" ],
                       sortBy: { "score": -1 },
                       n: 3
                    }
              }
           }
        }
  ]);
  
  //SELECT PLAYERID,GAMEID,SCORE
  //FROM(
  //   SELECT ROW_NUMBER() OVER (PARTITION BY GAMEID ORDER BY SCORE DESC) AS GAMERANK,
  //   GAMEID,PLAYERID,SCORE
  //   FROM GAMESCORES
  //) AS T
  //WHERE GAMERANK <= 3
  //ORDER BY GAMEID
  
  // Computing n Based on the Group Key for $group
  db.gamescores.aggregate([
     {
        $group:
        {
           _id: {"gameId": "$gameId"},
           gamescores:
              {
                 $topN:
                    {
                       output: "$score",
                       n: { $cond: { if: {$eq: ["$gameId","G2"] }, then: 1, else: 3 } },
                       sortBy: { "score": -1 }
                    }
              }
        }
     }
  ]);
  
  // Find the top score
  db.gamescores.aggregate([
     {
        $match : { gameId : "G1" }
     },
     {
        $group:
           {
              _id: "$gameId",
              playerId:
                 {
                    $top:
                    {
                       output: [ "$playerId", "$score" ],
                       sortBy: { "score": -1 }
                    }
                 }
           }
     }
  ]);
  
  db.getCollection('users').find();