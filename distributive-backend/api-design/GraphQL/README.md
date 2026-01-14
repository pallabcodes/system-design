# GraphQL API Design Patterns

> **Level**: Principal Architect / SDE-3
> **Scope**: Schema Design, DataLoader, Federation, and Subscriptions.

> [!WARNING]
> **The N+1 Trap**: GraphQL is flexible, but without **DataLoader**, a single query can trigger thousands of database calls. Implement batching from day one.

## Overview

GraphQL is a query language for APIs that provides a more efficient, powerful, and flexible alternative to REST. This comprehensive guide covers GraphQL schema design, resolvers, performance optimization, and enterprise patterns.

## Key Features

### 🎯 **Schema-First Design**
- **Type definitions** with strong typing and validation
- **Schema stitching** for microservices architecture
- **Directive-based** schema extensions and modifications
- **Introspection** for API documentation and tooling

### 🚀 **Query Optimization**
- **Dataloader** for batching and caching
- **Query complexity** analysis and limiting
- **Persisted queries** for performance and security
- **Apollo Federation** for distributed schemas

### 🔧 **Advanced Patterns**
- **Cursor-based pagination** for large datasets
- **Real-time subscriptions** with WebSocket connections
- **File uploads** with multipart requests
- **Error handling** with custom extensions

## Core Components

### Schema Definition
```graphql
# Root types
type Query {
  users(first: Int, after: String): UserConnection!
  user(id: ID!): User
  posts(category: String, limit: Int): [Post!]!
}

type Mutation {
  createUser(input: CreateUserInput!): UserPayload!
  updatePost(id: ID!, input: UpdatePostInput!): PostPayload!
}

type Subscription {
  userCreated: User!
  postUpdated(id: ID!): Post!
}

# Object types
type User {
  id: ID!
  email: String!
  name: String!
  posts(first: Int, after: String): PostConnection!
  createdAt: DateTime!
  updatedAt: DateTime!
}

type Post {
  id: ID!
  title: String!
  content: String!
  author: User!
  comments(first: Int, after: String): CommentConnection!
  tags: [String!]!
  published: Boolean!
  createdAt: DateTime!
  updatedAt: DateTime!
}

# Input types
input CreateUserInput {
  email: String!
  name: String!
  password: String!
}

input UpdatePostInput {
  title: String
  content: String
  tags: [String!]
  published: Boolean
}

# Payload types for mutations
type UserPayload {
  user: User
  errors: [Error!]
}

type PostPayload {
  post: Post
  errors: [Error!]
}

# Custom scalars
scalar DateTime
scalar Email

# Enums
enum Role {
  ADMIN
  MODERATOR
  USER
}

# Unions and Interfaces
interface Node {
  id: ID!
}

interface Commentable {
  comments(first: Int, after: String): CommentConnection!
}

type Post implements Node & Commentable {
  id: ID!
  title: String!
  content: String!
  comments(first: Int, after: String): CommentConnection!
}

type Video implements Node & Commentable {
  id: ID!
  title: String!
  url: String!
  comments(first: Int, after: String): CommentConnection!
}

union SearchResult = User | Post | Comment

# Error handling
type Error {
  field: String
  message: String!
  code: String
}
```

### Connection Pattern (Cursor-based Pagination)
```graphql
type PageInfo {
  hasNextPage: Boolean!
  hasPreviousPage: Boolean!
  startCursor: String
  endCursor: String
}

type UserConnection {
  edges: [UserEdge!]!
  pageInfo: PageInfo!
  totalCount: Int!
}

type UserEdge {
  node: User!
  cursor: String!
}
```

## Resolver Implementation

### Basic Resolvers
```javascript
const resolvers = {
  Query: {
    user: async (parent, args, context) => {
      return await context.dataSources.users.getById(args.id);
    },

    users: async (parent, args, context) => {
      const { first, after } = args;
      return await context.dataSources.users.getConnection(first, after);
    }
  },

  Mutation: {
    createUser: async (parent, args, context) => {
      try {
        const user = await context.dataSources.users.create(args.input);
        return { user, errors: null };
      } catch (error) {
        return { user: null, errors: [error] };
      }
    }
  },

  User: {
    posts: async (user, args, context) => {
      return await context.dataSources.posts.getByAuthorId(user.id, args);
    }
  }
};
```

### DataLoader for Batching
```javascript
const DataLoader = require('dataloader');

class UserDataSource {
  constructor(db) {
    this.db = db;
    this.userLoader = new DataLoader(async (ids) => {
      const users = await this.db.users.findMany({
        where: { id: { in: ids } }
      });

      // Return users in the same order as requested IDs
      return ids.map(id => users.find(user => user.id === id));
    });
  }

  async getById(id) {
    return this.userLoader.load(id);
  }

  async getByIds(ids) {
    return this.userLoader.loadMany(ids);
  }
}
```

## Performance Optimization

### Query Complexity Analysis
```javascript
const { createComplexityLimitRule } = require('graphql-validation-complexity');

const complexityRule = createComplexityLimitRule(1000, {
  scalarCost: 1,
  objectCost: 2,
  listFactor: 10,
});

const server = new ApolloServer({
  schema,
  validationRules: [complexityRule]
});
```

### Caching Strategy
```javascript
const { ApolloServer } = require('apollo-server');
const responseCachePlugin = require('apollo-server-plugin-response-cache');

const server = new ApolloServer({
  schema,
  plugins: [
    responseCachePlugin({
      sessionId: (requestContext) => {
        return requestContext.request.http.headers.get('authorization') || null;
      }
    })
  ]
});
```

### Persisted Queries
```javascript
const { createPersistedQueryLink } = require('apollo-link-persisted-queries');
const { createHttpLink } = require('apollo-link-http');
const { InMemoryCache } = require('apollo-cache-inmemory');
const ApolloClient = require('apollo-client');

const link = createPersistedQueryLink({
  sha256: (query) => require('crypto').createHash('sha256').update(query).digest('hex')
}).concat(
  createHttpLink({ uri: '/graphql' })
);

const client = new ApolloClient({
  link,
  cache: new InMemoryCache()
});
```

## Advanced Patterns

### Schema Stitching
```javascript
const { makeExecutableSchema } = require('graphql-tools');
const { mergeSchemas } = require('graphql-tools');

// User service schema
const userSchema = makeExecutableSchema({
  typeDefs: `
    type User {
      id: ID!
      name: String!
      posts: [Post!]!
    }

    type Query {
      users: [User!]!
    }
  `,
  resolvers: userResolvers
});

// Post service schema
const postSchema = makeExecutableSchema({
  typeDefs: `
    type Post {
      id: ID!
      title: String!
      author: User!
    }

    type Query {
      posts: [Post!]!
    }
  `,
  resolvers: postResolvers
});

// Stitched schema
const schema = mergeSchemas({
  schemas: [userSchema, postSchema],
  resolvers: {
    User: {
      posts: {
        fragment: '... on User { id }',
        resolve(user, args, context, info) {
          return context.dataSources.posts.getByAuthorId(user.id);
        }
      }
    },
    Post: {
      author: {
        fragment: '... on Post { authorId }',
        resolve(post, args, context, info) {
          return context.dataSources.users.getById(post.authorId);
        }
      }
    }
  }
});
```

### Apollo Federation
```javascript
// User service
const { ApolloServer, gql } = require('apollo-server');
const { buildFederatedSchema } = require('@apollo/federation');

const typeDefs = gql`
  type User @key(fields: "id") {
    id: ID!
    name: String!
    email: String!
  }

  extend type Query {
    users: [User!]!
  }
`;

const resolvers = {
  Query: {
    users: () => users
  },
  User: {
    __resolveReference(reference) {
      return users.find(user => user.id === reference.id);
    }
  }
};

const server = new ApolloServer({
  schema: buildFederatedSchema([{ typeDefs, resolvers }])
});
```

### Real-time Subscriptions
```javascript
const { PubSub } = require('graphql-subscriptions');
const pubsub = new PubSub();

const resolvers = {
  Subscription: {
    userCreated: {
      subscribe: () => pubsub.asyncIterator(['USER_CREATED'])
    }
  },
  Mutation: {
    createUser: async (parent, args) => {
      const user = await createUserInDB(args.input);
      pubsub.publish('USER_CREATED', { userCreated: user });
      return user;
    }
  }
};
```

## Error Handling

### Custom Error Extensions
```javascript
class AuthenticationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AuthenticationError';
    this.extensions = {
      code: 'UNAUTHENTICATED',
      http: { status: 401 }
    };
  }
}

class ValidationError extends Error {
  constructor(field, message) {
    super(message);
    this.name = 'ValidationError';
    this.extensions = {
      code: 'VALIDATION_ERROR',
      field
    };
  }
}

// In resolvers
const resolvers = {
  Mutation: {
    createUser: async (parent, args, context) => {
      if (!context.user) {
        throw new AuthenticationError('You must be logged in');
      }

      if (!isValidEmail(args.input.email)) {
        throw new ValidationError('email', 'Invalid email format');
      }

      return await context.dataSources.users.create(args.input);
    }
  }
};
```

## Testing

### Unit Testing Resolvers
```javascript
const { graphql } = require('graphql');
const { makeExecutableSchema } = require('graphql-tools');

describe('User Resolvers', () => {
  let schema;
  let mockDataSources;

  beforeEach(() => {
    mockDataSources = {
      users: {
        getById: jest.fn(),
        create: jest.fn()
      }
    };

    schema = makeExecutableSchema({
      typeDefs,
      resolvers: {
        Query: {
          user: (parent, args, { dataSources }) =>
            dataSources.users.getById(args.id)
        }
      }
    });
  });

  it('should resolve user query', async () => {
    mockDataSources.users.getById.mockResolvedValue({
      id: '1',
      name: 'John Doe'
    });

    const query = `
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
        }
      }
    `;

    const result = await graphql(schema, query, null, { dataSources: mockDataSources }, { id: '1' });

    expect(result.data.user).toEqual({
      id: '1',
      name: 'John Doe'
    });
  });
});
```

## Best Practices

### Schema Design
1. **Use descriptive names** for types, fields, and arguments
2. **Avoid deeply nested queries** - limit depth to 3-4 levels
3. **Use interfaces and unions** for polymorphic relationships
4. **Implement proper pagination** for list fields
5. **Define clear error types** with meaningful messages

### Performance
1. **Implement DataLoader** for N+1 query prevention
2. **Use query complexity limits** to prevent abuse
3. **Cache frequently accessed data** with appropriate TTL
4. **Monitor query performance** and optimize slow resolvers
5. **Use persisted queries** in production

### Security
1. **Validate input data** thoroughly
2. **Implement authentication** and authorization
3. **Limit query depth and complexity**
4. **Sanitize error messages** to prevent information leakage
5. **Use HTTPS** and proper CORS configuration

This GraphQL implementation provides a complete foundation for building scalable, efficient, and maintainable APIs with modern patterns and best practices.
