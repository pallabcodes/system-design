-- Social Media Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE SocialMediaDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE SocialMediaDB;
GO

-- Configure database for social media performance
ALTER DATABASE SocialMediaDB
SET
    RECOVERY SIMPLE,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON,
    QUERY_STORE = ON; -- Enable query performance monitoring
GO

-- =============================================
-- USER MANAGEMENT
-- =============================================

-- User master table
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

-- User sessions
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

-- =============================================
-- SOCIAL RELATIONSHIPS
-- =============================================

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

-- Friend relationships
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

-- User groups
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

-- =============================================
-- CONTENT MANAGEMENT
-- =============================================

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

-- Hashtags
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

-- User mentions
CREATE TABLE PostMentions (
    MentionID INT IDENTITY(1,1) PRIMARY KEY,
    PostID INT NOT NULL REFERENCES Posts(PostID) ON DELETE CASCADE,
    MentionedUserID INT NOT NULL REFERENCES Users(UserID),
    MentionPosition INT, -- Position in content for highlighting

    -- Indexes
    INDEX IX_PostMentions_Post (PostID),
    INDEX IX_PostMentions_User (MentionedUserID)
);

-- =============================================
-- INTERACTIONS & ENGAGEMENT
-- =============================================

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

-- Shares
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

-- Bookmarks
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

-- =============================================
-- FEED & DISCOVERY
-- =============================================

-- User feed items
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

-- Trending topics
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

-- =============================================
-- MODERATION & SAFETY
-- =============================================

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

-- Blocks
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

-- =============================================
-- ANALYTICS & REPORTING
-- =============================================

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

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- User profile view
CREATE VIEW vw_UserProfile
AS
SELECT
    u.UserID,
    u.Username,
    u.DisplayName,
    u.Bio,
    u.ProfilePictureURL,
    u.IsVerified,
    u.IsPrivate,
    u.CreatedDate,
    COUNT(DISTINCT f1.FollowingID) AS FollowingCount,
    COUNT(DISTINCT f2.FollowerID) AS FollowersCount,
    COUNT(DISTINCT p.PostID) AS PostsCount,
    MAX(p.CreatedDate) AS LastPostDate
FROM Users u
LEFT JOIN Followers f1 ON u.UserID = f1.FollowerID AND f1.IsAccepted = 1
LEFT JOIN Followers f2 ON u.UserID = f2.FollowingID AND f2.IsAccepted = 1
LEFT JOIN Posts p ON u.UserID = p.AuthorID AND p.IsDeleted = 0 AND p.ModerationStatus = 'Approved'
WHERE u.AccountStatus = 'Active'
GROUP BY u.UserID, u.Username, u.DisplayName, u.Bio, u.ProfilePictureURL,
         u.IsVerified, u.IsPrivate, u.CreatedDate;
GO

-- Post details view
CREATE VIEW vw_PostDetails
AS
SELECT
    p.PostID,
    p.AuthorID,
    u.Username,
    u.DisplayName,
    u.ProfilePictureURL,
    p.Content,
    p.ContentType,
    p.Visibility,
    p.CreatedDate,
    p.LikeCount,
    p.CommentCount,
    p.ShareCount,
    p.ViewCount,
    p.IsPinned,
    p.ModerationStatus,
    (
        SELECT STRING_AGG('#' + h.Tag, ' ')
        FROM PostHashtags ph
        INNER JOIN Hashtags h ON ph.HashtagID = h.HashtagID
        WHERE ph.PostID = p.PostID
    ) AS Hashtags
FROM Posts p
INNER JOIN Users u ON p.AuthorID = u.UserID
WHERE p.IsDeleted = 0;
GO

-- =============================================
-- TRIGGERS FOR DATA INTEGRITY
-- =============================================

-- Update post engagement counts
CREATE TRIGGER TR_PostLikes_UpdateCount
ON PostLikes
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE p
    SET p.LikeCount = (
        SELECT COUNT(*) FROM PostLikes pl WHERE pl.PostID = p.PostID
    )
    FROM Posts p
    WHERE p.PostID IN (
        SELECT DISTINCT PostID FROM inserted
        UNION
        SELECT DISTINCT PostID FROM deleted
    );
END;
GO

-- Update comment counts
CREATE TRIGGER TR_Comments_UpdateCount
ON Comments
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE p
    SET p.CommentCount = (
        SELECT COUNT(*) FROM Comments c
        WHERE c.PostID = p.PostID AND c.IsDeleted = 0
    )
    FROM Posts p
    WHERE p.PostID IN (
        SELECT DISTINCT PostID FROM inserted
        UNION
        SELECT DISTINCT PostID FROM deleted
    );
END;
GO

-- Update hashtag usage counts
CREATE TRIGGER TR_PostHashtags_UpdateCount
ON PostHashtags
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE h
    SET h.UsageCount = (
        SELECT COUNT(*) FROM PostHashtags ph WHERE ph.HashtagID = h.HashtagID
    )
    FROM Hashtags h
    WHERE h.HashtagID IN (
        SELECT DISTINCT HashtagID FROM inserted
        UNION
        SELECT DISTINCT HashtagID FROM deleted
    );
END;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Create post procedure
CREATE PROCEDURE sp_CreatePost
    @AuthorID INT,
    @Content NVARCHAR(MAX),
    @ContentType NVARCHAR(20) = 'Text',
    @Visibility NVARCHAR(20) = 'Public',
    @Location NVARCHAR(100) = NULL,
    @ScheduledDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Posts (
        AuthorID, Content, ContentType, Visibility, Location, ScheduledDate
    )
    VALUES (
        @AuthorID, @Content, @ContentType, @Visibility, @Location, @ScheduledDate
    );

    SELECT SCOPE_IDENTITY() AS PostID;
END;
GO

-- Get user feed procedure
CREATE PROCEDURE sp_GetUserFeed
    @UserID INT,
    @PageNumber INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Offset INT = (@PageNumber - 1) * @PageSize;

    SELECT
        uf.FeedID,
        p.PostID,
        p.Content,
        p.ContentType,
        p.CreatedDate,
        u.Username,
        u.DisplayName,
        u.ProfilePictureURL,
        uf.FeedType,
        uf.RelevanceScore
    FROM UserFeed uf
    INNER JOIN Posts p ON uf.PostID = p.PostID
    INNER JOIN Users u ON p.AuthorID = u.UserID
    WHERE uf.UserID = @UserID
    AND uf.IsHidden = 0
    AND p.IsDeleted = 0
    AND p.ModerationStatus = 'Approved'
    ORDER BY uf.RelevanceScore DESC, uf.CreatedDate DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample users
INSERT INTO Users (Username, Email, DisplayName, Bio) VALUES
('johndoe', 'john@example.com', 'John Doe', 'Tech enthusiast'),
('janedoe', 'jane@example.com', 'Jane Doe', 'Content creator');

-- Insert sample posts
INSERT INTO Posts (AuthorID, Content, ContentType) VALUES
(1, 'Hello world! This is my first post.', 'Text'),
(2, 'Check out this amazing photo!', 'Image');

-- Insert sample likes
INSERT INTO PostLikes (PostID, UserID) VALUES
(1, 2),
(2, 1);

-- Insert sample hashtags
INSERT INTO Hashtags (Tag) VALUES
('#FirstPost'), ('#HelloWorld');

-- Link hashtags to posts
INSERT INTO PostHashtags (PostID, HashtagID) VALUES
(1, 1), (1, 2);

PRINT 'Social Media database schema created successfully!';
GO
