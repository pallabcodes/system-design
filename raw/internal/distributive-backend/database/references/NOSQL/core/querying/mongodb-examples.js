// MongoDB Query Examples
// Comprehensive MongoDB query examples extracted from template_nosql.js
// Covers CRUD operations, queries, aggregation, and advanced patterns

// ===========================================
// BASIC CRUD OPERATIONS
// ===========================================

// Insert single document
db.inventory.insertOne({
   item: "journal",
   qty: 25,
   tags: ["writing", "stationery"],
   size: { h: 14, w: 21, uom: "cm" }
});

// Insert multiple documents
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
   }
]);

// Update single document
db.inventory.updateOne(
   { item: "journal" },
   { $set: { qty: 55 } }
);

// Update multiple documents
db.inventory.updateMany(
   { tags: "writing" },
   { $inc: { qty: 10 } }
);

// Replace document
db.inventory.replaceOne(
   { item: "notebook" },
   { item: "spiral notebook", qty: 45, tags: ["school", "stationery"] }
);

// Find and update
db.inventory.findOneAndUpdate(
   { item: "paper" },
   { $set: { qty: 120 } },
   { returnDocument: "after" }
);

// Delete single document
db.inventory.deleteOne({ item: "spiral notebook" });

// Delete multiple documents
db.inventory.deleteMany({ tags: "stationery" });

// Find and delete
db.inventory.findOneAndDelete({ item: "paper" });

// Upsert
db.inventory.findOneAndUpdate(
   { item: 'stencil' },
   { $set: {
       item: "stencil",
       qty: 10,
       tags: ["stationery"],
       size: { h: 2, w: 5, uom: "cm" }
     }
   },
   { upsert: true }
);

// Bulk write
db.inventory.bulkWrite([
   { insertOne: { document: { item: "marker", qty: 50 } } },
   { updateOne: { filter: { item: "pen" }, update: { $inc: { qty: 10 } }, upsert: true } },
   { deleteOne: { filter: { item: "eraser" } } }
]);

// ===========================================
// QUERY OPERATIONS
// ===========================================

// Find all documents
db.inventory.find();

// Find with filter
db.inventory.find({ status: 'A' });

// Find with multiple conditions
db.inventory.find({ status: 'A', qty: { $gt: 30 } });

// OR condition
db.inventory.find({ $or: [{ status: 'A' }, { qty: { $lt: 30 } }] });

// AND condition
db.inventory.find({ $and: [{ status: 'A' }, { qty: { $lte: 50 } }] });

// IN condition
db.inventory.find({ status: { $in: ['A', 'D'] } });

// ===========================================
// QUERYING EMBEDDED DOCUMENTS
// ===========================================

// Query nested field
db.inventory.find({ 'size.uom': 'cm', 'size.h': { $lt: 15 } });

// Query exact match
db.inventory.find({
   size: {
     h: NumberInt(14),
     w: NumberInt(21),
     uom: "cm"
   }
});

// ===========================================
// QUERYING ARRAYS
// ===========================================

// Array contains element
db.inventory.find({ tags: 'school' });

// Array contains all elements
db.inventory.find({ tags: { $all: ['school'] } });

// Array element match
db.inventory.find({ dim_cm: { $elemMatch: { $gt: 15, $lt: 20 } } });

// Array index
db.inventory.find({ 'dim_cm.1': { $gt: 20 } });

// Array size
db.inventory.find({ tags: { $size: 2 } });

// Query array of embedded documents
db.inventory.find({ instock: { warehouse: 'A', qty: 5 } });

// Query nested array field
db.inventory.find({ 'instock.qty': { $gte: 20 } });

// Query first element of array
db.inventory.find({ 'instock.0.qty': { $lte: 20 } });

// Array element match with multiple conditions
db.inventory.find({
   instock: { $elemMatch: { qty: 5, warehouse: 'A' } }
});

// ===========================================
// PROJECTION
// ===========================================

// Include specific fields
db.inventory.find({}, { item: 1, qty: 1 });

// Exclude specific fields
db.inventory.find({}, { status: 0, size: 0 });

// ===========================================
// SORTING AND LIMITING
// ===========================================

// Sort ascending
db.inventory.find().sort({ qty: 1 });

// Sort descending
db.inventory.find().sort({ qty: -1 });

// Sort multiple fields
db.inventory.find().sort({ status: 1, qty: -1 });

// Limit results
db.inventory.find().limit(10);

// Skip results
db.inventory.find().skip(20);

// ===========================================
// AGGREGATION PIPELINE
// ===========================================

// Simple aggregation
db.orders.aggregate([
   { $match: { status: "completed" } },
   { $group: { _id: "$userId", total: { $sum: "$totalAmount" } } },
   { $sort: { total: -1 } }
]);

// Group by multiple fields
db.orders.aggregate([
   {
     $group: {
       _id: { userId: "$userId", status: "$status" },
       count: { $sum: 1 },
       total: { $sum: "$totalAmount" }
     }
   }
]);

// Lookup (join)
db.orders.aggregate([
   {
     $lookup: {
       from: "users",
       localField: "userId",
       foreignField: "_id",
       as: "user"
     }
   }
]);

// Unwind array
db.orders.aggregate([
   { $unwind: "$items" },
   { $group: { _id: "$items.productId", totalQuantity: { $sum: "$items.quantity" } } }
]);

// Project with computed fields
db.orders.aggregate([
   {
     $project: {
       orderNumber: 1,
       totalAmount: 1,
       year: { $year: "$createdAt" },
       month: { $month: "$createdAt" }
     }
   }
]);

// ===========================================
// TEXT SEARCH
// ===========================================

// Text search
db.products.find({ $text: { $search: "laptop wireless" } });

// Text search with score
db.products.find(
   { $text: { $search: "laptop wireless" } },
   { score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } });

// ===========================================
// GEOSPATIAL QUERIES
// ===========================================

// Near query
db.locations.find({
   location: {
     $near: {
       $geometry: {
         type: "Point",
         coordinates: [-73.965355, 40.782865]
       },
       $maxDistance: 1000
     }
   }
});

// GeoWithin query
db.locations.find({
   location: {
     $geoWithin: {
       $geometry: {
         type: "Polygon",
         coordinates: [[...]]
       }
     }
   }
});

// ===========================================
// INDEX OPERATIONS
// ===========================================

// Create index
db.users.createIndex({ email: 1 });

// Create unique index
db.users.createIndex({ email: 1 }, { unique: true });

// Create compound index
db.orders.createIndex({ userId: 1, createdAt: -1 });

// Create text index
db.products.createIndex({ name: "text", description: "text" });

// Create geospatial index
db.locations.createIndex({ location: "2dsphere" });

// Create TTL index
db.sessions.createIndex({ createdAt: 1 }, { expireAfterSeconds: 3600 });

// List indexes
db.collection.getIndexes();

// Drop index
db.collection.dropIndex("index_name");

// ===========================================
// EXPLAIN AND PERFORMANCE
// ===========================================

// Explain query
db.orders.find({ userId: ObjectId("...") }).explain("executionStats");

// Explain aggregation
db.orders.aggregate([...]).explain("executionStats");

// Check index usage
db.orders.aggregate([{ $indexStats: {} }]);

