USE [dbacentral]
GO
/****** Object:  StoredProcedure [dbo].[dbasp_Build_regsrvr_file]    Script Date: 8/22/2014 12:05:46 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[dbasp_Build_regsrvr_file]
	(
	@DBAName		SYSNAME		= NULL
	,@SpecificSet		VarChar(MAX)	= '' -- COMMA DELIMITED LIST OF SQL NAME WILDCARDS
	,@IncludeNewCloneNames	bit		= 0
	)
AS

--DECLARE	@DBAName		SYSNAME		--= 'sledridge'
--	,@SpecificSet		VarChar(MAX)	= '' -- COMMA DELIMITED LIST OF SQL NAME WILDCARDS
--	,@IncludeNewCloneNames	bit		= 0


SET		NOCOUNT			ON
DECLARE		@DBAName_Save		SYSNAME
DECLARE		@Text			VarChar(max)
DECLARE		@Level1			VarChar(max)
DECLARE		@Level2			VarChar(max)
DECLARE		@Level3			VarChar(max)
DECLARE		@Level4			VarChar(max)
DECLARE		@Server			VarChar(max)
DECLARE		@Desc			VarChar(max)
DECLARE		@Level1Desc 		VarChar(max)
DECLARE		@Level2Desc 		VarChar(max)
DECLARE		@Level3Desc 		VarChar(max)
DECLARE		@Port			VarChar(max)
DECLARE		@DomainName 		VarChar(max)
DECLARE		@Apps			VarChar(max)
DECLARE		@DBs			VarChar(max)
DECLARE		@xDomLogin 		VarChar(max)
DECLARE		@xDomPaswd		VarChar(max)
DECLARE		@OutputFileData		VarChar(max)
DECLARE		@OutputPath		VarChar(max)
DECLARE		@OutputFileName		VarChar(max)
DECLARE		@TempValue		VarChar(max)
DECLARE		@CRLF			CHAR(2)

SELECT		@OutputPath		= '\\SEAPDBASQL01\SEAPDBASQL01_dbasql\dba_reports\regsrvr\'
		,@CRLF			= CHAR(13)+CHAR(10)
		,@DBAName_Save		= @DBAName

DECLARE		@DBATable		TABLE
		(
		DBAName			sysname PRIMARY KEY
		,DBALoginName		SYSNAME
		,MachineDescription	VarChar(max)
		,EncryptedPassword	VarChar(max)
		,OutputFileName		VarChar(max)
		)

DECLARE		@ServerList		Table
		(
		 Col1			VarChar(max)	 -- LEVEL 1 ('Active')
		,Col2			VarChar(max)	 -- Level 2 ('By Environment','By DB','By App','ALL')
		,Col3			VarChar(max)	 -- Level 3 ({SQLEnv},{DBName},{Appl_desc},'ALL')
		,Col4			VarChar(max)	 -- Level 4 ({DomainName},{DEPLStatus},',')
		,Col5			VarChar(max)	 -- {ServerName}
		,Col6			VarChar(max)	 -- {SQLPort}
		,Col7			VarChar(max)	 -- {DomainName}
		,Col8			VarChar(max)	 -- concatonated {Appl_desc} When Not "By APP"
		,Col9			VarChar(max)	 -- concatonated {DBName} When Not "By DB"
		)

DECLARE		 @ServerInfoList	Table
		(
		SQLName			VarChar(max)
		,Port			VarChar(max)
		,SQLEnv			VarChar(max)
		,DomainName		VarChar(max)
		,Apps			VarChar(max)
		,DBs			VarChar(max)
		,Active			VarChar(max)
		,SQLver			VarChar(MAX)
		,OSVer			VarChar(MAX)
		)

INSERT INTO	@DBATable
VALUES		('sledridge1'	,'DBAsledridge'	,'Laptop'	,'AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAAHJfG51DxI0CuOznOmyGQ9AQAAAACAAAAAAADZgAAwAAAABAAAAAbjabuawaJLihOxGPJE7ssAAAAAASAAACgAAAAEAAAAHB9whCLd9pKfUBkbeLEzR8YAAAAe7yI/SzrtvfJDmXfhq2FDaz5hK8GtCDWFAAAAIFL2iOy6L7x41tFOf0yvgBtCE6r'			,'sledridge_Laptop')
		,('sledridge2'	,'DBAsledridge'	,'Desktop'	,'AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAAY7klVD1bukqaf9BpT0GgygQAAAACAAAAAAADZgAAwAAAABAAAADeiwnQKuXDV2tmE+Lse5M2AAAAAASAAACgAAAAEAAAAFGlzc1m5Hp90Dd02y7PG+4YAAAAPXqmg6INysg6ovIH/Y5WmR+kpXBbWjKVFAAAABk3GveJQMb3xUeiXWsridZqfxrA'			,'sledridge_Desktop')
		,('sledridge3'	,'DBAsledridge'	,'Tablet'	,'AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAAPC2W8eOS9k+pz2Yih9N2PgQAAAACAAAAAAAQZgAAAAEAACAAAAAZsGD6y7UEoHncV9xR/BChlANxW9N002TwmHPnoe06vwAAAAAOgAAAAAIAACAAAADJlwV0B5sw60NYEC32zqzXo+99fiK3ZzaX/LjczhqzIyAAAACPmRz+0VAFgIFHIemQpIIW/zLs7VCx8kT/i5kUF8fKdkAAAACZyRTXF1Mv4fFWew0ACu5DzfmtZCA7oE/Wpa0O6vRZzDy/ojyiqms41BcoebamufrINkO3lvI78phSDUoMMePd'  ,'sledridge_Tablet')
		,('jimw'	,'DBAjimw'	,'Desktop'	,'AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAAdEE3wriO+Eyoc26b0OpFpgQAAAACAAAAAAADZgAAwAAAABAAAAC0tIEHXD6fABTndv6n8yDTAAAAAASAAACgAAAAEAAAAA4bgvL4gf4XIHBhA/8okzwQAAAAPLAAyj2lCirZDWbL+pgs4RQAAAAxvvUh+gIzluvBh7CS6hcJKXOvow=='				,'jimw_Desktop'	)
		,('jbrown'	,'DBAjbrown'	,'Desktop'	,'AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAAZ4JP3oI0OkKx6PRhGWitfwQAAAACAAAAAAADZgAAwAAAABAAAAB1axWWmd3+4KhbVPiuW1pKAAAAAASAAACgAAAAEAAAAGPDmuQI5yIozcnR7zCxhYoQAAAAsDSUZP6CeBURxlYMU1SeoRQAAAAALW+6mXbKQef3qRyMhNAhwOW7pw=='				,'jbrown_Desktop')
		,('rreynolds'	,'DBArreynolds'	,'Desktop'	,'AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAApKyJL9CPdkeQABxfsE1YFQQAAAACAAAAAAADZgAAwAAAABAAAACz5O3JYvJ2C74Dih8S4ThQAAAAAASAAACgAAAAEAAAAPaRuV6BoyKCv+ccktcjeD8gAAAA37uNzhL0QMv7FlM/Ul7URDT/A+R8DSM8ivCMUguOs58UAAAAelrX7QfdZ4QQ1BnuDim/z8vJ4wU='		,'rreynolds_Desktop')
		,('scraig'	,'DBAscraig'	,'Desktop'	,'AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAAHIJGkZt8PU2LRDHVZX2N1wQAAAACAAAAAAADZgAAwAAAABAAAACsnlkUtudmrZxTbWOIgiBUAAAAAASAAACgAAAAEAAAAHv6LnQ0JXQHj2V9a36UruwYAAAAxmpXZIDb7GXtR2VpGrjfYEB1XK+17vN9FAAAAA/ipHPHV0cGorIKePYaZojQBuhJ;'			,'scraig_Desktop')
		,('mdeitz'	,'DBAmdeitz'	,'Desktop'	,'AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAA5AVhD/1KIki4hhNfe2ccuwQAAAACAAAAAAADZgAAwAAAABAAAABMRLr6iDuiyxOwSkGb6FV4AAAAAASAAACgAAAAEAAAAHF1iOw2en1U4luCpTYrQ3wgAAAAkC/zaF4rv2ze9MofWXJ5H6cceHs1NEWQqfYkAGecp34UAAAArJKGM6Vce3RxC89TzNMOQv+8Wq8='		,'mdeitz_Desktop')
		,('BULK'	,'$xDomLogin$'	,'BULK'		,'$xDomPaswd$'		,'BULK_TEMPLATE')
		

IF nullif(@DBAName,'') IS NOT NULL
BEGIN

	IF NOT EXISTS (SELECT * FROM @DBATable WHERE DBAName Like ISNULL(@DBAName,'') +'%')
	BEGIN
		SELECT	@TempValue = dbaadmin.dbo.dbaudf_Concatenate(DBAName) FROM @DBATable
		RAISERROR ('Invalid @DBAName, Must be one of these (%s)',-1,-1,@TempValue) WITH NOWAIT
		GOTO ExitProcedure
	END
	ELSE
	BEGIN
		SELECT	@TempValue = dbaadmin.dbo.dbaudf_Concatenate(DBAName) FROM @DBATable WHERE DBAName Like ISNULL(@DBAName,'') +'%'
		RAISERROR ('Generating REGSRVR File for the following DBA''s (%s)',-1,-1,@TempValue) WITH NOWAIT
	END
END			
ELSE
	RAISERROR ('Generating REGSRVR File for all registered DBA''s',-1,-1) WITH NOWAIT

-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------
--
--					BUILD @ServerInfoList TABLE
--
-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------

BEGIN
		INSERT INTO	@ServerInfoList (SQLName,Port,SQLEnv,DomainName,Apps,DBs,Active,SQLVer,OSVer)
		SELECT		UPPER(SI.[SQLName])																	[SQLName]
					,MAX(COALESCE(SI.[Port],'1433'))													[Port]
					,MAX(UPPER(COALESCE(SI.SQLEnv,'--')))												[SQLEnv]
					,MAX(UPPER(COALESCE(SI.DomainName,'--')))											[DomainName]
					,UPPER(isnull(NULLIF(dbaadmin.dbo.dbaudf_ConcatenateUNIQUE(DI.[Appl_desc]),''),'OTHER'))	[Apps]
					,dbaadmin.dbo.dbaudf_ConcatenateUNIQUE(UPPER(COALESCE(T2.DBName_Cleaned,T3.DBName_Cleaned,DI.DBName)))								[DBs]
					,MAX(CASE SI.Active WHEN 'Y' THEN 'ACTIVE' ELSE 'NOT ACTIVE' END)					[Active]
					,MAX(COALESCE(SI.SQLVer,'--'))														[SQLVer]
					,MAX(COALESCE(SI.OSName,'--'))														[OSVer]
		FROM		[DBAcentral].[dbo].[DBA_ServerInfo] SI
		LEFT JOIN	[DBAcentral].[dbo].[DBA_DBInfo] DI
			ON		SI.SQLName = DI.SQLName
		LEFT 
		JOIN	[dbacentral].[dbo].[DBA_DBNameCleaner] T2
			ON	DI.DBName Like T2.DBName
		LEFT
		JOIN	(
			SELECT	DISTINCT
				[DBName_Cleaned]+'%' [DBName]
				,[DBName_Cleaned]
			FROM	[dbacentral].[dbo].[DBA_DBNameCleaner]
			) T3
			ON	DI.DBName Like T3.DBName
		LEFT JOIN	[dbaadmin].dbo.dbaudf_Split2(@SpecificSet,',') SS
			ON		SI.SQLName LIKE SS.SplitValue
		WHERE		@SpecificSet = '' OR SS.SplitValue IS NOT NULL 	
		GROUP BY	SI.[SQLName] 
		ORDER BY	1



		IF @SpecificSet != '' AND @IncludeNewCloneNames = 1
			INSERT INTO	@ServerInfoList
			SELECT		CASE WHEN CHARINDEX('\',SQLName) > 0 THEN REPLACE(SQLName,'\','-n\') ELSE SQLName+'-n' END		
						,NULL		
						,SQLEnv		
						,DomainName	
						,Apps		
						,DBs		
						,Active		
						,SQLver		
						,OSVer		
			FROM		@ServerInfoList



		UPDATE		@ServerInfoList
			SET	[Apps] =	LTRIM((
							SELECT		dbaadmin.dbo.dbaudf_Concatenate(' '+ExtractedText)
							FROM		(
									SELECT		DISTINCT 
											ExtractedText
									FROM		dbo.dbaudf_StringToTable(T1.[Apps],',')
									WHERE		nullif(ExtractedText,'') IS NOT NULL
									) Data
									))
				,[DBs] =	LTRIM((
							SELECT		dbaadmin.dbo.dbaudf_Concatenate(' '+ExtractedText)
							FROM		(
									SELECT		DISTINCT 
											ExtractedText
									FROM		dbo.dbaudf_StringToTable(T1.[DBs],',')
									WHERE		nullif(ExtractedText,'') IS NOT NULL
									) Data
									))
		FROM		@ServerInfoList T1	


		--SELECT * FROM @ServerInfoList

-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------
--
--					BUILD @ServerList TABLE
--
-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------

		INSERT INTO	@ServerList (Col1,Col2,Col3,Col4,Col5,Col6,Col7,Col8,Col9)
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		VIRTUAL SERVERS
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		CASE Active WHEN 'Y' THEN 'ACTIVE' ELSE 'NOT ACTIVE' END		[Level1]
					,'Virtual Servers'						[Level2]
					,UPPER([SQLEnv])						[Level3]
					,COALESCE(nullif(REPLACE(
					 (	select max(ENVnum) 
						FROM dbacentral.dbo.DBA_DBInfo 
						WHERE SQLName = T1.[SQLName]
					 ),[SQLEnv],''),''),'01')					[Level4]
					,[SQLName]							[SQLInstance]
					,[Port]								[SQLPort]
					,UPPER(COALESCE(DomainName,'--'))				[DomainName]
					,''								[Apps]
					,''								[DBs]
		FROM		[dbacentral].[dbo].[DBA_ServerInfo] T1
		WHERE		[SystemModel] like '%VMware%' --order by 5
			AND	@SpecificSet = ''

		UNION ALL

		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		BY ENVIRONMENT
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		SI.Active														[Level1]
					,'BY ENV'														[Level2]
					,SI.[SQLEnv]													[Level3]
					,SI.DomainName													[Level4]
					,SI.[SQLName]													[SQLInstance]
					,SI.[Port]														[SQLPort]
					,SI.DomainName													[DomainName]
					,SI.[APPs]														[Apps]
					,SI.[DBs]														[DBs]
		FROM		@ServerInfoList SI
		WHERE		@SpecificSet = ''

		UNION ALL

		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		BY SQL VERSION PART 1
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		SI.Active								[Level1]
				,'BY SQLVer'								[Level2]
				,COALESCE(nullif(dbo.dbaudf_ReturnWord(REPLACE(cast(SQLver as VarChar(max)),'(Intel ','('),8),''),'--') 
				 + COALESCE(' '+nullif(LTRIM(RTRIM(REPLACE(REPLACE(
				   dbo.dbaudf_ReturnWord(REPLACE(SQLver,'(Intel ','('),9)
				   ,'(',''),')',''))),''),'')						[Level3]
				,SI.DomainName								[Level4]
				,SI.[SQLName]								[SQLInstance]
				,SI.[Port]								[SQLPort]
				,SI.DomainName								[DomainName]
				,SI.[APPs]								[Apps]
				,SI.[DBs]								[DBs]
		FROM		@ServerInfoList SI
		WHERE		dbo.dbaudf_ReturnWord(REPLACE(SQLver,'(Intel ','('),1) != 'Microsoft'
			AND	@SpecificSet = ''
	
		UNION ALL

		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		BY SQL VERSION PART 2
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		SI.Active								[Level1]
				,'BY SQLVer'								[Level2]
				,COALESCE(nullif(dbo.dbaudf_ReturnWord(REPLACE(SQLver,'(Intel ','('),4),''),'--')	[Level3]
				,SI.DomainName								[Level4]
				,SI.[SQLName]								[SQLInstance]
				,SI.[Port]								[SQLPort]
				,SI.DomainName								[DomainName]
				,SI.[APPs]								[Apps]
				,SI.[DBs]								[DBs]
		FROM		@ServerInfoList SI
		WHERE		dbo.dbaudf_ReturnWord(REPLACE(SQLver,'(Intel ','('),1) = 'Microsoft'
			AND	@SpecificSet = ''
	
		UNION ALL

		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		BY OS VERSION
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		SI.Active								[Level1]
				,'BY OSVer'								[Level2]
				,COALESCE(nullif(REPLACE(Coalesce(
					dbo.dbaudf_ReturnWord(REPLACE(OSVer,'(Intel ','('),4)
					,dbo.dbaudf_ReturnWord(REPLACE(OSVer,'(Intel ','('),3)
					),',',''),''),'--')						[Level3]
				,SI.DomainName								[Level4]
				,SI.[SQLName]								[SQLInstance]
				,SI.[Port]								[SQLPort]
				,SI.DomainName								[DomainName]
				,SI.[APPs]								[Apps]
				,SI.[DBs]								[DBs]
		FROM		@ServerInfoList SI
		WHERE		@SpecificSet = ''

		UNION ALL

		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		BY DATABASE
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		SI.Active														[Level1]
					,'BY DB'														[Level2]
					,UPPER(COALESCE(DBName_Cleaned,DI.[DBName]))					[Level3]
					,UPPER(CASE WHEN DI.[DBName] = COALESCE(DBName_Cleaned,DI.[DBName])
						THEN '--' ELSE 	DI.[DBName] END)							[Level4]
					,SI.[SQLName]													[SQLInstance]
					,MAX(SI.[Port])													[SQLPort]
					,MAX(SI.SQLEnv)+'-'+MAX(SI.DomainName)							[DomainName]
					,MAX(SI.[APPs])													[Apps]
					,MAX(SI.[DBs])													[DBs]
		FROM		@ServerInfoList SI
		JOIN		(
					SELECT		DI.*,DNC.DBName_Cleaned
					FROM		[DBAcentral].[dbo].[DBA_DBInfo]		DI
					LEFT JOIN	[DBAcentral].dbo.DBA_DBNameCleaner	DNC
							ON	DI.[DBName] = DNC.[DBName]
					) DI
			ON		SI.SQLName = DI.SQLName
		WHERE		SI.Active = 'ACTIVE'
			AND	@SpecificSet = ''
		GROUP BY	SI.Active														-- LEVEL 1
					,UPPER(COALESCE(DBName_Cleaned,DI.[DBName]))					-- LEVEL 3
					,CASE WHEN DI.[DBName] = COALESCE(DBName_Cleaned,DI.[DBName])
						THEN '--' ELSE 	DI.[DBName] END								-- LEVEL 4
					,SI.[SQLName]													-- SERVER NAME
		--ORDER BY  1,2,3,4,5

		UNION ALL

		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		BY APPLICATION / ENVIRONMENT
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		SI.Active														[Level1]
					,'BY APP-ENV'													[Level2]
					,UPPER(isnull(NULLIF(DI.[Appl_desc],''),'OTHER'))				[Level3]
					,SI.[SQLEnv]													[Level4]
					,SI.[SQLName]													[SQLInstance]
					,MAX(SI.[Port])													[SQLPort]
					,MAX(SI.DomainName)												[DomainName]
					,MAX(SI.[APPs])													[Apps]
					,MAX(SI.[DBs])													[DBs]
		FROM		@ServerInfoList SI
		LEFT JOIN	[DBAcentral].[dbo].[DBA_DBInfo] DI
			ON		SI.SQLName = DI.SQLName
		WHERE		SI.Active = 'ACTIVE'
			AND	@SpecificSet = ''
		GROUP BY	SI.Active														-- LEVEL 1
					,UPPER(isnull(NULLIF(DI.[Appl_desc],''),'OTHER'))				-- LEVEL 3
					,SI.[SQLEnv]													-- LEVEL 4
					,SI.[SQLName]													-- SERVER NAME

		UNION ALL

		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		BY APPLICATION / DATABASE
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		SI.Active														[Level1]
					,'By APP-DB'													[Level2]
					,UPPER(isnull(NULLIF(DI.[Appl_desc],''),'OTHER'))				[Level3]
					,UPPER(DI.[DBName])												[Level4]
					,SI.[SQLName]													[SQLInstance]
					,MAX(SI.[Port])													[SQLPort]
					,MAX(SI.DomainName)												[DomainName]
					,MAX(SI.[APPs])													[Apps]
					,MAX(SI.[DBs])													[DBs]
		FROM		@ServerInfoList SI
		LEFT JOIN	[DBAcentral].[dbo].[DBA_DBInfo] DI
			ON		SI.SQLName = DI.SQLName
		WHERE		SI.Active = 'ACTIVE'
			AND	@SpecificSet = ''
		GROUP BY	SI.Active														-- LEVEL 1
					,UPPER(isnull(NULLIF(DI.[Appl_desc],''),'OTHER'))				-- LEVEL 3
					,DI.[DBName]													-- LEVEL 4
					,SI.[SQLName]													-- SERVER NAME

		UNION ALL

		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		ALL SERVERS
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		DISTINCT
					SI.Active														[Level1]
					,'ALL'															[Level2]
					,'--'															[Level3]
					,'--'															[Level4]
					,SI.[SQLName]													[SQLInstance]
					,SI.[Port]														[SQLPort]
					,SI.[DomainName]												[DomainName]
					,SI.[APPs]														[Apps]
					,SI.[DBs]														[DBs]
		FROM		@ServerInfoList SI

		UNION ALL

		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		SUPPORT SERVERS
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		DISTINCT
					'SUPPORT'														[Level1]
					,'--'															[Level2]
					,'--'															[Level3]
					,'--'															[Level4]
					,SI.[SQLName]													[SQLInstance]
					,SI.[Port]														[SQLPort]
					,SI.DomainName													[DomainName]
					,SI.[APPs]														[Apps]
					,SI.[DBs]														[DBs]
		FROM		@ServerInfoList SI
		LEFT JOIN	[DBAcentral].[dbo].[DBA_DBInfo] DI
			ON		SI.SQLName = DI.SQLName
		WHERE		(
					DI.DBName	IN ('DEPLOYCENTRAL','DBACENTRAL','DEPLCONTROL','QUEST_PERFORMANCE_REPOSITORY','FOGLIGHT','SpotlightPluginPlayBackDatabase')
				OR	SI.SQLName	Like	'%deployer%'
				OR	SI.SQLName	Like	'%dply%'
					) 
			AND	@SpecificSet = ''			

		UNION ALL

		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		--		HOT LIST SERVERS
		-----------------------------------------------------------------------------------------------------------
		-----------------------------------------------------------------------------------------------------------
		SELECT		DISTINCT
					'HOT LIST'														[Level1]
					,SI.DomainName													[Level2]
					,'--'															[Level3]
					,'--'															[Level4]
					,SI.[SQLName]													[SQLInstance]
					,SI.[Port]														[SQLPort]
					,SI.DomainName													[DomainName]
					,SI.[APPs]														[Apps]
					,SI.[DBs]														[DBs]

		FROM		@ServerInfoList SI
		WHERE		dbo.dbaudf_GetServerClass(SI.SQLName) = 'high'
			AND	@SpecificSet = ''


		ORDER BY 1,2,3,4,5


-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------
--		CLEANUP
-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------
		UPDATE		@ServerList
			SET		[Col1] = REPLACE(REPLACE(Col1,'/','-'),'.','-')
					,[Col2] = REPLACE(REPLACE(Col2,'/','-'),'.','-')
					,[Col3] = REPLACE(REPLACE(Col3,'/','-'),'.','-')
					,[Col4] = REPLACE(REPLACE(Col4,'/','-'),'.','-')
			


		--SELECT * FROM @ServerList
END

-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------
--
--					START GENERATING OUTPUT
--
-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------
RAISERROR ('STARTING GENERATION OF OUTPUT',-1,-1) WITH NOWAIT

--$xDomLogin$,$xDomPaswd$
IF (SELECT COUNT(*) FROM @DBATable WHERE DBAName Like ISNULL(@DBAName,'') +'%' AND DBAName != 'BULK') > 1
BEGIN
	DECLARE DBACursor CURSOR
	FOR
	SELECT		DBAName			
			,DBALoginName		
			,EncryptedPassword	
			,OutputFileName		
	FROM		@DBATable 
	WHERE		DBAName = 'BULK'
END
ELSE
BEGIN
	DECLARE DBACursor CURSOR
	FOR
	SELECT		DBAName			
			,DBALoginName		
			,EncryptedPassword	
			,OutputFileName		
	FROM		@DBATable 
	WHERE		DBAName Like ISNULL(@DBAName,'') +'%'
		AND	DBAName != 'BULK'
END


OPEN DBACursor;
FETCH DBACursor INTO @DBAName,@xDomLogin,@xDomPaswd,@OutputFileName;
WHILE (@@fetch_status <> -1)
BEGIN
	IF (@@fetch_status <> -2)
	BEGIN
		---------------------------- 
		---------------------------- CURSOR LOOP TOP
		SELECT		@OutputFileData		= ''
				,@OutputFileName	= @OutputPath + @OutputFileName + '.regsrvr'

		RAISERROR ('  Generating REGSRVR File for: %s',-1,-1,@DBAName) WITH NOWAIT
		RAISERROR ('  Output to: %s',-1,-1,@OutputFileName) WITH NOWAIT
		RAISERROR ('    ',-1,-1) WITH NOWAIT								

		--BUILD HEADER
		SET @Text = '<?xml version="1.0"?>
		<model xmlns="http://schemas.serviceml.org/smlif/2007/02">
		  <identity>
		    <name>urn:uuid:96fe1236-abf6-4a57-b54d-e9baab394fd1</name>
		    <baseURI>http://documentcollection/</baseURI>
		  </identity>
		  <xs:bufferSchema xmlns:xs="http://www.w3.org/2001/XMLSchema">
		    <definitions xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08">
		      <document>
			<docinfo>
			  <aliases>
			    <alias>/system/schema/RegisteredServers</alias>
			  </aliases>
			  <sfc:version DomainVersion="1" />
			</docinfo>
			<data>
			  <xs:schema targetNamespace="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema" elementFormDefault="qualified">
			    <xs:element name="ServerGroup">
			      <xs:complexType>
				<xs:sequence>
				  <xs:any namespace="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" processContents="skip" minOccurs="0" maxOccurs="unbounded" />
				</xs:sequence>
			      </xs:complexType>
			    </xs:element>
			    <xs:element name="RegisteredServer">
			      <xs:complexType>
				<xs:sequence>
				  <xs:any namespace="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" processContents="skip" minOccurs="0" maxOccurs="unbounded" />
				</xs:sequence>
			      </xs:complexType>
			    </xs:element>
			    <RegisteredServers:bufferData xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08">
			      <instances xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08">'
		
		exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,0,1
		SET @Text = ''

		--LEVEL 0 HEADER
		SET @Text = '                <document>
				  <docinfo>
				    <aliases>
				      <alias>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup</alias>
				    </aliases>
				    <sfc:version DomainVersion="1" />
				  </docinfo>
				  <data>
				    <RegisteredServers:ServerGroup xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema">'
		exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1


		IF EXISTS (SELECT * FROM @ServerList Where Col1 = '--') -- ARE THERE ANY LEVEL0 SERVERS
		BEGIN
		  RAISERROR ('        BUILD LEVEL 0 SERVERS HEADER',-1,-1) WITH NOWAIT
		  --LEVEL 0 SERVERS HEADER
		  SET @Text = '                      <RegisteredServers:RegisteredServers>
			      <sfc:Collection>'
		  exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		  --LEVEL 0 SERVERS DATA
		  DECLARE Level0_Cursor CURSOR
		  FOR
		  SELECT	DISTINCT 
				Col5 
		  FROM		@ServerList
		  WHERE		Col1 = '--'
		  ORDER BY	1
		  OPEN Level0_Cursor
		  FETCH NEXT FROM Level0_Cursor INTO @Server
		  WHILE (@@fetch_status <> -1)
		  BEGIN
		    IF (@@fetch_status <> -2)
		    BEGIN
			SET @Text = '                          <sfc:Reference sml:ref="true">
				<sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/RegisteredServer/'+@Server+'</sml:Uri>
				</sfc:Reference>'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		    END
		    FETCH NEXT FROM Level0_Cursor INTO @Server
		  END
		  CLOSE Level0_Cursor
		  DEALLOCATE Level0_Cursor

		  --LEVEL 0 SRVERS FOOTER
		  SET @Text = '                        </sfc:Collection>
			      </RegisteredServers:RegisteredServers>'
		  exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		END

		--LEVEL 0 GROUPS HEADER
		SET @Text = '                      <RegisteredServers:ServerGroups>
					<sfc:Collection>'
		exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		--LEVEL 0 GROUPS DATA
		DECLARE Level0_Cursor CURSOR
		FOR
		  Select    DISTINCT 
			Col1 
		  From    @ServerList
		  Where    Col1 != '--'
		  ORDER BY  1
		OPEN Level0_Cursor
		FETCH NEXT FROM Level0_Cursor INTO @Level1
		WHILE (@@fetch_status <> -1)
		BEGIN
		  IF (@@fetch_status <> -2)
		  BEGIN
			RAISERROR ('  BUILD LEVEL 1 GROUP INDEX (%s)',-1,-1,@Level1) WITH NOWAIT
			SET @Text = '                          <sfc:Reference sml:ref="true">
					    <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'</sml:Uri>
					  </sfc:Reference>'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		  END
		  FETCH NEXT FROM Level0_Cursor INTO @Level1
		END
		CLOSE Level0_Cursor
		DEALLOCATE Level0_Cursor

		--LEVEL 0 GROUPS FOOTER
		SET @Text = '                        </sfc:Collection>
				      </RegisteredServers:ServerGroups>'
		exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		--LEVEL 0 FOOTER
		SET @Text = '                      <RegisteredServers:Parent>
					<sfc:Reference sml:ref="true">
					  <sml:Uri>/RegisteredServersStore</sml:Uri>
					</sfc:Reference>
				      </RegisteredServers:Parent>
				      <RegisteredServers:Name type="string">DatabaseEngineServerGroup</RegisteredServers:Name>
				      <RegisteredServers:ServerType type="ServerType">DatabaseEngine</RegisteredServers:ServerType>
				    </RegisteredServers:ServerGroup>
				  </data>
				</document>'
		exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		--LEVEL 0 SERVERS DATA
		DECLARE Level0_Cursor CURSOR
		FOR
		  Select    DISTINCT 
			Col5,Col6,Col7,Col8,Col9
		  From    @ServerList
		  Where    Col1 = '--'
		  ORDER BY  1
		OPEN Level0_Cursor
		FETCH NEXT FROM Level0_Cursor INTO @Server,@Port,@DomainName,@Apps,@DBs
		WHILE (@@fetch_status <> -1)
		BEGIN
		  IF (@@fetch_status <> -2)
		  BEGIN
			SET @Desc = '[Env-Dom] '+@DomainName+'&lt;?char 13?&gt;'+CHAR(10)+'[Apps] '+@Apps+'&lt;?char 13?&gt;'+CHAR(10)+'[DBs] '+@DBs
			SET @Text = '                <document>
				  <docinfo>
				    <aliases>
				      <alias>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/RegisteredServer/'+@Server+'</alias>
				    </aliases>
				    <sfc:version DomainVersion="1" />
				  </docinfo>
				  <data>
				    <RegisteredServers:RegisteredServer xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema">
				      <RegisteredServers:Parent>
					<sfc:Reference sml:ref="true">
					  <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup</sml:Uri>
					</sfc:Reference>
				      </RegisteredServers:Parent>
				      <RegisteredServers:Name type="string">'+@Server+'</RegisteredServers:Name>
				      <RegisteredServers:Description type="string">'+@Desc+'</RegisteredServers:Description>
				      <RegisteredServers:ServerName type="string">tcp:'+@Server+ISNULL(','+@Port,'')+'</RegisteredServers:ServerName>
				      <RegisteredServers:UseCustomConnectionColor type="boolean">'+CASE WHEN @DomainName Not Like '%AMER%' THEN 'true' ELSE 'false' END +'</RegisteredServers:UseCustomConnectionColor>
				      <RegisteredServers:CustomConnectionColorArgb type="int">-32640</RegisteredServers:CustomConnectionColorArgb>
				      <RegisteredServers:ServerType type="ServerType">DatabaseEngine</RegisteredServers:ServerType>
				      <RegisteredServers:ConnectionStringWithEncryptedPassword type="string">server=tcp:'+@Server+ISNULL(','+@Port,'')+CASE WHEN @DomainName Not Like '%AMER%' THEN ';uid='+@xDomLogin+';password='+@xDomPaswd ELSE ';trusted_connection=true' END + ';pooling=false;packet size=4096;multipleactiveresultsets=false</RegisteredServers:ConnectionStringWithEncryptedPassword>
				      <RegisteredServers:CredentialPersistenceType type="CredentialPersistenceType">'+CASE WHEN @DomainName Not Like '%AMER%' THEN 'PersistLoginNameAndPassword' ELSE 'PersistLoginName' END +'</RegisteredServers:CredentialPersistenceType>
				    </RegisteredServers:RegisteredServer>
				  </data>
				</document>'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		  END
		  FETCH NEXT FROM Level0_Cursor INTO @Server,@Port,@DomainName,@Apps,@DBs
		END
		CLOSE Level0_Cursor
		DEALLOCATE Level0_Cursor

		--LEVEL 1 NESTING GROUP
		DECLARE Level0_Cursor CURSOR
		FOR
		  Select    DISTINCT 
			Col1 
		  From    @ServerList
		  Where    Col1 != '--'
		  ORDER BY  1
		OPEN Level0_Cursor
		FETCH NEXT FROM Level0_Cursor INTO @Level1
		WHILE (@@fetch_status <> -1)
		BEGIN
		  IF (@@fetch_status <> -2)
		  BEGIN
			RAISERROR ('   BUILD LEVEL 1 GROUP DATA (%s)',-1,-1,@Level1) WITH NOWAIT
			--LEVEL 1 HEADER
			SET @Text = '                <document>
			  <docinfo>
			  <aliases>
			    <alias>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'</alias>
			  </aliases>
			  <sfc:version DomainVersion="1" />
			  </docinfo>
			  <data>
			  <RegisteredServers:ServerGroup xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema">'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1


		    IF EXISTS (SELECT * FROM @ServerList Where Col1 = @Level1 AND Col2 = '--') -- ARE THERE ANY LEVEL 1 SERVERS
		    BEGIN
		      --LEVEL 1 SERVERS HEADER
		      SET @Text = '                      <RegisteredServers:RegisteredServers>
			      <sfc:Collection>'
		      exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		      --LEVEL 1 SERVERS DATA
		      DECLARE Level1_Cursor CURSOR
		      FOR
			Select    DISTINCT 
			      Col5 
			From    @ServerList
			Where    Col2 = '--'
			  AND    Col1 = @Level1
			ORDER BY  1
		      OPEN Level1_Cursor
		      FETCH NEXT FROM Level1_Cursor INTO @Server
		      WHILE (@@fetch_status <> -1)
		      BEGIN
			IF (@@fetch_status <> -2)
			BEGIN
				SET @Text = '                          <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/RegisteredServer/'+@Server+'</sml:Uri>
			      </sfc:Reference>'
				exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
			END
			FETCH NEXT FROM Level1_Cursor INTO @Server
		      END
		      CLOSE Level1_Cursor
		      DEALLOCATE Level1_Cursor

		      --LEVEL 1 SRVERS FOOTER
		      SET @Text = '                        </sfc:Collection>
			       </RegisteredServers:RegisteredServers>'
		      exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		    END

		    --LEVEL 2 GROUPS HEADER
		    SET @Text = '                      <RegisteredServers:ServerGroups>
			    <sfc:Collection>'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1


		    --LEVEL 2 GROUPS DATA
		    DECLARE Level1_Cursor CURSOR
		    FOR
		      Select    DISTINCT 
			    Col2 
		      From    @ServerList
		      Where    Col2 != '--'
		      ORDER BY  1
		    OPEN Level1_Cursor
		    FETCH NEXT FROM Level1_Cursor INTO @Level2
		    WHILE (@@fetch_status <> -1)
		    BEGIN
		      IF (@@fetch_status <> -2)
		      BEGIN
			RAISERROR ('    BUILD LEVEL 2 GROUP INDEX (%s)',-1,-1,@Level2) WITH NOWAIT
			SET @Text = '                          <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'</sml:Uri>
			      </sfc:Reference>'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		      END
		      FETCH NEXT FROM Level1_Cursor INTO @Level2
		    END
		    CLOSE Level1_Cursor
		    DEALLOCATE Level1_Cursor

		    --LEVEL 1 GROUPS FOOTER
		    SET @Text = '                        </sfc:Collection>
			    </RegisteredServers:ServerGroups>'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1


		    --LEVEL 1 FOOTER
		    SET @Text = '                      <RegisteredServers:Parent>
			    <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup</sml:Uri>
			    </sfc:Reference>
			    </RegisteredServers:Parent>
			    <RegisteredServers:Name type="string">'+@Level1+'</RegisteredServers:Name>
			    <RegisteredServers:Description type="string">'+@Level1+'</RegisteredServers:Description>
			    <RegisteredServers:ServerType type="ServerType">DatabaseEngine</RegisteredServers:ServerType>
			  </RegisteredServers:ServerGroup>
			  </data>
			</document>'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		    --LEVEL 1 SERVERS DATA
		    DECLARE Level1_Cursor CURSOR
		    FOR
		      Select    DISTINCT 
			    Col5,Col6,Col7,Col8,Col9
		      From    @ServerList
		      Where    Col2 = '--'
			AND    Col1 = @Level1
		      ORDER BY  1
		    OPEN Level1_Cursor
		    FETCH NEXT FROM Level1_Cursor INTO @Server,@Port,@DomainName,@Apps,@DBs
		    WHILE (@@fetch_status <> -1)
		    BEGIN
		      IF (@@fetch_status <> -2)
		      BEGIN
			SET @Desc = '[Env-Dom] '+@DomainName+'&lt;?char 13?&gt;'+CHAR(10)+'[Apps] '+@Apps+'&lt;?char 13?&gt;'+CHAR(10)+'[DBs] '+@DBs
			SET @Text = '                <document>
			  <docinfo>
			  <aliases>
			    <alias>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/RegisteredServer/'+@Server+'</alias>
			  </aliases>
			  <sfc:version DomainVersion="1" />
			  </docinfo>
			  <data>
			  <RegisteredServers:RegisteredServer xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema">
			    <RegisteredServers:Parent>
			    <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'</sml:Uri>
			    </sfc:Reference>
			    </RegisteredServers:Parent>
			    <RegisteredServers:Name type="string">'+@Server+'</RegisteredServers:Name>
			    <RegisteredServers:Description type="string">'+@Desc+'</RegisteredServers:Description>
			    <RegisteredServers:ServerName type="string">tcp:'+@Server+ISNULL(','+@Port,'')+'</RegisteredServers:ServerName>
			    <RegisteredServers:UseCustomConnectionColor type="boolean">'+CASE WHEN @DomainName Not Like '%AMER%' THEN 'true' ELSE 'false' END +'</RegisteredServers:UseCustomConnectionColor>
			    <RegisteredServers:CustomConnectionColorArgb type="int">-32640</RegisteredServers:CustomConnectionColorArgb>
			    <RegisteredServers:ServerType type="ServerType">DatabaseEngine</RegisteredServers:ServerType>
			    <RegisteredServers:ConnectionStringWithEncryptedPassword type="string">server=tcp:'+@Server+ISNULL(','+@Port,'')+CASE WHEN @DomainName Not Like '%AMER%' THEN ';uid='+@xDomLogin+';password='+@xDomPaswd ELSE ';trusted_connection=true' END + ';pooling=false;packet size=4096;multipleactiveresultsets=false</RegisteredServers:ConnectionStringWithEncryptedPassword>
			    <RegisteredServers:CredentialPersistenceType type="CredentialPersistenceType">'+CASE WHEN @DomainName Not Like '%AMER%' THEN 'PersistLoginNameAndPassword' ELSE 'PersistLoginName' END +'</RegisteredServers:CredentialPersistenceType>
			  </RegisteredServers:RegisteredServer>
			  </data>
			</document>'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		      END
		      FETCH NEXT FROM Level1_Cursor INTO @Server,@Port,@DomainName,@Apps,@DBs
		    END
		    CLOSE Level1_Cursor
		    DEALLOCATE Level1_Cursor

		--LEVEL 2 NESTING GROUP
		DECLARE Level1_Cursor CURSOR
		FOR
		  Select    DISTINCT 
			Col2 
		  From    @ServerList
		  Where    Col2 != '--'
		    AND    Col1 = @Level1
		  ORDER BY  1
		OPEN Level1_Cursor
		FETCH NEXT FROM Level1_Cursor INTO @Level2
		WHILE (@@fetch_status <> -1)
		BEGIN
		  IF (@@fetch_status <> -2)
		  BEGIN
			RAISERROR ('     BUILD LEVEL 2 GROUP DATA (%s)',-1,-1,@Level2) WITH NOWAIT
			--LEVEL 1 HEADER
			SET @Text = '                <document>
			  <docinfo>
			  <aliases>
			    <alias>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'</alias>
			  </aliases>
			  <sfc:version DomainVersion="1" />
			  </docinfo>
			  <data>
			  <RegisteredServers:ServerGroup xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema">'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1


		    IF EXISTS (SELECT * FROM @ServerList Where Col1 = @Level1 AND Col2 = @Level2 AND Col3 = '--') -- ARE THERE ANY LEVEL 2 SERVERS
		    BEGIN
			--LEVEL 2 SERVERS HEADER
			SET @Text = '                      <RegisteredServers:RegisteredServers>
			      <sfc:Collection>'
		      exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		      --LEVEL 2 SERVERS DATA
		      DECLARE Level2_Cursor CURSOR
		      FOR
			Select    DISTINCT 
			      Col5 
			From    @ServerList
			Where    Col3 = '--'
			  AND    Col2 = @Level2
			  AND    Col1 = @Level1
			ORDER BY  1
		      OPEN Level2_Cursor
		      FETCH NEXT FROM Level2_Cursor INTO @Server
		      WHILE (@@fetch_status <> -1)
		      BEGIN
			IF (@@fetch_status <> -2)
			BEGIN
			  SET @Text = '                          <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/RegisteredServer/'+@Server+'</sml:Uri>
			      </sfc:Reference>'
			  exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
			END
			FETCH NEXT FROM Level2_Cursor INTO @Server
		      END
		      CLOSE Level2_Cursor
		      DEALLOCATE Level2_Cursor

		      --LEVEL 2 SRVERS FOOTER
		      SET @Text = '                        </sfc:Collection>
			       </RegisteredServers:RegisteredServers>'
		      exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		    END

		    --LEVEL 2 GROUPS HEADER
		    SET @Text = '                      <RegisteredServers:ServerGroups>
				    <sfc:Collection>'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		    --LEVEL 2 GROUPS DATA
		    DECLARE Level2_Cursor CURSOR
		    FOR
		      Select    DISTINCT 
			    Col3 
		      From    @ServerList
		      Where    Col3 != '--'
			AND    Col2 = @Level2
			AND    Col1 = @Level1
		      ORDER BY  1
		    OPEN Level2_Cursor
		    FETCH NEXT FROM Level2_Cursor INTO @Level3
		    WHILE (@@fetch_status <> -1)
		    BEGIN
		      IF (@@fetch_status <> -2)
		      BEGIN
			RAISERROR ('      BUILD LEVEL 3 GROUP INDEX (%s)',-1,-1,@Level3) WITH NOWAIT
			SET @Text = '                          <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/ServerGroup/'+@Level3+'</sml:Uri>
			      </sfc:Reference>'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		      END
		      FETCH NEXT FROM Level2_Cursor INTO @Level3
		    END
		    CLOSE Level2_Cursor
		    DEALLOCATE Level2_Cursor

		    --LEVEL 2 GROUPS FOOTER
		    SET @Text = '                        </sfc:Collection>
			    </RegisteredServers:ServerGroups>'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		    --LEVEL 2 FOOTER
		    SET @Text = '                      <RegisteredServers:Parent>
			    <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup</sml:Uri>
			    </sfc:Reference>
			    </RegisteredServers:Parent>
			    <RegisteredServers:Name type="string">'+@Level2+'</RegisteredServers:Name>
			    <RegisteredServers:Description type="string">'+@Level2+'</RegisteredServers:Description>
			    <RegisteredServers:ServerType type="ServerType">DatabaseEngine</RegisteredServers:ServerType>
			  </RegisteredServers:ServerGroup>
			  </data>
			</document>'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		    --LEVEL 2 SERVERS DATA
		    DECLARE Level2_Cursor CURSOR
		    FOR
		      Select    DISTINCT 
			    Col5,Col6,Col7,Col8,Col9
		      From    @ServerList
		      Where    Col3 = '--'
			AND    Col2 = @Level2
			AND    Col1 = @Level1
		      ORDER BY  1
		    OPEN Level2_Cursor
		    FETCH NEXT FROM Level2_Cursor INTO @Server,@Port,@DomainName,@Apps,@DBs
		    WHILE (@@fetch_status <> -1)
		    BEGIN
		      IF (@@fetch_status <> -2)
		      BEGIN
			SET @Desc = '[Env-Dom] '+@DomainName+'&lt;?char 13?&gt;'+CHAR(10)+'[Apps] '+@Apps+'&lt;?char 13?&gt;'+CHAR(10)+'[DBs] '+@DBs
			SET @Text = '                <document>
			  <docinfo>
			  <aliases>
			    <alias>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/RegisteredServer/'+@Server+'</alias>
			  </aliases>
			  <sfc:version DomainVersion="1" />
			  </docinfo>
			  <data>
			  <RegisteredServers:RegisteredServer xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema">
			    <RegisteredServers:Parent>
			    <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'</sml:Uri>
			    </sfc:Reference>
			    </RegisteredServers:Parent>
			    <RegisteredServers:Name type="string">'+@Server+'</RegisteredServers:Name>
			    <RegisteredServers:Description type="string">'+@Desc+'</RegisteredServers:Description>
			    <RegisteredServers:ServerName type="string">tcp:'+@Server+ISNULL(','+@Port,'')+'</RegisteredServers:ServerName>
			    <RegisteredServers:UseCustomConnectionColor type="boolean">'+CASE WHEN @DomainName Not Like '%AMER%' THEN 'true' ELSE 'false' END +'</RegisteredServers:UseCustomConnectionColor>
			    <RegisteredServers:CustomConnectionColorArgb type="int">-32640</RegisteredServers:CustomConnectionColorArgb>
			    <RegisteredServers:ServerType type="ServerType">DatabaseEngine</RegisteredServers:ServerType>
			    <RegisteredServers:ConnectionStringWithEncryptedPassword type="string">server=tcp:'+@Server+ISNULL(','+@Port,'')+CASE WHEN @DomainName Not Like '%AMER%' THEN ';uid='+@xDomLogin+';password='+@xDomPaswd ELSE ';trusted_connection=true' END + ';pooling=false;packet size=4096;multipleactiveresultsets=false</RegisteredServers:ConnectionStringWithEncryptedPassword>
			    <RegisteredServers:CredentialPersistenceType type="CredentialPersistenceType">'+CASE WHEN @DomainName Not Like '%AMER%' THEN 'PersistLoginNameAndPassword' ELSE 'PersistLoginName' END +'</RegisteredServers:CredentialPersistenceType>
			  </RegisteredServers:RegisteredServer>
			  </data>
			</document>'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		      END
		      FETCH NEXT FROM Level2_Cursor INTO @Server,@Port,@DomainName,@Apps,@DBs
		    END
		    CLOSE Level2_Cursor
		    DEALLOCATE Level2_Cursor

		--LEVEL 3 NESTING GROUP
		DECLARE Level2_Cursor CURSOR
		FOR
		  Select    DISTINCT 
			Col3 
		  From    @ServerList
		  Where    Col3 != '--'
		    AND    Col2 = @Level2
		    AND    Col1 = @Level1
		  ORDER BY  1
		OPEN Level2_Cursor
		FETCH NEXT FROM Level2_Cursor INTO @Level3
		WHILE (@@fetch_status <> -1)
		BEGIN
		  IF (@@fetch_status <> -2)
		  BEGIN
			RAISERROR ('       BUILD LEVEL 3 GROUP DATA (%s)',-1,-1,@Level3) WITH NOWAIT
		    --LEVEL 1 HEADER
		    SET @Text = '                <document>
			  <docinfo>
			  <aliases>
			    <alias>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/ServerGroup/'+@Level3+'</alias>
			  </aliases>
			  <sfc:version DomainVersion="1" />
			  </docinfo>
			  <data>
			  <RegisteredServers:ServerGroup xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema">'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1


		    IF EXISTS (SELECT * FROM @ServerList Where Col1 = @Level1 AND Col2 = @Level2 AND Col3 = @Level3 AND Col4 = '--') -- ARE THERE ANY LEVEL 3 SERVERS
		    BEGIN
		      --LEVEL 3 SERVERS HEADER
		      SET @Text = '                      <RegisteredServers:RegisteredServers>
			      <sfc:Collection>'
		      exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		      --LEVEL 3 SERVERS DATA
		      DECLARE Level3_Cursor CURSOR
		      FOR
			Select    DISTINCT 
			      Col5 
			From    @ServerList
			Where    Col4 = '--'
			  AND    Col3 = @Level3
			  AND    Col2 = @Level2
			  AND    Col1 = @Level1
			ORDER BY  1
		      OPEN Level3_Cursor
		      FETCH NEXT FROM Level3_Cursor INTO @Server
		      WHILE (@@fetch_status <> -1)
		      BEGIN
			IF (@@fetch_status <> -2)
			BEGIN
			  SET @Text = '                          <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/ServerGroup/'+@Level3+'/RegisteredServer/'+@Server+'</sml:Uri>
			      </sfc:Reference>'
			  exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
			END
			FETCH NEXT FROM Level3_Cursor INTO @Server
		      END
		      CLOSE Level3_Cursor
		      DEALLOCATE Level3_Cursor

		      --LEVEL 3 SRVERS FOOTER
		      SET @Text = '                        </sfc:Collection>
			      </RegisteredServers:RegisteredServers>'
		      exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		    END

		    --LEVEL 3 GROUPS HEADER
		    SET @Text = '                      <RegisteredServers:ServerGroups>
			    <sfc:Collection>'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1


		    --LEVEL 3 GROUPS DATA
		    DECLARE Level3_Cursor CURSOR
		    FOR
		      Select    DISTINCT 
			    Col4 
		      From    @ServerList
		      Where    Col4 != '--'
			AND    Col3 = @Level3
			AND    Col2 = @Level2
			AND    Col1 = @Level1
		      ORDER BY  1
		    OPEN Level3_Cursor
		    FETCH NEXT FROM Level3_Cursor INTO @Level4
		    WHILE (@@fetch_status <> -1)
		    BEGIN
		      IF (@@fetch_status <> -2)
		      BEGIN
			RAISERROR ('        BUILD LEVEL 4 GROUP INDEX (%s)',-1,-1,@Level4) WITH NOWAIT
			SET @Text = '                          <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/ServerGroup/'+@Level3+'/ServerGroup/'+@Level4+'</sml:Uri>
			      </sfc:Reference>'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		      END
		      FETCH NEXT FROM Level3_Cursor INTO @Level4
		    END
		    CLOSE Level3_Cursor
		    DEALLOCATE Level3_Cursor

		    --LEVEL 1 GROUPS FOOTER
		    SET @Text = '                        </sfc:Collection>
			    </RegisteredServers:ServerGroups>'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1



		    --LEVEL 1 FOOTER
		    SET @Text = '                      <RegisteredServers:Parent>
			    <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup</sml:Uri>
			    </sfc:Reference>
			    </RegisteredServers:Parent>
			    <RegisteredServers:Name type="string">'+@Level3+'</RegisteredServers:Name>
			    <RegisteredServers:Description type="string">'+@Level3+'</RegisteredServers:Description>
			    <RegisteredServers:ServerType type="ServerType">DatabaseEngine</RegisteredServers:ServerType>
			  </RegisteredServers:ServerGroup>
			  </data>
			</document>'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		    --LEVEL 1 SERVERS DATA
		    DECLARE Level3_Cursor CURSOR
		    FOR
		      Select    DISTINCT 
			    Col5,Col6,Col7,Col8,Col9
		      From    @ServerList
		      Where    Col4 = '--'
			AND    Col3 = @Level3
			AND    Col2 = @Level2
			AND    Col1 = @Level1
		      ORDER BY  1
		    OPEN Level3_Cursor
		    FETCH NEXT FROM Level3_Cursor INTO @Server,@Port,@DomainName,@Apps,@DBs
		    WHILE (@@fetch_status <> -1)
		    BEGIN
		      IF (@@fetch_status <> -2)
		      BEGIN
			SET @Desc = '[Env-Dom] '+@DomainName+'&lt;?char 13?&gt;'+CHAR(10)+'[Apps] '+@Apps+'&lt;?char 13?&gt;'+CHAR(10)+'[DBs] '+@DBs
			SET @Text = '                <document>
			  <docinfo>
			  <aliases>
			    <alias>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/ServerGroup/'+@Level3+'/RegisteredServer/'+@Server+'</alias>
			  </aliases>
			  <sfc:version DomainVersion="1" />
			  </docinfo>
			  <data>
			  <RegisteredServers:RegisteredServer xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema">
			    <RegisteredServers:Parent>
			    <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/ServerGroup/'+@Level3+'</sml:Uri>
			    </sfc:Reference>
			    </RegisteredServers:Parent>
			    <RegisteredServers:Name type="string">'+@Server+'</RegisteredServers:Name>
			    <RegisteredServers:Description type="string">'+@Desc+'</RegisteredServers:Description>
			    <RegisteredServers:ServerName type="string">tcp:'+@Server+ISNULL(','+@Port,'')+'</RegisteredServers:ServerName>
			    <RegisteredServers:UseCustomConnectionColor type="boolean">'+CASE WHEN @DomainName Not Like '%AMER%' THEN 'true' ELSE 'false' END +'</RegisteredServers:UseCustomConnectionColor>
			    <RegisteredServers:CustomConnectionColorArgb type="int">-32640</RegisteredServers:CustomConnectionColorArgb>
			    <RegisteredServers:ServerType type="ServerType">DatabaseEngine</RegisteredServers:ServerType>
			    <RegisteredServers:ConnectionStringWithEncryptedPassword type="string">server=tcp:'+@Server+ISNULL(','+@Port,'')+CASE WHEN @DomainName Not Like '%AMER%' THEN ';uid='+@xDomLogin+';password='+@xDomPaswd ELSE ';trusted_connection=true' END + ';pooling=false;packet size=4096;multipleactiveresultsets=false</RegisteredServers:ConnectionStringWithEncryptedPassword>
			    <RegisteredServers:CredentialPersistenceType type="CredentialPersistenceType">'+CASE WHEN @DomainName Not Like '%AMER%' THEN 'PersistLoginNameAndPassword' ELSE 'PersistLoginName' END +'</RegisteredServers:CredentialPersistenceType>
			  </RegisteredServers:RegisteredServer>
			  </data>
			</document>'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		      END
		      FETCH NEXT FROM Level3_Cursor INTO @Server,@Port,@DomainName,@Apps,@DBs
		    END
		    CLOSE Level3_Cursor
		    DEALLOCATE Level3_Cursor

		--LEVEL 4 NESTING GROUP
		DECLARE Level3_Cursor CURSOR
		FOR
		  Select    DISTINCT 
			Col4 
		  From    @ServerList
		  Where    Col4 != '--'
		    AND    Col3 = @Level3
		    AND    Col2 = @Level2
		    AND    Col1 = @Level1
		  ORDER BY  1
		OPEN Level3_Cursor
		FETCH NEXT FROM Level3_Cursor INTO @Level4
		WHILE (@@fetch_status <> -1)
		BEGIN
		  IF (@@fetch_status <> -2)
		  BEGIN
			RAISERROR ('         BUILD LEVEL 4 GROUP DATA (%s)',-1,-1,@Level4) WITH NOWAIT
		    --LEVEL 4 HEADER
		    SET @Text = '                <document>
			  <docinfo>
			  <aliases>
			    <alias>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/ServerGroup/'+@Level3+'/ServerGroup/'+@Level4+'</alias>
			  </aliases>
			  <sfc:version DomainVersion="1" />
			  </docinfo>
			  <data>
			  <RegisteredServers:ServerGroup xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema">'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1


		    IF EXISTS (SELECT * FROM @ServerList Where Col1 = @Level1 AND Col2 = @Level2 AND Col3 = @Level3 AND Col4 = @Level4) -- ARE THERE ANY LEVEL 4 SERVERS
		    BEGIN
		      --LEVEL 4 SERVERS HEADER
		      SET @Text = '                      <RegisteredServers:RegisteredServers>
			    <sfc:Collection>'
		      exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		      --LEVEL 4 SERVERS DATA
		      DECLARE Level4_Cursor CURSOR
		      FOR
			Select    DISTINCT 
			      Col5 
			From    @ServerList
			Where    Col4 = @Level4
			  AND    Col3 = @Level3
			  AND    Col2 = @Level2
			  AND    Col1 = @Level1
			ORDER BY  1
		      OPEN Level4_Cursor
		      FETCH NEXT FROM Level4_Cursor INTO @Server
		      WHILE (@@fetch_status <> -1)
		      BEGIN
			IF (@@fetch_status <> -2)
			BEGIN
			  SET @Text = '                          <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/ServerGroup/'+@Level3+'/ServerGroup/'+@Level4+'/RegisteredServer/'+@Server+'</sml:Uri>
			      </sfc:Reference>'
			  exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
			END
			FETCH NEXT FROM Level4_Cursor INTO @Server
		      END
		      CLOSE Level4_Cursor
		      DEALLOCATE Level4_Cursor

		      --LEVEL 4 SRVERS FOOTER
		      SET @Text = '                        </sfc:Collection>
			    </RegisteredServers:RegisteredServers>'
		      exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		    END

    
		    --LEVEL 1 FOOTER
		    SET @Text = '                      <RegisteredServers:Parent>
			    <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup</sml:Uri>
			    </sfc:Reference>
			    </RegisteredServers:Parent>
			    <RegisteredServers:Name type="string">'+@Level4+'</RegisteredServers:Name>
			    <RegisteredServers:Description type="string">'+@Level4+'</RegisteredServers:Description>
			    <RegisteredServers:ServerType type="ServerType">DatabaseEngine</RegisteredServers:ServerType>
			  </RegisteredServers:ServerGroup>
			  </data>
			</document>'
		    exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		    --LEVEL 1 SERVERS DATA
		    DECLARE Level4_Cursor CURSOR
		    FOR
		      Select    DISTINCT 
			    Col5,Col6,Col7,Col8,Col9
		      From    @ServerList
		      Where    Col4 = @Level4
			AND    Col3 = @Level3
			AND    Col2 = @Level2
			AND    Col1 = @Level1
		      ORDER BY  1
		    OPEN Level4_Cursor
		    FETCH NEXT FROM Level4_Cursor INTO @Server,@Port,@DomainName,@Apps,@DBs
		    WHILE (@@fetch_status <> -1)
		    BEGIN
		      IF (@@fetch_status <> -2)
		      BEGIN
			SET @Desc = '[Env-Dom] '+@DomainName+'&lt;?char 13?&gt;'+CHAR(10)+'[Apps] '+@Apps+'&lt;?char 13?&gt;'+CHAR(10)+'[DBs] '+@DBs
			SET @Text = '                <document>
			  <docinfo>
			  <aliases>
			    <alias>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/ServerGroup/'+@Level3+'/ServerGroup/'+@Level4+'/RegisteredServer/'+@Server+'</alias>
			  </aliases>
			  <sfc:version DomainVersion="1" />
			  </docinfo>
			  <data>
			  <RegisteredServers:RegisteredServer xmlns:RegisteredServers="http://schemas.microsoft.com/sqlserver/RegisteredServers/2007/08" xmlns:sfc="http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08" xmlns:sml="http://schemas.serviceml.org/sml/2007/02" xmlns:xs="http://www.w3.org/2001/XMLSchema">
			    <RegisteredServers:Parent>
			    <sfc:Reference sml:ref="true">
			      <sml:Uri>/RegisteredServersStore/ServerGroup/DatabaseEngineServerGroup/ServerGroup/'+@Level1+'/ServerGroup/'+@Level2+'/ServerGroup/'+@Level3+'/ServerGroup/'+@Level4+'</sml:Uri>
			    </sfc:Reference>
			    </RegisteredServers:Parent>
			    <RegisteredServers:Name type="string">'+@Server+'</RegisteredServers:Name>
			    <RegisteredServers:Description type="string">'+@Desc+'</RegisteredServers:Description>
			    <RegisteredServers:ServerName type="string">tcp:'+@Server+ISNULL(','+@Port,'')+'</RegisteredServers:ServerName>
			    <RegisteredServers:UseCustomConnectionColor type="boolean">'+CASE WHEN @DomainName Not Like '%AMER%' THEN 'true' ELSE 'false' END +'</RegisteredServers:UseCustomConnectionColor>
			    <RegisteredServers:CustomConnectionColorArgb type="int">-32640</RegisteredServers:CustomConnectionColorArgb>
			    <RegisteredServers:ServerType type="ServerType">DatabaseEngine</RegisteredServers:ServerType>
			    <RegisteredServers:ConnectionStringWithEncryptedPassword type="string">server=tcp:'+@Server+ISNULL(','+@Port,'')+CASE WHEN @DomainName Not Like '%AMER%' THEN ';uid='+@xDomLogin+';password='+@xDomPaswd ELSE ';trusted_connection=true' END + ';pooling=false;packet size=4096;multipleactiveresultsets=false</RegisteredServers:ConnectionStringWithEncryptedPassword>
			    <RegisteredServers:CredentialPersistenceType type="CredentialPersistenceType">'+CASE WHEN @DomainName Not Like '%AMER%' THEN 'PersistLoginNameAndPassword' ELSE 'PersistLoginName' END +'</RegisteredServers:CredentialPersistenceType>
			  </RegisteredServers:RegisteredServer>
			  </data>
			</document>'
			exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1
		      END
		      FETCH NEXT FROM Level4_Cursor INTO @Server,@Port,@DomainName,@Apps,@DBs
		    END
		    CLOSE Level4_Cursor
		    DEALLOCATE Level4_Cursor

		  END
		  FETCH NEXT FROM Level3_Cursor INTO @Level4
		END
		CLOSE Level3_Cursor
		DEALLOCATE Level3_Cursor

		  END
		  FETCH NEXT FROM Level2_Cursor INTO @Level3
		END
		CLOSE Level2_Cursor
		DEALLOCATE Level2_Cursor

		  END
		  FETCH NEXT FROM Level1_Cursor INTO @Level2
		END
		CLOSE Level1_Cursor
		DEALLOCATE Level1_Cursor

		  END
		  FETCH NEXT FROM Level0_Cursor INTO @Level1
		END
		CLOSE Level0_Cursor
		DEALLOCATE Level0_Cursor

		SET @Text = '              </instances>
			    </RegisteredServers:bufferData>
			  </xs:schema>
			</data>
		      </document>
		    </definitions>
		  </xs:bufferSchema>
		</model>'
		exec dbaadmin.dbo.dbasp_FileAccess_Write @Text, @OutputFileName,1,1

		DoneWithCode:

		---------------------------- CURSOR LOOP BOTTOM
		----------------------------
	END
	FETCH NEXT FROM DBACursor INTO @DBAName,@xDomLogin,@xDomPaswd,@OutputFileName;
END
CLOSE DBACursor;
DEALLOCATE DBACursor;

-- RESET DBAName
SET @DBAName = @DBAName_Save


IF (SELECT COUNT(*) FROM @DBATable WHERE DBAName Like ISNULL(@DBAName_Save,'') +'%' AND DBAName != 'BULK') > 1
BEGIN

	SELECT	@OutputFileName	= @OutputPath + 'BULK_TEMPLATE.regsrvr'	
	RAISERROR ('READ %s',-1,-1,@OutputFileName) WITH NOWAIT

	exec [dbaadmin].[dbo].[dbasp_FileAccess_Read_Blob] @FullFileName = @OutputFileName, @FileText = @Text OUT

	DECLARE DBACursor CURSOR
	FOR
	SELECT		DBAName			
			,DBALoginName		
			,EncryptedPassword	
			,OutputFileName		
	FROM		@DBATable 
	WHERE		DBAName Like ISNULL(@DBAName,'') +'%'
		AND	DBAName != 'BULK'

	SELECT	@TempValue = dbaadmin.dbo.dbaudf_Concatenate(DBAName) FROM @DBATable WHERE DBAName Like ISNULL(@DBAName,'') +'%'
	RAISERROR ('Generating REGSRVR File for the following DBA''s (%s)',-1,-1,@TempValue) WITH NOWAIT
	PRINT ''

	OPEN DBACursor;
	FETCH DBACursor INTO @DBAName,@xDomLogin,@xDomPaswd,@OutputFileName;
	WHILE (@@fetch_status <> -1)
	BEGIN
		IF (@@fetch_status <> -2)
		BEGIN
			--SELECT		@DBAName,@xDomLogin,@xDomPaswd,@OutputFileName;

			SELECT		@OutputFileData		= REPLACE(REPLACE(@Text,'$xDomLogin$',@xDomLogin),'$xDomPaswd$',@xDomPaswd)
					,@OutputFileName	= @OutputPath + @OutputFileName + '.regsrvr'

			RAISERROR ('  Generating REGSRVR File for: %s',-1,-1,@DBAName) WITH NOWAIT
			RAISERROR ('  Output to: %s',-1,-1,@OutputFileName) WITH NOWAIT
			RAISERROR ('    ',-1,-1) WITH NOWAIT

			--SELECT		@OutputFileName
			exec dbaadmin.dbo.dbasp_FileAccess_Write @OutputFileData, @OutputFileName,0,1

		END
		FETCH NEXT FROM DBACursor INTO @DBAName,@xDomLogin,@xDomPaswd,@OutputFileName;
	END
	CLOSE DBACursor;
	DEALLOCATE DBACursor;

END
ELSE
	RAISERROR ('BULK_TEMPLATE.regsrvr was not used',-1,-1) WITH NOWAIT


ExitProcedure:					


