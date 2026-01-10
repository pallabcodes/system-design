// E-Commerce Platform Schema Design (MongoDB)
// Comprehensive MongoDB schema for online shopping, marketplace, and quick commerce
// Uses embedded documents and references appropriately for optimal performance

const { MongoClient, ObjectId } = require('mongodb');

// ============================================
// DATABASE AND COLLECTION SETUP
// ============================================

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
        { key: { 'addresses.geolocation': '2dsphere' } },
        { key: { createdAt: -1 } }
    ]);

    // Products collection indexes
    await db.collection('products').createIndexes([
        { key: { sku: 1 }, unique: true },
        { key: { slug: 1 }, unique: true },
        { key: { categoryId: 1, status: 1, basePrice: 1 } },
        { key: { 'location': '2dsphere' } },
        { key: { name: 'text', description: 'text', searchKeywords: 'text' } }
    ]);

    // Orders collection indexes
    await db.collection('orders').createIndexes([
        { key: { orderNumber: 1 }, unique: true },
        { key: { userId: 1, createdAt: -1 } },
        { key: { status: 1, createdAt: -1 } },
        { key: { 'shippingAddress.geolocation': '2dsphere' } }
    ]);

    // Cart collection indexes
    await db.collection('carts').createIndexes([
        { key: { userId: 1 }, unique: true },
        { key: { sessionId: 1 }, sparse: true },
        { key: { updatedAt: 1 }, expireAfterSeconds: 2592000 } // 30 days TTL
    ]);
}

// ============================================
// USER SCHEMA AND OPERATIONS
// ============================================

async function createUser(db, userData) {
    const user = {
        email: userData.email,
        passwordHash: userData.passwordHash,
        firstName: userData.firstName,
        lastName: userData.lastName,
        phone: userData.phone,
        dateOfBirth: userData.dateOfBirth,
        gender: userData.gender,
        emailVerified: false,
        phoneVerified: false,
        isActive: true,
        userType: 'customer', // 'customer', 'seller', 'admin'
        preferredLanguage: 'en',
        marketingEmail: false,
        marketingSMS: false,
        marketingPush: false,
        lastLoginAt: null,
        loginCount: 0,
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
        label: addressData.label,
        firstName: addressData.firstName,
        lastName: addressData.lastName,
        company: addressData.company,
        streetAddress: addressData.streetAddress,
        apartment: addressData.apartment,
        city: addressData.city,
        state: addressData.state,
        postalCode: addressData.postalCode,
        country: addressData.country || 'USA',
        latitude: addressData.latitude,
        longitude: addressData.longitude,
        geolocation: addressData.latitude && addressData.longitude ? {
            type: 'Point',
            coordinates: [addressData.longitude, addressData.latitude]
        } : null,
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

async function getUserByEmail(db, email) {
    return await db.collection('users').findOne({ email });
}

// ============================================
// PRODUCT SCHEMA AND OPERATIONS
// ============================================

async function createProduct(db, productData) {
    const product = {
        sku: productData.sku,
        name: productData.name,
        slug: productData.slug,
        description: productData.description,
        shortDescription: productData.shortDescription,
        brandId: productData.brandId ? new ObjectId(productData.brandId) : null,
        categoryId: productData.categoryId ? new ObjectId(productData.categoryId) : null,
        basePrice: productData.basePrice,
        salePrice: productData.salePrice,
        costPrice: productData.costPrice,
        stockQuantity: productData.stockQuantity || 0,
        stockStatus: 'in_stock',
        lowStockThreshold: 5,
        trackInventory: true,
        status: 'draft', // 'draft', 'active', 'inactive', 'discontinued'
        visibility: 'public',
        weight: productData.weight,
        dimensions: productData.dimensions, // {length, width, height, unit}
        requiresShipping: true,
        shippingClass: 'standard',
        taxClass: 'standard',
        taxRate: productData.taxRate,
        mainImageUrl: productData.mainImageUrl,
        galleryImages: productData.galleryImages || [],
        metaTitle: productData.metaTitle,
        metaDescription: productData.metaDescription,
        searchKeywords: productData.searchKeywords || [],
        totalSales: 0,
        totalReviews: 0,
        averageRating: 0.00,
        sellerId: productData.sellerId ? new ObjectId(productData.sellerId) : null,
        variations: [],
        attributes: [],
        createdAt: new Date(),
        updatedAt: new Date()
    };

    const result = await db.collection('products').insertOne(product);
    return result.insertedId;
}

async function addProductVariation(db, productId, variationData) {
    const variation = {
        variationId: new ObjectId(),
        variationName: variationData.variationName,
        attributes: variationData.attributes, // {color: 'red', size: 'large'}
        sku: variationData.sku,
        priceModifier: variationData.priceModifier || 0.00,
        stockQuantity: variationData.stockQuantity || 0,
        isAvailable: true,
        imageUrl: variationData.imageUrl,
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

async function searchProducts(db, searchTerm, filters = {}) {
    const query = {
        $text: { $search: searchTerm },
        status: 'active',
        visibility: 'public'
    };

    if (filters.categoryId) {
        query.categoryId = new ObjectId(filters.categoryId);
    }

    if (filters.minPrice || filters.maxPrice) {
        query.basePrice = {};
        if (filters.minPrice) query.basePrice.$gte = filters.minPrice;
        if (filters.maxPrice) query.basePrice.$lte = filters.maxPrice;
    }

    return await db.collection('products')
        .find(query)
        .sort({ score: { $meta: 'textScore' } })
        .limit(filters.limit || 50)
        .toArray();
}

// ============================================
// CART SCHEMA AND OPERATIONS
// ============================================

async function createOrUpdateCart(db, userId, sessionId, items) {
    const cart = {
        userId: userId ? new ObjectId(userId) : null,
        sessionId: sessionId,
        items: items.map(item => ({
            productId: new ObjectId(item.productId),
            variationId: item.variationId ? new ObjectId(item.variationId) : null,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            customizations: item.customizations || {}
        })),
        updatedAt: new Date(),
        createdAt: new Date()
    };

    const filter = userId 
        ? { userId: new ObjectId(userId) }
        : { sessionId: sessionId };

    await db.collection('carts').replaceOne(
        filter,
        cart,
        { upsert: true }
    );

    return cart;
}

async function getCart(db, userId, sessionId) {
    const filter = userId 
        ? { userId: new ObjectId(userId) }
        : { sessionId: sessionId };

    return await db.collection('carts').findOne(filter);
}

// ============================================
// ORDER SCHEMA AND OPERATIONS
// ============================================

async function createOrder(db, orderData) {
    const order = {
        orderNumber: `ORD-${Date.now().toString(36).toUpperCase()}`,
        userId: new ObjectId(orderData.userId),
        status: 'pending',
        paymentStatus: 'pending',
        fulfillmentStatus: 'unfulfilled',
        subtotal: orderData.subtotal,
        taxAmount: orderData.taxAmount,
        shippingAmount: orderData.shippingAmount,
        discountAmount: orderData.discountAmount || 0,
        totalAmount: orderData.subtotal + orderData.taxAmount + orderData.shippingAmount - (orderData.discountAmount || 0),
        billingAddress: orderData.billingAddress,
        shippingAddress: orderData.shippingAddress,
        items: orderData.items.map(item => ({
            productId: new ObjectId(item.productId),
            variationId: item.variationId ? new ObjectId(item.variationId) : null,
            productName: item.productName,
            sku: item.sku,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            totalPrice: item.quantity * item.unitPrice,
            fulfilledQuantity: 0,
            fulfillmentStatus: 'pending'
        })),
        paymentMethodId: orderData.paymentMethodId ? new ObjectId(orderData.paymentMethodId) : null,
        paymentProvider: orderData.paymentProvider,
        paymentProviderTransactionId: orderData.paymentProviderTransactionId,
        shippingMethodId: orderData.shippingMethodId,
        trackingNumber: orderData.trackingNumber,
        carrier: orderData.carrier,
        customerNotes: orderData.customerNotes,
        internalNotes: orderData.internalNotes,
        createdAt: new Date(),
        updatedAt: new Date(),
        shippedAt: null,
        deliveredAt: null
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

async function updateOrderStatus(db, orderId, status, paymentStatus = null) {
    const update = {
        $set: {
            status: status,
            updatedAt: new Date()
        }
    };

    if (paymentStatus) {
        update.$set.paymentStatus = paymentStatus;
    }

    await db.collection('orders').updateOne(
        { _id: new ObjectId(orderId) },
        update
    );
}

// ============================================
// REVIEW SCHEMA AND OPERATIONS
// ============================================

async function createReview(db, reviewData) {
    const review = {
        productId: new ObjectId(reviewData.productId),
        userId: new ObjectId(reviewData.userId),
        orderId: reviewData.orderId ? new ObjectId(reviewData.orderId) : null,
        rating: reviewData.rating,
        title: reviewData.title,
        reviewText: reviewData.reviewText,
        pros: reviewData.pros,
        cons: reviewData.cons,
        images: reviewData.images || [],
        videos: reviewData.videos || [],
        status: 'pending',
        isVerifiedPurchase: !!reviewData.orderId,
        helpfulVotes: 0,
        totalVotes: 0,
        createdAt: new Date(),
        updatedAt: new Date(),
        publishedAt: null
    };

    const result = await db.collection('reviews').insertOne(review);

    // Update product review statistics
    await updateProductReviewStats(db, reviewData.productId);

    return result.insertedId;
}

async function updateProductReviewStats(db, productId) {
    const stats = await db.collection('reviews').aggregate([
        {
            $match: {
                productId: new ObjectId(productId),
                status: 'approved'
            }
        },
        {
            $group: {
                _id: null,
                totalReviews: { $sum: 1 },
                averageRating: { $avg: '$rating' }
            }
        }
    ]).toArray();

    if (stats.length > 0) {
        await db.collection('products').updateOne(
            { _id: new ObjectId(productId) },
            {
                $set: {
                    totalReviews: stats[0].totalReviews,
                    averageRating: Math.round(stats[0].averageRating * 100) / 100,
                    updatedAt: new Date()
                }
            }
        );
    }
}

// ============================================
// ANALYTICS OPERATIONS
// ============================================

async function getProductAnalytics(db, productId, startDate, endDate) {
    return await db.collection('product_analytics').aggregate([
        {
            $match: {
                productId: new ObjectId(productId),
                date: {
                    $gte: new Date(startDate),
                    $lte: new Date(endDate)
                }
            }
        },
        {
            $group: {
                _id: null,
                totalPageViews: { $sum: '$pageViews' },
                totalUniqueVisitors: { $sum: '$uniqueVisitors' },
                totalAddToCart: { $sum: '$addToCartCount' },
                totalPurchases: { $sum: '$purchaseCount' },
                totalRevenue: { $sum: '$revenue' }
            }
        }
    ]).toArray();
}

module.exports = {
    setupDatabase,
    createIndexes,
    createUser,
    addUserAddress,
    getUserByEmail,
    createProduct,
    addProductVariation,
    searchProducts,
    createOrUpdateCart,
    getCart,
    createOrder,
    getUserOrders,
    updateOrderStatus,
    createReview,
    updateProductReviewStats,
    getProductAnalytics
};

