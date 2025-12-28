// E-Commerce Platform Schema Design (DynamoDB)
// Comprehensive DynamoDB schema for online shopping, marketplace, and quick commerce
// Optimized for DynamoDB with single-table design patterns and GSI strategies

const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB();
const docClient = new AWS.DynamoDB.DocumentClient();

// ============================================
// TABLE CREATION
// ============================================

// Main E-Commerce Table (Single-table design pattern)
async function createEcommerceTable() {
    const params = {
        TableName: 'Ecommerce',
        KeySchema: [
            { AttributeName: 'PK', KeyType: 'HASH' },      // Partition key
            { AttributeName: 'SK', KeyType: 'RANGE' }      // Sort key
        ],
        AttributeDefinitions: [
            { AttributeName: 'PK', AttributeType: 'S' },
            { AttributeName: 'SK', AttributeType: 'S' },
            { AttributeName: 'GSI1PK', AttributeType: 'S' },
            { AttributeName: 'GSI1SK', AttributeType: 'S' },
            { AttributeName: 'GSI2PK', AttributeType: 'S' },
            { AttributeName: 'GSI2SK', AttributeType: 'S' },
            { AttributeName: 'GSI3PK', AttributeType: 'S' },
            { AttributeName: 'GSI3SK', AttributeType: 'S' }
        ],
        GlobalSecondaryIndexes: [
            {
                IndexName: 'GSI1',
                KeySchema: [
                    { AttributeName: 'GSI1PK', KeyType: 'HASH' },
                    { AttributeName: 'GSI1SK', KeyType: 'RANGE' }
                ],
                Projection: { ProjectionType: 'ALL' },
                BillingMode: 'PAY_PER_REQUEST'
            },
            {
                IndexName: 'GSI2',
                KeySchema: [
                    { AttributeName: 'GSI2PK', KeyType: 'HASH' },
                    { AttributeName: 'GSI2SK', KeyType: 'RANGE' }
                ],
                Projection: { ProjectionType: 'ALL' },
                BillingMode: 'PAY_PER_REQUEST'
            },
            {
                IndexName: 'GSI3',
                KeySchema: [
                    { AttributeName: 'GSI3PK', KeyType: 'HASH' },
                    { AttributeName: 'GSI3SK', KeyType: 'RANGE' }
                ],
                Projection: { ProjectionType: 'ALL' },
                BillingMode: 'PAY_PER_REQUEST'
            }
        ],
        BillingMode: 'PAY_PER_REQUEST',
        StreamSpecification: {
            StreamEnabled: true,
            StreamViewType: 'NEW_AND_OLD_IMAGES'
        }
    };

    await dynamodb.createTable(params).promise();
    console.log('Ecommerce table created successfully');
}

// ============================================
// ACCESS PATTERNS AND ENTITY DESIGN
// ============================================

// Access Pattern 1: Get user by userId
// PK: USER#<userId>, SK: PROFILE

// Access Pattern 2: Get user by email
// GSI1PK: EMAIL#<email>, GSI1SK: USER#<userId>

// Access Pattern 3: Get all orders for a user
// PK: USER#<userId>, SK: ORDER#<orderId>

// Access Pattern 4: Get order by orderId
// PK: ORDER#<orderId>, SK: METADATA

// Access Pattern 5: Get products by category
// PK: CATEGORY#<categoryId>, SK: PRODUCT#<productId>

// Access Pattern 6: Get product by productId
// PK: PRODUCT#<productId>, SK: METADATA

// Access Pattern 7: Get cart items for user
// PK: USER#<userId>, SK: CART#<productId>

// ============================================
// ENTITY CREATION FUNCTIONS
// ============================================

// Create User Entity
async function createUser(userId, email, firstName, lastName) {
    const timestamp = new Date().toISOString();
    
    const user = {
        PK: `USER#${userId}`,
        SK: 'PROFILE',
        GSI1PK: `EMAIL#${email}`,
        GSI1SK: `USER#${userId}`,
        EntityType: 'USER',
        UserId: userId,
        Email: email,
        FirstName: firstName,
        LastName: lastName,
        IsActive: true,
        EmailVerified: false,
        CreatedAt: timestamp,
        UpdatedAt: timestamp
    };

    await docClient.put({
        TableName: 'Ecommerce',
        Item: user
    }).promise();

    return user;
}

// Create Product Entity
async function createProduct(productId, name, categoryId, price, sku) {
    const timestamp = new Date().toISOString();
    
    const product = {
        PK: `PRODUCT#${productId}`,
        SK: 'METADATA',
        GSI1PK: `CATEGORY#${categoryId}`,
        GSI1SK: `PRODUCT#${productId}`,
        GSI2PK: 'PRODUCTS',
        GSI2SK: `PRODUCT#${productId}`,
        EntityType: 'PRODUCT',
        ProductId: productId,
        Name: name,
        CategoryId: categoryId,
        SKU: sku,
        BasePrice: price,
        StockQuantity: 0,
        StockStatus: 'in_stock',
        Status: 'active',
        CreatedAt: timestamp,
        UpdatedAt: timestamp
    };

    await docClient.put({
        TableName: 'Ecommerce',
        Item: product
    }).promise();

    return product;
}

// Create Order Entity
async function createOrder(orderId, userId, items, totalAmount) {
    const timestamp = new Date().toISOString();
    const orderDate = new Date().toISOString().split('T')[0];
    
    // Main order entity
    const order = {
        PK: `ORDER#${orderId}`,
        SK: 'METADATA',
        GSI1PK: `USER#${userId}`,
        GSI1SK: `ORDER#${orderId}`,
        GSI2PK: `ORDERDATE#${orderDate}`,
        GSI2SK: `ORDER#${orderId}`,
        EntityType: 'ORDER',
        OrderId: orderId,
        UserId: userId,
        OrderNumber: `ORD-${orderId.substring(0, 8).toUpperCase()}`,
        Status: 'pending',
        PaymentStatus: 'pending',
        TotalAmount: totalAmount,
        Items: items,
        CreatedAt: timestamp,
        UpdatedAt: timestamp
    };

    await docClient.put({
        TableName: 'Ecommerce',
        Item: order
    }).promise();

    // Create order items as separate entities for query flexibility
    for (const item of items) {
        await docClient.put({
            TableName: 'Ecommerce',
            Item: {
                PK: `ORDER#${orderId}`,
                SK: `ITEM#${item.ProductId}`,
                GSI1PK: `PRODUCT#${item.ProductId}`,
                GSI1SK: `ORDER#${orderId}`,
                EntityType: 'ORDER_ITEM',
                OrderId: orderId,
                ProductId: item.ProductId,
                ProductName: item.ProductName,
                Quantity: item.Quantity,
                UnitPrice: item.UnitPrice,
                TotalPrice: item.TotalPrice,
                CreatedAt: timestamp
            }
        }).promise();
    }

    return order;
}

// Create Cart Item
async function addToCart(userId, productId, quantity, unitPrice) {
    const timestamp = new Date().toISOString();
    
    const cartItem = {
        PK: `USER#${userId}`,
        SK: `CART#${productId}`,
        GSI1PK: `PRODUCT#${productId}`,
        GSI1SK: `CART#${userId}`,
        EntityType: 'CART_ITEM',
        UserId: userId,
        ProductId: productId,
        Quantity: quantity,
        UnitPrice: unitPrice,
        CreatedAt: timestamp,
        UpdatedAt: timestamp
    };

    await docClient.put({
        TableName: 'Ecommerce',
        Item: cartItem
    }).promise();

    return cartItem;
}

// ============================================
// QUERY FUNCTIONS
// ============================================

// Get user by userId
async function getUser(userId) {
    const result = await docClient.get({
        TableName: 'Ecommerce',
        Key: {
            PK: `USER#${userId}`,
            SK: 'PROFILE'
        }
    }).promise();

    return result.Item;
}

// Get user by email
async function getUserByEmail(email) {
    const result = await docClient.query({
        TableName: 'Ecommerce',
        IndexName: 'GSI1',
        KeyConditionExpression: 'GSI1PK = :email',
        ExpressionAttributeValues: {
            ':email': `EMAIL#${email}`
        }
    }).promise();

    return result.Items[0];
}

// Get all orders for a user
async function getUserOrders(userId) {
    const result = await docClient.query({
        TableName: 'Ecommerce',
        IndexName: 'GSI1',
        KeyConditionExpression: 'GSI1PK = :userId AND begins_with(GSI1SK, :orderPrefix)',
        ExpressionAttributeValues: {
            ':userId': `USER#${userId}`,
            ':orderPrefix': 'ORDER#'
        }
    }).promise();

    return result.Items;
}

// Get order with items
async function getOrder(orderId) {
    const result = await docClient.query({
        TableName: 'Ecommerce',
        KeyConditionExpression: 'PK = :orderId',
        ExpressionAttributeValues: {
            ':orderId': `ORDER#${orderId}`
        }
    }).promise();

    const order = result.Items.find(item => item.SK === 'METADATA');
    const items = result.Items.filter(item => item.SK.startsWith('ITEM#'));

    return {
        ...order,
        Items: items
    };
}

// Get products by category
async function getProductsByCategory(categoryId, limit = 20) {
    const result = await docClient.query({
        TableName: 'Ecommerce',
        IndexName: 'GSI1',
        KeyConditionExpression: 'GSI1PK = :categoryId AND begins_with(GSI1SK, :productPrefix)',
        ExpressionAttributeValues: {
            ':categoryId': `CATEGORY#${categoryId}`,
            ':productPrefix': 'PRODUCT#'
        },
        Limit: limit
    }).promise();

    return result.Items;
}

// Get cart items for user
async function getCartItems(userId) {
    const result = await docClient.query({
        TableName: 'Ecommerce',
        KeyConditionExpression: 'PK = :userId AND begins_with(SK, :cartPrefix)',
        ExpressionAttributeValues: {
            ':userId': `USER#${userId}`,
            ':cartPrefix': 'CART#'
        }
    }).promise();

    return result.Items;
}

// ============================================
// UPDATE FUNCTIONS
// ============================================

// Update order status
async function updateOrderStatus(orderId, status) {
    const timestamp = new Date().toISOString();
    
    await docClient.update({
        TableName: 'Ecommerce',
        Key: {
            PK: `ORDER#${orderId}`,
            SK: 'METADATA'
        },
        UpdateExpression: 'SET #status = :status, UpdatedAt = :updatedAt',
        ExpressionAttributeNames: {
            '#status': 'Status'
        },
        ExpressionAttributeValues: {
            ':status': status,
            ':updatedAt': timestamp
        }
    }).promise();
}

// Update product stock
async function updateProductStock(productId, quantityChange) {
    const timestamp = new Date().toISOString();
    
    await docClient.update({
        TableName: 'Ecommerce',
        Key: {
            PK: `PRODUCT#${productId}`,
            SK: 'METADATA'
        },
        UpdateExpression: 'ADD StockQuantity :quantityChange SET UpdatedAt = :updatedAt',
        ExpressionAttributeValues: {
            ':quantityChange': quantityChange,
            ':updatedAt': timestamp
        }
    }).promise();
}

// ============================================
// BATCH OPERATIONS
// ============================================

// Batch write cart items
async function batchWriteCartItems(userId, items) {
    const putRequests = items.map(item => ({
        PutRequest: {
            Item: {
                PK: `USER#${userId}`,
                SK: `CART#${item.ProductId}`,
                GSI1PK: `PRODUCT#${item.ProductId}`,
                GSI1SK: `CART#${userId}`,
                EntityType: 'CART_ITEM',
                UserId: userId,
                ProductId: item.ProductId,
                Quantity: item.Quantity,
                UnitPrice: item.UnitPrice,
                CreatedAt: new Date().toISOString(),
                UpdatedAt: new Date().toISOString()
            }
        }
    }));

    // DynamoDB batch write supports up to 25 items
    const chunks = [];
    for (let i = 0; i < putRequests.length; i += 25) {
        chunks.push(putRequests.slice(i, i + 25));
    }

    for (const chunk of chunks) {
        await docClient.batchWrite({
            RequestItems: {
                'Ecommerce': chunk
            }
        }).promise();
    }
}

// ============================================
// TRANSACTION OPERATIONS
// ============================================

// Create order from cart (transaction)
async function createOrderFromCart(userId, orderId, shippingAddress) {
    const timestamp = new Date().toISOString();
    
    // Get cart items
    const cartItems = await getCartItems(userId);
    
    if (cartItems.length === 0) {
        throw new Error('Cart is empty');
    }

    // Calculate total
    const totalAmount = cartItems.reduce((sum, item) => 
        sum + (item.Quantity * item.UnitPrice), 0
    );

    // Prepare transaction items
    const transactionItems = [];

    // 1. Create order
    transactionItems.push({
        Put: {
            TableName: 'Ecommerce',
            Item: {
                PK: `ORDER#${orderId}`,
                SK: 'METADATA',
                GSI1PK: `USER#${userId}`,
                GSI1SK: `ORDER#${orderId}`,
                GSI2PK: `ORDERDATE#${new Date().toISOString().split('T')[0]}`,
                GSI2SK: `ORDER#${orderId}`,
                EntityType: 'ORDER',
                OrderId: orderId,
                UserId: userId,
                OrderNumber: `ORD-${orderId.substring(0, 8).toUpperCase()}`,
                Status: 'pending',
                PaymentStatus: 'pending',
                TotalAmount: totalAmount,
                ShippingAddress: shippingAddress,
                CreatedAt: timestamp,
                UpdatedAt: timestamp
            }
        }
    });

    // 2. Create order items
    cartItems.forEach(item => {
        transactionItems.push({
            Put: {
                TableName: 'Ecommerce',
                Item: {
                    PK: `ORDER#${orderId}`,
                    SK: `ITEM#${item.ProductId}`,
                    GSI1PK: `PRODUCT#${item.ProductId}`,
                    GSI1SK: `ORDER#${orderId}`,
                    EntityType: 'ORDER_ITEM',
                    OrderId: orderId,
                    ProductId: item.ProductId,
                    ProductName: item.ProductName || 'Product',
                    Quantity: item.Quantity,
                    UnitPrice: item.UnitPrice,
                    TotalPrice: item.Quantity * item.UnitPrice,
                    CreatedAt: timestamp
                }
            }
        });
    });

    // 3. Delete cart items
    cartItems.forEach(item => {
        transactionItems.push({
            Delete: {
                TableName: 'Ecommerce',
                Key: {
                    PK: `USER#${userId}`,
                    SK: `CART#${item.ProductId}`
                }
            }
        });
    });

    // Execute transaction
    await docClient.transactWrite({
        TransactItems: transactionItems
    }).promise();

    return { orderId, totalAmount };
}

module.exports = {
    createEcommerceTable,
    createUser,
    createProduct,
    createOrder,
    addToCart,
    getUser,
    getUserByEmail,
    getUserOrders,
    getOrder,
    getProductsByCategory,
    getCartItems,
    updateOrderStatus,
    updateProductStock,
    batchWriteCartItems,
    createOrderFromCart
};

