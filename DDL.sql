/*
--DROP TABLE dbo.Promotions
--DROP TABLE dbo.PromotionProducts
DROP TABLE dbo.FSBTrackings
DROP TABLE dbo.FSBCommission
DROP TABLE dbo.FSBCommissionDetail
*/
IF OBJECT_ID('dbo.Promotions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Promotions
    (
        PromotionID BIGINT IDENTITY(1,1) NOT NULL,
        Code VARCHAR(50) NOT NULL,
        Type VARCHAR(50) NOT NULL,
        PromoName VARCHAR(150) NOT NULL,
        PromoDesc VARCHAR(500) NULL,
        StartDate DATETIME NOT NULL,
        EndDate DATETIME NOT NULL,
        CreatedAt DATETIME NOT NULL CONSTRAINT DF_Promotions_CreatedAt DEFAULT(GETDATE()),

        CONSTRAINT PK_Promotions PRIMARY KEY CLUSTERED (PromotionID),
        CONSTRAINT UQ_Promotions_Code UNIQUE (Code)
    );
END;
GO

IF OBJECT_ID('dbo.PromotionProducts', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.PromotionProducts
	(
		PromotionProductID BIGINT IDENTITY(1,1) NOT NULL,
		PromotionID BIGINT NOT NULL,
		ProductID INT NOT NULL,

		IsExcluded BIT NOT NULL DEFAULT(0),

		CONSTRAINT PK_PromotionProducts PRIMARY KEY CLUSTERED (PromotionProductID),

		CONSTRAINT UQ_PromotionProducts
		UNIQUE (PromotionID, ProductID)
	);

    /*ALTER TABLE dbo.PromotionProducts
    ADD CONSTRAINT FK_PromotionProducts_Promotions
    FOREIGN KEY (PromotionID)
    REFERENCES dbo.Promotions(PromotionID);*/
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FSBTrackings
    (
        FSBTrackingID BIGINT IDENTITY(1,1) NOT NULL,
        CreatedAt DATETIME NOT NULL CONSTRAINT DF_FSBTrackings_CreatedAt DEFAULT(GETDATE()),

        PromotionID BIGINT NOT NULL,

        SponsorID BIGINT NOT NULL,
        PromoterID BIGINT NOT NULL,
        OrderID BIGINT NOT NULL,

        FSBType VARCHAR(20) NOT NULL,

        SponsorFSB1Start DATETIME NOT NULL,
        SponsorFSB1End DATETIME NOT NULL,
        SponsorFSB1ExtEnd DATETIME NOT NULL,

        SponsorFSB2Start DATETIME NULL,
        SponsorFSB2End DATETIME NULL,

        SponsorFSB3Start DATETIME NULL,
        SponsorFSB3End DATETIME NULL,

        FirstRPHID BIGINT NULL,
        SecondRPHID BIGINT NULL,

        CONSTRAINT PK_FSBTrackings PRIMARY KEY CLUSTERED (FSBTrackingID),

        CONSTRAINT CK_FSBTrackings_FSBType
        CHECK (FSBType IN ('FSB1', 'FSB1_EXT', 'FSB2', 'FSB3')),

        CONSTRAINT UQ_FSBTrackings
        UNIQUE
        (
            PromotionID,
            SponsorID,
            PromoterID,
            OrderID,
            FSBType,
            SponsorFSB1Start
        )
    );

    /*ALTER TABLE dbo.FSBTrackings
    ADD CONSTRAINT FK_FSBTrackings_Promotions
    FOREIGN KEY (PromotionID)
    REFERENCES dbo.Promotions(PromotionID);*/
END;
GO

IF OBJECT_ID('dbo.FSBCommission', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FSBCommission
    (
        FSBCommissionID BIGINT IDENTITY(1,1) NOT NULL,
        CreatedAt DATETIME NOT NULL CONSTRAINT DF_FSBCommission_CreatedAt DEFAULT(GETDATE()),

        PromotionID BIGINT NOT NULL,

        SponsorID BIGINT NOT NULL,
        SponsorFSB1Start DATETIME NOT NULL,

        FSBType VARCHAR(10) NOT NULL,
        HalfType VARCHAR(10) NOT NULL,

        DailyRealTimeCommissionID BIGINT NULL,

        CONSTRAINT PK_FSBCommission PRIMARY KEY CLUSTERED (FSBCommissionID),

        CONSTRAINT CK_FSBCommission_FSBType
        CHECK (FSBType IN ('FSB1', 'FSB1_EXT', 'FSB2', 'FSB3')),

        CONSTRAINT CK_FSBCommission_HalfType
        CHECK (HalfType IN ('FIRST', 'SECOND')),

        CONSTRAINT UQ_FSBCommission
        UNIQUE
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBType,
            HalfType
        )
    );

    /*ALTER TABLE dbo.FSBCommission
    ADD CONSTRAINT FK_FSBCommission_Promotions
    FOREIGN KEY (PromotionID)
    REFERENCES dbo.Promotions(PromotionID);

    ALTER TABLE dbo.FSBCommission
    ADD CONSTRAINT FK_FSBCommission_DailyRealTimeCommission
    FOREIGN KEY (DailyRealTimeCommissionID)
    REFERENCES dbo.DailyRealTimeCommission(ID);*/
END;
GO

IF OBJECT_ID('dbo.FSBCommissionDetail', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FSBCommissionDetail
    (
        FSBCommissionDetailID BIGINT IDENTITY(1,1) NOT NULL,
        CreatedAt DATETIME NOT NULL CONSTRAINT DF_FSBCommissionDetail_CreatedAt DEFAULT(GETDATE()),

        FSBCommissionID BIGINT NOT NULL,
        FSBTrackingID BIGINT NOT NULL,

        CONSTRAINT PK_FSBCommissionDetail
        PRIMARY KEY CLUSTERED (FSBCommissionDetailID),

        CONSTRAINT UQ_FSBCommissionDetail
        UNIQUE (FSBCommissionID, FSBTrackingID)
    );

    /*ALTER TABLE dbo.FSBCommissionDetail
    ADD CONSTRAINT FK_FSBCommissionDetail_FSBCommission
    FOREIGN KEY (FSBCommissionID)
    REFERENCES dbo.FSBCommission(FSBCommissionID);

    ALTER TABLE dbo.FSBCommissionDetail
    ADD CONSTRAINT FK_FSBCommissionDetail_FSBTrackings
    FOREIGN KEY (FSBTrackingID)
    REFERENCES dbo.FSBTrackings(FSBTrackingID);*/
END;
GO


IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_FSBTrackings_Sponsor_Cycle_Type'
      AND object_id = OBJECT_ID('dbo.FSBTrackings')
)
BEGIN
    CREATE INDEX IX_FSBTrackings_Sponsor_Cycle_Type
    ON dbo.FSBTrackings
    (
        PromotionID,
        SponsorID,
        SponsorFSB1Start,
        FSBType
    )
    INCLUDE
    (
        PromoterID,
        OrderID,
        SecondRPHID,
        CreatedAt
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_FSBTrackings_Promoter_Order'
      AND object_id = OBJECT_ID('dbo.FSBTrackings')
)
BEGIN
    CREATE INDEX IX_FSBTrackings_Promoter_Order
    ON dbo.FSBTrackings
    (
        PromotionID,
        PromoterID,
        OrderID,
        SponsorFSB1Start
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_FSBCommission_Sponsor_Cycle'
      AND object_id = OBJECT_ID('dbo.FSBCommission')
)
BEGIN
    CREATE INDEX IX_FSBCommission_Sponsor_Cycle
    ON dbo.FSBCommission
    (
        PromotionID,
        SponsorID,
        SponsorFSB1Start,
        FSBType,
        HalfType
    )
    INCLUDE
    (
        DailyRealTimeCommissionID,
        CreatedAt
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_FSBCommissionDetail_Commission_Tracking'
      AND object_id = OBJECT_ID('dbo.FSBCommissionDetail')
)
BEGIN
    CREATE INDEX IX_FSBCommissionDetail_Commission_Tracking
    ON dbo.FSBCommissionDetail
    (
        FSBCommissionID,
        FSBTrackingID
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_PromotionProducts_Product_Promotion'
      AND object_id = OBJECT_ID('dbo.PromotionProducts')
)
BEGIN
    CREATE INDEX IX_PromotionProducts_Product_Promotion
    ON dbo.PromotionProducts
    (
        ProductID,
        PromotionID
    );
END;
GO
