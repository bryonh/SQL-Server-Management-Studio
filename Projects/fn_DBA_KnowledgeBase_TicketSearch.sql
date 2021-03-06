USE [users]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[fn_DBA_KnowledgeBase_TicketSearch](@Search VarChar(8000),@IncludeArchived BIT)
RETURNS	@Results	Table
		(
		TID		INT
		,Archived	BIT
		)
BEGIN

	INSERT INTO	@Results
	------------------------------------------------------
	------------------------------------------------------
	-- ALL TICKETS WITH SEARCH VALUE
	------------------------------------------------------
	------------------------------------------------------
	SELECT		TID,0		
	FROM		Users.dbo.frmTransactions FT		
	WHERE		CONTAINS (*, @Search)
	UNION
	------------------------------------------------------
	------------------------------------------------------
	-- ALL NOTES WITH SEARCH VALUE
	------------------------------------------------------
	------------------------------------------------------
	SELECT		TID,0
	FROM		Users.dbo.frmNotes
	WHERE		CONTAINS (*, @Search)
	UNION
	------------------------------------------------------
	------------------------------------------------------
	-- ALL FORMS WITH SEARCH VALUE
	------------------------------------------------------
	------------------------------------------------------
	SELECT		TID,0
	FROM		Users.dbo.frmData
	WHERE		CONTAINS (*, @Search)
	UNION
	------------------------------------------------------
	------------------------------------------------------
	-- ALL USERS WITH SEARCH VALUE
	------------------------------------------------------
	------------------------------------------------------
	SELECT		TID,0		
	FROM		Users.dbo.frmTransactions FT
	JOIN		CONTAINSTABLE(users.dbo.tbl_users,*, @Search) UT
		ON	FT.userID	= UT.[KEY]
		OR	FT.handlerID	= UT.[KEY]
		OR	FT.delegateID	= UT.[KEY]
		
	------------------------------------------------------------------------------------------------------------
	------------------------------------------------------------------------------------------------------------
	--					TICKETING ARCHIVE DATA
	------------------------------------------------------------------------------------------------------------
	
	IF @IncludeArchived = 1
	INSERT INTO	@Results
	------------------------------------------------------
	------------------------------------------------------
	-- ALL TICKETS WITH SEARCH VALUE
	------------------------------------------------------
	------------------------------------------------------
	SELECT		TID,1
	FROM		TicketingArchive.dbo.frmTransactions FT		
	WHERE		CONTAINS (*, @Search)
	UNION
	------------------------------------------------------
	------------------------------------------------------
	-- ALL NOTES WITH SEARCH VALUE
	------------------------------------------------------
	------------------------------------------------------
	SELECT		TID,1
	FROM		TicketingArchive.dbo.frmNotes
	WHERE		CONTAINS (*, @Search)
	UNION
	------------------------------------------------------
	------------------------------------------------------
	-- ALL FORMS WITH SEARCH VALUE
	------------------------------------------------------
	------------------------------------------------------
	SELECT		TID,1
	FROM		TicketingArchive.dbo.frmData
	WHERE		CONTAINS (*, @Search)
	UNION
	------------------------------------------------------
	------------------------------------------------------
	-- ALL USERS WITH SEARCH VALUE
	------------------------------------------------------
	------------------------------------------------------
	SELECT		TID,1		
	FROM		TicketingArchive.dbo.frmTransactions FT
	JOIN		CONTAINSTABLE(users.dbo.tbl_users,*, @Search) UT
		ON	FT.userID	= UT.[KEY]
		OR	FT.handlerID	= UT.[KEY]
		OR	FT.delegateID	= UT.[KEY]
	
	RETURN
END	
GO
	
	


DECLARE		@Search		VarChar(8000)
SET		@Search		= 'SQLDEPLOYER02'


SELECT		FT.[TID]
		,[userID]								[UserID_Creator]
		,(SELECT name from tbl_users WHERE ID = [UserID])			[UserName_Creator]
		,[handlerID]								[UserID_Owner]
		,[status]
		,CASE priority
			WHEN 1 THEN 'Low'
			WHEN 2 THEN 'Medium'
			WHEN 3 THEN 'High'
			WHEN 4 THEN 'Critical'
			ELSE 'Project' END						[Priority]
		,CAST(REPLACE(FD.Value,'sev','') AS INT)				[Severity]
		,[subject]
		,[stage]
		,[workflowTitle]
		,[category]
		,[category2]
		,[category3]								[ServiceLevel]
		,'Seattle NOC Ticket'							[Service]
		,timeStamp								[Date Received]
		,timeStamp2								[Date Resolved]
		,timeStamp3								[Date Updated]

FROM		Users.dbo.frmTransactions FT
JOIN		Users.dbo.frmData FD
	ON	FD.TID = FT.TID
	AND	FD.CID IN (14248,14249)
	AND	isnumeric(REPLACE(FD.Value,'sev','')) = 1
JOIN		[Users].[dbo].[fn_DBA_KnowledgeBase_TicketSearch](@Search,0) Search
	ON	Search.TID = FT.TID
WHERE		FT.FID = 840
