USE [AssetKeyword]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

	
ALTER PROCEDURE [dbo].[SaveAssetDeltasJob130_XPATH]
		@Username		VARCHAR(100)
		,@UserGroupCode		VARCHAR(10)
		,@AssetDeltasXML	NVARCHAR(MAX)
		,@oiErrorID		int			= 0	OUTPUT -- App-defined error if non-zero. 
		,@ovchErrorMessage	nvarchar(256)		= ''	OUTPUT -- Text description of app-defined error
AS

/* 
---------------------------------------------------------------------------
---------------------------------------------------------------------------
	Procedure: [SaveAssetDeltasJob130]
	For: Getty Images

	Revision History
		Created:	 
		
		Modified:	05/02/2007	jboen, Added logic to supply additional information into the VitriaEventLog table.
		Modified:	05/06/2008	Ziji Huang, Added @UserGroupCode parameter for auditing
			Added logic to audit StageID changes of Assets
			Modified Keyword delete logic use IsDeleted to perform soft deletion of AssetKeyword table records
			Added logic to audit Keyword changes of Assets
		Modified:	05/11/2008	Ziji Huang, Modified to use isnull() to replace nullif() to fix bug
		Modified:	05/16/2008	Ziji Huang, Modified to set Confidence = 5 for AssetKeyword Delete actions by a user
		Modified:	01/22/2009	Ziji Huang, Modified to set StackPriority = 60 as suggested by Michael Kosten
		Modified:	04/15/2009	Ziji Huang, Added logic to handle AssetRulesQueue, reduce frequency for indexing and republishing
        Modified:   05/07/2009  Michael Kosten, Optimized to resolve blocking issues and improve speed
		Modified:   06/10/2009  Michael Kosten, Workaround for bug in adding required term that is also upserted by job
		Modified:   06/15/2009  Michael Kosten, Revise prior change because bug is fixed in web method
		Modofied:   10/26/2009  Michael Kosten, Modified to set WeightConfidence and add option for not changing weight
		

	Return Values
		0:	Success
		-999:	Some failure; check output parameters
---------------------------------------------------------------------------
--------------------------------------------------------------------------- 
*/

/*
  <?xml version="1.0" encoding="utf-16" ?> 
- <AssetDeltaSets>
  <MasterIDs>56415050</MasterIDs> 
- <Deltas>
  <DeltaType>Update</DeltaType> 
  <FieldType>Info</FieldType> 
  <ItemID>0</ItemID> 
  <ItemValue>2</ItemValue> 
  </Deltas>
- <Deltas>
  <DeltaType>Delete</DeltaType> 
  <FieldType>Keyword</FieldType> 
  <ItemID>36108</ItemID> 
  <ItemValue>0</ItemValue> 
  </Deltas>
- <Deltas>
  <DeltaType>Upsert</DeltaType> 
  <FieldType>Keyword</FieldType> 
  <ItemID>36109</ItemID> 
  <ItemValue>5</ItemValue> 
  </Deltas>
  </AssetDeltaSet>

*/

SET NOCOUNT ON

CREATE TABLE #AssetsToIndex (MasterID varchar(50) not null)

BEGIN TRY
	DECLARE @XML XML
	DECLARE @dtStart datetime
	DECLARE @KeywordsModified bit
	DECLARE @MetadataModified bit
	DECLARE @VocabularyModified bit
	DECLARE @Delim char(1)
	DECLARE @VitriaPublishPriority varchar(10)
	DECLARE @BlockVitriaPublish bit
	DECLARE @BlockVitriaPublishString varchar(10)
	DECLARE	@WorkingID INT

	SET @dtStart = getdate()
	SET @KeywordsModified = 0
	SET @MetadataModified = 0
	SET @VocabularyModified = 0
	SET @Delim = ','
	SET @BlockVitriaPublish = 0

	DECLARE @indexPriority TINYINT
	
    DECLARE @Asset TABLE (
			MasterID varchar(50), 
			ResultCode int, 
			ResultMsg varchar(1000) )

    DECLARE @InfoDeltas TABLE (
			DeltaType varchar(20) null,
			FieldType varchar(50) null,
			ItemID int null,
			ItemValue varchar(2000) null)

    DECLARE @KeywordDeltas TABLE (
			DeltaType varchar(20) null,
			TermID int null,
			Weight int null)

	DECLARE		@Deltas TABLE	(
					DeltaType	varchar(20)	null
					,FieldType	varchar(50)	null
					,ItemID		int		null
					,ItemValue	varchar(2000)	null
					)


	IF OBJECT_ID('tempdb..#XMLDATA') IS NOT NULL
	       DROP TABLE #XMLDATA

	CREATE TABLE #XMLDATA 
		      (
		      id        INT PRIMARY KEY CLUSTERED IDENTITY, -- primary key required if XML index needed
		      XMLDOC	XML
		      )

	CREATE PRIMARY XML INDEX PXML_XMLDATA
	ON #XMLDATA (XMLDOC)

					
	SET @XML = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@AssetDeltasXML,'<?xml version="1.0" encoding="utf-16"?>',''),' <','<'),' <','<'),' <','<'),' <','<'),' >','>'),' >','>'),' >','>'),' >','>')

	INSERT INTO  #XMLDATA (XMLDOC) VALUES(@XML)
	SET           @WorkingID = SCOPE_IDENTITY()
	
	INSERT INTO	@Asset		
	SELECT		x.value('.[1]', 'VARCHAR(50)')	MasterID
			,0				ResultCode
			,''				ResultMsg
	FROM		@XML.nodes(N'/AssetDeltaSet/MasterIDs') t(x)		

	INSERT INTO	@Deltas
	SELECT		 x.value('DeltaType[1]'	,'varchar(20)')		DeltaType
			,x.value('FieldType[1]'	,'VARCHAR(50)')		FieldType
			,x.value('ItemID[1]'	,'INT')			ItemID
			,x.value('ItemValue[1]'	,'varchar(2000)')	ItemValue
	FROM		#XMLDATA 
	CROSS APPLY	[XMLDOC].nodes(N'/AssetDeltaSet/Deltas') t(x)
	WHERE		id = @WorkingID

	/* mark invalid ones as result 1000 */
	UPDATE		@Asset 
		set	ResultCode = 1000
	FROM		@Asset a
	WHERE		MasterID NOT IN (SELECT MasterID FROM dbo.AssetStatus WITH (NOLOCK))


	INSERT INTO	@InfoDeltas
	SELECT		 DeltaType
			,FieldType
			,ItemID
			,ItemValue
	FROM		@Deltas
	WHERE		FieldType = 'Info'
						
	INSERT INTO	@KeywordDeltas		
	SELECT		DeltaType
			,ItemID
			,ItemValue	   
	FROM		@Deltas
	WHERE		FieldType = 'Keyword'
	
	SELECT		@VitriaPublishPriority		= x.value('(./VitriaPublishPriority[1]/@*)[1]'	,'varchar(10)')
			,@BlockVitriaPublishString	= x.value('(./BlockVitriaPublish[1]/@*)[1]'	,'VARCHAR(10)')
	FROM		#XMLDATA 
	CROSS APPLY	[XMLDOC].nodes(N'/AssetDeltaSet') t(x)
	WHERE		id = @WorkingID

	IF lower(@BlockVitriaPublishString) = 'true' set @BlockVitriaPublish = 1
	SET @VitriaPublishPriority = nullif(@VitriaPublishPriority,'')

	IF NOT EXISTS ( SELECT 1 FROM @Asset)
	begin
		set @ovchErrorMessage='No assets specified'
		RAISERROR(@ovchErrorMessage, 15, 1)
	end

	declare @dt datetime
	set @dt = getutcdate()

	-- Collect list of assets with modifications for AssetStatus and QueuedAsset updates at end
	DECLARE @AssetsTouched TABLE (
	MasterID varchar(50)
	, KeywordsUpdated tinyint
	)
	DECLARE @AuditStageID TABLE (
	MasterID varchar(50) NOT NULL
	, StageIDPrevious tinyint NOT NULL
	, StageID tinyint NOT NULL
	)
	DECLARE @AuditAK TABLE (
	MasterID varchar(50) NOT NULL
	, TermID int NOT NULL
	, ConfidencePrevious tinyint NOT NULL
	, Confidence tinyint NOT NULL
	, WeightPrevious tinyint NOT NULL
	, Weight tinyint NOT NULL
	, WeightConfidencePrevious tinyint NULL
	, WeightConfidence tinyint NULL
	)

	DECLARE	@KEYWORDS_DELETED tinyint,
			@KEYWORDS_UPDATED tinyint,
			@KEYWORDS_NOT_UPDATED tinyint,
			@AKAUDIT_ADD tinyint,
			@AKAUDIT_UPDATE tinyint,
			@AKAUDIT_DELETE tinyint
			

	SELECT	@KEYWORDS_DELETED = 2,
			@KEYWORDS_UPDATED = 1,
			@KEYWORDS_NOT_UPDATED = 0,
			@AKAUDIT_ADD = 10,
			@AKAUDIT_UPDATE = 20,
			@AKAUDIT_DELETE = 30

	-- ===============================================
	/* INFO UPDATES: single value fields */
	-- Info.StageID --
	if (select count(*) from @InfoDeltas InfoDeltas where InfoDeltas.ItemID = 0 AND InfoDeltas.DeltaType = 'Update') > 0
	BEGIN
		-- build any missing AssetStatusHistory records for this asset
		DECLARE @InferredAuditHistory TABLE (MasterID varchar(50))

		-- Add missing AuditStageHistory from current data
		-- First, add Stage 0 if no history
		INSERT INTO dbo.AssetStageHistory (MasterID, StageIDPrevious, StageID, ChangeDate, EndDate, Username, UserGroupCode, SequenceNo)
		OUTPUT Inserted.MasterID INTO @InferredAuditHistory
		SELECT DISTINCT Asset.MasterID, 0, 0, Asset.AddedToAKSDate, case when AssetStatus.StageID = 0 then null else AssetStatus.StageLastUpdated end, 'SYSTEM', 'SYSTEM', 1
		FROM @Asset a
		JOIN dbo.AssetStatus WITH (NOLOCK)
		  ON a.MasterID = AssetStatus.MasterID
		JOIN dbo.Asset WITH (NOLOCK)
		  ON a.MasterID = Asset.MasterID
		LEFT JOIN dbo.AssetStageHistory WITH (NOLOCK)
		  ON a.MasterID = AssetStageHistory.MasterID
	   CROSS JOIN @InfoDeltas InfoDeltas
	   WHERE AssetStageHistory.AssetStageHistoryID IS NULL
		 AND InfoDeltas.ItemID = 0 
		 AND InfoDeltas.DeltaType = 'Update'
		 AND AssetStatus.StageID <> cast(InfoDeltas.ItemValue as int)

		-- Add history for current stage for these if not currently stage 0
		INSERT INTO dbo.AssetStageHistory (MasterID, StageIDPrevious, StageID, ChangeDate, Username, UserGroupCode, SequenceNo)
		SELECT DISTINCT AssetStatus.MasterID, 0, AssetStatus.StageID, AssetStatus.StageLastUpdated, 'SYSTEM', 'SYSTEM', 2
		  FROM @InferredAuditHistory iah
		  JOIN dbo.AssetStatus WITH (NOLOCK)
			ON iah.MasterID = AssetStatus.MasterID
		 WHERE AssetStatus.StageID <> 0 

		DELETE FROM @AuditStageID

		UPDATE dbo.AssetStatus set
		StageID = cast(InfoDeltas.ItemValue as tinyint)
		, StageLastUpdated = @dt
		, StageLastUpdatedBy = @Username
		OUTPUT INSERTED.MasterID, isnull(DELETED.StageID, 0), cast(InfoDeltas.ItemValue as tinyint) INTO @AuditStageID
		FROM @Asset a CROSS JOIN @InfoDeltas InfoDeltas
		WHERE InfoDeltas.ItemID = 0 
			AND InfoDeltas.DeltaType = 'Update'
			AND dbo.AssetStatus.MasterID = a.MasterID
			AND dbo.AssetStatus.StageID <> cast(InfoDeltas.ItemValue as int)
	   
		-- For capturing new AssetStatusHistoryID values for AssetStatus table
		DECLARE @AssetStageHistoryID TABLE (AssetStageHistoryID bigint, MasterID varchar(50), SequenceNo int)

		INSERT INTO dbo.AssetStageHistory (MasterID, StageIDPrevious, StageID, ChangeDate, Username ,UserGroupCode, SequenceNo)
		OUTPUT INSERTED.AssetStageHistoryID, INSERTED.MasterID, INSERTED.SequenceNo INTO @AssetStageHistoryID
			SELECT DISTINCT MasterID, StageIDPrevious, StageID, @dt, @Username, @UserGroupCode,
							isnull((SELECT MAX(SequenceNo)
									  FROM AssetStageHistory WITH (NOLOCK)
									 WHERE MasterID = asi.MasterID), 0) + 1 SequenceNo
			FROM @AuditStageID asi

		UPDATE dbo.AssetStageHistory
		   SET EndDate = @dt
		  FROM dbo.AssetStageHistory WITH (NOLOCK)
		  JOIN @AssetStageHistoryID ashi
			ON AssetStageHistory.MasterID = ashi.MasterID
		   AND AssetStageHistory.SequenceNo = ashi.SequenceNo - 1
	    
		UPDATE dbo.AssetStatus
		   SET AssetStageHistoryID = ashi.AssetStageHistoryID
		  FROM dbo.AssetStatus WITH (NOLOCK)
		  JOIN @AssetStageHistoryID ashi
			ON ashi.MasterID = AssetStatus.MasterID

		INSERT INTO @AssetsTouched (MasterID, KeywordsUpdated)
			SELECT DISTINCT MasterID, @KEYWORDS_NOT_UPDATED
			FROM @AuditStageID
	END
	-- ===============================================

	-- ===============================================
	-- KEYWORD UPDATES
	-- 1. special delete
	-- 2. delete
	-- 3. update (update and update step of upsert)
	-- 4. insert (insert and insert step of upsert)
	-- ===============================================

	-- 1. Special delete, if there is a deletekeyword with KeywordID of -1
	IF EXISTS(select * from @KeywordDeltas where DeltaType = 'Delete' and TermID = -1)
	BEGIN
		SET @KeywordsModified = 1

		DELETE FROM @AuditAK
		UPDATE dbo.AssetKeyword SET
		IsDeleted = 1
		, Confidence = 5
		, UpdatedDate = @dt
		, UpdatedBy = @Username
		OUTPUT DELETED.MasterID, DELETED.TermID, isnull(DELETED.Confidence, 0), isnull(INSERTED.Confidence, 0)
			, isnull(DELETED.Weight, 0) , isnull(DELETED.Weight, 0)
			, DELETED.WeightConfidence , DELETED.WeightConfidence INTO @AuditAK
		FROM @Asset a
		WHERE dbo.AssetKeyword.MasterID = a.MasterID
		
		-- Audit
		INSERT INTO dbo.AssetKeywordHistory (
		MasterID, TermID, ConfidencePrevious, Confidence, WeightPrevious, Weight, WeightConfidencePrevious
		, WeightConfidence, ActionID, ActionDate, Username, UserGroupCode)
			SELECT MasterID, TermID, ConfidencePrevious, Confidence, WeightPrevious, Weight, WeightConfidencePrevious
			, WeightConfidence, @AKAUDIT_DELETE, @dt, @Username, @UserGroupCode
			FROM @AuditAK

		-- @AssetsTouched
		INSERT INTO @AssetsTouched (MasterID, KeywordsUpdated)
			SELECT DISTINCT MasterID, @KEYWORDS_DELETED
			FROM @AuditAK

	END

	-- 2. normal delete
	IF EXISTS(select 1 from @KeywordDeltas where DeltaType = 'Delete')
	BEGIN
		SET @KeywordsModified = 1

		DELETE FROM @AuditAK
		UPDATE dbo.AssetKeyword SET
		IsDeleted = 1
		, Confidence = 5
		, UpdatedDate = @dt
		, UpdatedBy = @Username
		OUTPUT DELETED.MasterID, DELETED.TermID, isnull(DELETED.Confidence, 0), isnull(INSERTED.Confidence, 0)
			, isnull(DELETED.Weight, 0) , isnull(DELETED.Weight, 0)
			, DELETED.WeightConfidence , DELETED.WeightConfidence INTO @AuditAK
		FROM dbo.AssetKeyword WITH (NOLOCK, INDEX(AssetKeyword_PK))
        JOIN (SELECT a.MasterID, KeywordDeltas.TermID
                FROM @Asset a
                JOIN @KeywordDeltas KeywordDeltas
				  ON a.ResultCode = 0
                 AND KeywordDeltas.DeltaType = 'Delete') DeleteTerms
          ON AssetKeyword.MasterID = DeleteTerms.MasterID
         AND AssetKeyword.TermID = DeleteTerms.TermID
		
		-- Audit
		INSERT INTO dbo.AssetKeywordHistory (
		MasterID, TermID, ConfidencePrevious, Confidence, WeightPrevious, Weight, WeightConfidencePrevious
		, WeightConfidence, ActionID, ActionDate, Username, UserGroupCode)
			SELECT MasterID, TermID, ConfidencePrevious, Confidence, WeightPrevious, Weight, WeightConfidencePrevious
			, WeightConfidence, @AKAUDIT_DELETE, @dt, @Username, @UserGroupCode
			FROM @AuditAK

		-- @AssetsTouched
		INSERT INTO @AssetsTouched (MasterID, KeywordsUpdated)
			SELECT DISTINCT MasterID, @KEYWORDS_DELETED
			FROM @AuditAK
	END

	-- 3. Update (weight)
	IF EXISTS(select 1 from @KeywordDeltas where DeltaType IN ('Update','Upsert'))
	BEGIN
		SET @KeywordsModified = 1

		DELETE FROM @AuditAK
		UPDATE dbo.AssetKeyword
		   SET Weight = case when UpdateTerms.Weight >= 0 then UpdateTerms.Weight else isnull(AssetKeyword.Weight, 0) end,
		       Confidence = 5,
		       WeightConfidence = case when UpdateTerms.Weight >= 0 then 5 else AssetKeyword.WeightConfidence end,
		       UpdatedDate = @dt,
		       UpdatedBy = @Username
		OUTPUT DELETED.MasterID, DELETED.TermID, isnull(DELETED.Confidence, 0), isnull(INSERTED.Confidence, 0)
			, isnull(DELETED.Weight, 0), INSERTED.Weight
			, DELETED.WeightConfidence, INSERTED.WeightConfidence INTO @AuditAK
		FROM dbo.AssetKeyword WITH (NOLOCK, INDEX(AssetKeyword_PK))
        JOIN (SELECT a.MasterID, KeywordDeltas.TermID, KeywordDeltas.Weight
                FROM @Asset a
                JOIN @KeywordDeltas KeywordDeltas
                  ON a.ResultCode = 0
                 AND (KeywordDeltas.DeltaType = 'Update' or KeywordDeltas.DeltaType = 'Upsert')) UpdateTerms
          ON AssetKeyword.MasterID = UpdateTerms.MasterID
         AND AssetKeyword.TermID = UpdateTerms.TermID
         AND ISNULL(dbo.AssetKeyword.IsDeleted, 0) = 0
	--	WHERE (isnull(dbo.AssetKeyword.Weight, 0) <> isnull(KeywordDeltas.Weight, 0) OR dbo.AssetKeyword.Confidence <> 5)

		-- Remove NoOp changes to prevent nuisance audit trail
		DELETE @AuditAK
		 WHERE Weight = WeightPrevious
           AND Confidence = ConfidencePrevious
		   AND isnull(WeightConfidence, 0) = isnull(WeightConfidencePrevious, 0)

		-- Audit
		INSERT INTO dbo.AssetKeywordHistory (
		MasterID, TermID, ConfidencePrevious, Confidence, WeightPrevious, Weight, WeightConfidencePrevious
		, WeightConfidence, ActionID, ActionDate, Username, UserGroupCode
		)
			SELECT MasterID, TermID, ConfidencePrevious, Confidence, WeightPrevious, Weight, WeightConfidencePrevious
			, WeightConfidence, @AKAUDIT_UPDATE, @dt, @Username, @UserGroupCode
			FROM @AuditAK

		-- @AssetsTouched
		INSERT INTO @AssetsTouched (MasterID, KeywordsUpdated)
			SELECT DISTINCT MasterID, @KEYWORDS_UPDATED
			FROM @AuditAK
	END

	-- 3. Insert (weight)
	IF EXISTS(select 1 from @KeywordDeltas where DeltaType IN ('Insert','Upsert'))
	BEGIN
		SET @KeywordsModified = 1

		DELETE FROM @AuditAK
		-- Get set of records to insert. Separate NOLOCK SELECT from INSERT to reduce time intent exclusive lock held on AK table.
		INSERT INTO @AuditAK (MasterID, TermID, ConfidencePrevious, Confidence, WeightPrevious, Weight, WeightConfidencePrevious, WeightConfidence)
		SELECT InsertTerms.MasterID, -- MasterID
		       InsertTerms.TermID, -- TermID
		       0, -- ConfidencePrevious
		       5, -- Confidence
		       0, -- WeightPrevious
		       case when InsertTerms.Weight >= 0 then InsertTerms.Weight else 0 end, -- Weight
		       0, -- WeightConfidencePrevious
		       case when InsertTerms.Weight >= 0 then 5 else 0 end -- WeightConfidence
         FROM (SELECT a.MasterID, KeywordDeltas.TermID, KeywordDeltas.Weight
                 FROM @Asset a
                 JOIN @KeywordDeltas KeywordDeltas
                  ON a.ResultCode = 0
                  AND (KeywordDeltas.DeltaType = 'Insert' OR KeywordDeltas.DeltaType = 'Upsert')) InsertTerms
         LEFT JOIN dbo.AssetKeyword WITH (NOLOCK, INDEX(AssetKeyword_PK))
           ON AssetKeyword.MasterID = InsertTerms.MasterID
          AND AssetKeyword.TermID = InsertTerms.TermID
        WHERE AssetKeyword.MasterID IS NULL
           OR AssetKeyword.IsDeleted = 1

		-- Update AssetKeyword.IsDelete = 0 for matching @AuditAK records where AssetKeyword.IsDelete = 1
		UPDATE dbo.AssetKeyword SET
		IsDeleted = 0
		, Weight = ad.Weight
		, Confidence = ad.Confidence
		, WeightConfidence = ad.WeightConfidence
		, UpdatedDate = @dt
		, UpdatedBy = @Username
        FROM [dbo].[AssetKeyword] WITH (INDEX(AssetKeyword_PK))
		JOIN @AuditAK AS ad
		  ON ad.MasterID = dbo.AssetKeyword.MasterID
		 AND ad.TermID = dbo.AssetKeyword.TermID
		 AND dbo.AssetKeyword.IsDeleted = 1

		-- Insert records that exist in @AuditAK but not exist in AssetKeyword table yet
		INSERT INTO dbo.AssetKeyword (
		MasterID, TermID, Weight, Confidence, WeightConfidence
		, CreatedDate, CreatedBy, UpdatedDate, UpdatedBy, IsDeleted
		)
			SELECT ad.MasterID, ad.TermID, ad.Weight, ad.Confidence, ad.WeightConfidence
			, @dt, @Username, @dt, @Username, 0
			FROM @AuditAK AS ad
				LEFT JOIN dbo.AssetKeyword AS ak WITH (NOLOCK) ON ad.MasterID = ak.MasterID AND ad.TermID = ak.TermID
			WHERE ak.MasterID IS NULL

		-- Audit
		INSERT INTO dbo.AssetKeywordHistory (
		MasterID, TermID, ConfidencePrevious, Confidence, WeightPrevious, Weight, WeightConfidencePrevious
		, WeightConfidence, ActionID, ActionDate, Username, UserGroupCode
		)
			SELECT MasterID, TermID, ConfidencePrevious, Confidence, WeightPrevious, Weight, WeightConfidencePrevious
			, WeightConfidence, @AKAUDIT_ADD, @dt, @Username, @UserGroupCode
			FROM @AuditAK

		-- @AssetsTouched
		INSERT INTO @AssetsTouched (MasterID, KeywordsUpdated)
			SELECT DISTINCT MasterID, @KEYWORDS_UPDATED
			FROM @AuditAK
	END

	DECLARE @eventType varchar(30)
	SELECT @eventType = 'SaveAssetDeltas'  
	IF EXISTS (
		SELECT *
		FROM @AssetsTouched
	)
	BEGIN
		DECLARE @RetStatus int
		
		-- Update AssetStatus of all assets affected by keyword updates ONLY
		UPDATE dbo.AssetStatus SET
		KeywordsLastUpdated = @dt
		, KeywordsLastUpdatedBy = @Username
		FROM dbo.AssetStatus AST
		WHERE AST.MasterID IN (
			SELECT DISTINCT MasterID
			FROM @AssetsTouched
			WHERE KeywordsUpdated = @KEYWORDS_UPDATED or KeywordsUpdated = @KEYWORDS_DELETED
		)
		
		-- Add to indexing queue all assets affected by ALL updates
		-- if number of assets affected is large, lower the priority
		IF( SELECT COUNT(*) FROM @AssetsTouched ) >= 500
			SET @indexPriority = 50
		ELSE
			SET @indexPriority = 25

        INSERT #AssetsToIndex (MasterID)
		SELECT DISTINCT MasterID FROM @AssetsTouched
		IF @KeywordsModified = 1 OR @MetadataModified = 1
		BEGIN
			-- ===============================================
			-- if there is any Keyword or Metadata change, don't push to FAST index queue
			-- ===============================================
			EXEC @RetStatus= dbo.QueueAssetsForRules05 
				@indexPriority, @KeywordsModified, @MetadataModified, @VocabularyModified, @VitriaPublishPriority, @BlockVitriaPublish
			IF @RetStatus <> 0 RAISERROR('Error in QueueAssetsForRules', 15, 1)
		END
		ELSE
		BEGIN
			-- ===============================================
			-- if no Keyword or Metadata change, push to FAST index queue
			-- ===============================================
			EXEC @RetStatus=QueueAssetsForIndexing
				@indexPriority, @eventType -- uses #AssetsToIndex
			IF @RetStatus <> 0 RAISERROR('Error in QueueAssetsForIndexing', 15, 1)
		END

		-- ===============================================
		-- don't push to stacking queue
		-- ===============================================
	END

	-- ===============================================
	-- Log with us
	declare @duration int
	declare @assetcount int
	declare @keywordcount int

	set @duration = DateDiff(ss, @dtStart, getdate())
	select @assetcount = count(*) from @Asset where resultcode = 0
	select @keywordcount = count(*) from @InfoDeltas
	select @keywordcount = @keywordCount + count(*) from @KeywordDeltas

	exec dbo.LogEvent 
		@duration = @duration
		, @assetcount = @assetcount	-- show # assets attempted (that exist), not # actually processed by db, FAST indexer, or Vitria
		, @keywordcount = @keywordcount
		, @loglevel = 20
		, @username = @username
		, @eventType = @eventType
	-- ===============================================

	-- ===============================================
	-- don't publish
	-- ===============================================

END TRY
BEGIN CATCH

-------------------------------------------
-- Error handler
-------------------------------------------
	IF XACT_STATE() = -1 ROLLBACK TRAN
	IF OBJECT_ID('TEMPDB..#AssetsToIndex','U') IS NOT NULL DROP TABLE #AssetsToIndex

-- Log error
	DECLARE @ErrMsg nvarchar(4000), 
			@ErrSeverity int

	SELECT	@ErrMsg = ERROR_MESSAGE(),
			@ErrSeverity = ERROR_SEVERITY(),
			@duration = DateDiff(ss, @dtStart, getdate())

	EXEC dbo.LogEvent 
		@duration = @duration,
		@loglevel = 5,
		@username = 'SaveAssetDeltasJob',
		@eventType = 'SaveAssetDeltas',
		@eventData = @ErrMsg

	--RAISERROR(@ErrMsg, @ErrSeverity, 1)	--  in case ever called by code
	RETURN -999

END CATCH

-------------------------------------------
-- Normal exit
-------------------------------------------
NormalExit:
	IF OBJECT_ID('TEMPDB..#AssetsToIndex','U') IS NOT NULL DROP TABLE #AssetsToIndex
	RETURN 0
GO
