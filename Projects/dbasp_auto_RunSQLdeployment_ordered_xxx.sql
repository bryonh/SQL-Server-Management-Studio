USE [DEPLinfo]
GO
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[dpsp_auto_RunSQLdeployment_ordered_xxx]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[dpsp_auto_RunSQLdeployment_ordered_xxx]
GO
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[dpsp_auto_RunSQLdeployment_ordered_xxx] 
					(
					 @DBname				sysname			= null
					,@ProjectName			sysname			= null
					,@DB_Copy_BuildCode		varchar(255)	= null
					,@build_path			varchar(255)	= null
					,@BuildType				tinyint			= null
					,@ProcessType			sysname			= 'normal'
					)
/*========= DESCRIPTION ===========================================================================	
 **  dpsp_auto_RunSQLdeployment_ordered
 **
 **  Re-Written by Jim Wilson, Getty Images		**  Re-Re-Written by Steve Ledridge, Getty Images                
 **  February 7, 2005							**	April 20, 2011
 **  
 **  This sproc is set up to process SQL builds as part of the automated SQL deployment process.
 **
 **  PURPOSE:	This sproc is designed to be a generic installer for SQL Application code. It can be used
 **				to build and/or populate a database with objects and/or data. The sproc functions in a "blind"
 **				manner by running .sql files that reside in any of the directories identified below, with some
 **				exceptions. The order of the work is identified by the individual calls to an sqlcmd wrapper
 **				below, (consistent with what might be expected for building database objects). The order of
 **				processing files within each folder will be alphabetical.
 **
 **				Exceptions to the normal SQL file process are found in the Data_Load folders and the cmd_Scripts
 **				folder. The Data_Load folders '*.txt' files which are BCP'd into the database (file name matching
 **				table name). The cmd_scripts folder will contain script files, command files or DTS structured
 **				files which will be copied to the servername_dbasql share on the local server.
 **
 **				Subfolders Under Data_Load, Pre_Script and Post_Script can be used to control ordering 
 **				and sequencing processes.
 **
 **  REQUIRED SUBDIRECTORIES AND ORDER OF OPERATION:
 **				All Required Directories are Populated in the @DeploymentStages Table allong with
 **				Information on If included in Sprocs-Only, Exclusions from specific enviroments,
 **				and the types of files expected in each folder.
 **
 **  ASSUMES:
 **				FILE TYPES				=	SQL Files	must be a text file with the '.sql' extension.
 **											BCP	Files	must be a named as the object the data is inserted into.
 **											COPY Files	Can be and combination of files and folders.  
 **	
 **  INPUT PARMS:
 **				@dbname					=	Is the database name being processed
 **				@CT_DB_Copy_BuildCode	=	Is the name of the folder containing the build files
 **				@CL_BuildType			=	Is a flag indicating full-build (0) os sprocs-only (1)
 **				@allsprocs_flag			=	Is a flag indicating all sprocs will be processed
 **				@build_path				=	(optional) is the path to the build folder 
 **
 ** RETURN CODE TRANSLATION:
 **				X,YYY,ZZZ		X		=	Early Termination
 **								YYY		=	Number of Errors
 **								ZZZ 	=	Number of Warnings
 ** 
 ***************************************************************/
as
--========= COMMENT BLOCK =========================================================================	
--	Revision History
--	Date		Author     		Desc
--	==========	==============	=======================================================
--	02/07/2005	Jim Wilson		Revised old VSS related process to this mks version.
--	02/15/2005	Jim Wilson		Added code to update DEPLinfo build via sproc.
--	04/05/2005	Jim Wilson		Added post_build section.
--	05/10/2005	Jim Wilson		Added changelist cross check process.
--	07/22/2005	Jim Wilson		Convereted osql print processing to echo commands.
--	08/02/2005	Jim Wilson		Added bypass of *.doc and *.sav files in the changelist.
--	10/10/2005	Jim Wilson		Changelist records 'may' now include folder\filename.
--	11/02/2005	Jim Wilson		Added prior build history for DB to output log file.
--	12/19/2005	Jim Wilson		Check for file type prior to data load, and now check
--									change list for all files.
--	12/29/2005	Jim Wilson		Added output message for unicode or non-unicode file processing.
--	04/04/2006	Jim Wilson		Added /R to cmd file copy process.
--	05/03/2006	Jim Wilson		Added @CL_ProcessType input parm.
--	07/11/2006	Jim Wilson		Added triggers and functions to the sprocs only process.
--	08/02/2006	Jim Wilson		Modified 'copy /Y' to 'xcopy /Y /K /R'
--	08/29/2006	Jim Wilson		Added "terminated" to the error check
--	01/31/2007	Jim Wilson		Added 2nd try bcp with quoted identifiers (-q)
--	02/07/2007	Jim Wilson		Changed BCP process to set parms based on file and table attributes.
--	02/26/2007	Jim Wilson		Added logging for each script
--	03/30/2007	Jim Wilson		Added temp_pre and temp_post folder processing (for non-production)
--	04/18/2007	Jim Wilson		Fixed -ddbname for temp_pre and temp_post folder processing
--	06/05/2007	Jim Wilson		Added *.WRN output file process
--	07/03/2007	Jim Wilson		Change code for cmdscript section.  Will now create sub folders.
--	06/16/2008	Jim Wilson		Added code for codetype = FULL.
--	07/21/2008	Jim Wilson		New code to skip change list x-check for temp_pre and temp_post.
--	07/31/2008	Jim Wilson		Added support for non-dbo schemas in the dataload sections.
--	08/01/2008	Jim Wilson		New code to determine use of the -E parm for BCP.
--	08/08/2008	Jim Wilson		Removed code to determine use of the -E parm for BCP.  Back to the old way.
--	02/11/2009	Jim Wilson		Updated for DEPLinfo.
--	03/10/2009	Jim Wilson		Added views to sprocs-only processing.
--	05/15/2009	Jim Wilson		Moved function to after prescript.
--	06/16/2009	Jim Wilson		Added 'File not Processed' error to the deployment log output.
--	08/03/2009	Jim Wilson		Added process to skip deployment if build code was not copied.
--	09/23/2009	Jim Wilson		Check for error before the build table update process.
--	01/12/2010	Jim Wilson		Renamed and modified this sproc for deployment of the ordered build tree.
--	01/28/2010	Jim Wilson		Added code for the new folder 75_SQLJob.
--	02/03/2010	Jim Wilson		Added code for new build folder names (dynamic dual deployments).
--	03/11/2010	Jim Wilson		Changelist cross check will now bypass '%_temp_p%'.
--	03/30/2010	Jim Wilson		Ignore *.proj files in the change list.
--	06/01/2010	Jim Wilson		Now using DBA_changelist.txt.
--	02/25/2011	Jim Wilson		Added updates to the BuildDetail table.
--	03/17/2011	Jim Wilson		Added code for extended property updates.
--	04/20/2011	Steve Ledridge	Complete rewrite to implement Code Reuse and Standardizations.
--	===============================================================================================
SET NOCOUNT ON
--========= TESTING ===============================================================================	
/*
	declare @DBname					sysname
	declare @ProjectName			sysname
	declare @DB_Copy_BuildCode		varchar(255)
	declare @build_path				varchar(255)
	declare @BuildType				tinyint
	declare @ProcessType			sysname

	select @dbname					= 'Transcoder'
	select @ProjectName				= 'Transcoder'
	select @DB_Copy_BuildCode		= 'Transcoder'
	select @build_path				= 'd:\'
	select @BuildType				= 0
	select @ProcessType				= 'normal' --('normal', 'allsprocs')
--*/
SET NOCOUNT ON
--========= DECLARES ==============================================================================	
DECLARE							-- DECLARE REGULAR VARIABLES										
	@miscprint					VARCHAR(max)
	,@CRLF						Char(2)
	,@servername				SYSNAME
	,@servername2				SYSNAME
	,@servername3				SYSNAME
	,@EI_ENVName				SYSNAME
	,@EI_ENVNum					SYSNAME
	,@EI_BuildCodeServer		SYSNAME
	,@CL_DBname					SYSNAME
	,@CL_gears_id				INT
	,@CL_ProjectName			SYSNAME
	,@CL_ProcessType			SYSNAME
	,@CL_BuildType				SYSNAME
	,@CT_DB_Copy_BuildCode		SYSNAME
	,@currpath					NVARCHAR(500)
	,@currfolder				SYSNAME
	,@tablename					SYSNAME
	,@schemaname				SYSNAME
	,@run_duration_ss			INT
	,@codetype					VARCHAR(10)
	,@label						NVARCHAR(100)
	,@rev						NVARCHAR(100)
	,@version					NVARCHAR(100)
	,@BuildLabel				NVARCHAR(100)
	,@proc_code					NVARCHAR(10)
	,@DateStmp 					NCHAR(13)
	,@Hold_hhmmss				NVARCHAR(8)
	,@bcpcmd					VARCHAR(4000)
	,@cmd	 					NVARCHAR(4000)
	,@filecount					SMALLINT
	,@Result					INT
	,@error_count				INT
	,@warn_Count				INT
	,@TerminatedEarly			BIT
	,@BCPparms					SYSNAME
	,@cmptcolcount				INT
	,@indxviewcount				INT
	,@ReplEnabled				BIT
	,@IsAgentJob				BIT
	,@AppName					SYSNAME
	,@dynamicSQL				NVARCHAR(500)
	,@dynamicVAR				NVARCHAR(100)
	,@start_datetime			DATETIME
	,@end_datetime				DATETIME
	,@longrun_limit				SMALLINT
	,@rowcount					INT
	,@env_var					VARCHAR(500)
	,@log_file_name				VARCHAR(1024)
	,@log_file_name_W			VARCHAR(1024)
	,@log_file_name_E			VARCHAR(1024)
	,@extprop_cmd				NVARCHAR(4000)
	,@PARAMETERS				NVARCHAR(4000)
	,@ExtPropChk				SQL_VARIANT
	,@cu_cmdoutput				NVARCHAR(255)
	,@CurDateTime				DATETIME
	,@NestLevel					INT
	,@Reusable_String_1			VarChar(max)
	,@Reusable_String_2			VarChar(max)
	,@Reusable_String_3			VarChar(max)
	,@Reusable_String_4			VarChar(max)
	,@Reusable_DateTime_1		DateTime
	,@Reusable_DateTime_2		DateTime
	,@Reusable_DateTime_3		DateTime
	,@Reusable_DateTime_4		DateTime
	,@Reusable_INT_1			INT
	,@Reusable_INT_2			INT
	,@Reusable_INT_3			INT
	,@Reusable_INT_4			INT
	,@Reusable_FLOAT_1			FLOAT
	,@Reusable_FLOAT_2			FLOAT
	,@Reusable_FLOAT_3			FLOAT
	,@Reusable_FLOAT_4			FLOAT
	,@Reusable_BIT_1			BIT
	,@Reusable_BIT_2			BIT
	,@Reusable_BIT_3			BIT
	,@Reusable_BIT_4			BIT
	,@DeplStage					sysname
	,@DeplStageType				sysname
	,@DeplStageExpected			bit
	,@DeplStageFound			bit
	,@DeplStageInSprocOnly		bit
	,@DeplStageNotInProd		bit
	,@DeplStageNotInStage		bit
	,@DeplStageNotInDev			bit
	,@DeplStageNotInTest		bit
	,@DeplFileExpected			bit
	,@DeplFileFound				bit
	,@File_Name					sysname
	,@File_Path					VarChar(2048)
	,@File_RelativePath			VarChar(1024)
	,@OutputText				VarChar(max)
	,@IsFolder					BIT
DECLARE							-- DECLARE TABLE: @UpdateBuild										
	@UpdateBuild				TABLE ([RowNumber] Bigint PRIMARY KEY,[Row] VarChar(max))
DECLARE							-- DECLARE TABLE: @change_Info										
	@change_Info				TABLE ([detail] sysname null, [run_flag] char(1) null)
DECLARE							-- DECLARE TABLE: @DeploymentStages									
	@DeploymentStages			TABLE ([DeplStage] sysname,[DeplType] sysname,[InSprocOnly] BIT,[NotInProd] BIT,[NotInStage] BIT,[NotInTest] Bit, [NotInDev] Bit)
--========= GET INITAL VALUES =====================================================================
INSERT INTO	@DeploymentStages	-- CREATE LIST OF EXPECTED DEPLOYMENT STAGES						
	([DeplStage],[DeplType],[InSprocOnly],[NotInProd],[NotInStage],[NotInTest],[NotInDev])			
SELECT			'05_Pre_DB'				,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'10_Temp_Pre'			,'SQL'	,0,1,0,0,0
UNION ALL
SELECT			'15_User_Type'			,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'20_Function'			,'SQL'	,1,0,0,0,0
UNION ALL
SELECT			'25_Pre_Script'			,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'30_View'				,'SQL'	,1,0,0,0,0
UNION ALL
SELECT			'35_DataLoad'			,'BCP'	,0,0,0,0,0
UNION ALL
SELECT			'40_StoredProcedure'	,'SQL'	,1,0,0,0,0
UNION ALL
SELECT			'45_Trigger'			,'SQL'	,1,0,0,0,0
UNION ALL
SELECT			'50_Post_Script'		,'SQL'	,1,0,0,0,0
UNION ALL
SELECT			'55_CmdScript'			,'COPY'	,0,0,0,0,0
UNION ALL
SELECT			'60_Post_DB'			,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'65_Temp_Post'			,'SQL'	,0,1,0,0,0
UNION ALL
SELECT			'70_Post_Build'			,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'75_SQLJob'				,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'90_RawData'			,'BCP'	,0,0,0,0,0
SELECT							-- NON TABLE VALUES (EARLY)											
		@CRLF					= CHAR(13) + CHAR(10)
		,@NestLevel				= 0
		,@error_count			= 0
		,@warn_count			= 0
		,@TerminatedEarly		= 0
		,@longrun_limit			= 5
		,@codetype				= 'normal'
		
		-- STANDARDIZED SERVER NAMES
		,@servername			= REPLACE(@@SERVERNAME,'\' + @@SERVICENAME,'')
		,@servername2			= REPLACE(@@SERVERNAME,'\','$')
		,@servername3			= @servername + CASE @@SERVICENAME WHEN 'MSSQLSERVER' THEN '' ELSE '(' + @@SERVICENAME +')' END
		
		-- STANDARDIZED DATE AND TIME STAMPS
		,@CurDateTime			= GetDate()
		,@Hold_hhmmss			= convert(varchar(8), @CurDateTime, 8)
		,@DateStmp				= convert(char(8), @CurDateTime, 112) + substring(@Hold_hhmmss, 1, 2) + substring(@Hold_hhmmss, 4, 2) + substring(@Hold_hhmmss, 7, 2) 
		,@AppName				= [dbo].[dbaudf_APP_NAME](NULL)
		,@IsAgentJob			= CASE WHEN @AppName LIKE 'SQLAgent - TSQL JobStep%' THEN 1 ELSE 0 END
		,@DBname				= DB_NAME(DB_ID(@DBNAME))
		,@build_path			= [dbo].[dbaudf_GetFileProperty] (@build_path,'Folder','Path')
		,@AppName				= [dbo].[dbaudf_APP_NAME](NULL)
		,@IsAgentJob			= CASE WHEN @AppName LIKE 'SQLAgent - TSQL JobStep%' THEN 1 ELSE 0 END

--========= TEST INPUTS ===========================================================================

If @IsAgentJob = 0				-- CHECK: IF MANUALLY RUN (NOT SQL AGENT JOB)						
   BEGIN						-- MANUALY RUN
	SELECT	@miscprint			= 'Note:  This process is being run manually'						-- SET IT
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT IT
	SELECT	@NestLevel			= @NestLevel + 1

	If DB_ID(@DBName) IS NULL						-- CHECK: DBNAME
	   BEGIN
		SELECT	@miscprint	= 'Error: A VALID Database was not specified for the @DBName parameter.'
				,@error_count = @error_count + 1										-- SET IT
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT IT
	   END
	   
	If COALESCE(@DB_Copy_BuildCode,'')=''			-- CHECK: BUILDCODE
	   BEGIN
		SELECT	@miscprint	= 'Error: A VALID Value was not specified for the @DB_Copy_BuildCode parameter.'
				,@error_count = @error_count + 1										-- SET IT
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT IT
	   END
	   
	If @ProcessType not in ('normal', 'allsprocs')	-- CHECK: PROCESSTYPE
	   BEGIN
		SELECT	@miscprint	= 'Error: A VALID Value was not specified for the @@ProcessType parameter.'
				,@error_count = @error_count + 1										-- SET IT
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT IT
	   END

	IF @error_count > 0								-- CHECK: ERROR COUNT SO FAR
	   BEGIN
		Select	@NestLevel	= @NestLevel + 1																	
				,@miscprint	= @CRLF+'Here is a sample execute command for this sproc (without standard shares):' + @CRLF
							+ 'Note:  If the @build_path parameter is not provided, the path to the build folder' + @CRLF
							+ '       is automatically determined using the standard shares.' + @CRLF
							+ @CRLF
							+ 'exec DEPLinfo.dbo.dpsp_auto_RunSQLdeployment_ordered' + @CRLF
							+ '		 @DBname            = ''wcds''		--  Database Name' + @CRLF
							+ '		,@ProjectName       = ''WEaD''		--  Project Title (from TFS)' + @CRLF
							+ '		,@DB_Copy_BuildCode = ''wcds''		--  Build Folder Name' + @CRLF
							+ '		,@build_path        = ''d:\builds''	--  Drive Letter Path to the Build Folder (not including the build folder name)' + @CRLF
							+ '		,@BuildType         = 0             --  0 (for full), 1 (for sprocs only)' + @CRLF
							+ '		,@ProcessType       = ''normal''		--  ''Normal'', ''allsprocs'' (will deploy all sprocs)' + @CRLF
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT IT

		-- RAISERROR AND EXIT --
		SELECT	@miscprint			= 'Error: Manual Execution Failed Because of Invalid Parameters' + @CRLF
				,@NestLevel			= @NestLevel + 1
				,@TerminatedEarly	= 1													-- SET IT
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT IT
		EXEC	[dbo].[dbasp_print] '-------------------------------------FORCED ERROR----------------------------------------',0,0,1
		RAISERROR(@miscprint,16,1) WITH LOG												-- RAISERROR
		EXEC	[dbo].[dbasp_print] '-----------------------------------------------------------------------------------------',0,0,1
		GOTO label99																	-- EXIT
	   END
   END
ELSE
   BEGIN						-- AGENT JOB
	Select	@miscprint	= 'Note:  This process is being run by ' 
						+ @AppName + @CRLF + @CRLF										-- SET IT
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1								-- PRINT IT
   END
	
--========= GET INITAL VALUES =====================================================================
INSERT INTO	@DeploymentStages	-- CREATE LIST OF EXPECTED DEPLOYMENT STAGES						
	([DeplStage],[DeplType],[InSprocOnly],[NotInProd],[NotInStage],[NotInTest],[NotInDev])			
SELECT			'05_Pre_DB'				,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'10_Temp_Pre'			,'SQL'	,0,1,0,0,0
UNION ALL
SELECT			'15_User_Type'			,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'20_Function'			,'SQL'	,1,0,0,0,0
UNION ALL
SELECT			'25_Pre_Script'			,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'30_View'				,'SQL'	,1,0,0,0,0
UNION ALL
SELECT			'35_DataLoad'			,'BCP'	,0,0,0,0,0
UNION ALL
SELECT			'40_StoredProcedure'	,'SQL'	,1,0,0,0,0
UNION ALL
SELECT			'45_Trigger'			,'SQL'	,1,0,0,0,0
UNION ALL
SELECT			'50_Post_Script'		,'SQL'	,1,0,0,0,0
UNION ALL
SELECT			'55_CmdScript'			,'COPY'	,0,0,0,0,0
UNION ALL
SELECT			'60_Post_DB'			,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'65_Temp_Post'			,'SQL'	,0,1,0,0,0
UNION ALL
SELECT			'70_Post_Build'			,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'75_SQLJob'				,'SQL'	,0,0,0,0,0
UNION ALL
SELECT			'90_RawData'			,'BCP'	,0,0,0,0,0
SELECT							-- NON TABLE VALUES (EARLY)											
		@CRLF					= CHAR(10) + CHAR(13)
		,@NestLevel				= 0
		,@error_count			= 0
		,@warn_count			= 0
		,@TerminatedEarly		= 0
		,@longrun_limit			= 5
		,@codetype				= 'normal'
		
		-- STANDARDIZED SERVER NAMES
		,@servername			= REPLACE(@@SERVERNAME,'\' + @@SERVICENAME,'')
		,@servername2			= REPLACE(@@SERVERNAME,'\','$')
		,@servername3			= @servername + CASE @@SERVICENAME WHEN 'MSSQLSERVER' THEN '' ELSE '(' + @@SERVICENAME +')' END
		
		-- STANDARDIZED DATE AND TIME STAMPS
		,@CurDateTime			= GetDate()
		,@Hold_hhmmss			= convert(varchar(8), @CurDateTime, 8)
		,@DateStmp				= convert(char(8), @CurDateTime, 112) + substring(@Hold_hhmmss, 1, 2) + substring(@Hold_hhmmss, 4, 2) + substring(@Hold_hhmmss, 7, 2) 
		--,@AppName				= [dbo].[dbaudf_APP_NAME](NULL)
		--,@IsAgentJob			= CASE WHEN @AppName LIKE 'SQLAgent - TSQL JobStep%' THEN 1 ELSE 0 END

SELECT							-- ENVIRO_INFO VALUES												
		@EI_ENVName				= 'user' -- SET DEFAULT VALUE IF NOT FOUND IN TABLE
		,@EI_ENVName			= CASE [env_type]	WHEN 'ENVname'			THEN COALESCE([env_name],@EI_ENVName)			ELSE @EI_ENVName			END
		,@EI_ENVNum				= CASE [env_type]	WHEN 'ENVnum'			THEN COALESCE([env_name],@EI_ENVNum)			ELSE @EI_ENVNum				END
		,@EI_BuildCodeServer	= CASE [env_type]	WHEN 'BuildCodeServer'	THEN COALESCE([env_name],@EI_BuildCodeServer)	ELSE @EI_BuildCodeServer	END

FROM	DEPLinfo.dbo.enviro_info WITH(NOLOCK)

SELECT							-- CONTROL_LOCAL VALUES												
		@CL_DBname				= COALESCE(@DBname,[DBname],@CL_ProjectName)
		,@CL_gears_id			= COALESCE([gears_id],@CL_gears_id)
		,@CL_ProjectName		= COALESCE(@ProjectName,[Projectname],@CL_ProjectName)
		,@CL_ProcessType		= COALESCE(@ProcessType,[ProcessType],@CL_ProcessType)
		,@CL_BuildType			= COALESCE(@BuildType,CASE WHEN @CL_ProcessType LIKE 'sproc%' THEN 1 ELSE 0 END)
		,@CL_ProcessType		= CASE WHEN @CL_ProcessType like '%Allsp%' THEN 'allsprocs' END
FROM	DEPLinfo.dbo.control_local WITH(NOLOCK) 
WHERE	[status] NOT IN ('completed','cancelled') 

SELECT							-- CONTROLTABLE VALUES												
		@CT_DB_Copy_BuildCode	= COALESCE(	@DB_Copy_BuildCode
											,CASE	WHEN [subject] = 'DB_copy_buildcode' AND [control01] = @CL_DBname and [control03] = 'in-work' 
													THEN COALESCE([control02],@CT_DB_Copy_BuildCode)	
													ELSE @CT_DB_Copy_BuildCode END)
FROM	DEPLinfo.dbo.controltable WITH(NOLOCK)

SELECT							-- NON TABLE VALUES (LATE)											
		@ReplEnabled			= CASE WHEN DATABASEPROPERTYEX(@DBName,'IsMergePublished')=1 OR DATABASEPROPERTYEX(@DBName,'IsPublished')=1 OR DATABASEPROPERTYEX(@DBName,'IsSubscribed')=1 THEN 1 ELSE 0 END
		,@proc_code				= CASE @CL_BuildType WHEN 1 THEN 'I' ELSE 'F' EnD
		
		-- STANDARDIZED PATHS --
		,@build_path			= COALESCE(@build_path,'\\' + @servername + '\' + @servername + '_builds\')
		,@build_path			= @build_path + CASE RIGHT(@build_path,1) WHEN '\' THEN '' ELSE '\' END 
		,@currpath				= @build_path + @CT_DB_Copy_BuildCode
		,@log_file_name			= @build_path + 'deployment_logs\SQLDEPL_' + @servername + '_' + @CT_DB_Copy_BuildCode + '_' + @proc_code + '_' + @DateStmp

--========= SETUPS AND CHECKS =====================================================================

If DB_ID(@CL_DBName) IS NULL	-- CHECK: DBNAME
   BEGIN
	SELECT	@miscprint	= 'ERROR: Control row for this Restore job step could not be found (Server ' + @@SERVERNAME + ').' + @CRLF
			,@error_count = @error_count + 1										-- SET IT
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT IT

	-- RAISERROR AND EXIT --
	SELECT	@miscprint			= 'Error: Automated Execution Failed Because of Invalid or Missing Control_Local Record' + @CRLF
			,@NestLevel			= @NestLevel + 1
			,@TerminatedEarly	= 1													-- SET IT
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT IT
	EXEC	[dbo].[dbasp_print] '-------------------------------------FORCED ERROR----------------------------------------',0,0,1
	RAISERROR(@miscprint,16,1) WITH LOG												-- RAISERROR
	EXEC	[dbo].[dbasp_print] '-----------------------------------------------------------------------------------------',0,0,1
	GOTO label99																	-- EXIT
   END

BEGIN							-- CHECK: DEPLOYMENT LOG DIRECTORY									
	SELECT	@Reusable_String_1	= @build_path + 'deployment_logs\'
	IF [dbo].[dbaudf_GetFileProperty] (@Reusable_String_1,'Folder','Path') IS NULL
	   BEGIN						-- FAILURE
		SELECT	@miscprint	= 'Path to Deployment Logs [' 
							+ @Reusable_String_1 + '] is NOT Valid'					-- SET IT
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1						-- PRINT IT
		
		-- RAISERROR AND EXIT --
		SELECT	@miscprint			= 'Error: Deployment Logs Folder is Invalid'
				,@error_count		= @error_count + 1
				,@TerminatedEarly	= 1												-- SET IT
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1						-- PRINT IT
		EXEC	[dbo].[dbasp_print] '-------------------------------------FORCED ERROR----------------------------------------',0,0,1
		RAISERROR(@miscprint,16,1) WITH LOG												-- RAISERROR
		EXEC	[dbo].[dbasp_print] '-----------------------------------------------------------------------------------------',0,0,1
		goto label99																-- EXIT
	   END
	Else
	   BEGIN						-- SUCCESS
		SELECT	@miscprint	= 'Deployment Logs Folder [' + @Reusable_String_1 
							+ '] WILL Be Used For This SQL Deployment.' + @CRLF		-- SET IT
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1						-- PRINT IT
	   END
	SELECT	@Reusable_String_1	= NULL   
END

BEGIN							-- CREATE LOG FILES													
	SELECT	@miscprint = 'Creating Empty Log Files.' + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
	SELECT	@NestLevel			= @NestLevel + 1
			,@Reusable_String_1	= 'LOG'

	CreateLog:
		-- LOOP TO CREATE AND VERIFY 3 LOG FILES --
		SELECT	@Reusable_String_2	= @log_file_name + '.' + LOWER(@Reusable_String_1)
				,@miscprint			= 'CREATING: '+COALESCE(@Reusable_String_1,'{EXT}')+' File: ' + COALESCE(@Reusable_String_2,'{File}')
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1		
		EXEC	[dbo].[dbasp_FileAccess_Write] '', @Reusable_String_2, NULL, 0 -- OVERWRITE

		IF [dbo].[dbaudf_GetFileProperty] (@Reusable_String_2,'FIle','Path') IS NOT NULL
		   BEGIN
			SELECT	@miscprint = 'CREATED: '+@Reusable_String_1+' File: ' + @Reusable_String_2
			EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
			INSERT	DEPLinfo.dbo.build_files VALUES (@Reusable_String_2,@Reusable_String_1)
		   END
		ELSE
		   BEGIN
			-- RAISERROR AND EXIT --
			SELECT	@miscprint			= 'Error: Unable to Create '+@Reusable_String_1+' File: ' + @Reusable_String_2
					,@error_count		= @error_count + 1
					,@TerminatedEarly	= 1
			EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1	
			EXEC	[dbo].[dbasp_print] '-------------------------------------FORCED ERROR----------------------------------------',0,0,1
			RAISERROR(@miscprint,16,1) WITH LOG												-- RAISERROR
			EXEC	[dbo].[dbasp_print] '-----------------------------------------------------------------------------------------',0,0,1
			goto label99
		   END	

		IF @Reusable_String_1 = 'WRN' GOTO LogsDone
		IF @Reusable_String_1 = 'ERR' SET @Reusable_String_1 = 'WRN'
		IF @Reusable_String_1 = 'LOG' SET @Reusable_String_1 = 'ERR'
		GOTO CreateLog

	LogsDone:

	SELECT	@log_file_name_E	= @log_file_name + '.err'
			,@log_file_name_W	= @log_file_name + '.wrn'
			,@log_file_name		= @log_file_name + '.log'
END

IF								-- CHECK: BUILD CODE DIRECTORY										
   [dbo].[dbaudf_GetFileProperty] (@currpath,'Folder','Path') IS NULL
   BEGIN
	SELECT	@miscprint = 'Path to Build Folder [' + @CT_DB_Copy_BuildCode + '] is NOT Valid' + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1					-- APPEND ERROR
	
	-- RAISERROR AND EXIT --
	SELECT	@miscprint			= 'Error: Database Build Folder is Invalid' + @CRLF
			,@error_count		= @error_count + 1
			,@TerminatedEarly	= 1
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1					-- APPEND ERROR
	EXEC	[dbo].[dbasp_print] '-------------------------------------FORCED ERROR----------------------------------------',0,0,1
	RAISERROR(@miscprint,16,1) WITH LOG												-- RAISERROR
	EXEC	[dbo].[dbasp_print] '-----------------------------------------------------------------------------------------',0,0,1
	goto label99																					-- EXIT
   END
Else
   BEGIN
	SELECT	@miscprint = 'Build Folder [' + @currpath + '] WILL Be Used For This SQL Deployment.' + @CRLF + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG
   END
IF @ReplEnabled = 1				-- CHECK: REPLICATION												
   BEGIN
	-- RAISERROR AND EXIT --
	SELECT	@miscprint			= 'Error:  Replication (table) Detected in database ' + @DBname + '.' + @CRLF
			,@error_count		= @error_count + 1
			,@TerminatedEarly	= 1
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1													-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1								-- APPEND LOG
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1							-- APPEND ERR
	EXEC	[dbo].[dbasp_print] '-------------------------------------FORCED ERROR----------------------------------------',0,0,1
	RAISERROR(@miscprint,16,1) WITH LOG												-- RAISERROR
	EXEC	[dbo].[dbasp_print] '-----------------------------------------------------------------------------------------',0,0,1
	goto label99																							-- ERROR
   END
BEGIN							-- CHECK: ReleaseNotes.doc											
	SELECT	@NestLevel			= @NestLevel + 1
			,@Reusable_String_1	= @currpath + 'ReleaseNotes.doc'
			,@miscprint			= 'Checking for ReleaseNotes.doc' + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG

	IF [dbo].[dbaudf_GetFileProperty] (@Reusable_String_1,'File','Path') IS NULL	-- CHECK: RELEASENOTES.DOC
	   BEGIN
		SELECT	@miscprint = 'Note: ReleaseNotes.doc WAS NOT Found in ' + @currpath + @CRLF
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1										-- PRINT
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- APPEND LOG
	   END
	Else
	   BEGIN
		INSERT	DEPLinfo.dbo.build_files VALUES (@Reusable_String_1, 'RLN')							-- ADD: BUILD_FILES
		SELECT	@miscprint = 'Note: ReleaseNotes.doc Located.' + @CRLF
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1										-- PRINT
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- APPEND LOG
	   END

	SELECT	@NestLevel			= @NestLevel - 1
			,@Reusable_String_1	= NULL
END
BEGIN							-- CHECK: DBA_CHANGELIST.TXT										
	SELECT		@Reusable_String_1	= @currpath + '\DBA_ChangeList.txt'
	IF [dbo].[dbaudf_GetFileProperty] (@Reusable_String_1,'File','Path') IS NULL
	   begin
	   
		-- RAISERROR AND EXIT --
		SELECT	@miscprint			= 'Error: DBA_ChangeList.txt WAS NOT Found in ' + @currpath + @CRLF
				,@NestLevel			= @NestLevel + 1
				,@TerminatedEarly	= 1
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1										-- PRINT
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- APPEND LOG
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1				-- APPEND ERR
		EXEC	[dbo].[dbasp_print] '-------------------------------------FORCED ERROR----------------------------------------',0,0,1
		RAISERROR(@miscprint,16,1) WITH LOG												-- RAISERROR
		EXEC	[dbo].[dbasp_print] '-----------------------------------------------------------------------------------------',0,0,1
		GOTO label99																				-- EXIT
	END
END
BEGIN							-- START: WRITING LOG HEADER										
	SELECT	@miscprint = '--------------------------------------------------------------------------' + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG

	SELECT	@miscprint = 'START OF SQLDEPLOYMENT PROCESS'
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG

	SELECT	@miscprint = 'w/ Logging to ' + @log_file_name + '.log'
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG

	SELECT	@miscprint = 'Process type is ' + @CL_ProcessType
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG

	SELECT	@miscprint = '--------------------------------------------------------------------------' + @CRLF + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG

	SELECT	@miscprint = '--------------------------------------------------------------------------' + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG

	SELECT	@miscprint = 'PRIOR BUILD HISTORY FOR DATABASE ' + @dbname + ' ON ' + upper(@@servername) 
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG

	SELECT	@miscprint = '--------------------------------------------------------------------------' + @CRLF + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG

	SELECT		@Reusable_String_2	= 'set nocount on; select top 5 convert(char(20), vchName) as vchName, convert(char(35), vchLabel) as vchLabel, convert(char(25), dtBuildDate, 121) as dtBuildDate, convert(char(80), vchNotes) as vchNotes from dbo.build order by ibuildID desc'
				,@NestLevel			= @NestLevel + 1
			
	EXEC	[dbo].[dbasp_RunTSQL]
			@Name				= 'Last 5 Builds'
			,@TSQL				= @Reusable_String_2	
			,@DBName			= @DBname
			,@Server			= @@Servername
			,@OutputPath		= @log_file_name
			,@StartNestLevel	= @NestLevel

	SELECT	@Reusable_String_1	= NULL
			,@Reusable_String_2	= NULL
			,@NestLevel			= @NestLevel - 1
									
	SELECT	@miscprint = @CRLF + '--------------------------------------------------------------------------' + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1												-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1							-- APPEND LOG

	SELECT	@miscprint = '--------------------------------------------------------------------------' + @CRLF + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1												-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1							-- APPEND LOG
END
BEGIN							-- LOAD:  UPDATEBUILD.TXT											
	SELECT @miscprint = 'Reading UpdateBuild.txt to Retreive Values.';EXEC [dbo].[dbasp_print] @miscprint,@NestLevel
	DECLARE UpdateBuild CURSOR
	KEYSET FOR SELECT * 
	FROM [dbo].[dbaudf_FileAccess_Read] (@currpath,'UpdateBuild.txt')
	OPEN UpdateBuild
	FETCH NEXT FROM UpdateBuild INTO @Reusable_Int_1,@Reusable_String_1
	WHILE (@@fetch_status <> -1)
	BEGIN
		IF (@@fetch_status <> -2)
		BEGIN
			IF dbo.dbaudf_ReturnPart (REPLACE(@Reusable_String_1,':','|'),1) = 'Label'
				SELECT	@label = dbo.dbaudf_ReturnPart (REPLACE(@Reusable_String_1,':','|'),2)

			IF dbo.dbaudf_ReturnPart (REPLACE(@Reusable_String_1,':','|'),1) = 'Version'
				SELECT	@version = dbo.dbaudf_ReturnPart (REPLACE(@Reusable_String_1,':','|'),2)
				--if contains "\" keep only to the right of the slash

			IF dbo.dbaudf_ReturnPart (REPLACE(@Reusable_String_1,':','|'),1) = 'rev'
				SELECT	@rev = dbo.dbaudf_ReturnPart (REPLACE(@Reusable_String_1,':','|'),2)
		END
		FETCH NEXT FROM UpdateBuild INTO @Reusable_Int_1,@Reusable_String_1
	END
	CLOSE UpdateBuild
	DEALLOCATE UpdateBuild

	SELECT	@BuildLabel			= COALESCE(COALESCE(@version + '_','') 
								+ CASE COALESCE(@rev,'') WHEN '' THEN rtrim(@label) ELSE rtrim(@label) 
								+ '_' + rtrim(@rev) END,'unknown')
			,@start_datetime	= getdate()
			,@miscprint			= 'Building Build Label. ('+ @BuildLabel +')'
			
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel													-- PRINT

	SELECT	@miscprint = 'Updating BuildDetail:'+@BuildLabel+':00 start deployment';
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel													-- PRINT
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1							-- APPEND LOG

	EXEC	dbo.dpsp_update_BuildDetail 
				@dbname					= @dbname
				, @vchLabel				= @BuildLabel
				, @scriptName			= '00 start deployment'
				, @scriptPath			= @currpath
				, @scriptResult			= ''
				, @scriptRundate		= @start_datetime
				, @scriptRunduration	= 0
END
--========= MAINLINE ==============================================================================
BEGIN							-- Headers for Start of the Build Database Section					
	SELECT	@miscprint = '--------------------------------------------------------------------------' + @CRLF 
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1 -- APPEND

	SELECT	@miscprint = '--------------------------------------------------------------------------' + @CRLF 
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1 -- APPEND

	SELECT	@miscprint = 'START BUILDING DATABASE OBJECTS ON ' + upper(@@servername) + ' DB=' + @dbname + @CRLF 
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1 -- APPEND

	SELECT	@miscprint = 'IN THE ' + upper(@EI_ENVName) + ' ENVIRONMENT' + @CRLF 
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1 -- APPEND

	SELECT	@miscprint = '--------------------------------------------------------------------------' + @CRLF 
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1 -- APPEND
END
If @CL_BuildType = 1			-- Insert sprocs-only record into build_files						
   begin
	insert	DEPLinfo.dbo.build_files values ('[sprocs only]', 'JOB')
	SELECT	@miscprint = 'A sprocs-only build will be done.' + @CRLF 
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1 -- APPEND
   end
Else
   begin
	SELECT	@miscprint = 'A full build will be done.'
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1
	EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1 -- APPEND
   end
--========= DEPLOYMENT ============================================================================
DECLARE DeplStage_Cursor CURSOR	-- DEFINE CURSOR FOR DEPLOYMENT STAGES								
KEYSET
FOR
SELECT		COALESCE(T1.[Name],T2.[DeplStage])						[DeplStage]
			,COALESCE(T2.[DeplType],'SQL')							[DeplType]
			,CASE WHEN T2.[DeplStage] IS NOT NULL THEN 1 ELSE 0 END	[Expected]
			,COALESCE(IsFolder,0)									[Found]
			,COALESCE(T2.[InSprocOnly],0)							[InSprocOnly]
			,COALESCE(T2.[NotInProd],0)								[DeplStageNotInProd]
			,COALESCE(T2.[NotInStage],0)							[DeplStageNotInStage]
			,COALESCE(T2.[NotInTest],0)								[DeplStageNotInTest]
			,COALESCE(T2.[NotInDev],0)								[DeplStageNotInDev]
FROM		[dbo].[dbaudf_Dir](@currpath) t1
FULL JOIN	@DeploymentStages T2
	ON		T1.[Name] = T2.[DeplStage]
Where		COALESCE(IsFolder,1) = 1
ORDER BY	COALESCE(T1.[Name],T2.[DeplStage])
OPEN DeplStage_Cursor			-- OPEN CURSOR FOR DEPLOYMENT STAGES				
FETCH							-- GET NEXT STAGE													
	NEXT FROM DeplStage_Cursor INTO @DeplStage,@DeplStageType,@DeplStageExpected,@DeplStageFound,@DeplStageInSprocOnly,@DeplStageNotInProd,@DeplStageNotInStage,@DeplStageNotInTest,@DeplStageNotInDev	
WHILE (@@fetch_status <> -1)	-- START DEPLOYMENT STAGE LOOP										
BEGIN							--													
	IF (@@fetch_status <> -2)	--
	BEGIN						--
		BEGIN						-- PRINT AND LOG									
			SELECT	@miscprint = CONVERT(VarChar(20),GetDate(),114)+ ': Starting ' + @DeplStage + ' Stage...' + @CRLF
			EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1										-- PRINT
			EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- APPEND LOG
			SELECT	@NestLevel = @NestLevel + 1
		END
		BEGIN					-- DEPL Stage SKIPS
		
			IF						-- CHECK: Extra Folder Found						
				@DeplStageExpected = 0 AND @DeplStageFound = 1
			BEGIN							-- PRINT/LOG/SKIP							
				SELECT	@miscprint	= CONVERT(VarChar(20),GetDate(),114) + ': ' + @DeplStage + ' Folder was not Expected, Stage Was Skiped...' + @CRLF
				EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1								-- PRINT
				EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1			-- APPEND LOG	
				EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_W, NULL, 1		-- APPEND WARNING	
				GOTO DeplStageComplete
			END		

			IF						-- CHECK: Expected Folder Missing						
				@DeplStageExpected = 1 AND @DeplStageFound = 0
			BEGIN							-- PRINT/LOG/SKIP							
				SELECT	@miscprint	= CONVERT(VarChar(20),GetDate(),114) + ': ' + @DeplStage + ' Folder was Expected, But NOT Found...' + @CRLF
				EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1								-- PRINT
				EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1			-- APPEND LOG	
				EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1		-- APPEND WARNING	
				GOTO DeplStageComplete
			END		
				
											
			IF						-- CHECK: SPROC ONLY BUILD						
				@CL_BuildType <> 0 AND @DeplStageInSprocOnly = 0
			BEGIN							-- PRINT/LOG/SKIP							
				SELECT	@miscprint	= CONVERT(VarChar(20),GetDate(),114)
									+ ': Sproc''s Only Build, ' 
									+ @DeplStage + ' Stage Was Skiped...' + @CRLF
				EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1								-- PRINT
				EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1			-- APPEND LOG	
				GOTO DeplStageComplete
			END
			IF						-- SKIPS STAGES IF ENVIRONMENT EXCLUDED			
				(@EI_ENVName in ('production') AND @DeplStageNotInProd = 1)
					OR
				(@EI_ENVName in ('Stage,Staging') AND @DeplStageNotInStage = 1)
					OR
				(@EI_ENVName in ('Test') AND @DeplStageNotInTest = 1)
					OR
				(@EI_ENVName in ('Dev') AND @DeplStageNotInDev = 1)	
			BEGIN
				SELECT	@miscprint = CONVERT(VarChar(20),GetDate(),114)+ ': ' + @EI_ENVName + ' Environment, ' + @DeplStage + ' Stage Was Skiped...' + @CRLF
				EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1								-- PRINT
				EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1			-- APPEND LOG
				GOTO DeplStageComplete
			END
		END
		BEGIN					-- STAGE HEADER										
			SELECT	@miscprint = @CRLF + @CRLF
			EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1										-- PRINT
			EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- APPEND LOG

			SELECT	@miscprint = '--------------------------------------------------------------------------' + @CRLF 
			EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1										-- PRINT
			EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- APPEND LOG


			SELECT	@miscprint = CONVERT(VarChar(20),GetDate(),114)+ ': RUNNING ' + @DeplStage + @CRLF
			EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1										-- PRINT
			EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- APPEND LOG

			SELECT	@miscprint = '--------------------------------------------------------------------------' + @CRLF + @CRLF
			EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1										-- PRINT
			EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- APPEND LOG
		END
		BEGIN					-- PROCESS FILES									
			SELECT							-- SET @CURRFOLDER						
				@currfolder = @currpath + @DeplStage + '\'
			DECLARE							-- DEFINE CURSOR FOR FILES				
				DeplFile_Cursor CURSOR KEYSET FOR
				SELECT		COALESCE(T1.Name,REPLACE(T2.[Line],@DeplStage+'\',''))	[name]
							,COALESCE([Path],@currpath+T2.[Line])					[LongPath]
							,REPLACE([Path],@currpath,'')							[ShortPath]
							,COALESCE([IsFolder],0)									[IsFolder]
							,CASE WHEN T2.[Line] IS NOT NULL THEN 1 ELSE 0 END		[Expected]
							,COALESCE(IsFileSystem,0)								[Found]				
				FROM		[dbo].[dbaudf_Dir](@currfolder)T1 
				FULL JOIN	(
							SELECT		[Line]
							FROM		[dbo].[dbaudf_FileAccess_Read](@currpath,'DBA_ChangeList.txt')
							WHERE		Line Like @DeplStage +'%'
							) T2
					ON		REPLACE(T1.[Path],@currpath,'') = T2.[Line]
				WHERE		COALESCE(T2.[Line],'') != '' OR COALESCE(@CL_ProcessType,'') NOT IN ('normal', 'allsprocs') -- REMOVE THIS LINE TO REMOVE RESTRICTION ON CHANGELIST
				ORDER BY	COALESCE(REPLACE(T1.[Path],@currpath,''),T2.[Line])
			OPEN							-- OPEN CURSOR							
				DeplFile_Cursor
			FETCH							-- GET FILE								
				NEXT FROM DeplFile_Cursor INTO @File_Name,@File_Path,@File_RelativePath,@IsFolder,@DeplFileExpected,@DeplFileFound
			WHILE (@@fetch_status <> -1)	-- START FILE CURSOR					
			BEGIN							--
				IF (@@fetch_status <> -2)	--
				BEGIN						--
					BEGIN					-- START:		FILE HEADER				
						SELECT	-- FILE NAME/PATH/COUNT								
								@filecount			= @@CURSOR_ROWS
								,@Reusable_String_1	= '\' + @DeplStage
								,@Reusable_String_2	= REPLACE(@File_Path,@currfolder,'')
						BEGIN		-- PRINT AND LOG									
							SELECT	@miscprint = @CRLF + '==========================================================================' + @CRLF 
							EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
							EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG
						END
						BEGIN		-- PRINT AND LOG									
							SELECT	@miscprint = 'SQL FILE: ' + REPLACE(@File_Path,@currfolder,'') + @CRLF 
							EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
							EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG
						END
						BEGIN		-- PRINT AND LOG									
							SELECT	@miscprint = '==========================================================================' + @CRLF 
							EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
							EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG
						END
						BEGIN		-- PRINT AND LOG									
							SELECT	@miscprint = convert(varchar(50), getdate(), 120)+ @CRLF + @CRLF 
							EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
							EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG
						END
					END
					SELECT					-- SET:			FILE START TIME			
						@start_datetime		= getdate()
					INSERT					-- DEPL_LOG:	LOG STARTED				
						into	DEPLinfo.dbo.DEPL_log				
								(dbname, foldername, scriptname, startdate, status, completed) 
						values	(@dbname, @Reusable_String_1, @Reusable_String_2, @start_datetime, 'Started', 'n')
					BEGIN					-- START:		PROCESS FILE			
						IF		-- CHECK:	StageType								
							@DeplStageType = 'BCP'		
							BEGIN	-- BCP IN DATA								
								SELECT	-- GET:		BCP TABLE AND SCHEMA NAME						
										@tablename		= PARSENAME(@File_Name,1)
										,@schemaname	= PARSENAME(@File_Name,2)
								IF		-- CHECK:	UNICODE/ASCII									
								   dbo.dpudf_CheckFileType(@File_Path) = 1
								   begin										-- UNICODE FILE FOUND	
									SELECT	@miscprint	= 'Processing UNICODE File'
											,@BCPparms	= ' -m 0 -w -b 1000 -E'
									EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1						-- PRINT
									EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1	-- APPEND LOG
								   end
								Else
								   begin										-- ASCII FILE FOUND		
									SELECT	@miscprint	= 'Processing ASCII File'
											,@BCPparms	= ' -m 0 -c -b 1000 -E'
									EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1						-- PRINT
									EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1	-- APPEND LOG
								   end
								BEGIN	-- CHECK:	Indexed Views or Indexes on Computed Columns	
									SELECT		-- SETUP FOR @indxviewcount 
												@dynamicVAR				= '@indxviewcount INT OUTPUT'
												,@indxviewcount			= 0
												,@dynamicSQL			= 'SELECT @indxviewcount = COUNT(v.name) from ' 
																		+ @dbname + '.INFORMATION_SCHEMA.VIEW_TABLE_USAGE u, ' 
																		+ @dbname + '.sys.all_views v, ' + @dbname + '.sys.indexes i '
																		+ 'where u.table_name = ''' + @tablename + ''''
																		+ 'and u.table_schema = ''' + @schemaname + ''''
																		+ 'and u.view_name = v.name'
																		+ 'and v.object_id = i.object_id'
									EXEC		-- CHECK FOR @indxviewcount	
										sp_executesql @dynamicSQL, @dynamicVAR, @indxviewcount OUTPUT
									SELECT		-- SETUP FOR @cmptcolcount	
												@dynamicVAR				= '@cmptcolcount INT OUTPUT'
												,@cmptcolcount			= 0
												,@dynamicSQL			= 'SELECT @cmptcolcount = count(*) from ' 
																		+ @dbname + '.sys.columns C join ' 
																		+ @dbname + '.sys.index_columns i '
																		+ 'on c.object_id = i.object_id '
																		+ 'and c.column_id = i.column_id '
																		+ 'where c.object_id = object_id(''' 
																		+ @schemaname + '.' + @tablename + ''') '
																		+ 'and c.is_computed = 1'
									EXEC		-- CHECK FOR @cmptcolcount	
										sp_executesql @dynamicSQL, @dynamicVAR, @cmptcolcount OUTPUT
									IF			-- SET BCP PARAM IF NEEDED	
										@indxviewcount > 0 or @cmptcolcount > 0
										Select @BCPparms = @BCPparms + ' -q'
								END
								SELECT	-- BUILD:	BCP COMMAND										
									@bcpcmd = 'BCP ' + @dbname + '.' + @schemaname 
											+ '.' + @tablename + ' in ' 
											+ @File_Path + @BCPparms + ' -S' 
											+ @@servername + ' -T  >>' + @log_file_name
								BEGIN		-- PRINT:	AND LOG IT										
									EXEC	[dbo].[dbasp_print] @bcpcmd,@NestLevel,1,1								-- PRINT
									EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG
								END
								EXEC	-- BCP:		DO IT											
									@Result = master.sys.xp_cmdshell @bcpcmd, no_output
							END
						ELSE IF
							@DeplStageType = 'COPY'
							BEGIN	-- COPY FILES								
								SELECT	-- SET:		DESTINATION TO SUBDIR IF ITS A FOLDER	
									@Reusable_String_1		= '\\' + @servername + '\' + @servername2 + '_dbasql\'
															+ CASE @IsFolder WHEN 1 THEN @File_Name + '\' ELSE '' END
								IF		-- CHECK:	CREATE SUBFOLDER						
									@IsFolder = 1 AND [dbo].[dbaudf_GetFileProperty] (@Reusable_String_1,'File','Path') IS NULL
									BEGIN
										Select @cmd = 'mkdir "' + @Reusable_String_1 + '"'
										EXEC	[dbo].[dbasp_print] @cmd,@NestLevel,1,1										-- PRINT
										EXEC @Result = master.sys.xp_cmdshell @cmd, no_output										
										IF	-- FAIL:	FOLDER DOES NOT EXIST AND CANT BE CREATED	
											@Result != 0	
											BEGIN	
												SELECT	@miscprint = 'ERROR: FOLDER ['+@Reusable_String_1+'], DOES NOT EXIST BUT COULD NOT BE CREATED.' + @CRLF 
														,@error_count = @error_count + 1
												EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
												EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG												
												EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1	-- APPEND ERROR												
											END
										ELSE
											BEGIN	
												SELECT	@miscprint = 'Created Folder ['+@Reusable_String_1+'], WAS CREATED.' + @CRLF 
												EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1									-- PRINT
												EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1				-- APPEND LOG																		
											END
									END
								SELECT	-- BUILD:	XCOPY COMMAND							
									@cmd	= 'xcopy /Y /K /R ' 
											+ CASE @IsFolder WHEN 0 THEN '' ELSE '/E ' END
											+ @File_Path 
											+ CASE @IsFolder WHEN 0 THEN ' ' ELSE '\*.* ' END 
											+ @Reusable_String_1 + ' >>' + @log_file_name
								BEGIN		-- PRINT:	AND LOG	IT								
									EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
									EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG
								END
								EXEC	-- XCOPY:	DO IT									
									@Result = master.sys.xp_cmdshell @cmd, no_output						
								IF		-- FAIL:	XCOPY RETURNED AN ERROR					
									@Result != 0	
									BEGIN	
										SELECT	@miscprint = 'ERROR: XCOPY Failed to copy ['+@File_Path+'] to ['+@Reusable_String_1+']' + @CRLF 
												,@error_count = @error_count + 1
										EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
										EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG												
										EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1	-- APPEND ERROR												
									END
								ELSE
									BEGIN	-- SUCCESS:	PRINT AND LOG IT						
										SELECT	@miscprint	= 'XCOPY Successfully Copied ['
															+ @File_Path + '] to ['
															+ @Reusable_String_1 + ']' + @CRLF 
										EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
										EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG
									END
							END
						ELSE
							BEGIN	-- EXECUTE SQL									
								EXEC	-- RUN: SCRIPT FILE									
									@Result =	[dbo].[dbasp_RunTSQL]	-- RUN SQL FILE
													@Name				= @File_Path
													,@TSQL				= NULL	
													,@DBName			= @dbname
													,@Server			= @@Servername
													,@OutputPath		= @log_file_name
													,@StartNestLevel	= @NestLevel
													,@OutputText		= @OutputText OUT
													,@OutputMatrix		= 4
								BEGIN	-- LOG: TO OUTPUT FILES								
									EXEC	[dbo].[dbasp_FileAccess_Write] @OutputText, @log_file_name, NULL, 1			-- APPEND LOG
									IF @Result != 0
									BEGIN
										SELECT	@error_count = @error_count + 1
										EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1	-- APPEND ERROR
									END
								END
							END   						
					SELECT					-- SET:			FILE STOP TIME			
							@end_datetime		= getdate()
							,@run_duration_ss	= datediff(ss, @start_datetime, @end_datetime)
					END
					IF						-- CHECK:		RESULT STATUS			
						@Result != 0									
					   BEGIN		-- FAILURE										
						UPDATE		-- DEPL_LOG:	LOG FAILED						
							DEPLinfo.dbo.DEPL_log			
							SET	status = 'Failed', enddate = @end_datetime 
						WHERE		dbname = @dbname and foldername = @Reusable_String_1 
							AND		scriptname = @Reusable_String_2 and status = 'Started'
						EXEC		-- BUILDDETAIL: SET SQLCMD ERROR				
							dbo.dpsp_update_BuildDetail			
							@dbname = @dbname, @vchLabel = @BuildLabel, @scriptName = @Reusable_String_2
							,@scriptPath = @Reusable_String_1, @scriptResult = 'sqlcmd ERROR'
							,@scriptRundate = @start_datetime, @scriptRunduration = @run_duration_ss
						BEGIN		-- START:		FAILURE HEADER					
							SELECT	@miscprint	= @CRLF + @CRLF 
												+ '***' + @CRLF
												+ '*** SQLCMD ERROR: Script ' + @File_Path + ' returned an error.'
												+ '***' + @CRLF
									,@NestLevel = @NestLevel + 1
							EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
							EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG
							EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1	-- APPEND ERROR
						END
					   END
					ELSE BEGIN		-- SUCCESS										
						UPDATE		DEPLinfo.dbo.DEPL_log			-- DEPL_LOG: LOG SUCCEEDED
							SET		status = 'Succeeded', enddate = @end_datetime 
						WHERE		dbname = @dbname and foldername = @Reusable_String_1 
							AND		scriptname = @Reusable_String_2 and status = 'Started'

						EXEC dbo.dpsp_update_BuildDetail			-- BUILDDETAIL: SET EXECUTED OK
							@dbname = @dbname, @vchLabel = @BuildLabel, @scriptName = @Reusable_String_2
							,@scriptPath = @Reusable_String_1, @scriptResult = 'Executed OK'
							,@scriptRundate = @start_datetime, @scriptRunduration = @run_duration_ss

						SELECT	@miscprint = '+++ Executed OK.'	
						EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
						EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG
					   end
					IF						-- CHECK:		LONG RUNNING SCRIPT		
						(@run_duration_ss / 60.0) > @longrun_limit	
					   BEGIN		-- WARNING										
						SELECT	@miscprint = '*** Long Running SQL script: ' + @File_Path + ' ran for ' + CAST((@run_duration_ss / 60.0) AS VarChar(10)) + ' minutes.' + @CRLF
								,@NestLevel = @NestLevel + 1
								,@warn_count = @warn_count + 1
						EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1							-- PRINT
						EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1		-- APPEND LOG
						EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_W, NULL, 1	-- APPEND WARN
						SELECT	@NestLevel = @NestLevel - 1
					   END
				END
				FETCH						-- GET NEXT FILE						
					NEXT FROM DeplFile_Cursor INTO @File_Name,@File_Path,@File_RelativePath,@IsFolder,@DeplFileExpected,@DeplFileFound
			END
			CLOSE DeplFile_Cursor 			-- CLOSE FILE CURSOR					
			DEALLOCATE DeplFile_Cursor		-- DEALLOCATE FILE CURSOR				
		END
		BEGIN						-- PRINT AND LOG									
			SELECT	@NestLevel = @NestLevel - 1
					,@miscprint = CONVERT(VarChar(20),GetDate(),114)+ ': Completed ' + @DeplStage + ' Stage...'  + @CRLF
			EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
			EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG
		END
		DeplStageComplete:
	END
	FETCH					-- GET NEXT STAGE										
		NEXT FROM DeplStage_Cursor INTO @DeplStage,@DeplStageType,@DeplStageExpected,@DeplStageFound,@DeplStageInSprocOnly,@DeplStageNotInProd,@DeplStageNotInStage,@DeplStageNotInTest,@DeplStageNotInDev
END
CLOSE DeplStage_Cursor			-- CLOSE CURSOR											
DEALLOCATE DeplStage_Cursor		-- DEALLOCATE CURSOR									
--========= FINALIZATION ==========================================================================
SELECT							-- RESET FOR NEXT FINALIZATION PROCESS	(dpsp_UpdateDEPLinfoBuild)	
		@Reusable_BIT_1			= 1
		,@Reusable_String_1		= 'dpsp_UpdateDEPLinfoBuild'
		,@Reusable_String_2		= 'SPROC ONLY UPDATE DEPLINFO'
		,@Reusable_String_3		= 'exec dbo.'+ @Reusable_String_1 +'	''' + rtrim(@dbname)	+ ''', ''' 
																			+ @CL_ProjectName	+ ''', ''' 
																			+ @currpath			+ ''''
Start_Finalization_Process:
IF @Reusable_BIT_1 = 1			-- RUN FINALIZATION PROCESS											
	BEGIN		
	  BEGIN						-- PRINT & LOG FINALIZATION PROCESS HEADER				
		SELECT	@NestLevel	= @NestLevel + 1
				,@miscprint = @CRLF + @CRLF + '--------------------------------------------------------------------------'	+ @CRLF
											+ 'RUNNING:		' + @Reusable_String_1 + '....'									+ @CRLF
											+ '--------------------------------------------------------------------------'	+ @CRLF 
											+ convert(varchar(50), getdate(), 120) + @CRLF + @CRLF
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG

		SELECT	@miscprint = @CRLF + @CRLF + '=========================================================================='	+ @CRLF
											+ 'SQL SPROC:	DEPLinfo.dbo.' + @Reusable_String_1								+ @CRLF
											+ '=========================================================================='	+ @CRLF 
											+ convert(varchar(50), getdate(), 120) + @CRLF + @CRLF
		EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG
	  END
		BEGIN				-- EXECUTE SCRIPT										
			EXEC			-- RUN: SCRIPT 							
				@Result =	[dbo].[dbasp_RunTSQL]
								@Name				= @Reusable_String_1
								,@TSQL				= @Reusable_String_3	
								,@DBName			= @dbname
								,@Server			= @@Servername
								,@OutputPath		= @log_file_name
								,@StartNestLevel	= @NestLevel
								,@OutputText		= @OutputText OUT
								,@OutputMatrix		= 4
			BEGIN			-- LOG: TO OUTPUT FILES					
				EXEC	[dbo].[dbasp_FileAccess_Write] @OutputText, @log_file_name, NULL, 1
				IF @Result != 0
				BEGIN			-- PRINT AND LOG ERROR
					SET		@error_count = @error_count + 1										
					EXEC	[dbo].[dbasp_FileAccess_Write] @OutputText, @log_file_name_E, NULL, 1		-- APPEND RESULTS TO ERROR
					SELECT	@miscprint = @CRLF + @CRLF	+ '=========================================================================='	+ @CRLF
														+ 'ERROR:	DEPLinfo.dbo.'+ @Reusable_String_1 +' returned an error.'			+ @CRLF
														+ '=========================================================================='	+ @CRLF
														+ convert(varchar(50), getdate(), 120) + @CRLF + @CRLF
					EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
					EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG
					EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1					-- APPEND ERROR									
				END
				ELSE
				BEGIN			-- PRINT AND LOG SUCCESS									
					SELECT	@miscprint = @CRLF + @CRLF	+ '=========================================================================='	+ @CRLF
														+ 'SUCCESS:	DEPLinfo.dbo.'+ @Reusable_String_1 +' Completed.'					+ @CRLF
														+ '=========================================================================='	+ @CRLF
														+ convert(varchar(50), getdate(), 120) + @CRLF + @CRLF
					EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
					EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1						-- APPEND LOG
				END
			END
		END
		SET		@Reusable_BIT_1	= 0
	END
IF								-- RESET FOR NEXT FINALIZATION PROCESS	(dpsp_DBOwnerCheck)			
	@Reusable_String_1 = 'dpsp_UpdateDEPLinfoBuild'
	SELECT	@Reusable_BIT_1		= 1
			,@Reusable_String_1		= 'dpsp_DBOwnerCheck'
			,@Reusable_String_2		= 'CHECK DATABASE OWNERSHIP'
			,@Reusable_String_3		= 'exec dbo.'+@Reusable_String_1+'	''' + rtrim(@dbname) + ''''
IF								-- RESET FOR NEXT FINALIZATION PROCESS	(dpsp_DBObjectOwnerCheck)	
	@Reusable_String_1 = 'dpsp_DBOwnerCheck'
	SELECT	@Reusable_BIT_1		= 1
			,@Reusable_String_1		= 'dpsp_DBObjectOwnerCheck'
			,@Reusable_String_2		= 'CHECK OBJECT OWNERSHIP'
			,@Reusable_String_3		= 'exec dbo.'+@Reusable_String_1+'	''' + rtrim(@dbname) + ''''
IF								-- RESET FOR NEXT FINALIZATION PROCESS	(dpsp_DBObjectOwnerCheck)	
	@Reusable_String_1 = 'dpsp_DBObjectOwnerCheck'
	SELECT	@Reusable_BIT_1		= 1
			,@Reusable_String_1		= 'ControlTable'
			,@Reusable_String_2		= 'UPDATE DEPLOYMENT SCRIPT COMPLETED'
			,@Reusable_String_3		= 'Update dbo.controltable set control03 = ''completed'' where subject = ''DB_copy_buildcode'' and control01 = '''+@DBname+''' and control02 = '''+@CT_DB_Copy_BuildCode+''' and control03 = ''in-work'''
IF								-- LOOP IF NEEDED													
	@Reusable_BIT_1 = 1
	GOTO Start_Finalization_Process
--========= DONE ==================================================================================
label99:
SET @Reusable_INT_1 = 0
IF @TerminatedEarly = 1
BEGIN
	SET @Reusable_INT_1 = 1000000
	SELECT	@miscprint	= @CRLF	+ '=========================================================================='	+ @CRLF
								+ 'FAILURE:		Deployment Terminated Early and Not All Code Was Deployed.'			+ @CRLF
								+ '=========================================================================='	+ @CRLF
								+ convert(varchar(50), getdate(), 120) + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	IF @log_file_name_E IS NOT NULL
	BEGIN
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- LOG
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1				-- ERROR
	END
END

IF @error_count > 0
BEGIN
	SET @Reusable_INT_1 = @Reusable_INT_1 + (@error_count * 1000)
	SELECT	@miscprint = @CRLF	+ '=========================================================================='	+ @CRLF
								+ 'ERRORS:		'+CAST(@error_count as varchar)+' Errors were identified durring this deployment.'			+ @CRLF
								+ '=========================================================================='	+ @CRLF
								+ convert(varchar(50), getdate(), 120) + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	IF @log_file_name_E IS NOT NULL
	BEGIN
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- LOG
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_E, NULL, 1				-- ERROR
	END
END

IF @warn_count > 0
BEGIN
	SET @Reusable_INT_1 = @Reusable_INT_1 + @warn_count
	SELECT	@miscprint = @CRLF	+ '=========================================================================='	+ @CRLF
								+ 'WARNINGS:	'+CAST(@warn_count as varchar)+' Warnings were identified durring this deployment'			+ @CRLF
								+ '=========================================================================='	+ @CRLF
								+ convert(varchar(50), getdate(), 120) + @CRLF
	EXEC	[dbo].[dbasp_print] @miscprint,@NestLevel,1,1											-- PRINT
	IF @log_file_name_W IS NOT NULL
	BEGIN
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name, NULL, 1					-- LOG
		EXEC	[dbo].[dbasp_FileAccess_Write] @miscprint, @log_file_name_W, NULL, 1				-- WARN
	END
END

RETURN @Reusable_INT_1

GO

EXEC sys.sp_addextendedproperty @name=N'BuildApplication', @value=N'' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'PROCEDURE',@level1name=N'dpsp_auto_RunSQLdeployment_ordered_xxx'
GO

EXEC sys.sp_addextendedproperty @name=N'BuildBranch', @value=N'' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'PROCEDURE',@level1name=N'dpsp_auto_RunSQLdeployment_ordered_xxx'
GO

EXEC sys.sp_addextendedproperty @name=N'BuildNumber', @value=N'' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'PROCEDURE',@level1name=N'dpsp_auto_RunSQLdeployment_ordered_xxx'
GO

EXEC sys.sp_addextendedproperty @name=N'DeplFileName', @value=N'' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'PROCEDURE',@level1name=N'dpsp_auto_RunSQLdeployment_ordered_xxx'
GO

EXEC sys.sp_addextendedproperty @name=N'Version', @value=N'1.0.0' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'PROCEDURE',@level1name=N'dpsp_auto_RunSQLdeployment_ordered_xxx'
GO


