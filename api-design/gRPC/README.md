# gRPC API Design Patterns

## Overview

gRPC is a high-performance, open-source universal RPC framework that uses HTTP/2 for transport and Protocol Buffers as the interface definition language. This comprehensive guide covers gRPC service design, streaming patterns, load balancing, and enterprise implementation.

## Key Features

### 🚀 **High Performance**
- **HTTP/2 multiplexing** for concurrent requests
- **Binary serialization** with Protocol Buffers
- **Bidirectional streaming** for real-time communication
- **Built-in load balancing** and service discovery

### 🔧 **Developer Experience**
- **Strong typing** with generated client/server code
- **Multi-language support** with automatic code generation
- **Built-in authentication** and encryption
- **Rich ecosystem** with middleware and tooling

### 🏗️ **Scalability**
- **Service mesh integration** (Istio, Linkerd)
- **Distributed tracing** with OpenTelemetry
- **Circuit breakers** and retries
- **Health checking** and graceful degradation

## Protocol Buffer Definition

### Basic Service Definition
```protobuf
syntax = "proto3";

package ecommerce.v1;

import "google/api/annotations.proto";
import "google/protobuf/timestamp.proto";
import "google/protobuf/empty.proto";

// User service
service UserService {
  rpc CreateUser(CreateUserRequest) returns (CreateUserResponse) {
    option (google.api.http) = {
      post: "/v1/users"
      body: "*"
    };
  }

  rpc GetUser(GetUserRequest) returns (GetUserResponse) {
    option (google.api.http) = {
      get: "/v1/users/{user_id}"
    };
  }

  rpc ListUsers(ListUsersRequest) returns (ListUsersResponse) {
    option (google.api.http) = {
      get: "/v1/users"
    };
  }

  rpc UpdateUser(UpdateUserRequest) returns (UpdateUserResponse) {
    option (google.api.http) = {
      patch: "/v1/users/{user.user_id}"
      body: "*"
    };
  }

  rpc DeleteUser(DeleteUserRequest) returns (google.protobuf.Empty) {
    option (google.api.http) = {
      delete: "/v1/users/{user_id}"
    };
  }

  // Streaming endpoints
  rpc WatchUsers(WatchUsersRequest) returns (stream UserEvent);
}

// Messages
message User {
  string user_id = 1;
  string email = 2;
  string name = 3;
  string avatar_url = 4;
  google.protobuf.Timestamp created_at = 5;
  google.protobuf.Timestamp updated_at = 6;
  UserStatus status = 7;
  repeated string roles = 8;
}

enum UserStatus {
  USER_STATUS_UNSPECIFIED = 0;
  USER_STATUS_ACTIVE = 1;
  USER_STATUS_INACTIVE = 2;
  USER_STATUS_SUSPENDED = 3;
}

message CreateUserRequest {
  string email = 1;
  string name = 2;
  string password = 3;
}

message CreateUserResponse {
  User user = 1;
}

message GetUserRequest {
  string user_id = 1;
}

message GetUserResponse {
  User user = 1;
}

message ListUsersRequest {
  int32 page_size = 1;
  string page_token = 2;
  string filter = 3;
  string order_by = 4;
}

message ListUsersResponse {
  repeated User users = 1;
  string next_page_token = 2;
  int32 total_count = 3;
}

message UpdateUserRequest {
  User user = 1;
  google.protobuf.FieldMask update_mask = 2;
}

message UpdateUserResponse {
  User user = 1;
}

message DeleteUserRequest {
  string user_id = 1;
}

message WatchUsersRequest {
  string filter = 1;
}

message UserEvent {
  UserEventType event_type = 1;
  User user = 2;
  google.protobuf.Timestamp timestamp = 3;
}

enum UserEventType {
  USER_EVENT_TYPE_UNSPECIFIED = 0;
  USER_EVENT_TYPE_CREATED = 1;
  USER_EVENT_TYPE_UPDATED = 2;
  USER_EVENT_TYPE_DELETED = 3;
}
```

### Advanced Patterns

#### Bidirectional Streaming
```protobuf
service ChatService {
  rpc Chat(stream ChatMessage) returns (stream ChatMessage);
}

message ChatMessage {
  string room_id = 1;
  string user_id = 2;
  string content = 3;
  google.protobuf.Timestamp timestamp = 4;
  MessageType type = 5;
}

enum MessageType {
  MESSAGE_TYPE_UNSPECIFIED = 0;
  MESSAGE_TYPE_TEXT = 1;
  MESSAGE_TYPE_IMAGE = 2;
  MESSAGE_TYPE_SYSTEM = 3;
}
```

#### File Upload with Streaming
```protobuf
service FileService {
  rpc UploadFile(stream FileChunk) returns (UploadResponse);
  rpc DownloadFile(DownloadRequest) returns (stream FileChunk);
}

message FileChunk {
  string file_id = 1;
  bytes data = 2;
  int32 chunk_index = 3;
  bool is_last_chunk = 4;
  string checksum = 5;
}

message UploadResponse {
  string file_id = 1;
  string upload_url = 2;
  int64 file_size = 3;
  string checksum = 4;
}

message DownloadRequest {
  string file_id = 1;
  int64 offset = 2;
  int64 limit = 3;
}
```

## Server Implementation

### Go Server Example
```go
package main

import (
    "context"
    "log"
    "net"

    pb "github.com/your-org/ecommerce/v1"
    "google.golang.org/grpc"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
)

type userServer struct {
    pb.UnimplementedUserServiceServer
    userStore UserStore
}

func (s *userServer) CreateUser(ctx context.Context, req *pb.CreateUserRequest) (*pb.CreateUserResponse, error) {
    // Validate request
    if req.Email == "" || req.Name == "" {
        return nil, status.Error(codes.InvalidArgument, "email and name are required")
    }

    // Check if user already exists
    existing, err := s.userStore.GetByEmail(ctx, req.Email)
    if err != nil {
        return nil, status.Error(codes.Internal, "failed to check existing user")
    }
    if existing != nil {
        return nil, status.Error(codes.AlreadyExists, "user with this email already exists")
    }

    // Hash password
    hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
    if err != nil {
        return nil, status.Error(codes.Internal, "failed to hash password")
    }

    // Create user
    user := &User{
        Email:    req.Email,
        Name:     req.Name,
        Password: string(hashedPassword),
    }

    createdUser, err := s.userStore.Create(ctx, user)
    if err != nil {
        return nil, status.Error(codes.Internal, "failed to create user")
    }

    return &pb.CreateUserResponse{
        User: convertUserToProto(createdUser),
    }, nil
}

func (s *userServer) GetUser(ctx context.Context, req *pb.GetUserRequest) (*pb.GetUserResponse, error) {
    user, err := s.userStore.GetByID(ctx, req.UserId)
    if err != nil {
        return nil, status.Error(codes.Internal, "failed to get user")
    }
    if user == nil {
        return nil, status.Error(codes.NotFound, "user not found")
    }

    return &pb.GetUserResponse{
        User: convertUserToProto(user),
    }, nil
}

func (s *userServer) ListUsers(ctx context.Context, req *pb.ListUsersRequest) (*pb.ListUsersResponse, error) {
    pageSize := int(req.PageSize)
    if pageSize <= 0 || pageSize > 100 {
        pageSize = 50
    }

    users, nextToken, totalCount, err := s.userStore.List(ctx, pageSize, req.PageToken, req.Filter)
    if err != nil {
        return nil, status.Error(codes.Internal, "failed to list users")
    }

    protoUsers := make([]*pb.User, len(users))
    for i, user := range users {
        protoUsers[i] = convertUserToProto(user)
    }

    return &pb.ListUsersResponse{
        Users:          protoUsers,
        NextPageToken:  nextToken,
        TotalCount:     int32(totalCount),
    }, nil
}

func (s *userServer) WatchUsers(req *pb.WatchUsersRequest, stream pb.UserService_WatchUsersServer) error {
    // Subscribe to user events
    eventChan, err := s.userStore.SubscribeToEvents(ctx, req.Filter)
    if err != nil {
        return status.Error(codes.Internal, "failed to subscribe to user events")
    }
    defer s.userStore.UnsubscribeFromEvents(eventChan)

    for {
        select {
        case event := <-eventChan:
            userEvent := &pb.UserEvent{
                EventType: convertEventType(event.Type),
                User:      convertUserToProto(event.User),
                Timestamp: timestamppb.New(event.Timestamp),
            }

            if err := stream.Send(userEvent); err != nil {
                return err
            }

        case <-stream.Context().Done():
            return nil
        }
    }
}

func main() {
    lis, err := net.Listen("tcp", ":50051")
    if err != nil {
        log.Fatalf("failed to listen: %v", err)
    }

    s := grpc.NewServer(
        grpc.UnaryInterceptor(unaryLoggingInterceptor),
        grpc.StreamInterceptor(streamLoggingInterceptor),
    )

    pb.RegisterUserServiceServer(s, &userServer{
        userStore: NewUserStore(),
    })

    log.Printf("server listening at %v", lis.Addr())
    if err := s.Serve(lis); err != nil {
        log.Fatalf("failed to serve: %v", err)
    }
}
```

### Node.js Server Example
```javascript
const grpc = require('@grpc/grpc-js');
const protoLoader = require('@grpc/proto-loader');

const packageDefinition = protoLoader.loadSync('ecommerce.proto', {
  keepCase: true,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
});

const protoDescriptor = grpc.loadPackageDefinition(packageDefinition);
const userService = protoDescriptor.ecommerce.v1.UserService;

class UserServiceImpl {
  async CreateUser(call, callback) {
    try {
      const { email, name, password } = call.request;

      // Validate input
      if (!email || !name || !password) {
        return callback({
          code: grpc.status.INVALID_ARGUMENT,
          message: 'Email, name, and password are required',
        });
      }

      // Check if user exists
      const existingUser = await this.userStore.findByEmail(email);
      if (existingUser) {
        return callback({
          code: grpc.status.ALREADY_EXISTS,
          message: 'User with this email already exists',
        });
      }

      // Hash password
      const hashedPassword = await bcrypt.hash(password, 10);

      // Create user
      const user = await this.userStore.create({
        email,
        name,
        password: hashedPassword,
      });

      callback(null, {
        user: this.convertUserToProto(user),
      });
    } catch (error) {
      console.error('CreateUser error:', error);
      callback({
        code: grpc.status.INTERNAL,
        message: 'Internal server error',
      });
    }
  }

  async GetUser(call, callback) {
    try {
      const { user_id } = call.request;
      const user = await this.userStore.findById(user_id);

      if (!user) {
        return callback({
          code: grpc.status.NOT_FOUND,
          message: 'User not found',
        });
      }

      callback(null, {
        user: this.convertUserToProto(user),
      });
    } catch (error) {
      console.error('GetUser error:', error);
      callback({
        code: grpc.status.INTERNAL,
        message: 'Internal server error',
      });
    }
  }

  async WatchUsers(call) {
    try {
      // Subscribe to user events
      const eventStream = this.userStore.subscribeToEvents(call.request.filter);

      eventStream.on('data', (event) => {
        call.write({
          event_type: this.convertEventType(event.type),
          user: this.convertUserToProto(event.user),
          timestamp: event.timestamp,
        });
      });

      eventStream.on('error', (error) => {
        console.error('Event stream error:', error);
        call.end();
      });

      call.on('cancelled', () => {
        eventStream.destroy();
      });

      call.on('end', () => {
        eventStream.destroy();
      });
    } catch (error) {
      console.error('WatchUsers error:', error);
      call.end();
    }
  }

  convertUserToProto(user) {
    return {
      user_id: user.id,
      email: user.email,
      name: user.name,
      avatar_url: user.avatarUrl,
      created_at: user.createdAt,
      updated_at: user.updatedAt,
      status: user.status,
      roles: user.roles,
    };
  }

  convertEventType(type) {
    const types = {
      'created': 'USER_EVENT_TYPE_CREATED',
      'updated': 'USER_EVENT_TYPE_UPDATED',
      'deleted': 'USER_EVENT_TYPE_DELETED',
    };
    return types[type] || 'USER_EVENT_TYPE_UNSPECIFIED';
  }
}

function main() {
  const server = new grpc.Server();

  server.addService(userService.service, new UserServiceImpl());

  server.bindAsync('0.0.0.0:50051', grpc.ServerCredentials.createInsecure(), () => {
    server.start();
    console.log('gRPC server running on port 50051');
  });
}

main();
```

## Client Implementation

### Go Client Example
```go
package main

import (
    "context"
    "log"
    "time"

    pb "github.com/your-org/ecommerce/v1"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)

func main() {
    // Connect to server
    conn, err := grpc.Dial("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
    if err != nil {
        log.Fatalf("failed to connect: %v", err)
    }
    defer conn.Close()

    client := pb.NewUserServiceClient(conn)

    // Create user
    ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
    defer cancel()

    createResp, err := client.CreateUser(ctx, &pb.CreateUserRequest{
        Email:    "john@example.com",
        Name:     "John Doe",
        Password: "securepassword",
    })
    if err != nil {
        log.Fatalf("failed to create user: %v", err)
    }

    log.Printf("Created user: %s", createResp.User.Name)

    // Get user
    getResp, err := client.GetUser(ctx, &pb.GetUserRequest{
        UserId: createResp.User.UserId,
    })
    if err != nil {
        log.Fatalf("failed to get user: %v", err)
    }

    log.Printf("Retrieved user: %s", getResp.User.Name)

    // Watch users (streaming)
    watchReq := &pb.WatchUsersRequest{
        Filter: "status:active",
    }

    stream, err := client.WatchUsers(ctx, watchReq)
    if err != nil {
        log.Fatalf("failed to watch users: %v", err)
    }

    go func() {
        for {
            event, err := stream.Recv()
            if err != nil {
                log.Printf("stream error: %v", err)
                return
            }

            log.Printf("User event: %s for user %s", event.EventType, event.User.Name)
        }
    }()

    // Keep the program running
    select {}
}
```

### Node.js Client Example
```javascript
const grpc = require('@grpc/grpc-js');
const protoLoader = require('@grpc/proto-loader');

const packageDefinition = protoLoader.loadSync('ecommerce.proto', {
  keepCase: true,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
});

const protoDescriptor = grpc.loadPackageDefinition(packageDefinition);
const userService = protoDescriptor.ecommerce.v1.UserService;

function main() {
  const client = new userService(
    'localhost:50051',
    grpc.credentials.createInsecure()
  );

  // Create user
  client.CreateUser({
    email: 'john@example.com',
    name: 'John Doe',
    password: 'securepassword',
  }, (error, response) => {
    if (error) {
      console.error('CreateUser error:', error);
      return;
    }

    console.log('Created user:', response.user.name);

    // Get user
    client.GetUser({
      user_id: response.user.user_id,
    }, (error, response) => {
      if (error) {
        console.error('GetUser error:', error);
        return;
      }

      console.log('Retrieved user:', response.user.name);

      // Watch users
      const call = client.WatchUsers({
        filter: 'status:active',
      });

      call.on('data', (event) => {
        console.log('User event:', event.event_type, 'for user:', event.user.name);
      });

      call.on('error', (error) => {
        console.error('Stream error:', error);
      });

      call.on('end', () => {
        console.log('Stream ended');
      });
    });
  });
}

main();
```

## Advanced Patterns

### Interceptors and Middleware
```go
// Logging interceptor
func unaryLoggingInterceptor(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
    start := time.Now()
    method := info.FullMethod

    log.Printf("Started %s", method)

    resp, err := handler(ctx, req)

    duration := time.Since(start)
    if err != nil {
        log.Printf("Completed %s in %v with error: %v", method, duration, err)
    } else {
        log.Printf("Completed %s in %v", method, duration)
    }

    return resp, err
}

// Authentication interceptor
func unaryAuthInterceptor(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
    // Extract token from metadata
    md, ok := metadata.FromIncomingContext(ctx)
    if !ok {
        return nil, status.Error(codes.Unauthenticated, "missing metadata")
    }

    tokens := md.Get("authorization")
    if len(tokens) == 0 {
        return nil, status.Error(codes.Unauthenticated, "missing auth token")
    }

    // Validate token
    userID, err := validateToken(tokens[0])
    if err != nil {
        return nil, status.Error(codes.Unauthenticated, "invalid token")
    }

    // Add user ID to context
    newCtx := context.WithValue(ctx, "userID", userID)
    return handler(newCtx, req)
}
```

### Load Balancing and Service Discovery
```javascript
const grpc = require('@grpc/grpc-js');

// DNS-based load balancing
const client = new userService(
  'dns:///user-service:50051',
  grpc.credentials.createInsecure()
);

// Static load balancing
const client = new userService(
  'localhost:50051,localhost:50052,localhost:50053',
  grpc.credentials.createInsecure()
);

// With service mesh (Istio)
const client = new userService(
  'user-service.default.svc.cluster.local:50051',
  grpc.credentials.createInsecure()
);
```

### Health Checking
```protobuf
import "grpc/health/v1/health.proto";

service HealthService {
  rpc Check(grpc.health.v1.HealthCheckRequest) returns (grpc.health.v1.HealthCheckResponse);
  rpc Watch(grpc.health.v1.HealthCheckRequest) returns (stream grpc.health.v1.HealthCheckResponse);
}
```

```go
import "google.golang.org/grpc/health"
import "google.golang.org/grpc/health/grpc_health_v1"

func main() {
    // ... server setup ...

    // Register health service
    healthServer := health.NewServer()
    healthServer.SetServingStatus("ecommerce.v1.UserService", grpc_health_v1.HealthCheckResponse_SERVING)
    grpc_health_v1.RegisterHealthServer(s, healthServer)

    // ... start server ...
}
```

## Performance Optimization

### Connection Pooling
```javascript
const grpc = require('@grpc/grpc-js');

class ConnectionPool {
  constructor(addresses, options = {}) {
    this.addresses = addresses;
    this.options = {
      'grpc.max_receive_message_length': 1024 * 1024 * 100, // 100MB
      'grpc.max_send_message_length': 1024 * 1024 * 100,
      'grpc.keepalive_time_ms': 30000,
      'grpc.keepalive_timeout_ms': 5000,
      'grpc.http2.max_pings_without_data': 0,
      ...options,
    };

    this.pool = new Map();
    this.initializePool();
  }

  initializePool() {
    this.addresses.forEach(address => {
      const client = new grpc.Client(address, grpc.credentials.createInsecure(), this.options);
      this.pool.set(address, client);
    });
  }

  getClient(serviceName) {
    // Round-robin or other load balancing strategy
    const address = this.addresses[Math.floor(Math.random() * this.addresses.length)];
    return this.pool.get(address);
  }
}
```

### Compression
```go
server := grpc.NewServer(
    grpc.RPCCompressor(grpc.NewGZIPCompressor()),
    grpc.RPCDecompressor(grpc.NewGZIPDecompressor()),
    grpc.UnaryInterceptor(compressionInterceptor),
)

func compressionInterceptor(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
    // Enable compression for large responses
    if shouldCompressResponse(req) {
        // Set compression in response metadata
        grpc.SetHeader(ctx, metadata.Pairs("grpc-encoding", "gzip"))
    }
    return handler(ctx, req)
}
```

## Testing

### Unit Testing Services
```go
func TestCreateUser(t *testing.T) {
    // Create mock store
    mockStore := &MockUserStore{}
    mockStore.On("GetByEmail", mock.Anything, "john@example.com").Return(nil, nil)
    mockStore.On("Create", mock.Anything, mock.AnythingOfType("*User")).Return(&User{
        ID:    "123",
        Email: "john@example.com",
        Name:  "John Doe",
    }, nil)

    // Create server
    server := &userServer{userStore: mockStore}

    // Test request
    req := &pb.CreateUserRequest{
        Email:    "john@example.com",
        Name:     "John Doe",
        Password: "password123",
    }

    resp, err := server.CreateUser(context.Background(), req)

    assert.NoError(t, err)
    assert.Equal(t, "John Doe", resp.User.Name)
    mockStore.AssertExpectations(t)
}
```

### Integration Testing
```go
func TestUserServiceIntegration(t *testing.T) {
    // Start test server
    lis, err := net.Listen("tcp", ":0") // Random port
    require.NoError(t, err)

    s := grpc.NewServer()
    pb.RegisterUserServiceServer(s, &userServer{
        userStore: NewInMemoryUserStore(),
    })

    go s.Serve(lis)
    defer s.Stop()

    // Create client
    conn, err := grpc.Dial(lis.Addr().String(), grpc.WithTransportCredentials(insecure.NewCredentials()))
    require.NoError(t, err)
    defer conn.Close()

    client := pb.NewUserServiceClient(conn)

    // Test full workflow
    createResp, err := client.CreateUser(context.Background(), &pb.CreateUserRequest{
        Email:    "john@example.com",
        Name:     "John Doe",
        Password: "password123",
    })
    require.NoError(t, err)

    getResp, err := client.GetUser(context.Background(), &pb.GetUserRequest{
        UserId: createResp.User.UserId,
    })
    require.NoError(t, err)
    assert.Equal(t, "John Doe", getResp.User.Name)
}
```

## Best Practices

### Schema Design
1. **Use meaningful message names** and field descriptions
2. **Version your APIs** with package names (v1, v2, etc.)
3. **Keep messages small** and focused on specific use cases
4. **Use enums** for constrained values instead of strings
5. **Document field meanings** with comments

### Performance
1. **Enable compression** for large messages
2. **Use streaming** for large datasets or real-time features
3. **Implement connection pooling** for high-throughput clients
4. **Monitor performance** with metrics and tracing
5. **Use appropriate timeouts** to prevent hanging requests

### Security
1. **Use TLS encryption** in production
2. **Implement authentication** and authorization
3. **Validate input data** thoroughly
4. **Rate limit requests** to prevent abuse
5. **Log security events** for audit trails

### Error Handling
1. **Use appropriate gRPC status codes**
2. **Provide meaningful error messages**
3. **Include error details** in metadata when appropriate
4. **Handle network errors** gracefully with retries
5. **Log errors** for debugging and monitoring

This gRPC implementation provides a complete foundation for building high-performance, scalable, and reliable microservices with modern patterns and best practices.
