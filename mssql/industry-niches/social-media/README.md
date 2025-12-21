# Social Media Platform Database Design

## Overview

This comprehensive database schema supports modern social media platforms including user-generated content, real-time feeds, social networking, content moderation, and advertising systems. The design handles massive-scale user interactions, complex content relationships, real-time analytics, and enterprise-level content management.

## Key Features

### 👥 User Management & Social Networks
- **User profiles and authentication** with social login integration
- **Complex social relationships** including friends, followers, groups, and communities
- **Privacy controls** with granular permission settings
- **User-generated content** with multimedia support and rich metadata

### 📱 Content & Feed Management
- **Real-time content feeds** with algorithmic ranking and personalization
- **Multi-format content support** (text, images, videos, live streams, stories)
- **Content interaction systems** with likes, comments, shares, and reactions
- **Advanced content discovery** with hashtags, trending topics, and recommendations

### 🛡️ Moderation & Safety
- **Automated content moderation** with AI-powered filtering and classification
- **Community guidelines enforcement** with reporting and review workflows
- **User safety features** including blocking, muting, and harassment prevention
- **Regulatory compliance** with data retention and content archiving

## Database Schema Highlights

### Core Tables

#### User Management
```sql
-- User master table with comprehensive profile data
CREATE TABLE Users (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    Username NVARCHAR(50) UNIQUE NOT NULL,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    PasswordHash NVARCHAR(255),
    DisplayName NVARCHAR(100),
    FirstName NVARCHAR(50),
    LastName NVARCHAR(50),
    Bio NVARCHAR(MAX),
    Website NVARCHAR(500),
    ProfilePictureURL NVARCHAR(500),
    CoverPhotoURL NVARCHAR(500),
    Location NVARCHAR(100),
    Birthday DATE,
    Gender NVARCHAR(20),
    IsVerified BIT DEFAULT 0,
    IsPrivate BIT DEFAULT 0,
    AccountStatus NVARCHAR(20) DEFAULT 'Active',
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    LastLoginDate DATETIME2,
    EmailVerified BIT DEFAULT 0,

    -- Privacy settings (JSON)
    PrivacySettings NVARCHAR(MAX), -- {"profile_visibility": "public", "message_privacy": "friends"}

    -- Constraints
    CONSTRAINT CK_Users_Status CHECK (AccountStatus IN ('Active', 'Suspended', 'Deactivated', 'Banned')),
    CONSTRAINT CK_Users_Username CHECK (LEN(Username) >= 3),

    -- Indexes
    INDEX IX_Users_Username (Username),
    INDEX IX_Users_Email (Email),
    INDEX IX_Users_DisplayName (DisplayName),
    INDEX IX_Users_IsVerified (IsVerified),
    INDEX IX_Users_Status (AccountStatus),
    INDEX IX_Users_CreatedDate (CreatedDate)
);

-- User sessions for authentication and tracking
CREATE TABLE UserSessions (
    SessionID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NOT NULL REFERENCES Users(UserID) ON DELETE CASCADE,
    SessionToken NVARCHAR(255) UNIQUE NOT NULL,
    IPAddress NVARCHAR(45),
    UserAgent NVARCHAR(500),
    DeviceType NVARCHAR(50),
    Location NVARCHAR(100),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    ExpiresDate DATETIME2,
    IsActive BIT DEFAULT 1,

    -- Indexes
    INDEX IX_UserSessions_User (UserID),
    INDEX IX_UserSessions_Token (SessionToken),
    INDEX IX_UserSessions_Expires (ExpiresDate),
    INDEX IX_UserSessions_IsActive (IsActive)
);
```

#### Social Relationships
```sql
-- Follower relationships
CREATE TABLE Followers (
    FollowerID INT NOT NULL REFERENCES Users(UserID),
    FollowingID INT NOT NULL REFERENCES Users(UserID),
    FollowDate DATETIME2 DEFAULT GETDATE(),
    IsAccepted BIT DEFAULT 1, -- For private accounts requiring approval

    -- Constraints
    CONSTRAINT PK_Followers PRIMARY KEY (FollowerID, FollowingID),
    CONSTRAINT CK_Followers_Self CHECK (FollowerID != FollowingID),

    -- Indexes
    INDEX IX_Followers_Following (FollowingID),
    INDEX IX_Followers_Date (FollowDate),
    INDEX IX_Followers_IsAccepted (IsAccepted)
);

-- Friend relationships (mutual follows with additional features)
CREATE TABLE Friendships (
    UserID1 INT NOT NULL REFERENCES Users(UserID),
    UserID2 INT NOT NULL REFERENCES Users(UserID),
    FriendshipDate DATETIME2 DEFAULT GETDATE(),
    Status NVARCHAR(20) DEFAULT 'Accepted', -- Pending, Accepted, Blocked
    InitiatedBy INT NOT NULL REFERENCES Users(UserID),

    -- Constraints
    CONSTRAINT PK_Friendships PRIMARY KEY (UserID1, UserID2),
    CONSTRAINT CK_Friendships_Order CHECK (UserID1 < UserID2), -- Prevent duplicates
    CONSTRAINT CK_Friendships_Self CHECK (UserID1 != UserID2),
    CONSTRAINT CK_Friendships_Status CHECK (Status IN ('Pending', 'Accepted', 'Blocked')),

    -- Indexes
    INDEX IX_Friendships_User2 (UserID2),
    INDEX IX_Friendships_Status (Status),
    INDEX IX_Friendships_Date (FriendshipDate)
);

-- User groups/communities
CREATE TABLE Groups (
    GroupID INT IDENTITY(1,1) PRIMARY KEY,
    GroupName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),
    GroupType NVARCHAR(20) DEFAULT 'Public', -- Public, Private, Secret
    CreatedBy INT NOT NULL REFERENCES Users(UserID),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CoverPhotoURL NVARCHAR(500),
    MemberCount INT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    -- Group settings (JSON)
    Settings NVARCHAR(MAX), -- {"post_approval": false, "join_approval": true}

    -- Constraints
    CONSTRAINT CK_Groups_Type CHECK (GroupType IN ('Public', 'Private', 'Secret')),

    -- Indexes
    INDEX IX_Groups_CreatedBy (CreatedBy),
    INDEX IX_Groups_Type (GroupType),
    INDEX IX_Groups_IsActive (IsActive),
    INDEX IX_Groups_MemberCount (MemberCount)
);

-- Group memberships
CREATE TABLE GroupMembers (
    GroupID INT NOT NULL REFERENCES Groups(GroupID) ON DELETE CASCADE,
    UserID INT NOT NULL REFERENCES Users(UserID) ON DELETE CASCADE,
    Role NVARCHAR(20) DEFAULT 'Member', -- Owner, Admin, Moderator, Member
    JoinedDate DATETIME2 DEFAULT GETDATE(),
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT PK_GroupMembers PRIMARY KEY (GroupID, UserID),
    CONSTRAINT CK_GroupMembers_Role CHECK (Role IN ('Owner', 'Admin', 'Moderator', 'Member')),

    -- Indexes
    INDEX IX_GroupMembers_User (UserID),
    INDEX IX_GroupMembers_Role (Role),
    INDEX IX_GroupMembers_IsActive (IsActive)
);
```

### Content Management

#### Posts & Content
```sql
-- Posts master table
CREATE TABLE Posts (
    PostID INT IDENTITY(1,1) PRIMARY KEY,
    AuthorID INT NOT NULL REFERENCES Users(UserID),
    Content NVARCHAR(MAX),
    ContentType NVARCHAR(20) DEFAULT 'Text', -- Text, Image, Video, Link, Poll
    Visibility NVARCHAR(20) DEFAULT 'Public', -- Public, Friends, Private
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    UpdatedDate DATETIME2 DEFAULT GETDATE(),
    Location NVARCHAR(100),
    IsPinned BIT DEFAULT 0,
    IsDeleted BIT DEFAULT 0,
    DeletedDate DATETIME2,
    ScheduledDate DATETIME2,

    -- Engagement metrics
    LikeCount INT DEFAULT 0,
    CommentCount INT DEFAULT 0,
    ShareCount INT DEFAULT 0,
    ViewCount INT DEFAULT 0,

    -- Moderation
    ModerationStatus NVARCHAR(20) DEFAULT 'Approved', -- Pending, Approved, Rejected, Flagged
    ModeratedBy INT REFERENCES Users(UserID),
    ModeratedDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_Posts_ContentType CHECK (ContentType IN ('Text', 'Image', 'Video', 'Link', 'Poll', 'Live')),
    CONSTRAINT CK_Posts_Visibility CHECK (Visibility IN ('Public', 'Friends', 'Private')),
    CONSTRAINT CK_Posts_Moderation CHECK (ModerationStatus IN ('Pending', 'Approved', 'Rejected', 'Flagged')),

    -- Indexes
    INDEX IX_Posts_Author (AuthorID),
    INDEX IX_Posts_Type (ContentType),
    INDEX IX_Posts_Visibility (Visibility),
    INDEX IX_Posts_CreatedDate (CreatedDate),
    INDEX IX_Posts_IsPinned (IsPinned),
    INDEX IX_Posts_IsDeleted (IsDeleted),
    INDEX IX_Posts_ModerationStatus (ModerationStatus)
);

-- Post media attachments
CREATE TABLE PostMedia (
    MediaID INT IDENTITY(1,1) PRIMARY KEY,
    PostID INT NOT NULL REFERENCES Posts(PostID) ON DELETE CASCADE,
    MediaType NVARCHAR(20) NOT NULL, -- Image, Video, Audio, Document
    MediaURL NVARCHAR(500) NOT NULL,
    ThumbnailURL NVARCHAR(500),
    FileSize BIGINT,
    DurationSeconds INT, -- For videos/audio
    Width INT,
    Height INT,
    AltText NVARCHAR(500),
    DisplayOrder INT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_PostMedia_Type CHECK (MediaType IN ('Image', 'Video', 'Audio', 'Document')),

    -- Indexes
    INDEX IX_PostMedia_Post (PostID),
    INDEX IX_PostMedia_Type (MediaType),
    INDEX IX_PostMedia_Order (DisplayOrder)
);

-- Hashtags and mentions
CREATE TABLE Hashtags (
    HashtagID INT IDENTITY(1,1) PRIMARY KEY,
    Tag NVARCHAR(100) UNIQUE NOT NULL,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    UsageCount INT DEFAULT 0,
    IsTrending BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_Hashtags_Tag CHECK (Tag LIKE '#%'),

    -- Indexes
    INDEX IX_Hashtags_Tag (Tag),
    INDEX IX_Hashtags_UsageCount (UsageCount),
    INDEX IX_Hashtags_IsTrending (IsTrending)
);

-- Post hashtags mapping
CREATE TABLE PostHashtags (
    PostID INT NOT NULL REFERENCES Posts(PostID) ON DELETE CASCADE,
    HashtagID INT NOT NULL REFERENCES Hashtags(HashtagID) ON DELETE CASCADE,

    -- Constraints
    CONSTRAINT PK_PostHashtags PRIMARY KEY (PostID, HashtagID),

    -- Indexes
    INDEX IX_PostHashtags_Hashtag (HashtagID)
);

-- User mentions in posts
CREATE TABLE PostMentions (
    MentionID INT IDENTITY(1,1) PRIMARY KEY,
    PostID INT NOT NULL REFERENCES Posts(PostID) ON DELETE CASCADE,
    MentionedUserID INT NOT NULL REFERENCES Users(UserID),
    MentionPosition INT, -- Position in content for highlighting

    -- Indexes
    INDEX IX_PostMentions_Post (PostID),
    INDEX IX_PostMentions_User (MentionedUserID)
);
```

#### Interactions & Engagement
```sql
-- Likes/reactions
CREATE TABLE PostLikes (
    LikeID INT IDENTITY(1,1) PRIMARY KEY,
    PostID INT NOT NULL REFERENCES Posts(PostID) ON DELETE CASCADE,
    UserID INT NOT NULL REFERENCES Users(UserID),
    ReactionType NVARCHAR(20) DEFAULT 'Like', -- Like, Love, Haha, Wow, Sad, Angry
    CreatedDate DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT PK_PostLikes PRIMARY KEY (PostID, UserID), -- One reaction per user per post
    CONSTRAINT CK_PostLikes_Reaction CHECK (ReactionType IN ('Like', 'Love', 'Haha', 'Wow', 'Sad', 'Angry')),

    -- Indexes
    INDEX IX_PostLikes_User (UserID),
    INDEX IX_PostLikes_Reaction (ReactionType),
    INDEX IX_PostLikes_Date (CreatedDate)
);

-- Comments
CREATE TABLE Comments (
    CommentID INT IDENTITY(1,1) PRIMARY KEY,
    PostID INT NOT NULL REFERENCES Posts(PostID) ON DELETE CASCADE,
    AuthorID INT NOT NULL REFERENCES Users(UserID),
    ParentCommentID INT REFERENCES Comments(CommentID), -- For nested replies
    Content NVARCHAR(MAX) NOT NULL,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    UpdatedDate DATETIME2 DEFAULT GETDATE(),
    IsDeleted BIT DEFAULT 0,
    LikeCount INT DEFAULT 0,

    -- Moderation
    ModerationStatus NVARCHAR(20) DEFAULT 'Approved',
    ModeratedBy INT REFERENCES Users(UserID),
    ModeratedDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_Comments_Moderation CHECK (ModerationStatus IN ('Pending', 'Approved', 'Rejected', 'Flagged')),

    -- Indexes
    INDEX IX_Comments_Post (PostID),
    INDEX IX_Comments_Author (AuthorID),
    INDEX IX_Comments_Parent (ParentCommentID),
    INDEX IX_Comments_IsDeleted (IsDeleted),
    INDEX IX_Comments_ModerationStatus (ModerationStatus)
);

-- Shares/retweets
CREATE TABLE PostShares (
    ShareID INT IDENTITY(1,1) PRIMARY KEY,
    OriginalPostID INT NOT NULL REFERENCES Posts(PostID),
    SharedByUserID INT NOT NULL REFERENCES Users(UserID),
    ShareType NVARCHAR(20) DEFAULT 'Share', -- Share, Repost, Quote
    ShareText NVARCHAR(MAX),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    Visibility NVARCHAR(20) DEFAULT 'Public',

    -- Indexes
    INDEX IX_PostShares_Original (OriginalPostID),
    INDEX IX_PostShares_User (SharedByUserID),
    INDEX IX_PostShares_Type (ShareType),
    INDEX IX_PostShares_Date (CreatedDate)
);

-- Bookmarks/saves
CREATE TABLE PostBookmarks (
    BookmarkID INT IDENTITY(1,1) PRIMARY KEY,
    PostID INT NOT NULL REFERENCES Posts(PostID) ON DELETE CASCADE,
    UserID INT NOT NULL REFERENCES Users(UserID),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    CollectionName NVARCHAR(100), -- For organizing bookmarks

    -- Constraints
    CONSTRAINT PK_PostBookmarks PRIMARY KEY (PostID, UserID),

    -- Indexes
    INDEX IX_PostBookmarks_User (UserID),
    INDEX IX_PostBookmarks_Date (CreatedDate),
    INDEX IX_PostBookmarks_Collection (CollectionName)
);
```

### Feed & Discovery

#### User Feeds & Timelines
```sql
-- User feed items (materialized view of posts for each user)
CREATE TABLE UserFeed (
    FeedID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NOT NULL REFERENCES Users(UserID) ON DELETE CASCADE,
    PostID INT NOT NULL REFERENCES Posts(PostID) ON DELETE CASCADE,
    FeedType NVARCHAR(20) NOT NULL, -- Following, Trending, Recommended, Sponsored
    RelevanceScore DECIMAL(5,4) DEFAULT 1.0,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    IsRead BIT DEFAULT 0,
    IsHidden BIT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_UserFeed_Type CHECK (FeedType IN ('Following', 'Trending', 'Recommended', 'Sponsored', 'Group')),

    -- Indexes
    INDEX IX_UserFeed_User (UserID),
    INDEX IX_UserFeed_Post (PostID),
    INDEX IX_UserFeed_Type (FeedType),
    INDEX IX_UserFeed_Relevance (RelevanceScore DESC),
    INDEX IX_UserFeed_IsRead (IsRead),
    INDEX IX_UserFeed_IsHidden (IsHidden)
);

-- Trending topics and hashtags
CREATE TABLE TrendingTopics (
    TrendID INT IDENTITY(1,1) PRIMARY KEY,
    Topic NVARCHAR(200) NOT NULL,
    TopicType NVARCHAR(20) DEFAULT 'Hashtag', -- Hashtag, Keyword, Topic
    PostCount INT DEFAULT 0,
    UniqueUsers INT DEFAULT 0,
    TrendScore DECIMAL(10,2) DEFAULT 0,
    Rank INT,
    Location NVARCHAR(100), -- Geographic restriction
    StartDate DATETIME2 DEFAULT GETDATE(),
    PeakDate DATETIME2,
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_TrendingTopics_Type CHECK (TopicType IN ('Hashtag', 'Keyword', 'Topic')),

    -- Indexes
    INDEX IX_TrendingTopics_Topic (Topic),
    INDEX IX_TrendingTopics_Type (TopicType),
    INDEX IX_TrendingTopics_Score (TrendScore DESC),
    INDEX IX_TrendingTopics_IsActive (IsActive),
    INDEX IX_TrendingTopics_StartDate (StartDate)
);
```

### Moderation & Safety

#### Content Moderation
```sql
-- Content reports
CREATE TABLE ContentReports (
    ReportID INT IDENTITY(1,1) PRIMARY KEY,
    ReportedByUserID INT NOT NULL REFERENCES Users(UserID),
    ContentType NVARCHAR(20) NOT NULL, -- Post, Comment, User, Group
    ContentID INT NOT NULL, -- PostID, CommentID, UserID, or GroupID
    ReportType NVARCHAR(50) NOT NULL, -- Harassment, Spam, Hate Speech, etc.
    Description NVARCHAR(MAX),
    Severity NVARCHAR(20) DEFAULT 'Medium', -- Low, Medium, High, Critical
    Status NVARCHAR(20) DEFAULT 'Pending', -- Pending, Under Review, Resolved, Dismissed
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    ReviewedBy INT REFERENCES Users(UserID),
    ReviewedDate DATETIME2,
    Resolution NVARCHAR(MAX),

    -- Constraints
    CONSTRAINT CK_ContentReports_ContentType CHECK (ContentType IN ('Post', 'Comment', 'User', 'Group')),
    CONSTRAINT CK_ContentReports_Severity CHECK (Severity IN ('Low', 'Medium', 'High', 'Critical')),
    CONSTRAINT CK_ContentReports_Status CHECK (Status IN ('Pending', 'Under Review', 'Resolved', 'Dismissed')),

    -- Indexes
    INDEX IX_ContentReports_ReportedBy (ReportedByUserID),
    INDEX IX_ContentReports_ContentType (ContentType),
    INDEX IX_ContentReports_Status (Status),
    INDEX IX_ContentReports_CreatedDate (CreatedDate),
    INDEX IX_ContentReports_Severity (Severity)
);

-- Moderation queue
CREATE TABLE ModerationQueue (
    QueueID INT IDENTITY(1,1) PRIMARY KEY,
    ContentType NVARCHAR(20) NOT NULL,
    ContentID INT NOT NULL,
    Priority NVARCHAR(20) DEFAULT 'Normal', -- Low, Normal, High, Urgent
    ModerationReason NVARCHAR(MAX),
    AssignedTo INT REFERENCES Users(UserID),
    AssignedDate DATETIME2,
    CompletedDate DATETIME2,
    Status NVARCHAR(20) DEFAULT 'Queued', -- Queued, In Progress, Completed
    ActionTaken NVARCHAR(100), -- Approved, Rejected, Edited, Removed

    -- Constraints
    CONSTRAINT CK_ModerationQueue_ContentType CHECK (ContentType IN ('Post', 'Comment', 'User', 'Group')),
    CONSTRAINT CK_ModerationQueue_Priority CHECK (Priority IN ('Low', 'Normal', 'High', 'Urgent')),
    CONSTRAINT CK_ModerationQueue_Status CHECK (Status IN ('Queued', 'In Progress', 'Completed')),

    -- Indexes
    INDEX IX_ModerationQueue_AssignedTo (AssignedTo),
    INDEX IX_ModerationQueue_Status (Status),
    INDEX IX_ModerationQueue_Priority (Priority),
    INDEX IX_ModerationQueue_AssignedDate (AssignedDate)
);

-- Blocked content and users
CREATE TABLE Blocks (
    BlockID INT IDENTITY(1,1) PRIMARY KEY,
    BlockerUserID INT NOT NULL REFERENCES Users(UserID),
    BlockedUserID INT REFERENCES Users(UserID),
    BlockedContentType NVARCHAR(20), -- User, Post, Hashtag, Keyword
    BlockedContentID INT, -- UserID, PostID, HashtagID, or keyword ID
    BlockedValue NVARCHAR(500), -- For keywords/hashtags
    BlockReason NVARCHAR(MAX),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    ExpiresDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_Blocks_ContentType CHECK (BlockedContentType IN ('User', 'Post', 'Hashtag', 'Keyword')),

    -- Indexes
    INDEX IX_Blocks_Blocker (BlockerUserID),
    INDEX IX_Blocks_BlockedUser (BlockedUserID),
    INDEX IX_Blocks_ContentType (BlockedContentType),
    INDEX IX_Blocks_Expires (ExpiresDate)
);
```

### Analytics & Advertising

#### Content Analytics
```sql
-- Post analytics
CREATE TABLE PostAnalytics (
    AnalyticsID INT IDENTITY(1,1) PRIMARY KEY,
    PostID INT NOT NULL REFERENCES Posts(PostID) ON DELETE CASCADE,
    Date DATE NOT NULL,
    Views INT DEFAULT 0,
    UniqueViews INT DEFAULT 0,
    Likes INT DEFAULT 0,
    Comments INT DEFAULT 0,
    Shares INT DEFAULT 0,
    Saves INT DEFAULT 0,
    ClickThroughs INT DEFAULT 0,
    TimeSpentSeconds INT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_PostAnalytics_PostDate UNIQUE (PostID, Date),

    -- Indexes
    INDEX IX_PostAnalytics_Post (PostID),
    INDEX IX_PostAnalytics_Date (Date)
);

-- User engagement analytics
CREATE TABLE UserEngagement (
    EngagementID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NOT NULL REFERENCES Users(UserID),
    Date DATE NOT NULL,
    PostsCreated INT DEFAULT 0,
    CommentsMade INT DEFAULT 0,
    LikesGiven INT DEFAULT 0,
    SharesMade INT DEFAULT 0,
    TimeSpentMinutes INT DEFAULT 0,
    SessionsCount INT DEFAULT 0,
    ContentInteractions INT DEFAULT 0,

    -- Constraints
    CONSTRAINT UQ_UserEngagement_UserDate UNIQUE (UserID, Date),

    -- Indexes
    INDEX IX_UserEngagement_User (UserID),
    INDEX IX_UserEngagement_Date (Date)
);
```

## Integration Points

### External Systems
- **Authentication providers**: OAuth integration with Google, Facebook, Apple
- **Content delivery networks**: Cloudflare, Akamai for media delivery
- **Email services**: SendGrid, Mailgun for notifications and marketing
- **Payment processors**: For creator monetization and advertising
- **Analytics platforms**: Google Analytics, Mixpanel for user behavior
- **Moderation services**: AI-powered content moderation APIs

### API Endpoints
- **User Management APIs**: Authentication, profiles, privacy settings
- **Content APIs**: Posts, comments, media uploads, feed generation
- **Social APIs**: Following, friendships, groups, messaging
- **Moderation APIs**: Content reporting, review workflows, user safety
- **Analytics APIs**: Engagement metrics, trending content, user insights

## Monitoring & Analytics

### Key Performance Indicators
- **User engagement**: Daily active users, session duration, content interactions
- **Content metrics**: Post reach, engagement rates, viral coefficient
- **Community health**: Harassment reports, blocked users, community guidelines compliance
- **Platform growth**: User acquisition, retention rates, network effects
- **Monetization**: Ad impressions, creator revenue, platform revenue

### Real-Time Dashboards
```sql
-- Social media operations dashboard
CREATE VIEW SocialMediaDashboard AS
SELECT
    -- User metrics (current day)
    (SELECT COUNT(*) FROM UserSessions WHERE CAST(CreatedDate AS DATE) = CAST(GETDATE() AS DATE)) AS DailyActiveUsers,
    (SELECT COUNT(*) FROM Users WHERE CAST(CreatedDate AS DATE) = CAST(GETDATE() AS DATE)) AS NewUsersToday,
    (SELECT COUNT(*) FROM Posts WHERE CAST(CreatedDate AS DATE) = CAST(GETDATE() AS DATE)) AS PostsCreatedToday,

    -- Content engagement (current day)
    (SELECT SUM(LikeCount) FROM Posts WHERE CAST(CreatedDate AS DATE) = CAST(GETDATE() AS DATE)) AS LikesToday,
    (SELECT SUM(CommentCount) FROM Posts WHERE CAST(CreatedDate AS DATE) = CAST(GETDATE() AS DATE)) AS CommentsToday,
    (SELECT SUM(ShareCount) FROM Posts WHERE CAST(CreatedDate AS DATE) = CAST(GETDATE() AS DATE)) AS SharesToday,

    -- Moderation metrics
    (SELECT COUNT(*) FROM ContentReports WHERE Status = 'Pending') AS PendingReports,
    (SELECT COUNT(*) FROM ModerationQueue WHERE Status = 'Queued') AS ItemsInModerationQueue,
    (SELECT COUNT(*) FROM Posts WHERE ModerationStatus = 'Flagged') AS FlaggedContent,

    -- Trending content
    (SELECT COUNT(*) FROM TrendingTopics WHERE IsActive = 1) AS ActiveTrends,
    (SELECT TOP 1 Topic FROM TrendingTopics WHERE IsActive = 1 ORDER BY TrendScore DESC) AS TopTrend,

    -- Community health
    (SELECT COUNT(*) FROM Blocks WHERE ExpiresDate IS NULL OR ExpiresDate > GETDATE()) AS ActiveBlocks,
    (SELECT COUNT(DISTINCT BlockerUserID) FROM Blocks WHERE CAST(CreatedDate AS DATE) = CAST(GETDATE() AS DATE)) AS UsersBlockingToday,

    -- Platform performance
    (SELECT AVG(CAST(LikeCount + CommentCount + ShareCount AS DECIMAL(10,2))) FROM Posts
     WHERE CAST(CreatedDate AS DATE) = CAST(GETDATE() AS DATE)) AS AvgEngagementRate,

    -- Safety metrics
    (SELECT COUNT(*) FROM Users WHERE AccountStatus = 'Suspended') AS SuspendedAccounts,
    (SELECT COUNT(*) FROM Users WHERE AccountStatus = 'Banned') AS BannedAccounts

FROM (SELECT 1 AS Dummy) AS DummyTable;
GO
```

This social media database schema provides a comprehensive foundation for modern social platforms, supporting user engagement, content management, community features, and enterprise-level moderation while maintaining high performance and data integrity.
