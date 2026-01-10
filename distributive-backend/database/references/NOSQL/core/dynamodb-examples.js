// DynamoDB Examples and Patterns
// Comprehensive AWS DynamoDB implementations for serverless applications and high-scale workloads

const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB();
const docClient = new AWS.DynamoDB.DocumentClient();

// ===========================================
// TABLE CREATION AND MANAGEMENT
// ===========================================

// Create DynamoDB table
async function createUsersTable() {
    const params = {
        TableName: 'Users',
        KeySchema: [
            { AttributeName: 'userId', KeyType: 'HASH' }  // Partition key
        ],
        AttributeDefinitions: [
            { AttributeName: 'userId', AttributeType: 'S' },
            { AttributeName: 'email', AttributeType: 'S' },
            { AttributeName: 'createdAt', AttributeType: 'S' }
        ],
        GlobalSecondaryIndexes: [
            {
                IndexName: 'EmailIndex',
                KeySchema: [
                    { AttributeName: 'email', KeyType: 'HASH' }
                ],
                Projection: { ProjectionType: 'ALL' },
                BillingMode: 'PAY_PER_REQUEST'
            },
            {
                IndexName: 'CreatedAtIndex',
                KeySchema: [
                    { AttributeName: 'createdAt', KeyType: 'HASH' },
                    { AttributeName: 'userId', KeyType: 'RANGE' }
                ],
                Projection: { ProjectionType: 'KEYS_ONLY' },
                BillingMode: 'PAY_PER_REQUEST'
            }
        ],
        BillingMode: 'PAY_PER_REQUEST',
        StreamSpecification: {
            StreamEnabled: true,
            StreamViewType: 'NEW_AND_OLD_IMAGES'
        }
    };

    try {
        await dynamodb.createTable(params).promise();
        console.log('Users table created successfully');
    } catch (error) {
        console.error('Error creating table:', error);
    }
}

// Create table with composite primary key
async function createOrdersTable() {
    const params = {
        TableName: 'Orders',
        KeySchema: [
            { AttributeName: 'customerId', KeyType: 'HASH' },   // Partition key
            { AttributeName: 'orderId', KeyType: 'RANGE' }      // Sort key
        ],
        AttributeDefinitions: [
            { AttributeName: 'customerId', AttributeType: 'S' },
            { AttributeName: 'orderId', AttributeType: 'S' },
            { AttributeName: 'orderDate', AttributeType: 'S' },
            { AttributeName: 'status', AttributeType: 'S' }
        ],
        LocalSecondaryIndexes: [
            {
                IndexName: 'OrderDateIndex',
                KeySchema: [
                    { AttributeName: 'customerId', KeyType: 'HASH' },
                    { AttributeName: 'orderDate', KeyType: 'RANGE' }
                ],
                Projection: { ProjectionType: 'ALL' }
            }
        ],
        GlobalSecondaryIndexes: [
            {
                IndexName: 'StatusIndex',
                KeySchema: [
                    { AttributeName: 'status', KeyType: 'HASH' },
                    { AttributeName: 'orderDate', KeyType: 'RANGE' }
                ],
                Projection: { ProjectionType: 'INCLUDE', NonKeyAttributes: ['customerId', 'totalAmount'] }
            }
        ],
        BillingMode: 'PAY_PER_REQUEST'
    };

    await dynamodb.createTable(params).promise();
}

// ===========================================
// BASIC CRUD OPERATIONS
// ===========================================

class DynamoDBService {
    constructor(tableName) {
        this.tableName = tableName;
        this.docClient = new AWS.DynamoDB.DocumentClient();
    }

    // Create/Put item
    async putItem(item) {
        const params = {
            TableName: this.tableName,
            Item: item,
            ConditionExpression: 'attribute_not_exists(pk)', // Prevent overwrites
            ReturnValues: 'ALL_OLD'
        };

        try {
            const result = await this.docClient.put(params).promise();
            return { success: true, data: result };
        } catch (error) {
            if (error.code === 'ConditionalCheckFailedException') {
                throw new Error('Item already exists');
            }
            throw error;
        }
    }

    // Get item
    async getItem(key) {
        const params = {
            TableName: this.tableName,
            Key: key
        };

        const result = await this.docClient.get(params).promise();
        return result.Item || null;
    }

    // Update item
    async updateItem(key, updates, conditionExpression = null) {
        const updateExpressions = [];
        const expressionAttributeNames = {};
        const expressionAttributeValues = {};

        Object.entries(updates).forEach(([field, value], index) => {
            const placeholder = `:val${index}`;
            updateExpressions.push(`#${field} = ${placeholder}`);
            expressionAttributeNames[`#${field}`] = field;
            expressionAttributeValues[placeholder] = value;
        });

        const params = {
            TableName: this.tableName,
            Key: key,
            UpdateExpression: `SET ${updateExpressions.join(', ')}`,
            ExpressionAttributeNames: expressionAttributeNames,
            ExpressionAttributeValues: expressionAttributeValues,
            ReturnValues: 'ALL_NEW'
        };

        if (conditionExpression) {
            params.ConditionExpression = conditionExpression;
        }

        const result = await this.docClient.update(params).promise();
        return result.Attributes;
    }

    // Delete item
    async deleteItem(key, conditionExpression = null) {
        const params = {
            TableName: this.tableName,
            Key: key,
            ReturnValues: 'ALL_OLD'
        };

        if (conditionExpression) {
            params.ConditionExpression = conditionExpression;
        }

        const result = await this.docClient.delete(params).promise();
        return result.Attributes;
    }

    // Batch operations
    async batchPutItems(items) {
        const params = {
            RequestItems: {
                [this.tableName]: items.map(item => ({
                    PutRequest: { Item: item }
                }))
            }
        };

        const result = await this.docClient.batchWrite(params).promise();
        return result.UnprocessedItems;
    }

    async batchGetItems(keys) {
        const params = {
            RequestItems: {
                [this.tableName]: {
                    Keys: keys
                }
            }
        };

        const result = await this.docClient.batchGet(params).promise();
        return result.Responses[this.tableName];
    }
}

// Usage example
const usersService = new DynamoDBService('Users');

// Create user
const newUser = {
    userId: 'user123',
    email: 'john@example.com',
    name: 'John Doe',
    createdAt: new Date().toISOString(),
    status: 'active',
    profile: {
        avatar: 'https://example.com/avatar.jpg',
        bio: 'Software developer'
    },
    preferences: {
        notifications: true,
        theme: 'dark'
    }
};

await usersService.putItem(newUser);

// Get user
const user = await usersService.getItem({ userId: 'user123' });

// Update user
await usersService.updateItem(
    { userId: 'user123' },
    {
        lastLogin: new Date().toISOString(),
        loginCount: 5
    }
);

// ===========================================
// ADVANCED QUERY PATTERNS
// ===========================================

class QueryService extends DynamoDBService {
    // Query by partition key
    async queryByPartitionKey(partitionKey, sortKeyCondition = null) {
        const params = {
            TableName: this.tableName,
            KeyConditionExpression: '#pk = :pk',
            ExpressionAttributeNames: { '#pk': Object.keys(partitionKey)[0] },
            ExpressionAttributeValues: { ':pk': Object.values(partitionKey)[0] }
        };

        if (sortKeyCondition) {
            params.KeyConditionExpression += ` AND ${sortKeyCondition.expression}`;
            Object.assign(params.ExpressionAttributeValues, sortKeyCondition.values);
            if (sortKeyCondition.names) {
                Object.assign(params.ExpressionAttributeNames, sortKeyCondition.names);
            }
        }

        const result = await this.docClient.query(params).promise();
        return result.Items;
    }

    // Query with filters
    async queryWithFilter(partitionKey, filterExpression, filterValues = {}) {
        const params = {
            TableName: this.tableName,
            KeyConditionExpression: '#pk = :pk',
            FilterExpression: filterExpression,
            ExpressionAttributeNames: { '#pk': Object.keys(partitionKey)[0] },
            ExpressionAttributeValues: {
                ':pk': Object.values(partitionKey)[0],
                ...filterValues
            }
        };

        const result = await this.docClient.query(params).promise();
        return result.Items;
    }

    // Query GSI
    async queryGSI(indexName, partitionKey, sortKeyCondition = null) {
        const params = {
            TableName: this.tableName,
            IndexName: indexName,
            KeyConditionExpression: '#pk = :pk',
            ExpressionAttributeNames: { '#pk': Object.keys(partitionKey)[0] },
            ExpressionAttributeValues: { ':pk': Object.values(partitionKey)[0] }
        };

        if (sortKeyCondition) {
            params.KeyConditionExpression += ` AND ${sortKeyCondition.expression}`;
            Object.assign(params.ExpressionAttributeValues, sortKeyCondition.values);
        }

        const result = await this.docClient.query(params).promise();
        return result.Items;
    }

    // Scan with pagination
    async scanWithPagination(pageSize = 100, lastEvaluatedKey = null) {
        const params = {
            TableName: this.tableName,
            Limit: pageSize
        };

        if (lastEvaluatedKey) {
            params.ExclusiveStartKey = lastEvaluatedKey;
        }

        const result = await this.docClient.scan(params).promise();
        return {
            items: result.Items,
            lastEvaluatedKey: result.LastEvaluatedKey,
            hasMore: !!result.LastEvaluatedKey
        };
    }
}

// Usage examples
const ordersService = new QueryService('Orders');

// Query orders for a customer
const customerOrders = await ordersService.queryByPartitionKey(
    { customerId: 'customer123' },
    {
        expression: '#orderDate >= :startDate',
        values: { ':startDate': '2024-01-01' },
        names: { '#orderDate': 'orderDate' }
    }
);

// Query orders by status using GSI
const pendingOrders = await ordersService.queryGSI(
    'StatusIndex',
    { status: 'pending' },
    {
        expression: '#orderDate >= :startDate',
        values: { ':startDate': '2024-01-01' },
        names: { '#orderDate': 'orderDate' }
    }
);

// ===========================================
// SINGLE TABLE DESIGN PATTERNS
// ===========================================

// Single table design for e-commerce
async function createEcommerceTable() {
    const params = {
        TableName: 'Ecommerce',
        KeySchema: [
            { AttributeName: 'PK', KeyType: 'HASH' },
            { AttributeName: 'SK', KeyType: 'RANGE' }
        ],
        AttributeDefinitions: [
            { AttributeName: 'PK', AttributeType: 'S' },
            { AttributeName: 'SK', AttributeType: 'S' },
            { AttributeName: 'GSI1PK', AttributeType: 'S' },
            { AttributeName: 'GSI1SK', AttributeType: 'S' },
            { AttributeName: 'GSI2PK', AttributeType: 'S' },
            { AttributeName: 'GSI2SK', AttributeType: 'S' }
        ],
        GlobalSecondaryIndexes: [
            {
                IndexName: 'GSI1',
                KeySchema: [
                    { AttributeName: 'GSI1PK', KeyType: 'HASH' },
                    { AttributeName: 'GSI1SK', KeyType: 'RANGE' }
                ],
                Projection: { ProjectionType: 'ALL' }
            },
            {
                IndexName: 'GSI2',
                KeySchema: [
                    { AttributeName: 'GSI2PK', KeyType: 'HASH' },
                    { AttributeName: 'GSI2SK', KeyType: 'RANGE' }
                ],
                Projection: { ProjectionType: 'ALL' }
            }
        ],
        BillingMode: 'PAY_PER_REQUEST'
    };

    await dynamodb.createTable(params).promise();
}

// Single table item patterns
class SingleTableService {
    constructor(tableName) {
        this.tableName = tableName;
        this.docClient = new AWS.DynamoDB.DocumentClient();
    }

    // Create user
    async createUser(userId, userData) {
        const item = {
            PK: `USER#${userId}`,
            SK: `USER#${userId}`,
            GSI1PK: `USEREMAIL#${userData.email}`,
            GSI1SK: `USEREMAIL#${userData.email}`,
            ...userData,
            entityType: 'USER'
        };

        await this.docClient.put({
            TableName: this.tableName,
            Item: item,
            ConditionExpression: 'attribute_not_exists(PK)'
        }).promise();
    }

    // Create product
    async createProduct(productId, productData) {
        const item = {
            PK: `PRODUCT#${productId}`,
            SK: `PRODUCT#${productId}`,
            GSI1PK: `PRODUCTCATEGORY#${productData.category}`,
            GSI1SK: `PRODUCT#${productId}`,
            ...productData,
            entityType: 'PRODUCT'
        };

        await this.docClient.put({
            TableName: this.tableName,
            Item: item
        }).promise();
    }

    // Create order
    async createOrder(orderId, customerId, orderData) {
        const item = {
            PK: `CUSTOMER#${customerId}`,
            SK: `ORDER#${orderId}`,
            GSI1PK: `ORDERSTATUS#${orderData.status}`,
            GSI1SK: `ORDER#${orderId}`,
            GSI2PK: `ORDERDATE#${orderData.orderDate}`,
            GSI2SK: `ORDER#${orderId}`,
            ...orderData,
            entityType: 'ORDER'
        };

        await this.docClient.put({
            TableName: this.tableName,
            Item: item
        }).promise();
    }

    // Get user by ID
    async getUser(userId) {
        const result = await this.docClient.get({
            TableName: this.tableName,
            Key: {
                PK: `USER#${userId}`,
                SK: `USER#${userId}`
            }
        }).promise();

        return result.Item;
    }

    // Get user by email
    async getUserByEmail(email) {
        const result = await this.docClient.query({
            TableName: this.tableName,
            IndexName: 'GSI1',
            KeyConditionExpression: 'GSI1PK = :email',
            ExpressionAttributeValues: {
                ':email': `USEREMAIL#${email}`
            }
        }).promise();

        return result.Items[0] || null;
    }

    // Get customer orders
    async getCustomerOrders(customerId) {
        const result = await this.docClient.query({
            TableName: this.tableName,
            KeyConditionExpression: 'PK = :customerId AND begins_with(SK, :orderPrefix)',
            ExpressionAttributeValues: {
                ':customerId': `CUSTOMER#${customerId}`,
                ':orderPrefix': 'ORDER#'
            }
        }).promise();

        return result.Items;
    }

    // Get products by category
    async getProductsByCategory(category) {
        const result = await this.docClient.query({
            TableName: this.tableName,
            IndexName: 'GSI1',
            KeyConditionExpression: 'GSI1PK = :category AND begins_with(GSI1SK, :productPrefix)',
            ExpressionAttributeValues: {
                ':category': `PRODUCTCATEGORY#${category}`,
                ':productPrefix': 'PRODUCT#'
            }
        }).promise();

        return result.Items;
    }

    // Get orders by status
    async getOrdersByStatus(status) {
        const result = await this.docClient.query({
            TableName: this.tableName,
            IndexName: 'GSI1',
            KeyConditionExpression: 'GSI1PK = :status AND begins_with(GSI1SK, :orderPrefix)',
            ExpressionAttributeValues: {
                ':status': `ORDERSTATUS#${status}`,
                ':orderPrefix': 'ORDER#'
            }
        }).promise();

        return result.Items;
    }
}

// ===========================================
// TRANSACTIONS AND ATOMIC OPERATIONS
// ===========================================

class TransactionService extends DynamoDBService {
    // Execute transaction
    async executeTransaction(operations) {
        const transactItems = operations.map(op => {
            switch (op.type) {
                case 'PUT':
                    return {
                        Put: {
                            TableName: this.tableName,
                            Item: op.item,
                            ConditionExpression: op.condition
                        }
                    };
                case 'UPDATE':
                    return {
                        Update: {
                            TableName: this.tableName,
                            Key: op.key,
                            UpdateExpression: op.updateExpression,
                            ConditionExpression: op.condition
                        }
                    };
                case 'DELETE':
                    return {
                        Delete: {
                            TableName: this.tableName,
                            Key: op.key,
                            ConditionExpression: op.condition
                        }
                    };
                case 'CONDITION_CHECK':
                    return {
                        ConditionCheck: {
                            TableName: this.tableName,
                            Key: op.key,
                            ConditionExpression: op.condition
                        }
                    };
            }
        });

        const params = {
            TransactItems: transactItems
        };

        await this.docClient.transactWrite(params).promise();
    }

    // Transfer money between accounts (atomic)
    async transferMoney(fromAccountId, toAccountId, amount) {
        await this.executeTransaction([
            {
                type: 'CONDITION_CHECK',
                key: { accountId: fromAccountId },
                condition: 'balance >= :amount',
                values: { ':amount': amount }
            },
            {
                type: 'UPDATE',
                key: { accountId: fromAccountId },
                updateExpression: 'SET balance = balance - :amount',
                condition: 'balance >= :amount',
                values: { ':amount': amount }
            },
            {
                type: 'UPDATE',
                key: { accountId: toAccountId },
                updateExpression: 'SET balance = balance + :amount',
                values: { ':amount': amount }
            }
        ]);
    }

    // Place order with inventory check
    async placeOrder(orderData) {
        const operations = [];

        // Check product availability
        for (const item of orderData.items) {
            operations.push({
                type: 'CONDITION_CHECK',
                key: { productId: item.productId },
                condition: 'inventory >= :quantity',
                values: { ':quantity': item.quantity }
            });
        }

        // Create order
        operations.push({
            type: 'PUT',
            item: {
                orderId: orderData.orderId,
                customerId: orderData.customerId,
                status: 'confirmed',
                totalAmount: orderData.totalAmount,
                items: orderData.items,
                createdAt: new Date().toISOString()
            }
        });

        // Update inventory
        for (const item of orderData.items) {
            operations.push({
                type: 'UPDATE',
                key: { productId: item.productId },
                updateExpression: 'SET inventory = inventory - :quantity',
                values: { ':quantity': item.quantity }
            });
        }

        await this.executeTransaction(operations);
    }
}

// ===========================================
// STREAM PROCESSING
// ===========================================

class StreamProcessor {
    constructor(tableName) {
        this.tableName = tableName;
        this.dynamodbStreams = new AWS.DynamoDBStreams();
    }

    async processStreamRecords(records) {
        for (const record of records) {
            const eventName = record.eventName; // INSERT, MODIFY, REMOVE
            const newImage = record.dynamodb.NewImage;
            const oldImage = record.dynamodb.OldImage;

            switch (eventName) {
                case 'INSERT':
                    await this.handleInsert(newImage);
                    break;
                case 'MODIFY':
                    await this.handleUpdate(oldImage, newImage);
                    break;
                case 'REMOVE':
                    await this.handleDelete(oldImage);
                    break;
            }
        }
    }

    async handleInsert(newImage) {
        // Process new item insertion
        console.log('New item inserted:', newImage);

        // Example: Send welcome email for new user
        if (newImage.entityType === 'USER') {
            await this.sendWelcomeEmail(newImage.email, newImage.name);
        }

        // Example: Update search index
        if (newImage.entityType === 'PRODUCT') {
            await this.updateSearchIndex(newImage);
        }
    }

    async handleUpdate(oldImage, newImage) {
        // Process item updates
        console.log('Item updated:', { old: oldImage, new: newImage });

        // Example: Send notification for order status change
        if (oldImage.status !== newImage.status && newImage.entityType === 'ORDER') {
            await this.sendOrderStatusNotification(newImage);
        }
    }

    async handleDelete(oldImage) {
        // Process item deletion
        console.log('Item deleted:', oldImage);

        // Example: Clean up related data
        if (oldImage.entityType === 'USER') {
            await this.cleanupUserData(oldImage.userId);
        }
    }

    // Placeholder methods for actual implementations
    async sendWelcomeEmail(email, name) { /* Implementation */ }
    async updateSearchIndex(product) { /* Implementation */ }
    async sendOrderStatusNotification(order) { /* Implementation */ }
    async cleanupUserData(userId) { /* Implementation */ }
}

// ===========================================
// BATCH OPERATIONS AND MIGRATIONS
// ===========================================

class BatchOperationsService extends DynamoDBService {
    // Migrate data between tables
    async migrateTable(sourceTable, targetTable, transformFunction = null) {
        let lastEvaluatedKey = null;

        do {
            const scanParams = {
                TableName: sourceTable,
                ExclusiveStartKey: lastEvaluatedKey,
                Limit: 100
            };

            const scanResult = await this.docClient.scan(scanParams).promise();
            const items = scanResult.Items;

            if (items.length > 0) {
                // Transform items if needed
                const transformedItems = transformFunction
                    ? items.map(transformFunction)
                    : items;

                // Batch write to target table
                const batchParams = {
                    RequestItems: {
                        [targetTable]: transformedItems.map(item => ({
                            PutRequest: { Item: item }
                        }))
                    }
                };

                await this.docClient.batchWrite(batchParams).promise();
            }

            lastEvaluatedKey = scanResult.LastEvaluatedKey;
        } while (lastEvaluatedKey);
    }

    // Bulk update with conditional checks
    async bulkUpdate(items, updateFunction) {
        const transactItems = [];

        for (const item of items) {
            const updates = updateFunction(item);
            transactItems.push({
                Update: {
                    TableName: this.tableName,
                    Key: { PK: item.PK, SK: item.SK },
                    UpdateExpression: updates.expression,
                    ExpressionAttributeValues: updates.values,
                    ConditionExpression: updates.condition
                }
            });
        }

        const params = {
            TransactItems: transactItems
        };

        await this.docClient.transactWrite(params).promise();
    }

    // Archive old data
    async archiveOldData(archiveTable, dateThreshold) {
        const scanParams = {
            TableName: this.tableName,
            FilterExpression: 'createdAt < :threshold',
            ExpressionAttributeValues: {
                ':threshold': dateThreshold
            }
        };

        const itemsToArchive = await this.docClient.scan(scanParams).promise();

        if (itemsToArchive.Items.length > 0) {
            // Copy to archive table
            const archiveParams = {
                RequestItems: {
                    [archiveTable]: itemsToArchive.Items.map(item => ({
                        PutRequest: { Item: item }
                    }))
                }
            };

            await this.docClient.batchWrite(archiveParams).promise();

            // Delete from main table
            const deleteParams = {
                RequestItems: {
                    [this.tableName]: itemsToArchive.Items.map(item => ({
                        DeleteRequest: { Key: { PK: item.PK, SK: item.SK } }
                    }))
                }
            };

            await this.docClient.batchWrite(deleteParams).promise();
        }
    }
}

// ===========================================
// MONITORING AND OPTIMIZATION
// ===========================================

class DynamoDBMonitor {
    constructor() {
        this.cloudwatch = new AWS.CloudWatch();
    }

    // Get table metrics
    async getTableMetrics(tableName, startTime, endTime) {
        const metrics = [
            'ConsumedReadCapacityUnits',
            'ConsumedWriteCapacityUnits',
            'ReadThrottleEvents',
            'WriteThrottleEvents',
            'SuccessfulRequestLatency'
        ];

        const metricData = await Promise.all(
            metrics.map(metric => this.getMetricStatistics(tableName, metric, startTime, endTime))
        );

        return metricData.reduce((acc, data, index) => {
            acc[metrics[index]] = data;
            return acc;
        }, {});
    }

    async getMetricStatistics(tableName, metricName, startTime, endTime) {
        const params = {
            Namespace: 'AWS/DynamoDB',
            MetricName: metricName,
            Dimensions: [
                { Name: 'TableName', Value: tableName }
            ],
            StartTime: startTime,
            EndTime: endTime,
            Period: 300, // 5 minutes
            Statistics: ['Average', 'Maximum', 'Minimum']
        };

        const result = await this.cloudwatch.getMetricStatistics(params).promise();
        return result.Datapoints;
    }

    // Analyze access patterns
    async analyzeAccessPatterns(tableName) {
        // Get CloudWatch metrics for the last 24 hours
        const endTime = new Date();
        const startTime = new Date(endTime.getTime() - 24 * 60 * 60 * 1000);

        const metrics = await this.getTableMetrics(tableName, startTime, endTime);

        return {
            tableName,
            period: '24 hours',
            metrics,
            recommendations: this.generateRecommendations(metrics)
        };
    }

    generateRecommendations(metrics) {
        const recommendations = [];

        const avgReadCapacity = metrics.ConsumedReadCapacityUnits?.[0]?.Average || 0;
        const avgWriteCapacity = metrics.ConsumedWriteCapacityUnits?.[0]?.Average || 0;
        const readThrottleEvents = metrics.ReadThrottleEvents?.length || 0;
        const writeThrottleEvents = metrics.WriteThrottleEvents?.length || 0;

        if (readThrottleEvents > 0) {
            recommendations.push('Consider increasing read capacity or implementing DAX for caching');
        }

        if (writeThrottleEvents > 0) {
            recommendations.push('Consider increasing write capacity or implementing write sharding');
        }

        if (avgReadCapacity > avgWriteCapacity * 2) {
            recommendations.push('Read-heavy workload detected - consider read replicas or caching strategies');
        }

        if (avgWriteCapacity > avgReadCapacity * 2) {
            recommendations.push('Write-heavy workload detected - ensure adequate write capacity');
        }

        return recommendations;
    }
}

// ===========================================
// EXPORT FOR USE
// ===========================================

module.exports = {
    DynamoDBService,
    QueryService,
    SingleTableService,
    TransactionService,
    StreamProcessor,
    BatchOperationsService,
    DynamoDBMonitor
};

/*
DYNAMODB DESIGN PATTERNS:

1. **Single Table Design**: Use one table with multiple entity types and GSIs
2. **Composite Keys**: Use meaningful partition and sort keys
3. **GSI Overloading**: Use GSIs for multiple access patterns
4. **Sparse Indexes**: Only include items that have the GSI key attributes
5. **Item Collections**: Group related items under the same partition key

DYNAMODB BEST PRACTICES:

1. **Distribute Load**: Use high-cardinality partition keys
2. **Query Optimization**: Design for query patterns, not relationships
3. **Batch Operations**: Use batch APIs for multiple items
4. **Conditional Updates**: Use conditions to prevent race conditions
5. **TTL**: Use Time-To-Live for automatic data expiration
6. **Streams**: Use DynamoDB Streams for event-driven architectures

DYNAMODB IS IDEAL FOR:
- Serverless applications
- High-scale workloads
- Event-driven architectures
- Gaming leaderboards
- IoT data ingestion
- Session storage
- Shopping carts
- User preferences

PERFORMANCE OPTIMIZATION:
- Choose appropriate partition keys for distribution
- Use GSIs strategically
- Implement caching with DAX
- Monitor and adjust capacity
- Use batch operations
- Implement exponential backoff for throttles
*/
