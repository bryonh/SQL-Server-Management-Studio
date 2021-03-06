USE [DEPLcontrol]
GO
/****** Object:  View [dbo].[DBA_DashBoard_GearsTicketDetails_Local_Prod]    Script Date: 10/4/2013 11:02:05 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW	[dbo].[DBA_DashBoard_GearsTicketDetails_Local_Prod]
AS
SELECT		[Gears_id]
		,[APPLname] AS [APPL]	 
		,T1.[DBname] AS [DB]	 
		,[Process]  AS [Process]	 
		,[ProcessType]  AS [Type]	 
		,[ProcessDetail]  AS [Detail] 	 
		,[Status] AS [Status] 	 
		,[SQLname]  AS [SQL] 	 
		,[Domain]  AS [Domain] 	 
		,[BASEfolder] AS [Base] 	 	 
		,'file://\\'+LEFT([SQLname],CHARINDEX('\',[SQLname]+'\')-1) AS [Go]
		,CASE [Process] WHEN 'Start' THEN 1 WHEN 'Restore' THEN 2 WHEN 'Deploy' THEN 3 WHEN 'End' THEN 4 END AS [RecordOrder]
		,T2.[seq_id]
		,T1.[reqdet_id]
FROM		[DEPLcontrol].[dbo].[Request_detail] T1 WITH(NOLOCK)
LEFT JOIN	[DEPLcontrol].[dbo].[db_sequence] T2 WITH(NOLOCK)
	ON	T1.[DBName] = T2.[dbname]
WHERE		[Domain] = 'PRODUCTION'

GO
