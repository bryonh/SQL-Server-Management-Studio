USE DBACENTRAL
GO
ALTER PROCEDURE	dbasp_FileScan_ListServer_WithKnownCondition
		(
		@KnownCondition	sysname
		,@BeginDate	dateTime	= null
		,@EndDate	datetime	= null
		)
AS		
SELECT		DISTINCT
		T1.KnownCondition
		,T1.ErrorCount
		,T1.FirstOccurance
		,T1.LastOccurance
		,T2.*
FROM		(
		SELECT		Machine
				,Instance
				,KnownCondition
				,MIN(EventDateTime) FirstOccurance
				,MAX(EventDateTime) LastOccurance
				,COUNT(*) ErrorCount
		FROM		[dbo].[FileScan_History] 
		WHERE		KnownCondition Like @KnownCondition
			AND	(EventDateTime >= @BeginDate OR @BeginDate IS NULL)
			AND	(EventDateTime < @EndDate OR @EndDate IS NULL)	
		GROUP BY	Machine
				,Instance
				,KnownCondition		
		)T1
JOIN		dbo.ServerInfo T2
	ON	T1.Machine + CASE T1.Instance WHEN '' THEN '' ELSE '\' + T1.Instance END = T2.SQLName
order by	SQLEnv
		,SQL_BitLevel
		,MEM_MB_Total desc
Go


