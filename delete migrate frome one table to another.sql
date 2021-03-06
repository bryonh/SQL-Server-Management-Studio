

DECLARE	@ServerName		SYSNAME
DECLARE ServerName_Cursor	CURSOR
FOR
-- SELECT QUERY FOR CURSOR
SELECT	DISTINCT 
	ServerName 
FROM	[DBAperf_reports].[dbo].[IndexHealth_Results] 
OPEN ServerName_Cursor;
FETCH ServerName_Cursor INTO @ServerName;
WHILE (@@fetch_status <> -1)
BEGIN
	IF (@@fetch_status <> -2)
	BEGIN
		---------------------------- 
		---------------------------- CURSOR LOOP TOP

		DELETE	[DBAperf_reports].[dbo].[IndexHealth_Results]
		OUTPUT	DELETED.*
		INTO	[DBAperf_reports].[dbo].[IndexHealth_Results2]
		WHERE	ServerName = @ServerName

		---------------------------- CURSOR LOOP BOTTOM
		----------------------------
	END
 	FETCH NEXT FROM ServerName_Cursor INTO @ServerName;
END
CLOSE ServerName_Cursor;
DEALLOCATE ServerName_Cursor;
GO

--DROP TABLE [IndexHealth_Results]
--GO
--sp_rename 'IndexHealth_Results2','IndexHealth_Results'
--GO