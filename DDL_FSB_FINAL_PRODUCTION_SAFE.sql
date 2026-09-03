
/*
================================================================================
FSB FINAL DDL - PRODUCTION-SAFE / NON-DESTRUCTIVE
Target: Microsoft SQL Server
Status: FINAL CLEAN DDL

IMPORTANT:
- No DROP TABLE.
- Historical data is preserved.
- FSB1_EXT is allowed in dbo.FSBTrackings only.
- dbo.FSBCommission allows only FSB1 / FSB2 / FSB3.
- PromotionProducts supports exclusion mode with IsExcluded = 1.
================================================================================
*/

-------------------------------------------------------------------------------
-- 1. dbo.Promotions
-------------------------------------------------------------------------------

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


-------------------------------------------------------------------------------
-- 2. dbo.PromotionProducts
-- PromotionProducts is exclusion-aware.
-- For current FSB:
--      ProductID 4 and 22 should be inserted with IsExcluded = 1.
-------------------------------------------------------------------------------

IF OBJECT_ID('dbo.PromotionProducts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PromotionProducts
    (
        PromotionProductID BIGINT IDENTITY(1,1) NOT NULL,
        PromotionID BIGINT NOT NULL,
        ProductID INT NOT NULL,
        IsExcluded BIT NOT NULL CONSTRAINT DF_PromotionProducts_IsExcluded DEFAULT(0),

        CONSTRAINT PK_PromotionProducts PRIMARY KEY CLUSTERED (PromotionProductID),
        CONSTRAINT UQ_PromotionProducts UNIQUE (PromotionID, ProductID)
    );
END;
GO

IF OBJECT_ID('dbo.PromotionProducts', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.PromotionProducts', 'IsExcluded') IS NULL
BEGIN
    ALTER TABLE dbo.PromotionProducts
    ADD IsExcluded BIT NOT NULL
        CONSTRAINT DF_PromotionProducts_IsExcluded DEFAULT(0);
END;
GO

IF OBJECT_ID('dbo.PromotionProducts', 'U') IS NOT NULL
   AND OBJECT_ID('dbo.Promotions', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.foreign_keys
       WHERE name = 'FK_PromotionProducts_Promotions'
         AND parent_object_id = OBJECT_ID('dbo.PromotionProducts')
   )
BEGIN
    ALTER TABLE dbo.PromotionProducts WITH CHECK
    ADD CONSTRAINT FK_PromotionProducts_Promotions
    FOREIGN KEY (PromotionID)
    REFERENCES dbo.Promotions(PromotionID);
END;
GO


-------------------------------------------------------------------------------
-- 3. dbo.FSBCandidates
-- Complete auditable candidate universe at order level.
-------------------------------------------------------------------------------

IF OBJECT_ID('dbo.FSBCandidates', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FSBCandidates
    (
        FSBCandidateID BIGINT IDENTITY(1,1) NOT NULL,
        CreatedAt DATETIME NOT NULL CONSTRAINT DF_FSBCandidates_CreatedAt DEFAULT(GETDATE()),
        FirstSeenAt DATETIME NOT NULL CONSTRAINT DF_FSBCandidates_FirstSeenAt DEFAULT(GETDATE()),
        LastSeenAt DATETIME NOT NULL CONSTRAINT DF_FSBCandidates_LastSeenAt DEFAULT(GETDATE()),
        InactivatedAt DATETIME NULL,
        IsCurrent BIT NOT NULL CONSTRAINT DF_FSBCandidates_IsCurrent DEFAULT(1),

        PromotionID BIGINT NOT NULL,
        SponsorID BIGINT NOT NULL,
        SponsorUserID BIGINT NOT NULL,
        SponsorFSB1Start DATETIME NOT NULL,

        CandidateKey BIGINT NOT NULL,
        CandidateType VARCHAR(20) NOT NULL,

        PromoterID BIGINT NULL,
        CustomerID BIGINT NOT NULL,
        ParticipantUserID BIGINT NOT NULL,

        OrderID BIGINT NOT NULL,
        OrderDate DATETIME NOT NULL,
        ProductID INT NOT NULL,
        OrderStatus VARCHAR(20) NOT NULL,

        IsExcludedProduct BIT NOT NULL,
        IsStaticEligible BIT NOT NULL,
        StaticEligibilityReason VARCHAR(200) NULL,

        IsEliteTravelAdvantagePro BIT NULL,
        IsPromoCouponApplied BIT NULL,
        IsPermanentPromoCouponApplied BIT NULL,
        FreeCommission BIT NULL,
        IsDagCustomer BIT NULL,
        IsCreatedWithPromoPrice BIT NULL,

        CONSTRAINT PK_FSBCandidates PRIMARY KEY CLUSTERED (FSBCandidateID),

        CONSTRAINT CK_FSBCandidates_CandidateType
        CHECK (CandidateType IN ('PROMOTER', 'CUSTOMER')),

        CONSTRAINT UQ_FSBCandidates
        UNIQUE
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            CandidateType,
            OrderID
        )
    );
END;
GO

IF OBJECT_ID('dbo.FSBCandidates', 'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('dbo.FSBCandidates', 'FirstSeenAt') IS NULL
    BEGIN
        EXEC(N'ALTER TABLE dbo.FSBCandidates ADD FirstSeenAt DATETIME NULL');
        EXEC(N'UPDATE dbo.FSBCandidates SET FirstSeenAt = CreatedAt WHERE FirstSeenAt IS NULL');
        EXEC(N'ALTER TABLE dbo.FSBCandidates ALTER COLUMN FirstSeenAt DATETIME NOT NULL');
        EXEC(N'ALTER TABLE dbo.FSBCandidates ADD CONSTRAINT DF_FSBCandidates_FirstSeenAt DEFAULT(GETDATE()) FOR FirstSeenAt');
    END;
    IF COL_LENGTH('dbo.FSBCandidates', 'LastSeenAt') IS NULL
    BEGIN
        EXEC(N'ALTER TABLE dbo.FSBCandidates ADD LastSeenAt DATETIME NULL');
        EXEC(N'UPDATE dbo.FSBCandidates SET LastSeenAt = CreatedAt WHERE LastSeenAt IS NULL');
        EXEC(N'ALTER TABLE dbo.FSBCandidates ALTER COLUMN LastSeenAt DATETIME NOT NULL');
        EXEC(N'ALTER TABLE dbo.FSBCandidates ADD CONSTRAINT DF_FSBCandidates_LastSeenAt DEFAULT(GETDATE()) FOR LastSeenAt');
    END;
    IF COL_LENGTH('dbo.FSBCandidates', 'InactivatedAt') IS NULL
        ALTER TABLE dbo.FSBCandidates ADD InactivatedAt DATETIME NULL;
    IF COL_LENGTH('dbo.FSBCandidates', 'IsCurrent') IS NULL
        ALTER TABLE dbo.FSBCandidates ADD IsCurrent BIT NOT NULL CONSTRAINT DF_FSBCandidates_IsCurrent DEFAULT(1);
END;
GO

IF OBJECT_ID('dbo.FSBCandidates', 'U') IS NOT NULL
   AND OBJECT_ID('dbo.Promotions', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.foreign_keys
       WHERE name = 'FK_FSBCandidates_Promotions'
         AND parent_object_id = OBJECT_ID('dbo.FSBCandidates')
   )
BEGIN
    ALTER TABLE dbo.FSBCandidates WITH CHECK
    ADD CONSTRAINT FK_FSBCandidates_Promotions
    FOREIGN KEY (PromotionID)
    REFERENCES dbo.Promotions(PromotionID);
END;
GO


-------------------------------------------------------------------------------
-- 4. dbo.FSBTrackings
-- Historical tracking table.
-- Stores FSB1, FSB1_EXT, FSB2, FSB3 and NO_FSB classifications.
-- FirstRPHID = first SUCCESS payment by RPH.CreateDate.
-- SecondRPHID = second SUCCESS payment by RPH.CreateDate.
-------------------------------------------------------------------------------

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FSBTrackings
    (
        FSBTrackingID BIGINT IDENTITY(1,1) NOT NULL,
        CreatedAt DATETIME NOT NULL CONSTRAINT DF_FSBTrackings_CreatedAt DEFAULT(GETDATE()),

        PromotionID BIGINT NOT NULL,

        SponsorID BIGINT NOT NULL,
        PromoterID BIGINT NOT NULL,
        CustomerID BIGINT NOT NULL,
        ParticipantUserID BIGINT NOT NULL,
        CandidateType VARCHAR(20) NOT NULL,
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
        CHECK (FSBType IN ('FSB1', 'FSB1_EXT', 'FSB2', 'FSB3', 'NO_FSB')),

        CONSTRAINT CK_FSBTrackings_CandidateType
        CHECK (CandidateType IN ('PROMOTER', 'CUSTOMER')),

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
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.FSBTrackings', 'CustomerID') IS NULL
BEGIN
    ALTER TABLE dbo.FSBTrackings
    ADD CustomerID BIGINT NULL;
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND EXISTS
   (
       SELECT 1
       FROM sys.check_constraints
       WHERE name = 'CK_FSBTrackings_FSBType'
         AND parent_object_id = OBJECT_ID('dbo.FSBTrackings')
   )
BEGIN
    ALTER TABLE dbo.FSBTrackings
    DROP CONSTRAINT CK_FSBTrackings_FSBType;
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.check_constraints
       WHERE name = 'CK_FSBTrackings_FSBType'
         AND parent_object_id = OBJECT_ID('dbo.FSBTrackings')
   )
BEGIN
    ALTER TABLE dbo.FSBTrackings WITH CHECK
    ADD CONSTRAINT CK_FSBTrackings_FSBType
    CHECK (FSBType IN ('FSB1', 'FSB1_EXT', 'FSB2', 'FSB3', 'NO_FSB'));
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.FSBTrackings', 'ParticipantUserID') IS NULL
BEGIN
    ALTER TABLE dbo.FSBTrackings
    ADD ParticipantUserID BIGINT NULL;
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.FSBTrackings', 'CandidateType') IS NULL
BEGIN
    ALTER TABLE dbo.FSBTrackings
    ADD CandidateType VARCHAR(20) NULL;
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND OBJECT_ID('dbo.MWRCustomers', 'U') IS NOT NULL
   AND OBJECT_ID('dbo.Promoters', 'U') IS NOT NULL
BEGIN
    UPDATE ft
       SET
           CustomerID = ISNULL(ft.CustomerID, c.CustomerID),
           ParticipantUserID = ISNULL(ft.ParticipantUserID, c.UserID),
           CandidateType = ISNULL(ft.CandidateType, 'PROMOTER')
    FROM dbo.FSBTrackings ft
    INNER JOIN dbo.Promoters p
        ON p.PromoterID = ft.PromoterID
    INNER JOIN dbo.MWRCustomers c
        ON c.UserID = p.UserProfileID
    WHERE ft.CustomerID IS NULL
       OR ft.ParticipantUserID IS NULL
       OR ft.CandidateType IS NULL;
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.check_constraints
       WHERE name = 'CK_FSBTrackings_CandidateType'
         AND parent_object_id = OBJECT_ID('dbo.FSBTrackings')
   )
BEGIN
    ALTER TABLE dbo.FSBTrackings WITH CHECK
    ADD CONSTRAINT CK_FSBTrackings_CandidateType
    CHECK (CandidateType IN ('PROMOTER', 'CUSTOMER'));
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND OBJECT_ID('dbo.Promotions', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.foreign_keys
       WHERE name = 'FK_FSBTrackings_Promotions'
         AND parent_object_id = OBJECT_ID('dbo.FSBTrackings')
   )
BEGIN
    ALTER TABLE dbo.FSBTrackings WITH CHECK
    ADD CONSTRAINT FK_FSBTrackings_Promotions
    FOREIGN KEY (PromotionID)
    REFERENCES dbo.Promotions(PromotionID);
END;
GO


-------------------------------------------------------------------------------
-- 4. dbo.FSBCommission
-- Commission header.
--
-- IMPORTANT:
-- FSB1_EXT must NOT be stored here.
-- FSB1_EXT is a tracking classification only.
-- If extension wins FSB1, the commission header uses FSBType = 'FSB1'.
-------------------------------------------------------------------------------

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
        CHECK (FSBType IN ('FSB1', 'FSB2', 'FSB3')),

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
END;
GO

/*
    If the table already existed with the old CHECK allowing FSB1_EXT,
    replace it with the final constraint.

    NOTE:
    This will fail if dbo.FSBCommission currently contains FSBType = 'FSB1_EXT'.
    That is intentional because FSB1_EXT should not exist in commission headers.
*/
IF OBJECT_ID('dbo.FSBCommission', 'U') IS NOT NULL
   AND EXISTS
   (
       SELECT 1
       FROM sys.check_constraints
       WHERE name = 'CK_FSBCommission_FSBType'
         AND parent_object_id = OBJECT_ID('dbo.FSBCommission')
   )
BEGIN
    ALTER TABLE dbo.FSBCommission
    DROP CONSTRAINT CK_FSBCommission_FSBType;
END;
GO

IF OBJECT_ID('dbo.FSBCommission', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.check_constraints
       WHERE name = 'CK_FSBCommission_FSBType'
         AND parent_object_id = OBJECT_ID('dbo.FSBCommission')
   )
BEGIN
    ALTER TABLE dbo.FSBCommission WITH CHECK
    ADD CONSTRAINT CK_FSBCommission_FSBType
    CHECK (FSBType IN ('FSB1', 'FSB2', 'FSB3'));
END;
GO

IF OBJECT_ID('dbo.FSBCommission', 'U') IS NOT NULL
   AND OBJECT_ID('dbo.Promotions', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.foreign_keys
       WHERE name = 'FK_FSBCommission_Promotions'
         AND parent_object_id = OBJECT_ID('dbo.FSBCommission')
   )
BEGIN
    ALTER TABLE dbo.FSBCommission WITH CHECK
    ADD CONSTRAINT FK_FSBCommission_Promotions
    FOREIGN KEY (PromotionID)
    REFERENCES dbo.Promotions(PromotionID);
END;
GO

IF OBJECT_ID('dbo.FSBCommission', 'U') IS NOT NULL
   AND OBJECT_ID('dbo.DailyRealTimeCommission', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.DailyRealTimeCommission', 'ID') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.foreign_keys
       WHERE name = 'FK_FSBCommission_DailyRealTimeCommission'
         AND parent_object_id = OBJECT_ID('dbo.FSBCommission')
   )
BEGIN
    ALTER TABLE dbo.FSBCommission WITH CHECK
    ADD CONSTRAINT FK_FSBCommission_DailyRealTimeCommission
    FOREIGN KEY (DailyRealTimeCommissionID)
    REFERENCES dbo.DailyRealTimeCommission(ID);
END;
GO


-------------------------------------------------------------------------------
-- 5. dbo.FSBCommissionDetail
-- Official commission justification.
--
-- FIRST details:
--      all valid promoters from the group.
--
-- SECOND details:
--      only promoters with valid renewal according to FSBCommission_Generate.
-------------------------------------------------------------------------------

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
END;
GO

IF OBJECT_ID('dbo.FSBCommissionDetail', 'U') IS NOT NULL
   AND OBJECT_ID('dbo.FSBCommission', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.foreign_keys
       WHERE name = 'FK_FSBCommissionDetail_FSBCommission'
         AND parent_object_id = OBJECT_ID('dbo.FSBCommissionDetail')
   )
BEGIN
    ALTER TABLE dbo.FSBCommissionDetail WITH CHECK
    ADD CONSTRAINT FK_FSBCommissionDetail_FSBCommission
    FOREIGN KEY (FSBCommissionID)
    REFERENCES dbo.FSBCommission(FSBCommissionID);
END;
GO

IF OBJECT_ID('dbo.FSBCommissionDetail', 'U') IS NOT NULL
   AND OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.foreign_keys
       WHERE name = 'FK_FSBCommissionDetail_FSBTrackings'
         AND parent_object_id = OBJECT_ID('dbo.FSBCommissionDetail')
   )
BEGIN
    ALTER TABLE dbo.FSBCommissionDetail WITH CHECK
    ADD CONSTRAINT FK_FSBCommissionDetail_FSBTrackings
    FOREIGN KEY (FSBTrackingID)
    REFERENCES dbo.FSBTrackings(FSBTrackingID);
END;
GO


-------------------------------------------------------------------------------
-- 6. FSB INTERNAL INDEXES
-------------------------------------------------------------------------------

IF OBJECT_ID('dbo.FSBCandidates', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE name = 'IX_FSBCandidates_Sponsor_Cycle_Type'
         AND object_id = OBJECT_ID('dbo.FSBCandidates')
   )
BEGIN
    CREATE INDEX IX_FSBCandidates_Sponsor_Cycle_Type
    ON dbo.FSBCandidates
    (
        PromotionID,
        SponsorID,
        SponsorFSB1Start,
        CandidateType,
        IsCurrent,
        IsStaticEligible,
        CandidateKey
    )
    INCLUDE
    (
        PromoterID,
        CustomerID,
        ParticipantUserID,
        OrderID,
        OrderDate,
        ProductID,
        OrderStatus,
        StaticEligibilityReason
    );
END;
GO

IF OBJECT_ID('dbo.FSBCandidates', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE name = 'IX_FSBCandidates_Order'
         AND object_id = OBJECT_ID('dbo.FSBCandidates')
   )
BEGIN
    CREATE INDEX IX_FSBCandidates_Order
    ON dbo.FSBCandidates
    (
        OrderID,
        PromotionID
    )
    INCLUDE
    (
        SponsorID,
        SponsorFSB1Start,
        CandidateType,
        CandidateKey,
        IsStaticEligible
    );
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
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
        CustomerID,
        ParticipantUserID,
        CandidateType,
        OrderID,
        FirstRPHID,
        SecondRPHID,
        CreatedAt
    );
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE name = 'IX_FSBTrackings_Promoter_Order'
         AND object_id = OBJECT_ID('dbo.FSBTrackings')
   )
BEGIN
    CREATE INDEX IX_FSBTrackings_Promoter_Order
    ON dbo.FSBTrackings
    (
        PromotionID,
        CandidateType,
        PromoterID,
        OrderID,
        SponsorFSB1Start
    );
END;
GO

IF OBJECT_ID('dbo.FSBTrackings', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE name = 'IX_FSBTrackings_Order'
         AND object_id = OBJECT_ID('dbo.FSBTrackings')
   )
BEGIN
    CREATE INDEX IX_FSBTrackings_Order
    ON dbo.FSBTrackings
    (
        OrderID,
        PromotionID
    )
    INCLUDE
    (
        SponsorID,
        PromoterID,
        CustomerID,
        ParticipantUserID,
        CandidateType,
        FSBType,
        SponsorFSB1Start,
        FirstRPHID,
        SecondRPHID
    );
END;
GO

IF OBJECT_ID('dbo.FSBCommission', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
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

IF OBJECT_ID('dbo.FSBCommissionDetail', 'U') IS NOT NULL
   AND EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE name = 'IX_FSBCommissionDetail_Commission_Tracking'
         AND object_id = OBJECT_ID('dbo.FSBCommissionDetail')
   )
BEGIN
    DROP INDEX IX_FSBCommissionDetail_Commission_Tracking
        ON dbo.FSBCommissionDetail;
END;
GO

IF OBJECT_ID('dbo.FSBCommissionDetail', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE name = 'IX_FSBCommissionDetail_Tracking'
         AND object_id = OBJECT_ID('dbo.FSBCommissionDetail')
   )
BEGIN
    CREATE INDEX IX_FSBCommissionDetail_Tracking
    ON dbo.FSBCommissionDetail
    (
        FSBTrackingID,
        FSBCommissionID
    );
END;
GO

IF OBJECT_ID('dbo.PromotionProducts', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE name = 'IX_PromotionProducts_Product_Promotion'
         AND object_id = OBJECT_ID('dbo.PromotionProducts')
   )
BEGIN
    CREATE INDEX IX_PromotionProducts_Product_Promotion
    ON dbo.PromotionProducts
    (
        ProductID,
        PromotionID
    )
    INCLUDE
    (
        IsExcluded
    );
END;
GO

IF OBJECT_ID('dbo.PromotionProducts', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE name = 'IX_PromotionProducts_Excluded'
         AND object_id = OBJECT_ID('dbo.PromotionProducts')
   )
BEGIN
    CREATE INDEX IX_PromotionProducts_Excluded
    ON dbo.PromotionProducts
    (
        PromotionID,
        ProductID,
        IsExcluded
    );
END;
GO

-------------------------------------------------------------------------------
-- 8. OPTIONAL CONFIGURATION INSERTS
-- Uncomment and adjust if needed.
-------------------------------------------------------------------------------

/*
DECLARE @PromotionID BIGINT;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.Promotions
    WHERE Code = 'FSB_TEST'
)
BEGIN
    INSERT INTO dbo.Promotions
    (
        Code,
        Type,
        PromoName,
        PromoDesc,
        StartDate,
        EndDate
    )
    VALUES
    (
        'FSB_TEST',
        'FSB',
        'Fast Start Bonus TEST',
        'Test promotion for FSB integration and QA.',
        '2026-01-01 00:00:00',
        '2026-12-31 23:59:59'
    );
END;

SELECT @PromotionID = PromotionID
FROM dbo.Promotions
WHERE Code = 'FSB_TEST';

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.PromotionProducts
    WHERE PromotionID = @PromotionID
      AND ProductID = 4
)
BEGIN
    INSERT INTO dbo.PromotionProducts
    (
        PromotionID,
        ProductID,
        IsExcluded
    )
    VALUES
    (
        @PromotionID,
        4,
        1
    );
END;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.PromotionProducts
    WHERE PromotionID = @PromotionID
      AND ProductID = 22
)
BEGIN
    INSERT INTO dbo.PromotionProducts
    (
        PromotionID,
        ProductID,
        IsExcluded
    )
    VALUES
    (
        @PromotionID,
        22,
        1
    );
END;
*/
