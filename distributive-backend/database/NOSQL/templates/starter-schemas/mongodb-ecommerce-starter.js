// MongoDB E-Commerce Starter Schema
// Minimal but complete schema for launching an e-commerce platform
// Includes essential collections for products, orders, users, and carts

const { MongoClient, ObjectId } = require('mongodb');

// ===========================================
// DATABASE SETUP
// ===========================================

async function setupDatabase(uri) {
    const client = new MongoClient(uri);
    await client.connect();
    const db = client.db('ecommerce');
    
    // Create indexes
    await createIndexes(db);
    
    return { client, db };
}

async function createIndexes(db) {
    // Users collection indexes
    await db.collection('users').createIndexes([
        { key: { email: 1 }, unique: true },
        { key: { createdAt: -1 } }
    ]);

    // Products collection indexes
    await db.collection('products').createIndexes([
        { key: { sku: 1 }, unique: true },
        { key: { slug: 1 }, unique: true },
        { key: { categoryId: 1, status: 1 } },
        { key: { name: 'text', description: 'text' } }
    ]);

    // Orders collection indexes
    await db.collection('orders').createIndexes([
        { key: { orderNumber: 1 }, unique: true },
        { key: { userId: 1, createdAt: -1 } },
        { key: { status: 1, createdAt: -1 } }
    ]);

    // Carts collection indexes
    await db.collection('carts').createIndexes([
        { key: { userId: 1 }, unique: true, sparse: true },
        { key: { sessionId: 1 }, unique: true, sparse: true },
        { key: { updatedAt: 1 }, expireAfterSeconds: 2592000 } // 30 days TTL
    ]);
}

// ===========================================
// USERS COLLECTION
// ===========================================

async function createUser(db, userData) {
    const user = {
        email: userData.email,
        passwordHash: userData.passwordHash,
        firstName: userData.firstName,
        lastName: userData.lastName,
        phone: userData.phone,
        isActive: true,
        emailVerified: false,
        addresses: [],
        createdAt: new Date(),
        updatedAt: new Date()
    };

    const result = await db.collection('users').insertOne(user);
    return result.insertedId;
}

async function addUserAddress(db, userId, addressData) {
    const address = {
        addressId: new ObjectId(),
        addressType: addressData.addressType || 'shipping',
        isDefault: addressData.isDefault || false,
        firstName: addressData.firstName,
        lastName: addressData.lastName,
        streetAddress: addressData.streetAddress,
        city: addressData.city,
        state: addressData.state,
        postalCode: addressData.postalCode,
        country: addressData.country || 'USA',
        phone: addressData.phone,
        createdAt: new Date()
    };

    await db.collection('users').updateOne(
        { _id: new ObjectId(userId) },
        { 
            $push: { addresses: address },
            $set: { updatedAt: new Date() }
        }
    );

    return address.addressId;
}

// ===========================================
// PRODUCTS COLLECTION
// ===========================================

async function createProduct(db, productData) {
    const product = {
        sku: productData.sku,
        name: productData.name,
        slug: productData.slug,
        description: productData.description,
        shortDescription: productData.shortDescription,
        categoryId: productData.categoryId ? new ObjectId(productData.categoryId) : null,
        brand: productData.brand,
        basePrice: productData.basePrice,
        salePrice: productData.salePrice,
        stockQuantity: productData.stockQuantity || 0,
        stockStatus: 'in_stock',
        status: 'active',
        images: productData.images || [],
        variations: [],
        createdAt: new Date(),
        updatedAt: new Date()
    };

    const result = await db.collection('products').insertOne(product);
    return result.insertedId;
}

async function addProductVariation(db, productId, variationData) {
    const variation = {
        variationId: new ObjectId(),
        attributes: variationData.attributes, // {color: 'red', size: 'large'}
        sku: variationData.sku,
        priceModifier: variationData.priceModifier || 0,
        stockQuantity: variationData.stockQuantity || 0,
        isAvailable: true,
        createdAt: new Date()
    };

    await db.collection('products').updateOne(
        { _id: new ObjectId(productId) },
        { 
            $push: { variations: variation },
            $set: { updatedAt: new Date() }
        }
    );

    return variation.variationId;
}

// ===========================================
// CARTS COLLECTION
// ===========================================

async function createOrUpdateCart(db, userId, sessionId, items) {
    const cart = {
        userId: userId ? new ObjectId(userId) : null,
        sessionId: sessionId,
        items: items.map(item => ({
            productId: new ObjectId(item.productId),
            variationId: item.variationId ? new ObjectId(item.variationId) : null,
            quantity: item.quantity,
            unitPrice: item.unitPrice
        })),
        updatedAt: new Date(),
        createdAt: new Date()
    };

    const filter = userId 
        ? { userId: new ObjectId(userId) }
        : { sessionId: sessionId };

    await db.collection('carts').replaceOne(filter, cart, { upsert: true });
    return cart;
}

async function getCart(db, userId, sessionId) {
    const filter = userId 
        ? { userId: new ObjectId(userId) }
        : { sessionId: sessionId };

    return await db.collection('carts').findOne(filter);
}

// ===========================================
// ORDERS COLLECTION
// ===========================================

async function createOrder(db, orderData) {
    const order = {
        orderNumber: `ORD-${Date.now().toString(36).toUpperCase()}`,
        userId: new ObjectId(orderData.userId),
        status: 'pending',
        paymentStatus: 'pending',
        subtotal: orderData.subtotal,
        taxAmount: orderData.taxAmount,
        shippingAmount: orderData.shippingAmount,
        discountAmount: orderData.discountAmount || 0,
        totalAmount: orderData.subtotal + orderData.taxAmount + orderData.shippingAmount - (orderData.discountAmount || 0),
        shippingAddress: orderData.shippingAddress,
        billingAddress: orderData.billingAddress,
        items: orderData.items.map(item => ({
            productId: new ObjectId(item.productId),
            variationId: item.variationId ? new ObjectId(item.variationId) : null,
            productName: item.productName,
            sku: item.sku,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            totalPrice: item.quantity * item.unitPrice
        })),
        createdAt: new Date(),
        updatedAt: new Date()
    };

    const result = await db.collection('orders').insertOne(order);
    return result.insertedId;
}

async function getUserOrders(db, userId, limit = 20) {
    return await db.collection('orders')
        .find({ userId: new ObjectId(userId) })
        .sort({ createdAt: -1 })
        .limit(limit)
        .toArray();
}

// ===========================================
// EXPORTS
// ===========================================

module.exports = {
    setupDatabase,
    createIndexes,
    createUser,
    addUserAddress,
    createProduct,
    addProductVariation,
    createOrUpdateCart,
    getCart,
    createOrder,
    getUserOrders
};

