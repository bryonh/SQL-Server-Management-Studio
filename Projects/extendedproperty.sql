
DECLARE @DBName		sysname
DECLARE @DateTime	DateTime
SET		@DBName		= DB_Name()
SET		@DateTime	= GetDate()
-------------------------------------------------------------------
-------------------------------------------------------------------
-- CHECK & SET ORIGINSERVER
-------------------------------------------------------------------
-------------------------------------------------------------------
If Not EXISTS (SELECT Value FROM ::fn_listextendedproperty(N'OriginServer', NULL, NULL, NULL, NULL, NULL, NULL))
	EXEC dbo.sp_addextendedproperty	@name	=N'OriginServer'	,@value=@@ServerName
-------------------------------------------------------------------
-------------------------------------------------------------------
-- CHECK & SET ORIGINDATABASE
-------------------------------------------------------------------
-------------------------------------------------------------------
If Not EXISTS (SELECT Value FROM ::fn_listextendedproperty(N'OriginDatabase', NULL, NULL, NULL, NULL, NULL, NULL))
	EXEC dbo.sp_addextendedproperty	@name	=N'OriginDatabase'	,@value=@DBName



-------------------------------------------------------------------
-------------------------------------------------------------------
-- CHECK, SET, & UPDATE ORIGINDATE 
-- SHOULD BE DONE JUST BEFORE ALL BACKUPS
-------------------------------------------------------------------
-------------------------------------------------------------------
If Not EXISTS (SELECT Value FROM ::fn_listextendedproperty(N'OriginDate', NULL, NULL, NULL, NULL, NULL, NULL))
	EXEC dbo.sp_addextendedproperty	@name	=N'OriginDate'	,@value=@DateTime
ELSE
	IF		@@ServerName = (SELECT Value FROM ::fn_listextendedproperty(N'OriginServer', NULL, NULL, NULL, NULL, NULL, NULL))
	 AND	@DBName = (SELECT Value FROM ::fn_listextendedproperty(N'OriginDatabase', NULL, NULL, NULL, NULL, NULL, NULL))
		exec dbo.sp_updateextendedproperty @name	=N'OriginDate'	,@value=@DateTime



-------------------------------------------------------------------
-------------------------------------------------------------------
-- BUILD OPSDB LIST
-------------------------------------------------------------------
-------------------------------------------------------------------
DECLARE		@OpsDBList	Table (DBName sysname)
INSERT INTO	@OpsDBList
SELECT		name
FROM		master..sysdatabases
WHERE		dbid < 5
OR			name IN ('dbaadmin','dbaperf','sysinfo')

-- IF ORIGIN NAME IS AN OPSDB ADD CURRENT NAME TO LIST
INSERT INTO	@OpsDBList(DBName) 
SELECT		@DBName 
FROM		::fn_listextendedproperty(N'OriginDatabase', NULL, NULL, NULL, NULL, NULL, NULL)
WHERE		Value IN (SELECT DBName From @OpsDBList)
-------------------------------------------------------------------
-------------------------------------------------------------------
-- CHECK & SET OPPSDB
-------------------------------------------------------------------
-------------------------------------------------------------------
IF @DBName IN (SELECT DBName From @OpsDBList) 
AND Not EXISTS (SELECT Value FROM ::fn_listextendedproperty(N'OppsDB', NULL, NULL, NULL, NULL, NULL, NULL))
	EXEC dbo.sp_addextendedproperty		@name	=N'OppsDB'	,@value='true'




-------------------------------------------------------------------
-------------------------------------------------------------------
-- RETURN ALL DB EXTENDED PROPERTIES
-------------------------------------------------------------------
-------------------------------------------------------------------
SELECT Name,Value FROM ::fn_listextendedproperty(default, NULL, NULL, NULL, NULL, NULL, NULL)



GO





DECLARE @TSQL	VarChar(8000)
SET		@TSQL	=
'USE ?
DECLARE @DBName		sysname
DECLARE @DateTime	DateTime
SET		@DBName		= DB_Name()
SET		@DateTime	= GetDate()
If Not EXISTS (SELECT Value FROM ::fn_listextendedproperty(N''OriginServer'', NULL, NULL, NULL, NULL, NULL, NULL))
	EXEC dbo.sp_addextendedproperty	@name	=N''OriginServer''	,@value=@@ServerName
If Not EXISTS (SELECT Value FROM ::fn_listextendedproperty(N''OriginDatabase'', NULL, NULL, NULL, NULL, NULL, NULL))
	EXEC dbo.sp_addextendedproperty	@name	=N''OriginDatabase''	,@value=@DBName
If Not EXISTS (SELECT Value FROM ::fn_listextendedproperty(N''OriginDate'', NULL, NULL, NULL, NULL, NULL, NULL))
	EXEC dbo.sp_addextendedproperty	@name	=N''OriginDate''	,@value=@DateTime
ELSE
	IF		@@ServerName = (SELECT Value FROM ::fn_listextendedproperty(N''OriginServer'', NULL, NULL, NULL, NULL, NULL, NULL))
	 AND	@DBName = (SELECT Value FROM ::fn_listextendedproperty(N''OriginDatabase'', NULL, NULL, NULL, NULL, NULL, NULL))
		exec dbo.sp_updateextendedproperty @name	=N''OriginDate''	,@value=@DateTime
DECLARE		@OpsDBList	Table (DBName sysname)
INSERT INTO	@OpsDBList
SELECT		name
FROM		master..sysdatabases
WHERE		dbid < 5
OR			name IN (''dbaadmin'',''dbaperf'',''sysinfo'')
INSERT INTO	@OpsDBList(DBName) 
SELECT		@DBName 
FROM		::fn_listextendedproperty(N''OriginDatabase'', NULL, NULL, NULL, NULL, NULL, NULL)
WHERE		Value IN (SELECT DBName From @OpsDBList)
IF @DBName IN (SELECT DBName From @OpsDBList) 
AND Not EXISTS (SELECT Value FROM ::fn_listextendedproperty(N''OppsDB'', NULL, NULL, NULL, NULL, NULL, NULL))
	EXEC dbo.sp_addextendedproperty		@name	=N''OppsDB''	,@value=''true''
SELECT Name,Value FROM ::fn_listextendedproperty(default, NULL, NULL, NULL, NULL, NULL, NULL)'

exec sp_MSForEachDB @TSQL

-- get all db options for all dbs.

CREATE TABLE #ExtendedProperties
		(
		DatabaseName	sysname
		,Name			sysname
		,Value			sql_variant
		)

exec sp_MSForEachDB 'INSERT INTO #ExtendedProperties select ''?'',Name,Value From [?].sys.extended_properties where class_desc = ''DATABASE'''

SELECT * FROM #ExtendedProperties