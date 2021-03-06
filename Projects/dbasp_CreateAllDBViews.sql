USE [dbaadmin]
GO
/****** Object:  StoredProcedure [dbo].[dbasp_CreateAllDBViews]    Script Date: 11/22/2011 10:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[dbasp_CreateAllDBViews] 
			(
			@Age				INT				= 60 -- RECREATE IF OLDER THAN 60 MINUTES
			)
AS
--#region DOCUMENTATION HEADDER
/****************************************************************************
<CommentHeader>
	<VersionControl>
 		<DatabaseName>DBAADMIN</DatabaseName>				
		<SchemaName>dbo</SchemaName>
		<ObjectType>Procedure</ObjectType>
		<ObjectName>dbasp_CreateAllDBViews</ObjectName>
		<Version>1.0.0</Version>
		<Build Number="" Application="" Branch=""/>
		<Created By="Steve Ledridge" On="10/14/2011"/>
		<Modifications>
			<Mod By="" On="" Reason=""/>
			<Mod By="" On="" Reason=""/>
		</Modifications>
	</VersionControl>
	<Purpose>Drop and Recreate a set ov views used by several Index Maint Processes</Purpose>
	<Description>Uses the default or passed in value to evaluate existing views or synonyms and replace them when older in minutes to the value</Description>
	<Dependencies>
		<Object Type="" Schema="" Name="" VersionCompare="" Version=""/>
	</Dependencies>
	<Parameters>
		<Parameter Type="Int" Name="@Age" Desc="Age limit to keep existing views rather than replacing them"/>
	</Parameters>
	<Permissions>
		<Perm Type="" Priv="" To="" With=""/>
	</Permissions>
</CommentHeader>
*****************************************************************************/
--#endregion
BEGIN

	DECLARE		@TSQL1				VarChar(max)
				,@TSQL2				VarChar(max)
				,@SchemaName		sysname
				,@TableName			sysname

	DECLARE		CreateAllDBViews	CURSOR
	FOR
	SELECT 'sys','tables'
	UNION ALL
	SELECT 'sys','schemas'
	UNION ALL
	SELECT 'sys','sysindexes'
	UNION ALL
	SELECT 'sys','indexes'
	UNION ALL
	SELECT 'sys','dm_db_partition_stats'
	UNION ALL
	SELECT 'sys','allocation_units'
	UNION ALL
	SELECT 'sys','partitions'
	UNION ALL
	SELECT 'sys','columns'
	UNION ALL
	SELECT 'sys','index_columns'
	UNION ALL
	SELECT 'sys','foreign_keys'
	UNION ALL
	SELECT 'sys','foreign_key_columns'
	UNION ALL
	SELECT 'sys','objects'
	UNION ALL
	SELECT 'sys','stats'

	OPEN CreateAllDBViews
	FETCH NEXT FROM CreateAllDBViews INTO @SchemaName,@TableName
	WHILE (@@fetch_status <> -1)
	BEGIN
		/*#-BeginDebug CHECK EXISTANCE OF OBJECTS
		
			SELECT @TSQL1 = 'dbaadmin: '+Name+'('+Type+') AGE:'+CAST(DATEDIFF(minute,create_date,GetDate()) AS VarChar(50)) 
			FROM dbaadmin.sys.objects WHERE name = 'vw_AllDB_'+@TableName
			PRINT @TSQL1
			
			SELECT @TSQL1 = 'dbaadmin: '+Name+'('+Type+') AGE:'+CAST(DATEDIFF(minute,create_date,GetDate()) AS VarChar(50)) 
			FROM dbaperf.sys.objects WHERE name = 'vw_AllDB_'+@TableName
			PRINT @TSQL1			
		
		#-EndDebug*/
		IF (@@fetch_status <> -2)
		AND (
				NOT EXISTS (SELECT 1 FROM dbaadmin.sys.objects WHERE Type = 'V' AND DATEDIFF(minute,create_date,GetDate()) < @Age AND name = 'vw_AllDB_'+@TableName)
			OR	NOT EXISTS (SELECT 1 FROM dbaperf.sys.objects WHERE Type = 'SN' AND DATEDIFF(minute,create_date,GetDate()) < @Age AND name = 'vw_AllDB_'+@TableName)
			)
		BEGIN
			
			SET		@TSQL1	= 'IF OBJECT_ID(''[dbo].[vw_AllDB_'+@TableName+']'',''V'') IS NOT NULL'
							+ CHAR(13)+CHAR(10)
							+ 'DROP VIEW [dbo].[vw_AllDB_'+@TableName+']' 
							
			SET		@TSQL2	= 'USE [dbaadmin];'
							+ CHAR(13)+CHAR(10)
							+ 'EXEC (''' + REPLACE(@TSQL1,'''','''''') + ''')'
			
			PRINT 'Dropping [vw_AllDB_'+@TableName+'] View in dbaadmin.'
			/*#-BeginDebug Print Drop View Command in dbaadmin
				PRINT	(@TSQL2)
			#-EndDebug*/
			EXEC	(@TSQL2)

			SET		@TSQL2	= 'USE [dbaperf];'
							+ CHAR(13)+CHAR(10)
							+ 'EXEC (''' + REPLACE(@TSQL1,'''','''''') + ''')'
			
			PRINT 'Dropping [vw_AllDB_'+@TableName+'] View in dbaperf.'
			/*#-BeginDebug Print Drop View Command in dbaperf
				PRINT	(@TSQL2)
			#-EndDebug*/
			EXEC	(@TSQL2)
			
			SET		@TSQL1	= 'IF OBJECT_ID(''[dbo].[vw_AllDB_'+@TableName+']'',''SN'') IS NOT NULL'
							+ CHAR(13)+CHAR(10)
							+ 'DROP SYNONYM [dbo].[vw_AllDB_'+@TableName+']' 
							
			SET		@TSQL2	= 'USE [dbaperf];'
							+ CHAR(13)+CHAR(10)
							+ 'EXEC (''' + REPLACE(@TSQL1,'''','''''') + ''')'
			
			PRINT 'Dropping [vw_AllDB_'+@TableName+'] Synonym in dbaperf.'
			/*#-BeginDebug Print Drop Sysnonym Command
				PRINT	(@TSQL2)
			#-EndDebug*/
			EXEC	(@TSQL2)			
		
			
			SET		@TSQL1	= 'CREATE VIEW [dbo].[vw_AllDB_'+@TableName+'] AS' +CHAR(13)+CHAR(10)+'SELECT	''master'' AS database_name, DB_ID(''master'') AS database_id, * From [master].['+@SchemaName+'].['+@TableName+']'+CHAR(13)+CHAR(10)
			SELECT	@TSQL1	= @TSQL1 
							+ 'UNION ALL'
							+ CHAR(13)+CHAR(10)
							+ 'SELECT	'''+name+''', DB_ID('''+name+'''), * From ['+name+'].['+@SchemaName+'].['+@TableName+']'
							+ CHAR(13)+CHAR(10)
			FROM	master.sys.databases 
			WHERE	name not in('master')
				AND	DATABASEPROPERTYEX(name,'collation') =  'SQL_Latin1_General_CP1_CI_AS'

			SET		@TSQL2	= 'USE [dbaadmin];'
							+ CHAR(13)+CHAR(10)
							+ 'EXEC (''' + REPLACE(@TSQL1,'''','''''') + ''')'
			
			PRINT 'Creating [vw_AllDB_'+@TableName+'] View in dbaadmin.'
			/*#-BeginDebug Print Create View Command
				PRINT	(@TSQL2)
			#-EndDebug*/
			EXEC	(@TSQL2)			


			SET		@TSQL1	= 'CREATE SYNONYM [dbo].[vw_AllDB_'+@TableName+'] FOR [dbaadmin].[dbo].[vw_AllDB_'+@TableName+']' 
							
			SET		@TSQL2	= 'USE [dbaperf];'
							+ CHAR(13)+CHAR(10)
							+ 'EXEC (''' + REPLACE(@TSQL1,'''','''''') + ''')'
							
			PRINT 'Creating [vw_AllDB_'+@TableName+'] Synonym in dbaperf.'
			/*#-BeginDebug Print Create Sysnonym Command
				PRINT	(@TSQL2)
			#-EndDebug*/
			EXEC	(@TSQL2)			


		END
		ELSE PRINT '[vw_AllDB_'+@TableName+'] Parts are Recent: Nothing Done.'
		FETCH NEXT FROM CreateAllDBViews INTO @SchemaName,@TableName
	END

	CLOSE CreateAllDBViews
	DEALLOCATE CreateAllDBViews    
END
 
