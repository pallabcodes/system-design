-- Gaming Platform Database Schema
-- Microsoft SQL Server Implementation

-- Create database
CREATE DATABASE GamingDB
COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE GamingDB;
GO

-- Configure database for gaming performance
ALTER DATABASE GamingDB
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
-- PLAYER MANAGEMENT
-- =============================================

-- Player master table
CREATE TABLE Players (
    PlayerID INT IDENTITY(1,1) PRIMARY KEY,
    Username NVARCHAR(50) UNIQUE NOT NULL,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    PasswordHash NVARCHAR(255),
    DisplayName NVARCHAR(100),
    AvatarURL NVARCHAR(500),
    Country NVARCHAR(2),
    Timezone NVARCHAR(50),
    PreferredLanguage NVARCHAR(10) DEFAULT 'en',
    RegistrationDate DATETIME2 DEFAULT GETDATE(),
    LastLoginDate DATETIME2,
    IsActive BIT DEFAULT 1,
    IsVerified BIT DEFAULT 0,
    AccountStatus NVARCHAR(20) DEFAULT 'Active',

    -- Game statistics
    TotalPlayTime INT DEFAULT 0, -- In minutes
    Level INT DEFAULT 1,
    ExperiencePoints BIGINT DEFAULT 0,
    SkillRating INT DEFAULT 1000,

    -- Constraints
    CONSTRAINT CK_Players_Status CHECK (AccountStatus IN ('Active', 'Suspended', 'Banned', 'Inactive')),
    CONSTRAINT CK_Players_Level CHECK (Level >= 1),
    CONSTRAINT CK_Players_Rating CHECK (SkillRating >= 0),

    -- Indexes
    INDEX IX_Players_Username (Username),
    INDEX IX_Players_Email (Email),
    INDEX IX_Players_Level (Level),
    INDEX IX_Players_Rating (SkillRating),
    INDEX IX_Players_Status (AccountStatus),
    INDEX IX_Players_LastLogin (LastLoginDate)
);

-- Player sessions
CREATE TABLE PlayerSessions (
    SessionID INT IDENTITY(1,1) PRIMARY KEY,
    PlayerID INT NOT NULL REFERENCES Players(PlayerID),
    SessionStart DATETIME2 DEFAULT GETDATE(),
    SessionEnd DATETIME2,
    DurationMinutes INT,
    IPAddress NVARCHAR(45),
    DeviceType NVARCHAR(50),
    GameVersion NVARCHAR(20),
    Platform NVARCHAR(20), -- PC, Console, Mobile
    Region NVARCHAR(50),

    -- Session statistics
    MatchesPlayed INT DEFAULT 0,
    Wins INT DEFAULT 0,
    Losses INT DEFAULT 0,
    Score INT DEFAULT 0,

    -- Indexes
    INDEX IX_PlayerSessions_Player (PlayerID),
    INDEX IX_PlayerSessions_Start (SessionStart),
    INDEX IX_PlayerSessions_End (SessionEnd),
    INDEX IX_PlayerSessions_Platform (Platform)
);

-- =============================================
-- GAME ECONOMY & INVENTORY
-- =============================================

-- Virtual currencies
CREATE TABLE Currencies (
    CurrencyID INT IDENTITY(1,1) PRIMARY KEY,
    CurrencyCode NVARCHAR(10) UNIQUE NOT NULL,
    CurrencyName NVARCHAR(50) NOT NULL,
    Description NVARCHAR(255),
    ExchangeRate DECIMAL(10,4) DEFAULT 1.0, -- To real currency
    IsActive BIT DEFAULT 1,

    -- Indexes
    INDEX IX_Currencies_Code (CurrencyCode),
    INDEX IX_Currencies_IsActive (IsActive)
);

-- Player currency balances
CREATE TABLE PlayerCurrencies (
    PlayerID INT NOT NULL REFERENCES Players(PlayerID),
    CurrencyID INT NOT NULL REFERENCES Currencies(CurrencyID),
    Balance DECIMAL(15,2) DEFAULT 0,
    LifetimeEarned DECIMAL(15,2) DEFAULT 0,
    LifetimeSpent DECIMAL(15,2) DEFAULT 0,
    LastUpdated DATETIME2 DEFAULT GETDATE(),

    -- Constraints
    CONSTRAINT PK_PlayerCurrencies PRIMARY KEY (PlayerID, CurrencyID),
    CONSTRAINT CK_PlayerCurrencies_Balance CHECK (Balance >= 0),

    -- Indexes
    INDEX IX_PlayerCurrencies_Balance (Balance),
    INDEX IX_PlayerCurrencies_LastUpdated (LastUpdated)
);

-- Virtual items
CREATE TABLE VirtualItems (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    ItemCode NVARCHAR(50) UNIQUE NOT NULL,
    ItemName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),
    ItemType NVARCHAR(50) NOT NULL, -- Weapon, Armor, Cosmetic, Consumable, etc.
    Rarity NVARCHAR(20) DEFAULT 'Common', -- Common, Uncommon, Rare, Epic, Legendary
    Category NVARCHAR(50),
    MaxStackSize INT DEFAULT 1,
    IsTradable BIT DEFAULT 1,
    IsConsumable BIT DEFAULT 0,
    DurationHours INT, -- For temporary items
    IconURL NVARCHAR(500),
    ModelURL NVARCHAR(500),
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_VirtualItems_Rarity CHECK (Rarity IN ('Common', 'Uncommon', 'Rare', 'Epic', 'Legendary')),
    CONSTRAINT CK_VirtualItems_Stack CHECK (MaxStackSize > 0),

    -- Indexes
    INDEX IX_VirtualItems_Code (ItemCode),
    INDEX IX_VirtualItems_Type (ItemType),
    INDEX IX_VirtualItems_Rarity (Rarity),
    INDEX IX_VirtualItems_IsActive (IsActive)
);

-- Player inventory
CREATE TABLE PlayerInventory (
    InventoryID INT IDENTITY(1,1) PRIMARY KEY,
    PlayerID INT NOT NULL REFERENCES Players(PlayerID),
    ItemID INT NOT NULL REFERENCES VirtualItems(ItemID),
    Quantity INT NOT NULL DEFAULT 1,
    AcquiredDate DATETIME2 DEFAULT GETDATE(),
    Source NVARCHAR(50), -- Purchase, Reward, Loot, Gift, etc.
    ExpiresAt DATETIME2,
    IsEquipped BIT DEFAULT 0,
    EquipmentSlot NVARCHAR(50),

    -- Constraints
    CONSTRAINT CK_PlayerInventory_Quantity CHECK (Quantity > 0),

    -- Indexes
    INDEX IX_PlayerInventory_Player (PlayerID),
    INDEX IX_PlayerInventory_Item (ItemID),
    INDEX IX_PlayerInventory_Equipped (PlayerID) WHERE IsEquipped = 1,
    INDEX IX_PlayerInventory_Expires (ExpiresAt) WHERE ExpiresAt IS NOT NULL
);

-- =============================================
-- STORE & PURCHASES
-- =============================================

-- Store products
CREATE TABLE StoreProducts (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductCode NVARCHAR(50) UNIQUE NOT NULL,
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),
    ProductType NVARCHAR(50) NOT NULL, -- Item, Currency, Bundle, Subscription
    Price DECIMAL(10,2) NOT NULL,
    CurrencyID INT REFERENCES Currencies(CurrencyID),
    DiscountPrice DECIMAL(10,2),
    DiscountStart DATETIME2,
    DiscountEnd DATETIME2,
    IsLimitedTime BIT DEFAULT 0,
    StockQuantity INT,
    MaxPerPlayer INT,
    RequiredLevel INT DEFAULT 1,
    IsActive BIT DEFAULT 1,
    DisplayOrder INT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_StoreProducts_Price CHECK (Price > 0),
    CONSTRAINT CK_StoreProducts_Level CHECK (RequiredLevel >= 1),

    -- Indexes
    INDEX IX_StoreProducts_Code (ProductCode),
    INDEX IX_StoreProducts_Type (ProductType),
    INDEX IX_StoreProducts_IsActive (IsActive),
    INDEX IX_StoreProducts_DisplayOrder (DisplayOrder)
);

-- Store product contents (for bundles)
CREATE TABLE StoreProductContents (
    ProductID INT NOT NULL REFERENCES StoreProducts(ProductID),
    ItemID INT REFERENCES VirtualItems(ItemID),
    CurrencyID INT REFERENCES Currencies(CurrencyID),
    Quantity INT NOT NULL DEFAULT 1,
    Probability DECIMAL(5,4), -- For random bundles

    -- Constraints
    CONSTRAINT PK_StoreProductContents PRIMARY KEY (ProductID, ItemID, CurrencyID),
    CONSTRAINT CK_StoreProductContents_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_StoreProductContents_Probability CHECK (Probability BETWEEN 0 AND 1),

    -- Indexes
    INDEX IX_StoreProductContents_Item (ItemID),
    INDEX IX_StoreProductContents_Currency (CurrencyID)
);

-- Purchase transactions
CREATE TABLE Purchases (
    PurchaseID INT IDENTITY(1,1) PRIMARY KEY,
    PlayerID INT NOT NULL REFERENCES Players(PlayerID),
    ProductID INT NOT NULL REFERENCES StoreProducts(ProductID),
    PurchaseDate DATETIME2 DEFAULT GETDATE(),
    Quantity INT DEFAULT 1,
    UnitPrice DECIMAL(10,2),
    TotalAmount DECIMAL(10,2),
    CurrencyID INT REFERENCES Currencies(CurrencyID),
    PaymentMethod NVARCHAR(50),
    TransactionID NVARCHAR(100),
    Status NVARCHAR(20) DEFAULT 'Completed',
    Refunded BIT DEFAULT 0,
    RefundAmount DECIMAL(10,2),
    RefundDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_Purchases_Status CHECK (Status IN ('Pending', 'Completed', 'Failed', 'Refunded')),
    CONSTRAINT CK_Purchases_Quantity CHECK (Quantity > 0),

    -- Indexes
    INDEX IX_Purchases_Player (PlayerID),
    INDEX IX_Purchases_Product (ProductID),
    INDEX IX_Purchases_Date (PurchaseDate),
    INDEX IX_Purchases_Status (Status),
    INDEX IX_Purchases_Refunded (Refunded)
);

-- =============================================
-- GAME MECHANICS
-- =============================================

-- Game matches
CREATE TABLE Matches (
    MatchID INT IDENTITY(1,1) PRIMARY KEY,
    GameMode NVARCHAR(50) NOT NULL,
    MapName NVARCHAR(100),
    StartTime DATETIME2 DEFAULT GETDATE(),
    EndTime DATETIME2,
    DurationSeconds INT,
    Status NVARCHAR(20) DEFAULT 'InProgress',
    MaxPlayers INT,
    MinPlayers INT DEFAULT 1,
    ServerRegion NVARCHAR(50),
    GameVersion NVARCHAR(20),

    -- Match statistics
    TotalPlayers INT DEFAULT 0,
    WinnerTeam NVARCHAR(50),
    MatchScore INT,

    -- Constraints
    CONSTRAINT CK_Matches_Status CHECK (Status IN ('InProgress', 'Completed', 'Cancelled', 'Abandoned')),
    CONSTRAINT CK_Matches_Players CHECK (MaxPlayers >= MinPlayers),

    -- Indexes
    INDEX IX_Matches_Mode (GameMode),
    INDEX IX_Matches_Status (Status),
    INDEX IX_Matches_StartTime (StartTime),
    INDEX IX_Matches_EndTime (EndTime)
);

-- Player match participation
CREATE TABLE MatchParticipants (
    MatchID INT NOT NULL REFERENCES Matches(MatchID),
    PlayerID INT NOT NULL REFERENCES Players(PlayerID),
    Team NVARCHAR(50),
    JoinTime DATETIME2 DEFAULT GETDATE(),
    LeaveTime DATETIME2,
    FinalScore INT,
    Placement INT, -- Final ranking
    Kills INT DEFAULT 0,
    Deaths INT DEFAULT 0,
    Assists INT DEFAULT 0,
    IsWinner BIT DEFAULT 0,
    ExperienceGained INT DEFAULT 0,
    CurrencyEarned DECIMAL(15,2) DEFAULT 0,

    -- Constraints
    CONSTRAINT PK_MatchParticipants PRIMARY KEY (MatchID, PlayerID),

    -- Indexes
    INDEX IX_MatchParticipants_Player (PlayerID),
    INDEX IX_MatchParticipants_Team (Team),
    INDEX IX_MatchParticipants_IsWinner (IsWinner)
);

-- =============================================
-- ACHIEVEMENTS & PROGRESSION
-- =============================================

-- Achievement definitions
CREATE TABLE Achievements (
    AchievementID INT IDENTITY(1,1) PRIMARY KEY,
    AchievementCode NVARCHAR(50) UNIQUE NOT NULL,
    Name NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),
    IconURL NVARCHAR(500),
    Category NVARCHAR(50), -- Combat, Exploration, Social, Collection, etc.
    Difficulty NVARCHAR(20) DEFAULT 'Easy', -- Easy, Medium, Hard, Legendary
    Points INT DEFAULT 10,
    IsHidden BIT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    -- Achievement requirements (stored as JSON)
    Requirements NVARCHAR(MAX), -- {"stat": "kills", "value": 100, "operator": ">="}

    -- Constraints
    CONSTRAINT CK_Achievements_Difficulty CHECK (Difficulty IN ('Easy', 'Medium', 'Hard', Legendary')),

    -- Indexes
    INDEX IX_Achievements_Code (AchievementCode),
    INDEX IX_Achievements_Category (Category),
    INDEX IX_Achievements_IsActive (IsActive)
);

-- Player achievements
CREATE TABLE PlayerAchievements (
    PlayerID INT NOT NULL REFERENCES Players(PlayerID),
    AchievementID INT NOT NULL REFERENCES Achievements(AchievementID),
    UnlockedDate DATETIME2 DEFAULT GETDATE(),
    Progress INT DEFAULT 100, -- For partial achievements
    IsDisplayed BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT PK_PlayerAchievements PRIMARY KEY (PlayerID, AchievementID),
    CONSTRAINT CK_PlayerAchievements_Progress CHECK (Progress BETWEEN 0 AND 100),

    -- Indexes
    INDEX IX_PlayerAchievements_Achievement (AchievementID),
    INDEX IX_PlayerAchievements_Date (UnlockedDate)
);

-- =============================================
-- LEADERBOARDS & RANKINGS
-- =============================================

-- Leaderboard configurations
CREATE TABLE Leaderboards (
    LeaderboardID INT IDENTITY(1,1) PRIMARY KEY,
    LeaderboardCode NVARCHAR(50) UNIQUE NOT NULL,
    Name NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),
    GameMode NVARCHAR(50),
    StatType NVARCHAR(50) NOT NULL, -- Kills, Score, Wins, Level, etc.
    TimeFrame NVARCHAR(20) DEFAULT 'AllTime', -- AllTime, Daily, Weekly, Monthly
    ResetSchedule NVARCHAR(20), -- Daily, Weekly, Monthly, Never
    MaxEntries INT DEFAULT 100,
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT CK_Leaderboards_TimeFrame CHECK (TimeFrame IN ('AllTime', 'Daily', 'Weekly', 'Monthly')),
    CONSTRAINT CK_Leaderboards_Reset CHECK (ResetSchedule IN ('Daily', 'Weekly', 'Monthly', 'Never')),

    -- Indexes
    INDEX IX_Leaderboards_Code (LeaderboardCode),
    INDEX IX_Leaderboards_Mode (GameMode),
    INDEX IX_Leaderboards_IsActive (IsActive)
);

-- Leaderboard entries
CREATE TABLE LeaderboardEntries (
    LeaderboardID INT NOT NULL REFERENCES Leaderboards(LeaderboardID),
    PlayerID INT NOT NULL REFERENCES Players(PlayerID),
    Rank INT NOT NULL,
    Score DECIMAL(15,2) NOT NULL,
    RankChange INT DEFAULT 0, -- Change from previous period
    LastUpdated DATETIME2 DEFAULT GETDATE(),
    IsCurrent BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT PK_LeaderboardEntries PRIMARY KEY (LeaderboardID, PlayerID),
    CONSTRAINT CK_LeaderboardEntries_Rank CHECK (Rank > 0),

    -- Indexes
    INDEX IX_LeaderboardEntries_Player (PlayerID),
    INDEX IX_LeaderboardEntries_Rank (LeaderboardID, Rank),
    INDEX IX_LeaderboardEntries_Score (LeaderboardID, Score DESC),
    INDEX IX_LeaderboardEntries_IsCurrent (LeaderboardID) WHERE IsCurrent = 1
);

-- =============================================
-- SOCIAL FEATURES
-- =============================================

-- Guilds/clans
CREATE TABLE Guilds (
    GuildID INT IDENTITY(1,1) PRIMARY KEY,
    GuildName NVARCHAR(100) UNIQUE NOT NULL,
    GuildTag NVARCHAR(10) UNIQUE,
    Description NVARCHAR(MAX),
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    GuildLevel INT DEFAULT 1,
    MaxMembers INT DEFAULT 50,
    IsRecruiting BIT DEFAULT 1,
    GuildLogoURL NVARCHAR(500),
    LeaderID INT REFERENCES Players(PlayerID),

    -- Guild statistics
    TotalExperience BIGINT DEFAULT 0,
    Wins INT DEFAULT 0,
    Losses INT DEFAULT 0,
    TournamentWins INT DEFAULT 0,

    -- Constraints
    CONSTRAINT CK_Guilds_Level CHECK (GuildLevel >= 1),
    CONSTRAINT CK_Guilds_Members CHECK (MaxMembers >= 1),

    -- Indexes
    INDEX IX_Guilds_Name (GuildName),
    INDEX IX_Guilds_Tag (GuildTag),
    INDEX IX_Guilds_Level (GuildLevel),
    INDEX IX_Guilds_IsRecruiting (IsRecruiting)
);

-- Guild members
CREATE TABLE GuildMembers (
    GuildID INT NOT NULL REFERENCES Guilds(GuildID),
    PlayerID INT NOT NULL REFERENCES Players(PlayerID),
    JoinDate DATETIME2 DEFAULT GETDATE(),
    Role NVARCHAR(20) DEFAULT 'Member', -- Leader, Officer, Member
    ContributionPoints INT DEFAULT 0,
    IsActive BIT DEFAULT 1,

    -- Constraints
    CONSTRAINT PK_GuildMembers PRIMARY KEY (GuildID, PlayerID),
    CONSTRAINT CK_GuildMembers_Role CHECK (Role IN ('Leader', 'Officer', 'Member')),

    -- Indexes
    INDEX IX_GuildMembers_Player (PlayerID),
    INDEX IX_GuildMembers_Role (Role),
    INDEX IX_GuildMembers_IsActive (IsActive)
);

-- =============================================
-- FRIEND SYSTEM
-- =============================================

-- Friend relationships
CREATE TABLE Friendships (
    FriendshipID INT IDENTITY(1,1) PRIMARY KEY,
    PlayerID1 INT NOT NULL REFERENCES Players(PlayerID),
    PlayerID2 INT NOT NULL REFERENCES Players(PlayerID),
    Status NVARCHAR(20) DEFAULT 'Pending', -- Pending, Accepted, Blocked
    RequestedBy INT NOT NULL REFERENCES Players(PlayerID),
    RequestedDate DATETIME2 DEFAULT GETDATE(),
    AcceptedDate DATETIME2,

    -- Constraints
    CONSTRAINT CK_Friendships_Status CHECK (Status IN ('Pending', 'Accepted', 'Blocked')),
    CONSTRAINT CK_Friendships_Players CHECK (PlayerID1 < PlayerID2), -- Prevent duplicates
    CONSTRAINT CK_Friendships_Self CHECK (PlayerID1 != PlayerID2),

    -- Indexes
    INDEX IX_Friendships_Player1 (PlayerID1),
    INDEX IX_Friendships_Player2 (PlayerID2),
    INDEX IX_Friendships_Status (Status),
    INDEX IX_Friendships_RequestedBy (RequestedBy)
);

-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Player profile view
CREATE VIEW vw_PlayerProfile
AS
SELECT
    p.PlayerID,
    p.Username,
    p.DisplayName,
    p.Level,
    p.ExperiencePoints,
    p.SkillRating,
    p.TotalPlayTime,
    p.LastLoginDate,
    COUNT(DISTINCT mp.MatchID) AS TotalMatches,
    SUM(CASE WHEN mp.IsWinner = 1 THEN 1 ELSE 0 END) AS Wins,
    SUM(CASE WHEN mp.IsWinner = 0 THEN 1 ELSE 0 END) AS Losses,
    AVG(mp.FinalScore) AS AvgScore,
    COUNT(pa.AchievementID) AS AchievementsUnlocked,
    pc.Balance AS VirtualCurrencyBalance
FROM Players p
LEFT JOIN MatchParticipants mp ON p.PlayerID = mp.PlayerID
LEFT JOIN PlayerAchievements pa ON p.PlayerID = pa.PlayerID
LEFT JOIN PlayerCurrencies pc ON p.PlayerID = pc.PlayerID
    AND pc.CurrencyID = (SELECT CurrencyID FROM Currencies WHERE CurrencyCode = 'VIRTUAL')
WHERE p.IsActive = 1
GROUP BY p.PlayerID, p.Username, p.DisplayName, p.Level, p.ExperiencePoints,
         p.SkillRating, p.TotalPlayTime, p.LastLoginDate, pc.Balance;
GO

-- Leaderboard rankings view
CREATE VIEW vw_LeaderboardRankings
AS
SELECT
    l.Name AS LeaderboardName,
    l.StatType,
    l.TimeFrame,
    le.Rank,
    p.Username,
    p.DisplayName,
    le.Score,
    le.RankChange,
    le.LastUpdated
FROM Leaderboards l
INNER JOIN LeaderboardEntries le ON l.LeaderboardID = le.LeaderboardID
INNER JOIN Players p ON le.PlayerID = p.PlayerID
WHERE le.IsCurrent = 1 AND l.IsActive = 1
ORDER BY l.LeaderboardID, le.Rank;
GO

-- =============================================
-- STORED PROCEDURES
-- =============================================

-- Player level up procedure
CREATE PROCEDURE sp_PlayerLevelUp
    @PlayerID INT,
    @ExperienceGained INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentXP BIGINT;
    DECLARE @NewXP BIGINT;
    DECLARE @CurrentLevel INT;
    DECLARE @NewLevel INT;
    DECLARE @XPForNextLevel BIGINT;

    -- Get current player stats
    SELECT @CurrentXP = ExperiencePoints, @CurrentLevel = Level
    FROM Players WHERE PlayerID = @PlayerID;

    -- Calculate new XP
    SET @NewXP = @CurrentXP + @ExperienceGained;

    -- Calculate new level (simple formula: 1000 * level for next level)
    SET @XPForNextLevel = @CurrentLevel * 1000;
    SET @NewLevel = @CurrentLevel;

    WHILE @NewXP >= @XPForNextLevel
    BEGIN
        SET @NewLevel = @NewLevel + 1;
        SET @XPForNextLevel = @NewLevel * 1000;
    END

    -- Update player
    UPDATE Players
    SET ExperiencePoints = @NewXP,
        Level = @NewLevel,
        LastLoginDate = GETDATE()
    WHERE PlayerID = @PlayerID;

    -- Log level up if leveled up
    IF @NewLevel > @CurrentLevel
    BEGIN
        INSERT INTO PlayerAchievements (PlayerID, AchievementID)
        SELECT @PlayerID, AchievementID
        FROM Achievements
        WHERE AchievementCode = 'LEVEL_UP'
        AND AchievementID NOT IN (
            SELECT AchievementID FROM PlayerAchievements
            WHERE PlayerID = @PlayerID
        );
    END
END;
GO

-- Purchase item procedure
CREATE PROCEDURE sp_PurchaseItem
    @PlayerID INT,
    @ProductID INT,
    @Quantity INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @Price DECIMAL(10,2);
    DECLARE @CurrencyID INT;
    DECLARE @PlayerBalance DECIMAL(15,2);
    DECLARE @TotalCost DECIMAL(10,2);

    -- Get product price and currency
    SELECT @Price = Price, @CurrencyID = CurrencyID
    FROM StoreProducts
    WHERE ProductID = @ProductID AND IsActive = 1;

    IF @Price IS NULL
    BEGIN
        RAISERROR('Product not found or not active', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    -- Calculate total cost
    SET @TotalCost = @Price * @Quantity;

    -- Check player balance
    SELECT @PlayerBalance = Balance
    FROM PlayerCurrencies
    WHERE PlayerID = @PlayerID AND CurrencyID = @CurrencyID;

    IF @PlayerBalance < @TotalCost
    BEGIN
        RAISERROR('Insufficient funds', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    -- Deduct balance
    UPDATE PlayerCurrencies
    SET Balance = Balance - @TotalCost,
        LifetimeSpent = LifetimeSpent + @TotalCost,
        LastUpdated = GETDATE()
    WHERE PlayerID = @PlayerID AND CurrencyID = @CurrencyID;

    -- Record purchase
    INSERT INTO Purchases (PlayerID, ProductID, Quantity, UnitPrice, TotalAmount, CurrencyID)
    VALUES (@PlayerID, @ProductID, @Quantity, @Price, @TotalCost, @CurrencyID);

    -- Grant items (simplified - assumes single item per product)
    INSERT INTO PlayerInventory (PlayerID, ItemID, Quantity, Source)
    SELECT @PlayerID, spc.ItemID, @Quantity * spc.Quantity, 'Purchase'
    FROM StoreProductContents spc
    WHERE spc.ProductID = @ProductID;

    COMMIT TRANSACTION;
END;
GO

-- =============================================
-- SAMPLE DATA INSERTION
-- =============================================

-- Insert sample currencies
INSERT INTO Currencies (CurrencyCode, CurrencyName, Description, ExchangeRate) VALUES
('VIRTUAL', 'Virtual Coins', 'In-game virtual currency', 0.01),
('PREMIUM', 'Premium Currency', 'Premium in-game currency', 0.10);

-- Insert sample player
INSERT INTO Players (Username, Email, DisplayName, Country, Level, ExperiencePoints) VALUES
('player1', 'player1@example.com', 'Player One', 'US', 5, 4500);

-- Insert sample virtual items
INSERT INTO VirtualItems (ItemCode, ItemName, ItemType, Rarity, MaxStackSize) VALUES
('SWORD_001', 'Iron Sword', 'Weapon', 'Common', 1),
('POTION_001', 'Health Potion', 'Consumable', 'Common', 99),
('ARMOR_001', 'Steel Armor', 'Armor', 'Uncommon', 1);

-- Insert sample store products
INSERT INTO StoreProducts (ProductCode, ProductName, ProductType, Price, CurrencyID) VALUES
('BUNDLE_001', 'Starter Bundle', 'Bundle', 99.99, 1),
('COINS_100', '100 Virtual Coins', 'Currency', 4.99, 1);

-- Insert sample achievements
INSERT INTO Achievements (AchievementCode, Name, Description, Category, Points) VALUES
('FIRST_WIN', 'First Victory', 'Win your first match', 'Combat', 10),
('LEVEL_UP', 'Level Up', 'Reach a new level', 'Progression', 5);

PRINT 'Gaming database schema created successfully!';
GO
