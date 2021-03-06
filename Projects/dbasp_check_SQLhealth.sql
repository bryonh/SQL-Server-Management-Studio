USE [dbaadmin]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[dbasp_check_SQLhealth] (@rpt_recipient sysname = ''--'jim.wilson@gettyimages.com'
						,@checkin_grace_hours smallint = 32
						,@recycle_grace_days smallint = 120
						,@reboot_grace_days smallint = 120
						,@save_SQLEnv sysname = ''
						,@Verbose int = 1	-- -1=SILENT,0=ONLY FAILURE SUMMARY,1=STEP DETAILS,2=DEBUG INFO
						,@NestLevel	INT = 0
						,@PrintOnly INT = 0) 

/*********************************************************
 **  Stored Procedure dbasp_check_SQLhealth                  
 **  Written by Jim Wilson, Getty Images                
 **  August 31, 2010                                      
 **  
 **  This dbasp is set up to do a complete health check for
 **  the local SQL instance. 
 ***************************************************************/
  as
	-- Do not lock anything, and do not get held up by any locks. 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	SET	NOCOUNT ON
	SET ANSI_WARNINGS OFF
--	======================================================================================
--	Revision History
--	Date		Author     		Desc
--	==========	====================	=============================================
--	08/31/2010	Jim Wilson		New process.
--	01/07/2011	Jim Wilson		Added output files
--	01/12/2011	Jim Wilson		Fixed inserts into temp tables (no output)
--	01/13/2011	Jim Wilson		Converted @cmd = 'type c:\...) to use dbaudf_FileAccess_Read
--	01/19/2011	Jim Wilson		Fixed problem with cores vs core(s)
--	02/10/2011	Jim Wilson		Fixed output line for auditlevel and backup check to include type = 'F'
--	02/17/2011	Jim Wilson		Added check for 3gb='-' (for OSver 2008).
--	02/25/2011	Jim Wilson		Added top 1 for secedit_id queries.
--	03/04/2011	Jim Wilson		Added code for AHP procesing.
--	03/18/2011	Jim Wilson		Added ' 2048' for sc qc command (set buffer size)
--	04/22/2011	Jim Wilson		Modified backup_type check for 2008
--	06/02/2011	Jim Wilson		Added skip for *_new databases (reporting in restoring mode)
--	06/06/2011	Jim Wilson		Added check for DBowner override (nocheck)
--								New code for memory check (convert GB and KB to MB)
--	06/14/2011	Jim Wilson		New check for share security by creating and deleting a new folder.
--								Reversed convert of @cmd = 'type c:\...) to use dbaudf_FileAccess_Read
--	06/22/2011	Jim Wilson		Added instance name to folder security check.
--	06/30/2011	Jim Wilson		Fixed an issue with memory listed with a decimal.
--	07/05/2011	Jim Wilson		Fix DB owner if it's the sql srvc acct.
--	07/22/2011	Jim Wilson		Added time stamp the the report header.
--	07/25/2011	Jim Wilson		Added no_check lookup for SQLjobs.
--	08/10/2011	Jim Wilson		Updated DEPL related job check and added check for Failed jobs.
--	08/19/2011	Jim Wilson		Added orphan login and user check and cleanup.
--	09/13/2011	Jim Wilson		Updated central servername and central share name.
--	11/09/2011	Jim Wilson		Fixed code for orphaned user per DB alert.
--	11/15/2011	Jim Wilson		Commented out tempdb file size check.
--	01/03/2012	Steve Ledridge	Modified code for droping orphaned users schema to check if it exists and
--								has no objects using the schema before trying to drop it.
--	01/12/2012	Jim Wilson		Chg file_size variable to bigint and added check for DB autogrowth.
--	02/22/2012	Jim Wilson		New code to bypass mirroring DB's.
--	02/29/2012	Jim Wilson		Added localservice for SQLBrowser svcacct check.
--	04/02/2012	Jim Wilson		new check for Redgate entries to local_serverenviro when RG is not installed.
--	04/27/2012	Jim Wilson		Added SQL mail check.
--	05/01/2012	Jim Wilson		New section to check cluster resources, and new memory check for under use.
--	05/07/2012	Jim Wilson		Added no_check for OSmemory limit and MAXdop self healing.
--	06/01/2012	Steve Ledridge	Changed Disk Space Forecasting Section to run from the dbo.DMV_DiskSpaceForecast Table (line 4598)
--	06/04/2012	Steve Ledridge	Modified SQLMaxMemory Calculation to round down to 1GB increments to filter false positives (line 1048)
--	06/04/2012	Steve Ledridge	Modified TempDB_filecount to use a No_Check Overide. (line 1710)
--	06/04/2012	Steve Ledridge	Modified all Calls to GetDate() to use @CheckDate Variable that is set at the beginning so
--								that all reports, comments, and table entries use the exact same datetime for better grouping
--								of multiple records. 
--	06/05/2012	Jim Wilson		New code to skip snapshot DB's (source_database_id is null)
--	06/05/2012	Steve Ledridge	Modified Cluster Status Checking to be more reliable. (line 508)
--	06/05/2012	Steve Ledridge	Modified all output to use standard calls so that it can be groomed.
--	06/18/2012	Steve Ledridge	Modified Job Checking processes
--	06/18/2012	Steve Ledridge	Modified all Output and file writing processes to use newer methods.
--	======================================================================================

/*
declare @rpt_recipient sysname
declare @checkin_grace_hours smallint
declare @recycle_grace_days smallint
declare @reboot_grace_days smallint
--declare @save_SQLEnv sysname

select @rpt_recipient = 'jim.wilson@gettyimages.com'
Select @checkin_grace_hours = 32
select @recycle_grace_days = 120
select @reboot_grace_days = 120
--Select @save_SQLEnv = 'production'
--*/

-----------------  declares  ------------------
Declare 
	 @miscprint			nvarchar(255)
	,@cmd				nvarchar(4000)
	,@SQL				nvarchar(4000)
	,@charpos			int
	,@isNMinstance			char(1)
	,@save_sqlinstance		sysname
	,@save_servername		sysname
	,@save_servername2		sysname
	,@save_sqlservername		sysname
	,@save_sqlservername2		sysname
	,@save_DBname			sysname
	,@save_DBstatus			sysname
	,@save_envname			sysname
	,@save_SQLmax_memory_int	int
	,@save_SQLmax_memory_all	bigint
	,@save_OSmemory			int
	,@save_OSmemory_vch		sysname
	,@save_moddate			datetime
	,@date_control			datetime
	,@save_SQLrecycle_date		datetime
	,@save_OSuptime			sysname
	,@save_reboot_days		nvarchar(10)
	,@save_dbaadmin_Version		sysname
	,@save_size_of_userDBs_MB	int
	,@save_litespeed		sysname
	,@save_RedGate			sysname 
	,@save_backuptype		sysname
	,@save_SQLmax_memory		nvarchar(20)
	,@save_Memory			int
	,@save_memory_float		float
	,@save_awe			nchar(1)
	,@save_boot_pae			nchar(1)
	,@save_boot_3gb			nchar(1)
	,@save_boot_userva		nchar(1)
	,@version_control		sysname
	,@save_r_id			int
	,@save_subject01		nvarchar(500)
	,@save_value01			nvarchar(500)
	,@hold_value01			nvarchar(500)
	,@save_grade01			sysname
	,@save_notes01			nvarchar(500)
	,@save_text			nvarchar(500)
	,@file_size 			bigint
	,@day_count			int


Declare 
	 @rpt_flag			char(1)
	,@first_flag			char(1)
	,@fail_flag			char(1)
	,@nocheck_backup_flag		char(1)
	,@nocheck_maint_flag		char(1)
	,@subject			nvarchar(255)
	,@message			nvarchar(4000)
	,@reportfile_path		sysname
	,@save_domain			sysname
	,@save_Name2			sysname
	,@save_momverifydate		datetime
	,@trys				int
	,@central_server		sysname
	,@save_memory_varchar		sysname
	,@save_SQLSvcAcct		sysname
	,@save_svcsid			sysname
	,@save_DomainName		sysname
	,@save_sc_data			sysname
	,@save_sc_data_part		sysname
	,@save_start_type		sysname
	,@save_display_name		sysname
	,@save_SERVICE_START_NAME	sysname
	,@save_svc_state		sysname
	,@save_iscluster		char(1)
	,@save_DB_owner			sysname
	,@save_DBid			int
	,@save_RecoveryModel		sysname
	,@save_check	    		sysname
	,@save_old_check		sysname
	,@save_check_type		sysname
	,@save_master_filepath		nvarchar(2000)
	,@save_tempdb_filecount		nvarchar(10)
	,@save_tempdb_corecount		nvarchar(10)
	,@save_tempdb_filedrive		sysname
	,@save_tempdb_filesize		int
	,@save_loginmode		sysname
	,@save_auditlevel		sysname
	,@save_user_name		sysname
	,@save_user_sid			varchar(255)
	,@save_ObjectName		sysname
	,@save_ObjectType		sysname
	,@save_maxdop 			sysname
	,@save_maxdop_int 		int
	,@save_CPUcore 			sysname


DECLARE		@jobhistory_max_rows			INT
			,@jobhistory_max_rows_per_job	INT
			,@save_job_id					uniqueidentifier
			,@save_lastrun					int
			,@parm01						sysname
			,@save_joblog_outpath			nvarchar(2000)
			,@save_jobname					sysname
			,@save_jobstep					int
			,@saverun_date					int
			,@saverun_time					int
			,@save_outfilename				sysname
			,@save_sharename				sysname
			,@share_outpath					nvarchar(2000)
			,@save_status					sysname
			,@save_status2					sysname
			,@save_Redgate_flag				char(1)
			,@save_winzip_build				sysname
			,@save_rg_version				sysname
			,@save_rg_versiontype			sysname
			,@hold_backup_start_date		datetime
			,@save_backup_start_date		sysname
			,@updatefile_name				sysname
			,@updatefile_path				nvarchar(250)
			,@hold_source_path				sysname
			,@save_next_run_date			datetime
			,@save_secedit_id				int
			,@save_secedit_data				varchar(max)
			,@save_secedit_hold				varchar(max)
			,@save_login_name				sysname
			,@doesexist						int
			,@save_driveletter				nvarchar(10)
			,@save_GrowthPerWeekMB			int
			,@save_DriveFullWks				int
			,@save_dba_mail_path			sysname
			,@save_cluster_ActvActv_flag	char(1)

DECLARE		@OutputComment					VarChar(MAX)
DECLARE		@Result							INT
DECLARE		@OutputComments					TABLE(OutputComment VarChar(max))
DECLARE		@Report							TABLE	(
													[subject] VarChar(max)
													,[value] VarChar(max)
													,[grade] sysname
													,[notes] VarChar(max)
													,[OutputComment] VarChar(max)
													)
DECLARE		@ReportText						VarChar(max)	
DECLARE		@p2 							nvarchar(4000)
DECLARE		@p4 							int
DECLARE		@p5 							int
DECLARE		@CheckDate						DATETIME
DECLARE		@FilterOutlierPercent			INT
DECLARE		@FloatRange						INT
DECLARE		@Today							DateTime
DECLARE		@JobLog_Share_Name				VarChar(255)
DECLARE		@JobLog_Share_Path				VarChar(100)
DECLARE		@ColumnWrapCnt					INT
DECLARE		@TotalWidth						INT
DECLARE		@JobStatusResults				TABLE		(
														[JobName]						[sysname]	NOT NULL
														,[OwnerName]					[sysname]	NULL
														,[Enabled]						[INT]		NULL
														,[Schedules]					[INT]		NULL
														,[EnabledSchedules]				[INT]		NULL
														,[WeightedAverageRunDuration]	[INT]		NULL
														,[AverageRunDuration]			[INT]		NULL	
														,[AVGDevs]						[float]		NULL	
														,[ExecutionsToday]				[INT]		NULL	
														,[OutliersToday]				[INT]		NULL	
														,[Executions]					[INT]		NULL	
														,[LastRun]						[DateTime]	NULL
														,[Failures]						[INT]		NULL	
														,[FailuresToday]				[INT]		NULL	
														,[LastStatus]					[INT]		NULL
														,[LastStatusMsg]				[SYSNAME]	NULL
														,[CurrentCount]					[INT]		NULL
														,[AvgDailyExecutionsCount]		[FLOAT]		NULL	
														,[MaxDailyExecutionsCount]		[FLOAT]		NULL	
														,[AvgDailyFailCount]			[FLOAT]		NULL
														,[MaxDailyFailCount]			[FLOAT]		NULL
														,[AvgDailyFailPercent]			[FLOAT]		NULL
														,[MaxDailyFailPercent]			[FLOAT]		NULL
														,[next_scheduled_run_date]		[DateTime]	NULL
														)
DECLARE		@EnableCodeComments				sql_variant
DECLARE		@save_EnableCodeComments		sql_variant
DECLARE		@PrintWidth						INT	
DECLARE		@StatusPrint					INT
DECLARE		@DebugPrint						INT
DECLARE		@OutputPrint					INT
DECLARE		@MSG							VarChar(MAX)
DECLARE		@CRLF							CHAR(2)
DECLARE		@DBASQL_Share_Name				SYSNAME
DECLARE		@ReportPath						VarChar(8000)
DECLARE		@ReportFileName					VarChar(100)


CREATE TABLE #temp_results (
			r_id [int]	IDENTITY(1,1)	NOT NULL
			,subject01	varchar(max)	NOT NULL
			,value01	varchar(max)	NULL
			,grade01	varchar(10)		NULL			
			,notes01	varchar(max)	NULL
			);


CREATE TABLE #temp_tbl1	(tb11_id [int] IDENTITY(1,1) NOT NULL
			,text01	nvarchar(400)
			)
			
create table #miscTempTable(cmdoutput nvarchar(400) null)

create table #seceditTempTable(secedit_id [int] IDENTITY(1,1) NOT NULL
			  	,secedit_data varchar(max) null)

create table #showgrps(cmdoutput nvarchar(255) null)

Create table #ShareTempTable(path nvarchar(500) null)

CREATE TABLE #scTempTable (sctbl_id [int] IDENTITY(1,1) NOT NULL
			  ,sc_data        nvarchar(400)
			  )
			
CREATE TABLE #scTempTable2 (sctbl_id [int] IDENTITY(1,1) NOT NULL
			  ,sc_data        nvarchar(400)
			  )
			  
Create table #loginconfig (name sysname NULL
			  ,configvalue sysname null
			  )

CREATE table #dir_results (dir_row varchar(255))

create table #orphans(orph_sid varbinary(85), orph_name sysname null)

CREATE TABLE #Objects ( 
  DatabaseName sysname, 
  UserName sysname,
  ObjectName sysname,
  ObjectType NVARCHAR(60)); 

CREATE TABLE #SchemaObjCounts (SchemaName sysname,objCount bigint);

DECLARE @xp_results TABLE (job_id                UNIQUEIDENTIFIER NOT NULL,
                            last_run_date         INT              NOT NULL,
                            last_run_time         INT              NOT NULL,
                            next_run_date         INT              NOT NULL,
                            next_run_time         INT              NOT NULL,
                            next_run_schedule_id  INT   NOT NULL,
                            requested_to_run      INT              NOT NULL, -- BOOL
                            request_source        INT              NOT NULL,
                            request_source_id     sysname          COLLATE database_default NULL,
                            running               INT              NOT NULL, -- BOOL
                            current_step          INT              NOT NULL,
                            current_retry_attempt INT              NOT NULL,
                            job_state             INT              NOT NULL
                            )

			
			
declare @tblv_DBA_Serverinfo table (SQLServerName sysname
			    ,SQLServerENV sysname
			    ,Active char(1)
			    ,modDate datetime
			    ,SQL_Version nvarchar (500) null
			    ,dbaadmin_Version sysname null
			    ,backup_type sysname null
			    ,LiteSpeed sysname null
			    ,RedGate sysname NULL
			    ,DomainName sysname NULL
			    ,SQLrecycle_date sysname NULL
			    ,awe_enabled char(1) NULL
			    ,MAXdop_value nvarchar(5) NULL
			    ,SQLmax_memory nvarchar(20) NULL
			    ,tempdb_filecount nvarchar(10) NULL
			    ,iscluster char(1) NULL
			    ,Port nvarchar(10) NULL
			    ,IPnum sysname NULL
			    ,CPUcore sysname NULL
			    ,CPUtype sysname NULL
			    ,Memory sysname NULL
			    ,OSname sysname NULL
			    ,OSver sysname NULL
			    ,OSuptime sysname NULL
			    ,boot_3gb char(1) NULL
			    ,boot_pae char(1) NULL
			    ,boot_userva char(1) NULL
			    ,Pagefile_inuse sysname NULL
			    ,SystemModel sysname NULL
			    ,momverifydate datetime NULL
			    )

declare @tblv_moddate table (SQLServerName sysname
			    ,modDate datetime
			    )

declare @tblv_recycle table (SQLServerName sysname
			    ,SQLrecycle_date sysname NULL
			    )

declare @tblv_reboot table (SQLServerName sysname
			    ,OSuptime sysname NULL
			    )

declare @tblv_version table (SQLServerName sysname
			    ,dbaadmin_Version sysname null
			    )

declare @tblv_backup_usage table (SQLServerName sysname
			    ,size_of_userDBs_MB int null
			    )

declare @tblv_std_backup_check table (SQLServerName sysname
			    ,LiteSpeed char(1) null
			    ,RedGate char(1) NULL
			    )

declare @tblv_cmp_backup_check table (SQLServerName sysname
			    ,backup_type sysname null
			    ,LiteSpeed char(1) null
			    ,RedGate char(1) NULL
			    )


declare @tblv_memory table (SQLServerName sysname
			    ,awe_enabled char(1) NULL
			    ,SQLmax_memory nvarchar(20) NULL
			    ,Memory sysname NULL
			    ,boot_3gb char(1) NULL
			    ,boot_pae char(1) NULL
			    ,boot_userva char(1) NULL
			    )

declare @tblv_mom01 table (SQLServerName sysname
			    ,momverifydate datetime NULL)


declare @tblv_cluster table (SQLServerName sysname
			    ,Name2 sysname NULL
			    )





----------------  INITIAL VALUES  -------------------
SELECT	@CheckDate					= GetDate()
		,@Today						= CAST(CONVERT(VarChar(12),@CheckDate,101)AS DATETIME)
		,@subject					= 'SQL Health Check from [' + upper(@@servername) + '] on ' + convert(nvarchar(19), @CheckDate, 121)
		,@message					= ''
		,@rpt_flag					= 'n'
		,@fail_flag					= 'n'
		,@save_Redgate_flag			= 'n'
		,@isNMinstance				= 'n'
		,@CRLF						= CHAR(13)+CHAR(10)
		,@PrintWidth				= 250
		,@OutputPrint				= CASE WHEN @Verbose >= 0 THEN 1 ELSE 0 END
		,@StatusPrint				= CASE WHEN @Verbose >  0 THEN 1 ELSE 0 END
		,@DebugPrint				= CASE WHEN @Verbose >  1 THEN 1 ELSE 0 END

	-- SET JOB TIME AVERAGE CALCULATION VARIABLES
		,@FilterOutlierPercent		= 10
		,@FloatRange				= 100

	-- SET SERVERNAME VARIABLES
		,@save_sqlinstance			= @@SERVICENAME
		,@save_servername			= CAST(SERVERPROPERTY('Machinename') AS SYSNAME)
		,@save_servername2			= REPLACE(@@SERVERNAME,'\','$')
		,@isNMinstance				= CASE @@SERVICENAME WHEN 'MSSQLSERVER' THEN 'n' ELSE 'y' END
		,@save_domain				= (select env_detail from dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'domain')
		,@save_iscluster			= (select top 1 iscluster from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
		,@save_envname				= (select env_detail from dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'ENVname')

	-- SET SHARE, PATH, AND FILE NAMES
		,@JobLog_Share_Name			= @save_servername2 + '_SQLjob_logs'
		,@DBASQL_Share_Name			= @save_servername2 + '_dbasql'
		,@ReportPath				= '\\'+@save_servername+'\'+@save_servername2+'_dbasql\dba_reports\'
		,@ReportFileName			= 'SQLHealthReport_'+@save_servername2+'.txt'
		,@updatefile_name			= 'SQLHealthUpdate_'+@save_servername2+'.gsql'
		,@updatefile_path			= @ReportPath+@updatefile_name
		
		
	-- GET EXTENDED PROPERTY	
		,@EnableCodeComments		= CASE @DebugPrint WHEN 1 THEN 1 ELSE 0 END
		,@save_EnableCodeComments	= COALESCE([value],0)
FROM	fn_listextendedproperty('EnableCodeComments', default, default, default, default, default, default)


-- GET SHARE PATHS FROM SHARE NAMES 
EXEC	dbaadmin.dbo.dbasp_get_share_path @share_name = @JobLog_Share_Name, @phy_path = @JobLog_Share_Path OUT

--------------------  Set last-run date and time parameters  -------------------
select @saverun_date = (Select max(h.run_date) 
			from msdb.dbo.sysjobhistory  h,  msdb.dbo.sysjobs  j 
			where h.job_id = j.job_id 
			  and j.name = 'UTIL - DBA Archive process' 
			  and h.run_status = 1 
			  and h.step_id = 0)

If @saverun_date is not null
   begin
	select @saverun_time = (Select max(h.run_time) from msdb.dbo.sysjobhistory  h,  msdb.dbo.sysjobs  j 
				where h.job_id = j.job_id 
				  and h.run_date = @saverun_date 
				  and j.name = 'UTIL - DBA Archive process')
   end
Else
   begin
	select @saverun_date = convert(int,(convert(varchar(20),@CheckDate, 112)))
	select @saverun_time = 0
   end

SELECT		@OutputComment = ''
DELETE		@OutputComments
-----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------
--									STARTING PROCESSING
-----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------
SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint;INSERT INTO @OutputComments VALUES(@MSG)
SELECT @MSG='STARTING PROCESSING',@MSG=REPLICATE(' ',(@PrintWidth-LEN(@MSG))/2)+@MSG;EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint;INSERT INTO @OutputComments VALUES(@MSG)
SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint;INSERT INTO @OutputComments VALUES(@MSG)

-- SET "EnableCodeComments" VALUE FOR THIS EXECUTION
IF NOT EXISTS (SELECT value FROM fn_listextendedproperty('EnableCodeComments', default, default, default, default, default, default))
	EXEC sys.sp_addextendedproperty		@Name = 'EnableCodeComments', @value = @EnableCodeComments
ELSE
	EXEC sys.sp_updateextendedproperty	@Name = 'EnableCodeComments', @value = @EnableCodeComments


BEGIN -- POPULATE @JobStatusResults WITH DATA TO EVALUATE JOB STEP CONDITIONS
	SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
	SELECT @MSG='POPULATING @JobStatusResults',@MSG=REPLICATE(' ',(@PrintWidth-LEN(@MSG))/2)+@MSG;EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
	SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint

	 
	;WITH		JobHistoryData
				AS
				(
				SELECT		job_id
							,row_number() over (PARTITION BY job_id order by [StartDateTime])		AS RowNumber
							,row_number() over (PARTITION BY job_id order by [StartDateTime] DESC)	AS RowNumberInversion
							,COUNT(*) over (PARTITION BY job_id)									AS SetCount
							,(@FilterOutlierPercent 
								* COUNT(*) over (PARTITION BY job_id))
								/ 100																AS OutlierRowCount
							,row_number() OVER (PARTITION BY job_id order by [Duration_Seconds])	AS ValueRankAsc
							,row_number() OVER (PARTITION BY job_id order by [Duration_Seconds]DESC)AS ValueRankDesc
							,StartDateTime	[Start]
							,EndDateTime	[Stop]
							,Duration_Seconds [Seconds]
							,run_status
							,message						 
				FROM		(
							SELECT		msdb.dbo.agent_datetime(run_date,run_time) AS StartDateTime
										,DATEADD(s,DATEDIFF(s,msdb.dbo.agent_datetime(run_date,0),msdb.dbo.agent_datetime(run_date,run_duration%240000)+(run_duration/240000)),msdb.dbo.agent_datetime(run_date,run_time)) AS EndDateTime
										,DATEDIFF(s,msdb.dbo.agent_datetime(run_date,0),msdb.dbo.agent_datetime(run_date,run_duration%240000)+(run_duration/240000)) AS Duration_Seconds
										,*
							from		msdb..sysjobhistory
							where		step_id = 0
							) JobHistory
				)
				,F0
				AS
				(
				SELECT		job_id
							,RowNumber
				FROM		JobHistoryData
				WHERE		run_status = 0
				)
				,F1
				AS
				(
				SELECT		job_id
							,RowNumber
							,RowNumber - ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY RowNumber) AS Grp
				FROM		F0
				)
				,S0
				AS
				(
				SELECT		job_id
							,RowNumber
				FROM		JobHistoryData
				WHERE		run_status = 1
				)
				,S1
				AS
				(
				SELECT		job_id
							,RowNumber
							,RowNumber - ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY RowNumber) AS Grp
				FROM		S0
				)
				,T1
				AS
				(			
				SELECT		job_id
							,RowNumber
							,ROW_NUMBER() OVER (PARTITION BY job_id,Grp ORDER BY RowNumber) AS Consecutive
				FROM		F1
				UNION ALL
				SELECT		job_id
							,RowNumber
							,ROW_NUMBER() OVER (PARTITION BY job_id,Grp ORDER BY RowNumber) AS Consecutive
				FROM		S1
				)
				,DailyFailRate
				AS
				(
				SELECT		job_id
							,AVG([DailyExecutionsCount])	[AvgDailyExecutionsCount]
							,MAX([DailyExecutionsCount])	[MaxDailyExecutionsCount]
							,AVG([DailyFailCount])			[AvgDailyFailCount]
							,MAX([DailyFailCount])			[MaxDailyFailCount]
							,AVG([DailyFailPercent])		[AvgDailyFailPercent]
							,MAX([DailyFailPercent])		[MaxDailyFailPercent]
				FROM		(						
							SELECT		job_id
										,CAST(CONVERT(VarChar(12),[Start],101)AS DateTime)	AS [StartDay]
										,COUNT(*)+0.0										AS [DailyExecutionsCount]
										,COUNT(CASE run_status WHEN 0 THEN 1 END)+0.0		AS [DailyFailCount]
										,(100*(COUNT(CASE run_status WHEN 0 THEN 1 END)+0.0))
											/(COUNT(*)+0.0)									AS [DailyFailPercent] 
							FROM		JobHistoryData
							GROUP BY	job_id
										,CAST(CONVERT(VarChar(12),[Start],101)AS DateTime)
							)DFR
				GROUP BY	job_id						
				)
				,FloatingAverage
				AS
				(
				SELECT		[JobHistoryData].job_id
							,[JobHistoryData].RowNumber
							,AVG([JobHistoryData3].Seconds)				AS AVG_Value
							,STDEVP([JobHistoryData3].Seconds)			AS STDEVP_Value
				FROM		[JobHistoryData]
				JOIN		(
							SELECT		*
							FROM		[JobHistoryData]
							WHERE		ValueRankAsc	> OutlierRowCount
									AND	ValueRankDesc	> OutlierRowCount
							) [JobHistoryData3]
						ON	[JobHistoryData].job_id	= [JobHistoryData3].job_id
						AND ABS([JobHistoryData].RowNumber - [JobHistoryData3].RowNumber) < @FloatRange
				GROUP BY	[JobHistoryData].job_id	
							,[JobHistoryData].RowNumber
				)
				,Results
				AS
				(
				SELECT		T1.job_id
							,T1.RowNumber
							,T1.RowNumberInversion
							,T1.Start
							,T1.Stop
							,T1.Seconds
							,run_status
							,CASE run_status 
								WHEN 0 THEN 'Failure' 
								WHEN 1 THEN 'Success' 
								WHEN 2 THEN 'Retry' 
								WHEN 3 THEN 'Cancelled' 
								WHEN 4 THEN 'Running' 
								ELSE 'Other: ' + 
								Convert(VARCHAR,run_status) 
							  END AS run_status_msg
							,message				
							,ABS(Seconds-AVG_Value)/isnull(nullif(STDEVP_Value,0),1)		AS DevsFromAvg
							,CAST(ABS(Seconds-AVG_Value)/isnull(nullif(STDEVP_Value,0),1)/2 AS INT) AS TREND
							,T2.AVG_Value
							,T2.STDEVP_Value
				FROM		[JobHistoryData] T1
				LEFT JOIN	[FloatingAverage] T2
						ON	T1.job_id = T2.job_id
						AND T1.RowNumber = T2.RowNumber
				)
				,JobActivity
				AS
				(
				select		top 1 with ties 
							a.job_id
							,j.name AS job_name
							,CASE WHEN stop_execution_date IS NULL	THEN start_execution_date ELSE NULL END start_execution_date
							,CASE WHEN start_execution_date IS NULL THEN 0		WHEN stop_execution_date IS NULL THEN COALESCE(last_executed_step_id+1,1)						ELSE 0		END AS step_execution
							,CASE WHEN start_execution_date IS NULL THEN NULL	WHEN stop_execution_date IS NULL THEN COALESCE(last_executed_step_date,start_execution_date)	ELSE NULL	END AS step_execution_date
							,CASE WHEN start_execution_date IS NOT NULL AND stop_execution_date IS NULL THEN a.job_history_id ELSE NULL END job_history_id
							,next_scheduled_run_date
				from		msdb..sysjobactivity a
				join		msdb..sysjobs j 
						ON	j.job_id = a.job_id
				order by rank() OVER(ORDER BY a.session_id desc)
				)
				,JobSchedules
				AS
				(
				SELECT		JS.job_id
							,COUNT(*) [Schedules]
							,COUNT(CASE WHEN S.enabled = 1 THEN 1 END) [EnabledSchedules]
							,MIN(CASE WHEN S.enabled = 1 THEN msdb.dbo.agent_datetime(COALESCE(nullif(JS.next_run_date,0),20000101),JS.next_run_time) END) NextRunDateTime
				FROM		msdb.dbo.sysjobschedules JS
				JOIN		msdb.dbo.sysschedules S 
						ON	S.schedule_id = JS.schedule_id
				GROUP BY	JS.job_id	
				)
	INSERT INTO	@JobStatusResults						
	SELECT		j.name JobName
				,(SELECT Name From sys.syslogins WHERE sid = max(J.owner_sid))	AS [Owner Name]
				,MAX(COALESCE(j.enabled,0))										AS [Enabled]
				,MAX(COALESCE(JS.[Schedules],0))								AS [Schedules]
				,MAX(COALESCE(JS.[EnabledSchedules],0))							AS [EnabledSchedules]
				,AVG(AVG_Value)													AS [Weighted Average Run Duration]
				,AVG(Seconds)													AS [Average Run Duration]
				,AVG(DevsFromAvg)												AS [AVGDevs]
				,COUNT(CASE WHEN [Start] >= @Today 
							THEN 1 END)											AS [ExecutionsToday]
				,COUNT(CASE WHEN [Start] >= @Today AND [Trend] >= 20 
							THEN 1 END)											AS [OutliersToday]
				,Count(*)														AS [Executions]
				,max([Start])													AS [LastRun]
				
				,COUNT(CASE run_status WHEN 0 THEN 1 END)						AS [Failures]	
				,COUNT(CASE
						WHEN [Start] >= 
						CAST(CONVERT(VarChar(12),GetDate(),101)AS DATETIME) 
						AND [run_status]= 0 THEN 1 END)							AS [FailuresToday]
				,MAX(CASE RowNumberInversion WHEN 1 THEN [run_status] END)		AS [LastStatus]
				,MAX(CASE RowNumberInversion WHEN 1 THEN [run_status_msg] END)	AS [LastStatusMsg]
				,MAX(CASE RowNumberInversion WHEN 1 THEN T1.Consecutive END)	AS [CurrentCount]
				,MAX(DFR.[AvgDailyExecutionsCount])								AS [AvgDailyExecutionsCount]	
				,MAX(DFR.[MaxDailyExecutionsCount])								AS [MaxDailyExecutionsCount]	
				,MAX(DFR.[AvgDailyFailCount])									AS [AvgDailyFailCount]
				,MAX(DFR.[MaxDailyFailCount])									AS [MaxDailyFailCount]
				,MAX(DFR.[AvgDailyFailPercent])									AS [AvgDailyFailPercent]
				,MAX(DFR.[MaxDailyFailPercent])									AS [MaxDailyFailPercent]
				,MIN(JS.[NextRunDateTime])										AS [next_scheduled_run_date]
	FROM		msdb..sysjobs J 
	LEFT JOIN	Results JH
			ON	J.job_id = JH.job_id
	LEFT JOIN	T1
			ON	T1.job_id = jh.job_id
			AND	T1.RowNumber = jh.RowNumber	
	LEFT JOIN	DailyFailRate DFR
			ON	DFR.job_id = J.job_id
	LEFT JOIN	JobSchedules JS
			ON	JS.job_id = J.job_id							
	GROUP BY	J.Name

END				


/****************************************************************
 *                MainLine
 ***************************************************************/

--  reset the HealthCheck_current table 
Delete from dbo.HealthCheck_current


--  Make sure we have data in the Local_ServerEnviro table
If not exists (select 1 from dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'instance' and env_detail = @@servername)
   begin
	exec dbaadmin.dbo.dbasp_capture_local_serverenviro
   end


--  Make sure we have a current row in the DBA_Serverinfo table for this SQL instance
If not exists (select 1 from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername and moddate > @CheckDate-2)
   begin
	exec dbaadmin.dbo.dbasp_Self_Register
   end


--  Make sure sp_configure 'show advanced option' is set
If not exists (select 1 from sys.configurations with (NOLOCK) where name like '%show advanced options%' and value = 1)
   begin
	select @cmd = 'sp_configure ''show advanced option'', ''1'''
	exec master.sys.sp_executeSQL @cmd

	select @cmd = 'RECONFIGURE WITH OVERRIDE;'
	exec master.sys.sp_executeSQL @cmd
   end

--  Create secedit output file
Select @cmd = 'secedit /export /cfg c:\sql_healthcheck_secedit.INF /areas user_rights'
--Print '		'+@cmd
EXEC master.sys.xp_cmdshell @cmd, no_output 


------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT @OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10) FROM @OutputComments
SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint;
SELECT @MSG=REPLICATE(' ',(@PrintWidth-LEN(@OutputComment))/2)+@OutputComment;EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint;
SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint;
SELECT		@OutputComment = ''
DELETE		@OutputComments
-----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------
--									STARTING PROCESSING
-----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------
SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint;INSERT INTO @OutputComments VALUES(@MSG)
SELECT @MSG='STARTING PROCESSING',@MSG=REPLICATE(' ',(@PrintWidth-LEN(@MSG))/2)+@MSG;EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint;INSERT INTO @OutputComments VALUES(@MSG)
SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint;INSERT INTO @OutputComments VALUES(@MSG)



-----------------------------------------------------------------------------------------
--  Cluster verifications (resources online, nodes online, instance on node alone)
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start Cluster verifications')

  
If @save_iscluster = 'y'
BEGIN
	DECLARE		@Groups			Table(ResultLine VarChar(max))
	DECLARE		@Nodes			Table(ResultLine VarChar(max))
	DECLARE		@Results		Table(ResultLine VarChar(max))
	DECLARE		@ClusterStatus	Table(ClusterResource SYSNAME,ClusterGroup SYSNAME, SQLName SYSNAME NULL, ClusterNode SYSNAME, Status SYSNAME)

	INSERT INTO @Nodes		exec xp_CMDSHELL 'cluster NODE /status'
	INSERT INTO @Groups		exec xp_CMDSHELL 'cluster group /status'
	INSERT INTO @Results	exec xp_CMDSHELL 'cluster res /status'

	;WITH		ClusterNodes
				AS
				(
				SELECT		UPPER(dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],1)) [NodeName]
							,dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],2)	[NodeNumber]
							,dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],3)	[NodeStatus]
				FROM		(																						
							SELECT		REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ResultLine,CHAR(13),'|'),' ','|'),'||','|'),'||','|'),'||','|'),'||','|') [ResultLine]
							FROM		@Nodes
							) Nodes
				WHERE		isnumeric(dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],2)) = 1
				)
				,ClusterGroups
				AS
				(
				SELECT		dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],1) [GroupName]
							,UPPER(dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],2))	[NodeName]
							,dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],3)	[GroupStatus]
				FROM		(																						
							SELECT		REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ResultLine,N.NodeName,'|'+N.NodeName+'|'),CHAR(13),'|'),')',')|'),'  ','|'),' '+'|','|'),'|'+' ','|'),'|'+'|','|'),'|'+'|','|'),'|'+'|','|'),CHAR(9),''),'-|','-'),'|'+N.NodeName+'|'+N.NodeName+'|','|'+N.NodeName+'|') [ResultLine]
							FROM		@Groups G
							LEFT JOIN	ClusterNodes N
									ON	G.ResultLine LIKE '%'+N.NodeName+'%'
							) Groups
				WHERE		NULLIF(NULLIF(dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],2),''),'Node') IS NOT NULL
				)
				,ClusterResources
				AS
				(
				SELECT		LEFT(dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],1),CHARINDEX('(',dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],1)+'(')-1)	[ResourceName]
							,UPPER(dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],2))	[GroupName]
							,dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],3)	[NodeName]
							,LTRIM(RTRIM(CAST(dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],4)AS VarChar(20))))	[Status]
							,CASE	WHEN [ResultLine] LIKE 'SQL%(%)%'
									THEN 
									SUBSTRING	(
													[ResultLine]
													,CHARINDEX('(',[ResultLine]+'()')+ 1
													,CHARINDEX(')',[ResultLine]+'()') - CHARINDEX('(',[ResultLine]+'()')-1
													)
									END	AS SQLDetails
				FROM		(
							SELECT		REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(STUFF(REPLACE('|'+REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ResultLine,CHAR(13),''),G.GroupName,'|$GN$|'),G.NodeName,'|$NN$|'),'(|','('),'|)',')'),'   ',' '),'  ',' '),'  ',' '),'| ','|'),' |','|'),'||','|'),'| ','|'),' |','|'),'||','|'),1,1,''),'$GN$',G.GroupName),'$NN$',G.NodeName),'-|','-'),'|_','_'),'|$','$'),'for|','for ') [ResultLine]
							FROM		@Results R
							LEFT JOIN	ClusterGroups G
									ON	R.ResultLine LIKE '%'+G.GroupName+'%'
							) Resources
				WHERE		dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],1) IS NOT NULL							
				)
				,SQLNames
				AS
				(
				SELECT		[GroupName]
							,MAX(CASE WHEN [ResourceName] = 'SQL Network Name' THEN [SQLDetails] END) [ServerName]
							,MAX(CASE WHEN [ResourceName] = 'SQL Server' THEN [SQLDetails] END) [SQLInstance]
				FROM		ClusterResources
				WHERE		[GroupName] IS NOT NULL
				GROUP BY	[GroupName]
				)				
	INSERT INTO	@ClusterStatus
	SELECT		T1.[ResourceName]
				,T1.[GroupName]
				,UPPER(T2.[ServerName] + COALESCE('\'+nullif(T2.[SQLInstance],'MSSQLSERVER'),'')) [SQLName]
				,T1.[NodeName]
				,T1.[Status]
	FROM		ClusterResources T1
	JOIN		SQLNames T2
			ON	T1.GroupName = T2.GroupName		

	-- ARE ANY RESOURCES OF THIS INSTANCE OFFLINE
	---------------------------------------------
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	SELECT		'Cluster_Resource'
				,'Resource Not Online'
				,'fail'
				,ClusterResource
	FROM		@ClusterStatus 
	WHERE		[SQLName] = @@ServerName 
			AND [Status] != 'Online'
	
	IF @@ROWCOUNT = 0
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Cluster_Resource', 'Online', 'pass', '')	

	-- ARE ANY NODES OFFLINE
	---------------------------------------------
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	SELECT		'Cluster_node'
				,'Node Not Up'
				,'fail'
				,[NodeName]
	FROM		(
				SELECT		UPPER(dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],1)) [NodeName]
							,dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],2)	[NodeNumber]
							,dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],3)	[NodeStatus]
				FROM		(																						
							SELECT		REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ResultLine,CHAR(13),'|'),' ','|'),'||','|'),'||','|'),'||','|'),'||','|') [ResultLine]
							FROM		@Nodes
							) Nodes
				WHERE		isnumeric(dbaadmin.dbo.dbaudf_ReturnPart([ResultLine],2)) = 1
				) Nodes
	WHERE		NodeStatus != 'Up'

	IF @@ROWCOUNT = 0
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Cluster_node', 'Up', 'pass', '')		


	-- ARE MULTIPLE SQL GORUPS ACTIVE ON CLUSTER
	---------------------------------------------- 
	IF	(
		SELECT		COUNT(DISTINCT ClusterGroup)		
		FROM		@ClusterStatus
		WHERE		[ClusterResource]	= 'SQL Server'
				AND [Status]			= 'Online'
		) = 1
			Insert into #temp_results 
			OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
			INTO		@OutputComments
			values		('Cluster_active_active', 'Not active\active', 'pass', '')
	ELSE
		SET @save_cluster_ActvActv_flag = 'y'


	-- ARE MULTIPLE SQL GORUPS ACTIVE ON THIS NODE
	---------------------------------------------- 
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
 	SELECT		'Cluster_active_active'
 				, @@ServerName + ' AND ' + [SQLName]
 				, 'fail'
 				, 'Muti SQL Instances on node ' + [ClusterNode]
	FROM		@ClusterStatus
	WHERE		[ClusterResource]	= 'SQL Server'
			AND [Status]			= 'Online'
			AND [ClusterNode]		= SERVERPROPERTY('ComputerNamePhysicalNetBIOS')
			AND [SQLName]			!= @@SERVERNAME
 
	IF @@ROWCOUNT = 0
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Cluster_active_active', @@SERVERNAME, 'pass', 'One SQL Instance on node ' + CAST(SERVERPROPERTY('ComputerNamePhysicalNetBIOS')AS VarChar(255)))		

	END



------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Verify installation and standard configuration
-----------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------
--  verify ole and xp_cmdshell turned on (self healing)
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Verify installation and standard configuration')
INSERT INTO @OutputComments VALUES('Start verify OLE and xp_cmdshell')

--Insert into #temp_results values ('OLE_Automation', 'n', 'fail', '')
If not exists (select 1 from sys.configurations with (NOLOCK) where name like '%OLE Automation%' and value = 1)
   begin
	select @cmd = 'sp_configure ''OLE Automation Procedures'', ''1'''
	exec master.sys.sp_executeSQL @cmd

	select @cmd = 'RECONFIGURE WITH OVERRIDE;'
	exec master.sys.sp_executeSQL @cmd
   end
   
If exists (select 1 from sys.configurations with (NOLOCK) where name like '%OLE Automation%' and value = 1)
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('OLE_Automation', 'y', 'pass', '') 
   end
   ELSE
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('OLE_Automation', 'n', 'fail', '') 
   end
   
--Insert into #temp_results values ('xp_cmdshell', 'n', 'fail', '')
If not exists (select 1 from sys.configurations with (NOLOCK) where name like '%xp_cmdshell%' and value = 1)
   begin
	select @cmd = 'sp_configure ''xp_cmdshell'', ''1'''
	exec master.sys.sp_executeSQL @cmd

	select @cmd = 'RECONFIGURE WITH OVERRIDE;'
	exec master.sys.sp_executeSQL @cmd
   end

If exists (select 1 from sys.configurations with (NOLOCK) where name like '%xp_cmdshell%' and value = 1)
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('xp_cmdshell', 'y', 'pass', '') 
   end
   ELSE
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('xp_cmdshell', 'n', 'fail', '') 
   end


------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  check system32 utilities (self heal)  276610_276610.exe is the best test
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start check system32 utilities')


--Insert into #temp_results values ('system32_utils', 'n', 'fail', 'DBA standard utilities not found in system32 folder')

Select @trys = 0
Start_276610:
delete from #temp_tbl1
Select @cmd = 'echo. | 276610_276610.exe'
--Print '		'+@cmd
insert #temp_tbl1(text01) exec master.sys.xp_cmdshell @cmd
Delete from #temp_tbl1 where text01 is null or text01 = ''
--select * from #temp_tbl1

Delete from #temp_tbl1 where text01 not like '%System wide availability%'
If not exists (select 1 from #temp_tbl1 where text01 like '%System wide availability%')
   begin
	--select * from #temp_tbl1
	Select @central_server = env_detail from dbaadmin.dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'CentralServer'

	Select @cmd = 'copy \\' + @central_server + '\' + @central_server + '_builds\dbaadmin\system32\*.*  %windir%\system32 /Y'
	--Print '		'+@cmd
	exec master.sys.xp_cmdshell @cmd, no_output 
	
	Select @trys = @trys + 1
	If @trys < 2
	   begin
		goto Start_276610
	   end
   end
Else
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('system32_utils', 'y', 'pass', '')
	goto skip_sys32
   end


Select @trys = 0
start_chkcpu32:
delete from #temp_tbl1
Select @cmd = 'echo. | chkcpu32.exe'
--Print '		'+@cmd
insert #temp_tbl1(text01) exec master.sys.xp_cmdshell @cmd
Delete from #temp_tbl1 where text01 is null or text01 = ''
--select * from #temp_tbl1

Delete from #temp_tbl1 where text01 not like '%CPU Identification utility%'
If not exists (select 1 from #temp_tbl1 where text01 like '%CPU Identification utility%')
   begin
	--select * from #temp_tbl1
	Select @central_server = env_detail from dbaadmin.dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'CentralServer'

	Select @cmd = 'copy \\' + @central_server + '\' + @central_server + '_builds\dbaadmin\system32\*.*  %windir%\system32 /Y'
	--Print '		'+@cmd
	exec master.sys.xp_cmdshell @cmd, no_output 
	
	Select @trys = @trys + 1
	If @trys < 2
	   begin
		goto start_chkcpu32
	   end
   end
Else
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('system32_utils', 'y', 'pass', '')
   end

skip_sys32:

IF NOT EXISTS (SELECT * FROM #temp_results WHERE Subject01 = 'system32_utils')
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('system32_utils', 'n', 'fail', 'DBA standard utilities not found in system32 folder')
   end

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  check awe and boot.ini (3gb, pae, userva) settings
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('check awe and boot.ini (3gb, pae, userva) settings')


--  Get sql memory
Select @save_memory_varchar = (select top 1 memory from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
Select @save_memory_varchar = replace (@save_memory_varchar, ',', '')

If @save_memory_varchar like '%MB%'
   begin
	Select @save_memory_varchar = replace (@save_memory_varchar, 'MB', '')
	Select @save_memory_varchar = replace (@save_memory_varchar, ' ', '')
	Select @save_memory_varchar = rtrim(ltrim(@save_memory_varchar))
	Select @charpos = charindex('.', @save_memory_varchar)
	IF @charpos <> 0
	   begin
		Select @save_memory_varchar = left(@save_memory_varchar, @charpos-1)
	   end
	Select @save_memory = convert(int, @save_memory_varchar)
   end
Else If @save_memory_varchar like '%GB%'
   begin
	Select @save_memory_varchar = replace (@save_memory_varchar, 'GB', '')
	Select @save_memory_varchar = replace (@save_memory_varchar, ' ', '')
	Select @save_memory_varchar = rtrim(ltrim(@save_memory_varchar))
	Select @charpos = charindex('.', @save_memory_varchar)
	IF @charpos <> 0
	   begin
		Select @save_memory_varchar = left(@save_memory_varchar, @charpos-1)
	   end
	Select @save_memory_float = convert(float, @save_memory_varchar)
	Select @save_memory = @save_memory_float * 1024.0
   end
Else If @save_memory_varchar like '%KB%'
   begin
	Select @save_memory_varchar = replace (@save_memory_varchar, 'KB', '')
	Select @save_memory_varchar = replace (@save_memory_varchar, ' ', '')
	Select @save_memory_varchar = rtrim(ltrim(@save_memory_varchar))
	Select @charpos = charindex('.', @save_memory_varchar)
	IF @charpos <> 0
	   begin
		Select @save_memory_varchar = left(@save_memory_varchar, @charpos-1)
	   end
	Select @save_memory = convert(int, @save_memory_varchar)
	Select @save_memory = @save_memory / 1024.0
   end


Select @save_awe = (select top 1 awe_enabled from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
If @@version like '%x64%'
   begin
	If @save_awe = 'y'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('awe_enabled', 'y', 'warning', 'not needed for x64')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('awe_enabled', 'n', 'pass', '')
	   end
   end
Else If @save_memory < 4100
   begin
	If @save_awe = 'y'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('awe_enabled', 'y', 'fail', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('awe_enabled', 'n', 'pass', '')
	   end
   end
Else
   begin
	If @save_awe = 'y'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('awe_enabled', 'y', 'pass', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('awe_enabled', 'n', 'fail', '')
	   end
   end



Select @save_boot_3gb = (select top 1 boot_3gb from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
If @@version like '%x64%' or @save_memory < 4000 or @save_memory > 16384
   begin
	If @save_boot_3gb = '-'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_3gb', '-', 'pass', '')
	   end
	Else If @save_boot_3gb = 'y'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_3gb', 'y', 'fail', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_3gb', 'n', 'pass', '')
	   end
   end
Else
   begin
	If @save_boot_3gb = '-'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_3gb', '-', 'pass', '')
	   end
	Else If @save_boot_3gb = 'y'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_3gb', 'y', 'pass', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_3gb', 'n', 'fail', '')
	   end
   end


Select @save_boot_userva = (select top 1 boot_userva from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
If @@version like '%x64%' or @save_memory < 4000 or @save_memory > 16384
   begin
	If @save_boot_userva = 'y'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_userva', 'y', 'fail', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_userva', 'n', 'pass', '')
	   end
   end
Else
   begin
	If @save_boot_userva = 'y'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_userva', 'y', 'pass', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_userva', 'n', 'pass', '')
	   end
   end



Select @save_boot_pae = (select top 1 boot_pae from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
If @@version like '%x64%' or @save_memory < 4100
   begin
	If @save_boot_pae = 'y'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_pae', 'y', 'fail', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_pae', 'n', 'pass', '')
	   end
   end
Else
   begin
	If @save_boot_pae = 'y'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_pae', 'y', 'pass', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('boot_pae', 'n', 'fail', '')
	   end
   end



------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start check MAXdop settings
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start check MAXdop settings')

Select @save_maxdop = (select MAXdop_value from dbo.dba_serverinfo where sqlname = @@servername)
Select @save_maxdop = ltrim(@save_maxdop)
Select @save_maxdop = ltrim(@save_maxdop)
Select @charpos = charindex(' ', @save_maxdop)
IF @charpos <> 0
   begin
	Select @save_maxdop = left(@save_maxdop, @charpos-1)
   end
Select @save_CPUcore = (select CPUcore from dba_serverinfo where sqlname = @@servername)
Select @save_CPUcore = ltrim(@save_CPUcore)
Select @charpos = charindex(' ', @save_CPUcore)
IF @charpos <> 0
   begin
	Select @save_CPUcore = left(@save_CPUcore, @charpos-1)
   end

If @save_maxdop = 0 and isnumeric(@save_maxdop) = 1 and isnumeric(@save_CPUcore) = 1
   begin
	Select @save_maxdop_int = convert(int,@save_CPUcore)/4
	If @save_maxdop_int = 0
	   begin
		Select @save_maxdop_int = 1
	   end
		
	select @cmd = 'EXEC sp_configure ''max degree of parallelism'' , ' + convert(sysname, @save_maxdop_int)
	--Print '		'+@cmd
	exec (@cmd)

	select @cmd = 'RECONFIGURE WITH OVERRIDE'
	--Print '		'+@cmd
	exec (@cmd)	
   end

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start check memory settings
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start check memory settings')


If exists (select 1 from dbo.no_check where NoCheck_type = 'OSmemory')
   begin
	Select @save_OSmemory_vch = (select top 1 Detail01 from dbo.no_check where NoCheck_type = 'OSmemory')
	Select @save_OSmemory_vch = rtrim(ltrim(@save_OSmemory_vch))
	Select @save_OSmemory = convert(int, @save_OSmemory_vch)
   end
Else
   begin
	Select @save_OSmemory = 4608 
   end

--  Get sql memory
Select @save_SQLmax_memory = (select top 1 SQLmax_memory from dbaadmin.dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
Select @save_SQLmax_memory = replace (@save_SQLmax_memory, ',', '')
Select @save_SQLmax_memory = replace (@save_SQLmax_memory, 'MB', '')
Select @save_SQLmax_memory = replace (@save_SQLmax_memory, 'GB', '')
Select @save_SQLmax_memory = replace (@save_SQLmax_memory, 'KB', '')
Select @save_SQLmax_memory = replace (@save_SQLmax_memory, ' ', '')
Select @save_SQLmax_memory = rtrim(ltrim(@save_SQLmax_memory))
Select @save_SQLmax_memory_int = convert(int, @save_SQLmax_memory)

If @save_cluster_ActvActv_flag = 'y'
   begin
	If @save_SQLmax_memory_int > (@save_memory/2)
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'fail', 'max memory is greater than half the available memory on the server')
	   end
	Else If (@save_memory/2) > 8192 and @save_SQLmax_memory_int > ((@save_memory - 2024)/2)
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'fail', 'max memory for actv\actv has not been limited by at least 1GB (' + convert(nvarchar(20), (@save_memory/2)) + ' available)')
	   end
	Else If @save_memory < 4096
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'warning', 'memory on this actv\actv server is less than 4GB')
	   end
	Else If @save_SQLmax_memory_int < ((@save_memory-4608)/2)
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'fail', 'max memory for actv\actv is more than 2GB below available memory (' + convert(nvarchar(20), (@save_memory/2)) + ' available)')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'pass', '')
	   end
   end
Else
   begin
	If @save_SQLmax_memory_int > @save_memory
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'fail', 'max memory is greater than the available memory on the server')
	   end
	Else If @save_memory > 5120 and @save_SQLmax_memory_int > (@save_memory - 2048)
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'fail', 'max memory has not been limited by at least 2GB (' + convert(nvarchar(20), @save_memory) + ' available)')
	   end
	Else If @save_memory < 2048
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'warning', 'memory on this server is less than 2GB')
	   end
	Else If @save_SQLmax_memory_int > (@save_memory - 1024)
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'fail', 'max memory has not been limited by at least 1GB (' + convert(nvarchar(20), @save_memory) + ' available)')
	   end
	Else If (@save_memory /1024) -(@save_SQLmax_memory_int/1024 + @save_OSmemory/1024) > 1
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'fail', 'max memory is more than '+ CAST(@save_OSmemory/1024 AS VarChar(50)) + 'GB below available memory (' + convert(nvarchar(20), @save_memory) + ' available)')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SQLmax_memory', @save_SQLmax_memory, 'pass', '')
	   end
   end


------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start check lock pages in memory setting
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start check lock pages in memory setting')


Select @save_SQLSvcAcct = (select top 1 SQLSvcAcct from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
Select @cmd = 'whoami /user'

delete from #miscTempTable
insert into #miscTempTable exec master.sys.xp_cmdshell @cmd--, no_output 
delete from #miscTempTable where cmdoutput is null
delete from #miscTempTable where cmdoutput not like '%' + @save_SQLSvcAcct + '%'
Select TOP 1 @cmd=cmdoutput FROM #miscTempTable
--Print '		'+@cmd
--select * from #miscTempTable

Select @save_svcsid = (Select top 1 cmdoutput from #miscTempTable)
Select @save_svcsid = rtrim(ltrim(@save_svcsid))
Select @charpos = charindex(' ', @save_svcsid)
IF @charpos <> 0
   begin
	Select @save_svcsid = substring(@save_svcsid, @charpos+1, len(@save_svcsid)-@charpos)
   end
Select @save_svcsid = rtrim(ltrim(@save_svcsid))


--Select @cmd = 'insert into #seceditTempTable (secedit_data) select line from dbo.dbaudf_FileAccess_Read (''c:'', ''sql_healthcheck_secedit.INF'')'
select @cmd = 'type c:\sql_healthcheck_secedit.INF'
--Print '		'+@cmd
delete from #seceditTempTable
--insert into #seceditTempTable (secedit_data) select line from dbo.dbaudf_FileAccess_Read ('c:', 'sql_healthcheck_secedit.INF')
insert into #seceditTempTable (secedit_data) exec master.sys.xp_cmdshell @cmd
delete from #seceditTempTable where secedit_data is null
--delete from #seceditTempTable where secedit_data not like '%LockMemoryPrivilege%'
--select * from #seceditTempTable

If exists (select 1 from #seceditTempTable where secedit_data like '%LockMemoryPrivilege%')
   begin
	Select @save_secedit_id = (select top 1 secedit_id from #seceditTempTable where secedit_data like '%LockMemoryPrivilege%')
	Select @save_secedit_data = (select secedit_data from #seceditTempTable where secedit_id = @save_secedit_id)

	start_LockMemoryPrivilege:
	
	Select @save_secedit_id = @save_secedit_id + 1
	Select @save_secedit_hold = (select secedit_data from #seceditTempTable where secedit_id = @save_secedit_id)
	If @save_secedit_hold <> '' and @save_secedit_hold is not null and @save_secedit_hold not like 'Se%'
	   begin
		Select @save_secedit_data = @save_secedit_data + @save_secedit_hold
		goto start_LockMemoryPrivilege
	   end


	If exists (select 1 from #seceditTempTable where secedit_data like '%' + @save_svcsid + '%')
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('LockMemoryPrivilege', 'LockMemoryPrivilege granted', 'pass', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('LockMemoryPrivilege', 'LockMemoryPrivilege granted', 'warning', 'LockMemoryPrivilege needs to be granted for the current SQL service account.')
	   end
   end
Else
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('LockMemoryPrivilege', 'LockMemoryPrivilege granted', 'fail', 'LockMemoryPrivilege not found in the secedit output file.')
   end


------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start verify service account and local admin permissions
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start verify service account and local admin permissions')

--Select @cmd = 'insert into #seceditTempTable (secedit_data) select line from dbo.dbaudf_FileAccess_Read (''c:'', ''sql_healthcheck_secedit.INF'')'
select @cmd = 'type c:\sql_healthcheck_secedit.INF'
--Print '		'+@cmd
delete from #seceditTempTable
--insert into #seceditTempTable (secedit_data) select line from dbo.dbaudf_FileAccess_Read ('c:', 'sql_healthcheck_secedit.INF')
insert into #seceditTempTable (secedit_data) exec master.sys.xp_cmdshell @cmd
delete from #seceditTempTable where secedit_data is null
--delete from #seceditTempTable where secedit_data not like '%ServiceLogonRight%'
--select * from #seceditTempTable

If exists (select 1 from #seceditTempTable where secedit_data like '%ServiceLogonRight%')
   begin
	Select @save_secedit_id = (select top 1 secedit_id from #seceditTempTable where secedit_data like '%ServiceLogonRight%')
	Select @save_secedit_data = (select secedit_data from #seceditTempTable where secedit_id = @save_secedit_id)

	start_ServiceLogonRight:
	
	Select @save_secedit_id = @save_secedit_id + 1
	Select @save_secedit_hold = (select secedit_data from #seceditTempTable where secedit_id = @save_secedit_id)
	If @save_secedit_hold <> '' and @save_secedit_hold is not null and @save_secedit_hold not like 'Se%'
	   begin
		Select @save_secedit_data = @save_secedit_data + @save_secedit_hold
		goto start_ServiceLogonRight
	   end


	If exists (select 1 from #seceditTempTable where secedit_data like '%' + @save_svcsid + '%')
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('ServiceLogonRight', 'ServiceLogonRight granted', 'pass', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('ServiceLogonRight', 'ServiceLogonRight granted', 'warning', 'ServiceLogonRight may not be granted for the current SQL service account.')
	   end
   end
Else
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('ServiceLogonRight', 'ServiceLogonRight granted', 'fail', 'ServiceLogonRight not found in the secedit output file.')
   end




Select @cmd = 'local administrators \\' + @save_servername
--Print '		'+@cmd
delete from #miscTempTable
insert into #miscTempTable exec master.sys.xp_cmdshell @cmd--, no_output 
delete from #miscTempTable where cmdoutput is null
--select * from #miscTempTable

Select @save_DomainName = (select top 1 DomainName from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
Select @cmd = 'showgrps ' + @save_DomainName + '\' + @save_SQLSvcAcct
--Print '		'+@cmd
delete from #showgrps
insert into #showgrps exec master.sys.xp_cmdshell @cmd--, no_output 
delete from #showgrps where cmdoutput is null
delete from #showgrps where cmdoutput like '%is a member of%'
delete from #showgrps where cmdoutput like '%everyone%'
Update #showgrps set cmdoutput = ltrim(rtrim(cmdoutput)) 
--select * from #showgrps

If exists (select 1 from #miscTempTable where cmdoutput like '%' + @save_SQLSvcAcct + '%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAccount_LocalAdmin', 'verified', 'pass', '')
   end
Else If exists (select 1 from #miscTempTable l, #showgrps s where l.cmdoutput = s.cmdoutput)
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAccount_LocalAdmin', 'verified via group', 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAccount_LocalAdmin', @save_SQLSvcAcct, 'fail', 'Service account not found in local admin group')
   end

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start verify sql services set properly
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start verify sql services set properly')

Select @cmd = 'sc query state= all'
--Print '		'+@cmd
delete from #scTempTable
insert into #scTempTable exec master.sys.xp_cmdshell @cmd--, no_output 
delete from #scTempTable where sc_data is null
delete from #scTempTable where sc_data not like '%service[_]name%'
delete from #scTempTable where sc_data not like '% mssql%' and sc_data not like '% sql%'
--select * from #scTempTable

If (select count(*) from #scTempTable) > 0
   begin
	start_sctemp:
	Select @save_sc_data = (select top 1 sc_data from #scTempTable order by sc_data)
	Select @save_sc_data_part = replace(@save_sc_data, 'SERVICE_NAME:', '')
	Select @save_sc_data_part = rtrim(ltrim(@save_sc_data_part))

	Select @cmd = 'sc qc ' + @save_sc_data_part + ' 2048'
	--Print '		'+@cmd
	delete from #scTempTable2
	insert into #scTempTable2 exec master.sys.xp_cmdshell @cmd--, no_output 
	delete from #scTempTable2 where sc_data is null
	--select * from #scTempTable2
	
	Select @save_start_type = (select top 1 sc_data from #scTempTable2 where sc_data like '%START_TYPE%')
	Select @save_start_type = replace(@save_start_type, 'START_TYPE', '')
	Select @save_start_type = replace(@save_start_type, ':', '')
	Select @save_start_type = replace(@save_start_type, ' ', '')
	Select @save_start_type = rtrim(ltrim(@save_start_type))
	
	Select @save_display_name = (select top 1 sc_data from #scTempTable2 where sc_data like '%DISPLAY_NAME%')
	Select @save_display_name = replace(@save_display_name, 'DISPLAY_NAME', '')
	Select @save_display_name = replace(@save_display_name, ':', '')
	Select @save_display_name = rtrim(ltrim(@save_display_name))

	Select @save_SERVICE_START_NAME = (select top 1 sc_data from #scTempTable2 where sc_data like '%SERVICE_START_NAME%')
	Select @save_SERVICE_START_NAME = replace(@save_SERVICE_START_NAME, 'SERVICE_START_NAME', '')
	Select @save_SERVICE_START_NAME = replace(@save_SERVICE_START_NAME, ':', '')
	Select @save_SERVICE_START_NAME = rtrim(ltrim(@save_SERVICE_START_NAME))

	Select @cmd = 'sc query ' + @save_sc_data_part
	--Print '		'+@cmd
	delete from #miscTempTable
	insert into #miscTempTable exec master.sys.xp_cmdshell @cmd--, no_output 
	delete from #miscTempTable where cmdoutput is null
	delete from #miscTempTable where cmdoutput not like '%state%'
	--select * from #miscTempTable
	
	Select @save_svc_state = (select top 1 cmdoutput from #miscTempTable where cmdoutput like '%STATE%')
	Select @save_svc_state = replace(@save_svc_state, 'STATE', '')
	Select @save_svc_state = replace(@save_svc_state, ':', '')
	Select @save_svc_state = replace(@save_svc_state, ' ', '')
	Select @save_svc_state = rtrim(ltrim(@save_svc_state))

	If @save_sc_data_part like '%MSSQLServerAD%'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'pass', '')
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'pass', '')
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'pass', '')
	   end
	Else If @save_sc_data_part like '%MSSQLFDLauncher%' 
	   begin
		--  check running
		If @save_iscluster = 'y'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'na', 'see cluster resource info')
		   end
		Else If @save_svc_state like '%running%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'fail', '')
		   end
		   
		   
		--  Auto Start
		If @save_iscluster = 'y'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'na', 'see cluster resource info')
		   end
		Else If @save_start_type like '%DEMAND_START%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'fail', '')
		   end
		   
		   
		--  Svc Account
		If (select OSname from dbo.DBA_serverinfo where sqlname = @@servername) like '%Server 2003%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'warning', 'low-privileged local user account should be used for this.')
		   end
		Else If @save_SERVICE_START_NAME like '%local%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'fail', '')
		   end   
	   end

	Else If @save_sc_data_part like '%SQLEXPRESS%' 
	   begin
		--  Show status
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'pass', '')
		   
		   
		--  show start parm
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'pass', '')

		   
		--  Show Svc Account
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'pass', '')
  
	   end

	Else If @save_sc_data_part like '%MSSQL%' 
	   or @save_sc_data_part like '%SQLSERVERAGENT%'
	   or @save_sc_data_part like '%SQLAGENT%'
	   begin
		--  If this is a SQL named instance, make sure we are checking the right service
		If @@servicename <> 'MSSQLSERVER' and @save_sc_data_part not like '%$' + @@servicename + '%' 
		   begin
			goto skip_svc
		   end

		--  check running
		If @save_iscluster = 'y'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'na', 'see cluster resource info')
		   end
		Else If @save_svc_state like '%running%'
    		 begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'fail', '')
		   end
		   
		   
		--  Auto Start
		If @save_iscluster = 'y'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'na', 'see cluster resource info')
		   end
		Else If @save_start_type like '%AUTO_START%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'fail', '')
		   end
		   
		   
		--  Svc Account
		If @save_SERVICE_START_NAME like '%SQLadmin%' or @save_SERVICE_START_NAME like '%RoyaltyDatabase%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'fail', '')
		   end   
	   end
	Else If @save_sc_data_part like '%SQLBrowser%'
	   begin
		--  check running
		If @save_svc_state like '%running%' or (select count(*) from dbo.Local_ServerEnviro where env_type = 'SQL Port' and env_detail = '1433') > 0
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'fail', '')
		   end
		   
		   
		--  Auto Start
		If @save_start_type like '%AUTO_START%' or (select count(*) from dbo.Local_ServerEnviro where env_type = 'SQL Port' and env_detail = '1433') > 0
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'fail', '')
		   end
		   
		   
		--  Svc Account
		If @save_SERVICE_START_NAME like '%SQLadmin%' 
		   or @save_SERVICE_START_NAME like '%RoyaltyDatabase%' 
		   or @save_SERVICE_START_NAME like '%LOCALSERVICE%' 
		   or (select count(*) from dbo.Local_ServerEnviro where env_type = 'SQL Port' and env_detail = '1433') > 0
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'fail', '')
		   end   
	   end
	Else If @save_sc_data_part like '%SQLdm%'
	   begin
		--  check running
		If @save_svc_state like '%running%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'fail', '')
		   end
		   
		   
		--  Auto Start
		If @save_start_type like '%AUTO_START%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'fail', '')
		   end
		   
		   
		--  Svc Account
		If @save_SERVICE_START_NAME like '%SQLadmin%' or @save_SERVICE_START_NAME like '%RoyaltyDatabase%' 
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'fail', '')
		   end   
	   end
	Else If @save_sc_data_part like '%SQLWriter%'
	   begin
		--  check running
		If @save_svc_state like '%running%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'fail', '')
		   end
		   
		   
		--  Auto Start
		If @save_start_type like '%AUTO_START%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'fail', '')
		   end
		   
		   
		--  Svc Account
		If @save_SERVICE_START_NAME like '%Local%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'fail', '')
		   end
	   end
	Else If @save_sc_data_part like '%SQLBackupAgent%'
	   begin
		--  If this is a SQL named instance, make sure we are checking the right service
		If @@servicename <> 'MSSQLSERVER' and @save_sc_data_part <> 'SQLBackupAgent_' + @@servicename 
		   begin
			goto skip_svc
		   end

		Select @save_Redgate_flag = 'y'
		
		--  check running
		If @save_iscluster = 'y'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'na', 'see cluster resource info')
		   end
		Else If @save_svc_state like '%running%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcState_' + @save_sc_data_part, @save_svc_state, 'fail', '')
		   end
		   
		   
		--  Auto Start
		If @save_iscluster = 'y'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'na', 'see cluster resource info')
		   end
		Else If @save_start_type like '%AUTO_START%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcStartType_' + @save_sc_data_part, @save_start_type, 'fail', '')
		   end
		   
		   
		--  Svc Account
		If @save_SERVICE_START_NAME like '%SQLadmin%' or @save_SERVICE_START_NAME like '%RoyaltyDatabase%'
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'pass', '')
		   end
		Else
    		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_' + @save_sc_data_part, @save_SERVICE_START_NAME, 'fail', '')
		   end   
	   end
	Else
	   begin
   		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('SvcAcct_error' + @save_sc_data_part, 'Unknown service found', 'fail', 'no code to process this server at this time')
	   end

	skip_svc:

	Delete from #scTempTable where sc_data = @save_sc_data
	If (select count(*) from #scTempTable) > 0
	   begin
		goto start_sctemp
	   end

   end

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start verify master DB settings
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start verify master DB settings')

Select @save_DB_owner = (select suser_sname(owner_sid) from master.sys.databases with (NOLOCK) where name = 'master')
If @save_DB_owner = 'sa'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('master_owner', @save_DB_owner, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('master_owner', @save_DB_owner, 'fail', 'master owner should be "sa"')
   end


Select @save_RecoveryModel = (select recovery_model_desc from master.sys.databases with (NOLOCK) where name = 'master')
If @save_RecoveryModel = 'SIMPLE'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('master_RecoveryModel', @save_RecoveryModel, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('master_RecoveryModel', @save_RecoveryModel, 'fail', 'master recovery model should be SIMPLE')
   end
   


------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start login and security config
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start login and security config')

--  verify security audit level set to 'failure' (self heal)
insert into #loginconfig exec master.sys.xp_loginconfig
delete from #loginconfig where name is null
--select * from #loginconfig

Select @save_loginmode = (select configvalue from #loginconfig where name = 'login mode')
If @save_loginmode is null
   begin
	Select @save_loginmode = 'unknown'
   end
   
If  @save_loginmode = 'Mixed'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Security_loginmode', @save_loginmode, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Security_loginmode', @save_loginmode, 'warning', '')
   end

Select @save_auditlevel = (select configvalue from #loginconfig where name = 'audit level')
If @save_auditlevel is null
   begin
	Select @save_auditlevel = 'unknown'
   end
   
If  @save_auditlevel = 'failure'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Security_auditlevel', @save_auditlevel, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Security_auditlevel', @save_auditlevel, 'warning', '')
   end

   
------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Verify TempDB DB
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Verify TempDB DB')


Select @save_DB_owner = (select suser_sname(owner_sid) from master.sys.databases with (NOLOCK) where name = 'tempdb')
If @save_DB_owner = 'sa'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Tempdb_owner', @save_DB_owner, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Tempdb_owner', @save_DB_owner, 'fail', 'Tempdb owner should be "sa"')
   end


If exists(select 1 from tempdb.sys.sysusers with (NOLOCK) where name = 'guest' and status = 0 and hasdbaccess = 1)
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Tempdb_guest', 'verified', 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Tempdb_guest', '', 'fail', 'The guest needs to have access to Tempdb')
   end


Select @save_RecoveryModel = (select recovery_model_desc from master.sys.databases with (NOLOCK) where name = 'tempdb')
If @save_RecoveryModel = 'SIMPLE'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Tempdb_RecoveryModel', @save_RecoveryModel, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Tempdb_RecoveryModel', @save_RecoveryModel, 'fail', 'Tempdb recovery model should be SIMPLE')
   end


--  Get the system DB path
Select @save_master_filepath = (select filename from master.sys.sysfiles with (NOLOCK) where fileid = 1)
Select @save_master_filepath = reverse(@save_master_filepath)
Select @charpos = charindex('\', @save_master_filepath)
IF @charpos <> 0
   begin
	Select @save_master_filepath = substring(@save_master_filepath, @charpos+1, len(@save_master_filepath))
   end
Select @save_master_filepath = reverse(@save_master_filepath)

--  Get the tempdb drive letter
Select @save_tempdb_filedrive = (select physical_name from tempdb.sys.database_files with (NOLOCK) where file_id = 1)
Select @charpos = charindex('\', @save_tempdb_filedrive)
IF @charpos <> 0
   begin
	Select @save_tempdb_filedrive = left(@save_tempdb_filedrive, @charpos) + '%'
   end



If exists(select 1 from tempdb.sys.sysfiles with (NOLOCK) where groupid <> 0 and filename like @save_master_filepath + '%')
   begin
 	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Tempdb_location', 'Tempdb has not been moved from the original install path', 'pass', '')  
   end
Else If (select count(*) from master.sys.master_files
	where name not in (select name from tempdb.sys.database_files)
	and Physical_name like @save_tempdb_filedrive) = 0
   begin
	Select @save_tempdb_filecount = (select tempdb_filecount from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
	Select @save_tempdb_corecount = (select CPUcore from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername)
	Select @save_tempdb_corecount = replace(@save_tempdb_corecount, 'core(s)', '')
	Select @save_tempdb_corecount = replace(@save_tempdb_corecount, 'cores', '')
	Select @save_tempdb_corecount = replace(@save_tempdb_corecount, 'core', '')
	Select @save_tempdb_corecount = rtrim(ltrim(@save_tempdb_corecount))
	
	If exists (select 1 from dbo.no_check where NoCheck_type = 'SQLHealth' and detail01 = 'TempDB_FileCount')
   begin
	Select @save_tempdb_corecount = (select convert(int, detail03) from dbo.no_check where NoCheck_type = 'SQLHealth' and detail01 = 'TempDB_FileCount')
   end
	
	If exists(select 1 from dbo.dba_serverinfo with (NOLOCK) where sqlname = @@servername and convert(int, rtrim(@save_tempdb_filecount)) < convert(int, rtrim(@save_tempdb_corecount)))
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Tempdb_filecount', @save_tempdb_filecount, 'fail', 'Tempdb file count is less than the CPU core count')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Tempdb_filecount', @save_tempdb_filecount, 'pass', '')
	   end
   end
Else
   begin
 	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Tempdb_location', 'Tempdb has not been moved from the original install path', 'pass', '')  
   end


------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Verify MSDB DB
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Verify MSDB DB')

Select @save_DB_owner = (select suser_sname(owner_sid) from master.sys.databases with (NOLOCK) where name = 'msdb')
If @save_DB_owner = 'sa'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('msdb_owner', @save_DB_owner, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('msdb_owner', @save_DB_owner, 'fail', 'msdb owner should be "sa"')
   end


Select @save_RecoveryModel = (select recovery_model_desc from master.sys.databases with (NOLOCK) where name = 'msdb')
If @save_RecoveryModel = 'SIMPLE'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('msdb_RecoveryModel', @save_RecoveryModel, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('msdb_RecoveryModel', @save_RecoveryModel, 'fail', 'msdb recovery model should be SIMPLE')
   end

----------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------
--
--									AGENT JOB SYSTEM CHECKS
--
----------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------

---sqlagent history max set above 1000, 100 (self heal)
EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
                                       N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',
                                       N'JobHistoryMaxRows',
                                       @jobhistory_max_rows OUTPUT,
                                       N'no_output'
EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
                                       N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',
                                       N'JobHistoryMaxRowsPerJob',
                                       @jobhistory_max_rows_per_job OUTPUT,
                                       N'no_output'

If @jobhistory_max_rows < 1001
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('msdb_jobhistory_maxrows', convert(nvarchar(10), @jobhistory_max_rows), 'fail', 'jobhistory maxrows must be at least 10000')
   end
Else If @jobhistory_max_rows < 5000
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('msdb_jobhistory_maxrows', convert(nvarchar(10), @jobhistory_max_rows), 'warning', 'jobhistory maxrows is suggested to be 50000')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('msdb_jobhistory_maxrows', convert(nvarchar(10), @jobhistory_max_rows), 'pass', '')
   end

If @jobhistory_max_rows_per_job < 101
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('msdb_jobhistory_maxrowsperjob', convert(nvarchar(10), @jobhistory_max_rows_per_job), 'fail', 'jobhistory maxrows/job must be at least 1000')
   end
Else If @jobhistory_max_rows_per_job < 500
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('msdb_jobhistory_maxrowsperjob', convert(nvarchar(10), @jobhistory_max_rows_per_job), 'warning', 'jobhistory maxrows/job is suggested to be 5000')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('msdb_jobhistory_maxrowsperjob', convert(nvarchar(10), @jobhistory_max_rows_per_job), 'pass', '')
   end

;WITH		StandardJobs
			AS
			(
			SELECT	'MAINT - Daily Backup and DBCC' [JobName]			-- DO I REALLY NEED TO EXPLAIN THIS?
					,24								[HrsBetweenRuns]	-- IF NOT RUN FOR X HOURS JOB IS IN ERROR. -- 24=DAY 168=WEEK 744=MONTH
					,0								[Can_NotScheduled]	-- JOB DOES NOT NEED TO BE SCHEDULED OR ENABLED.
					,0								[Must_NotScheduled]	-- JOB SHOULD NOT BE SCHEDULED OR ENABLED.
			UNION ALL
			SELECT	'MAINT - Daily Index Maintenance'			,24,0,0		UNION ALL
			SELECT	'MAINT - TranLog Backup'					,24,1,0		UNION ALL
			SELECT	'MAINT - Weekly Backup and DBCC'			,168,0,0	UNION ALL
			SELECT	'MON - SQL Performance Reporting'			,168,0,0	UNION ALL
			SELECT	'UTIL - DBA Archive process'				,24,0,0		UNION ALL
			SELECT	'UTIL - DBA Check Misc process'				,24,0,0		UNION ALL
			SELECT	'UTIL - DBA Check Periodic'					,24,0,0		UNION ALL
			SELECT	'UTIL - DBA Errorlog Check'					,24,0,0		UNION ALL
			SELECT	'UTIL - DBA Log Parser'						,24,0,0		UNION ALL
			SELECT	'UTIL - DBA Nightly Processing'				,24,0,0		UNION ALL
			SELECT	'UTIL - DBA Update Files'					,24,0,0		UNION ALL
			SELECT	'UTIL - SQLTrace Process'					,24,1,0		UNION ALL
			SELECT	'UTIL - SQLTrace (Critical Response)'		,0,0,1
			)
			,NoCheckJobs
			AS
			(
			 SELECT		[detail02]		AS JobName
						,[detail03]*24	AS [HrsBetweenRuns]
			 FROM		dbaadmin.dbo.no_check 
			 where		NoCheck_type	= 'SQLHealth' 
					and	detail01		= 'SQLjob'
			)
INSERT INTO #temp_results 
	OUTPUT	'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO	@OutputComments
			
SELECT		CAST([subject01] AS VarChar(max))
			,CAST([value01] AS VarChar(max))
			,CAST(CASE WHEN [notes01] IS NULL THEN 'Pass' ELSE 'Fail' END  AS VarChar(max))
			,CAST(COALESCE([notes01],'')  AS VarChar(max))
FROM		(			
			SELECT		'SQLAgent Standard Job' [subject01] 
						,T1.JobName [value01]
						,CASE	WHEN	T2.JobName IS Null							THEN 'Standard Job ['+ T1.JobName + '] Does Not Exist.'
								WHEN	T2.Enabled = 0 
										AND T1.[Can_NotScheduled] = 0 
										AND T1.[Must_NotScheduled] = 0				THEN 'Standard Job ['+ T1.JobName + '] Is Disabled.'
								WHEN	T2.Schedules = 0 
										AND T1.[Can_NotScheduled] = 0 
										AND T1.[Must_NotScheduled] = 0				THEN 'Standard Job ['+ T1.JobName + '] Is Not Scheduled.'
								WHEN	T2.Enabled = 1 
										AND T1.[Must_NotScheduled] = 1				THEN 'Standard Job ['+ T1.JobName + '] Is Enabled and Should Not Be.'
								--WHEN	T2.Schedules > 0 
								--		AND T1.[Must_NotScheduled] = 1				THEN 'Standard Job ['+ T1.JobName + '] Is Scheduled and Should Not Be.'
								WHEN	T2.EnabledSchedules = 0 
										AND T1.[Can_NotScheduled] = 0 
										AND T1.[Must_NotScheduled] = 0				THEN 'Standard Job ['+ T1.JobName + '] Has It''s Schedule Disabled.'
								WHEN	T2.LastRun IS NULL	
										AND T2.next_scheduled_run_date < GetDate()
										AND T1.[Can_NotScheduled] = 0 
										AND T1.[Must_NotScheduled] = 0				THEN 'Standard Job ['+ T1.JobName + '] Has Not Run.  Next Run Date Is In The Past.'
								WHEN	T2.LastRun IS NULL
										AND T1.[Can_NotScheduled] = 0 
										AND T1.[Must_NotScheduled] = 0				THEN 'Standard Job ['+ T1.JobName + '] Has Never Run.'
								WHEN	DATEDIFF(hour,T2.LastRun,GetDate()) 
										> COALESCE(NCJ.[HrsBetweenRuns],T1.[HrsBetweenRuns])
										AND T1.[Can_NotScheduled] = 0 
										AND T1.[Must_NotScheduled] = 0				THEN 'Standard Job ['+ T1.JobName + '] Has Not Run In Over ' + CAST(DATEDIFF(hour,T2.LastRun,GetDate()) AS VarChar(10)) + ' Hours'
								END AS  [notes01]
			FROM		StandardJobs T1
			LEFT JOIN	@JobStatusResults T2
					ON	T1.JobName = T2.JobName
			LEFT JOIN	NoCheckJobs NCJ
					ON	NCJ.JobName = T1.JobName
					
			) JobStatusResults

UNION ALL			

SELECT		'SQLAgent Generic Job'			AS [subject01] 
			,JobName						AS [value01]
			,[Level]						AS [grade01]
			,CAST([Alert] AS VarChar(max))	AS [notes01]
FROM		(
			SELECT		'warning' AS [Level]
						,JobName
						,'The Job "'
						+JobName
						+'" has run longer or shorter than expected '+CAST(OutliersToday AS VarChar(10))+' times Today.'  AS [Alert]
			From		@JobStatusResults			
			WHERE		Enabled = 1 AND COALESCE(OutliersToday,0) > 0 AND LastStatus = 1	
			UNION ALL

			SELECT		CASE WHEN [FailuresToday] > [CurrentCount] THEN 'fail' ELSE	
						'warning' END AS [Level]
						,JobName
						,'The Job "'
						+JobName
						+'" has Failed '+CAST(FailuresToday AS VarChar(10))+' times Today.'  AS [Alert]
			From		@JobStatusResults			
			WHERE		Enabled = 1 AND COALESCE(FailuresToday,0) > 0 AND LastStatus = 1
			UNION ALL

			SELECT		'fail' AS [Level]
						,JobName
						,'The Job "'
						+JobName
						+'" last execution on "'+CAST(LastRun AS VarChar(50))+'" Failed' 
						+ CASE WHEN CurrentCount > 1 THEN ', and has Failed ' +CAST(CurrentCount AS VarChar(5))+ ' times in a row.' ELSE '.' END AS [Alert]
			From		@JobStatusResults			
			WHERE		Enabled = 1 AND LastStatus = 0	
			UNION ALL
						
			SELECT		'warning' AS [Level]
						,JobName
						,'The Job "'
						+JobName
						+'" is owned by "'+OwnerName+'" rather than "SA".' AS [Alert]
			From		@JobStatusResults			
			WHERE		Enabled = 1 AND OwnerName != 'sa'	
			UNION ALL
			
			
			SELECT		'warning' AS [Level]
						,(SELECT name from msdb..sysjobs where job_id = T1.job_id)
						,'The Job "'
						+(SELECT name from msdb..sysjobs where job_id = T1.job_id)
						+'" (step '+ Cast(step_id AS VarChar(5)) +') "'
						+step_name
						+'" Points to Database "'+database_name+'" rather than Master.' AS [Alert]
			FROM		msdb..sysjobsteps T1
			JOIN		msdb..sysjobs T2
					ON	T1.job_id = T2.job_id
			WHERE		Enabled = 1 AND database_name != 'master'			

			UNION ALL
			SELECT		'fail' AS [Level]
						,(SELECT name from msdb..sysjobs where job_id = T1.job_id)
						,'The Job "'
						+(SELECT name from msdb..sysjobs where job_id = T1.job_id)
						+'" (step '+ Cast(step_id AS VarChar(5)) +') "'
						+step_name
						+'" Does not have an output log.' AS [Alert]
			FROM		msdb..sysjobsteps T1
			JOIN		msdb..sysjobs T2
					ON	T1.job_id = T2.job_id
			WHERE		Enabled = 1 AND nullif(output_file_name,'') IS NULL
						
			UNION ALL
			SELECT		'warning' AS [Level]
						,(SELECT name from msdb..sysjobs where job_id = T1.job_id)
						,'The Job "'
						+(SELECT name from msdb..sysjobs where job_id = T1.job_id)
						+'" (step '+ Cast(step_id AS VarChar(5)) +') "'
						+step_name
						+'" Output Log File points to "'+output_file_name+'" to the "SQLjob_logs" share.' AS [Alert]
			FROM		msdb..sysjobsteps T1
			JOIN		msdb..sysjobs T2
					ON	T1.job_id = T2.job_id
			WHERE		Enabled = 1 AND output_file_name NOT LIKE @JobLog_Share_Path +'%'	
					AND	output_file_name NOT LIKE '\\'+CAST(SERVERPROPERTY('machinename')AS VarChar(50))+'\'+@JobLog_Share_Name +'\%'	
									
			UNION ALL
			SELECT		'warning' AS [Level]
						,(SELECT name from msdb..sysjobs where job_id = T1.job_id)
						,'The Job "'
						+(SELECT name from msdb..sysjobs where job_id = T1.job_id)
						+'" (step '+ Cast(step_id AS VarChar(5)) +') "'
						+step_name
						+'" Output Log File is set to Overwrite instead of Append.' AS [Alert]
			FROM		msdb..sysjobsteps T1
			JOIN		msdb..sysjobs T2
					ON	T1.job_id = T2.job_id
			WHERE		T2.Enabled = 1 AND flags & 2 != 2		

			UNION ALL
			SELECT		'warning' AS [Level]
						,(SELECT name from msdb..sysjobs where job_id = T1.job_id)
						,'The Job "'
						+(SELECT name from msdb..sysjobs where job_id = T1.job_id)
						+'" (step '+ Cast(step_id AS VarChar(5)) +') "'
						+step_name
						+'" Output Log File does not include job step output.' AS [Alert]
			FROM		msdb..sysjobsteps T1
			JOIN		msdb..sysjobs T2
					ON	T1.job_id = T2.job_id
			WHERE		T2.Enabled = 1 AND flags & 4 != 4
			) Alerts

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Verify DBAPerf DB
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Verify DBAPerf DB')

If (SELECT PATINDEX( '%[8].[00]%', @@version ) ) <> 0
   begin
	goto Skip_dbaperf
   end
   
If not exists (select 1 from master.sys.databases with (NOLOCK) where name = 'dbaperf')
 begin   
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf', '', 'fail', 'The dbaperf DB does not exist')
   end
Else
   begin
   	Select @save_status = (select state_desc from master.sys.databases with (NOLOCK) where name = 'dbaperf')

	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf', @save_status, 'pass', '')
   end

Select @save_DB_owner = (select suser_sname(owner_sid) from master.sys.databases with (NOLOCK) where name = 'dbaperf')
If @save_DB_owner = 'sa'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_owner', @save_DB_owner, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_owner', @save_DB_owner, 'fail', 'dbaperf owner should be "sa"')
   end


Select @save_RecoveryModel = (select recovery_model_desc from master.sys.databases with (NOLOCK) where name = 'dbaperf')
If @save_RecoveryModel = 'SIMPLE'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_RecoveryModel', @save_RecoveryModel, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_RecoveryModel', @save_RecoveryModel, 'fail', 'dbaperf recovery model should be SIMPLE')
   end
   
   
Select @save_job_id = (select job_id from msdb.dbo.sysjobs with (NOLOCK) where name = 'UTIL - PERF Check Non-Use') 
Select @save_lastrun = (select last_run_date from @xp_results where job_id = @save_job_id)
If not exists (select 1 from msdb.dbo.sysjobs with (NOLOCK) where name = 'UTIL - PERF Check Non-Use')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfCheckNonUse', 'UTIL - PERF Check Non-Use', 'fail', 'Standard SQL perf job not found')
   end
Else
   begin
	If (select enabled from msdb.dbo.sysjobs with (NOLOCK) where name = 'UTIL - PERF Check Non-Use')= 0
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfCheckNonUse', 'UTIL - PERF Check Non-Use', 'fail', 'Job disabled in production')
	   end
	Else If @save_lastrun = 0
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfCheckNonUse', 'UTIL - PERF Check Non-Use', 'fail', 'Job has never run in production')
	   end
	Else If @save_lastrun < convert(int, convert(char(08), @CheckDate-1, 112))
	   begin
		Select @save_next_run_date = (select top 1 ja.next_scheduled_run_date from msdb.dbo.sysjobactivity ja, msdb.dbo.sysjobs j
						where ja.job_id = j.job_id
						and j.name = 'UTIL - PERF Check Non-Use'
						and ja.next_scheduled_run_date is not null
						order by ja.next_scheduled_run_date desc)
		If @save_next_run_date is not null and @save_next_run_date < @CheckDate
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfCheckNonUse', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'fail', 'Job has not run.  Next run date is in the past.')
		   end
		Else
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfCheckNonUse', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'fail', 'Job has not run in the past day')
		   end
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfCheckNonUse', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'pass', '')
	   end
   end   
   
   
Select @save_job_id = (select job_id from msdb.dbo.sysjobs with (NOLOCK) where name = 'UTIL - PERF Stat Capture Process') 
Select @save_lastrun = (select last_run_date from @xp_results where job_id = @save_job_id)
If not exists (select 1 from msdb.dbo.sysjobs with (NOLOCK) where name = 'UTIL - PERF Stat Capture Process')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfStatCaptureProcess', 'UTIL - PERF Stat Capture Process', 'fail', 'Standard SQL perf job not found')
   end
Else
   begin
	If (select enabled from msdb.dbo.sysjobs with (NOLOCK) where name = 'UTIL - PERF Stat Capture Process')= 0
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfStatCaptureProcess', 'UTIL - PERF Stat Capture Process', 'fail', 'Job disabled in production')
	   end
	Else If @save_lastrun = 0
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfStatCaptureProcess', 'UTIL - PERF Stat Capture Process', 'fail', 'Job has never run in production')
	   end
	Else If @save_lastrun < convert(int, convert(char(08), @CheckDate-1, 112))
	   begin
		Select @save_next_run_date = (select top 1 ja.next_scheduled_run_date from msdb.dbo.sysjobactivity ja, msdb.dbo.sysjobs j
						where ja.job_id = j.job_id
						and j.name = 'UTIL - PERF Stat Capture Process'
						and ja.next_scheduled_run_date is not null
						order by ja.next_scheduled_run_date desc)
		If @save_next_run_date is not null and @save_next_run_date < @CheckDate
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfStatCaptureProcess', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'fail', 'Job has not run.  Next run date is in the past.')
		   end
		Else
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfStatCaptureProcess', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'fail', 'Job has not run in the past day')
		   end
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfStatCaptureProcess', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'pass', '')
	   end
   end    
   
   
Select @save_job_id = (select job_id from msdb.dbo.sysjobs with (NOLOCK) where name = 'UTIL - PERF Weekly Processing') 
Select @save_lastrun = (select last_run_date from @xp_results where job_id = @save_job_id)
If not exists (select 1 from msdb.dbo.sysjobs with (NOLOCK) where name = 'UTIL - PERF Weekly Processing')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfWeekly Processing', 'UTIL - PERF Weekly Processing', 'fail', 'Standard SQL perf job not found')
   end
Else
   begin
	If (select enabled from msdb.dbo.sysjobs with (NOLOCK) where name = 'UTIL - PERF Weekly Processing')= 0
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfWeekly', 'UTIL - PERF Weekly Processing', 'fail', 'Job disabled in production')
	   end
	Else If @save_lastrun = 0
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfWeekly', 'UTIL - PERF Weekly Processing', 'fail', 'Job has never run in production')
	   end
	Else If @save_lastrun < convert(int, convert(char(08), @CheckDate-8, 112))
	   begin
		Select @save_next_run_date = (select top 1 ja.next_scheduled_run_date from msdb.dbo.sysjobactivity ja, msdb.dbo.sysjobs j
						where ja.job_id = j.job_id
						and j.name = 'UTIL - PERF Weekly Processing'
						and ja.next_scheduled_run_date is not null
						order by ja.next_scheduled_run_date desc)
		If @save_next_run_date is not null and @save_next_run_date < @CheckDate
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfWeekly', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'fail', 'Job has not run.  Next run date is in the past.')
		   end
		Else
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfWeekly', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'fail', 'Job has not run in the past week')
		   end
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('dbaperf_job_UTIL_DBAPerfWeekly', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'pass', '')
	   end
   end       
   

Skip_dbaperf:



------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Verify DEPLInfo DB
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Verify DEPLInfo DB')


If exists (select 1 from dbo.no_check where NoCheck_type = 'DEPL_RD_Skip' and detail01 = 'all')
  and not exists (select 1 from master.sys.databases with (NOLOCK) where name = 'deplinfo')
   begin
	goto Skip_deplinfo
   end


If not exists (select 1 from master.sys.databases with (NOLOCK) where name in (select db_name from db_sequence))
  and not exists (select 1 from master.sys.databases with (NOLOCK) where name = 'deplinfo')
   begin
	goto Skip_deplinfo
   end


deplinfo_start:


If not exists (select 1 from master.sys.databases with (NOLOCK) where name = 'deplinfo')
   begin   
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('deplinfo', '', 'fail', 'The deplinfo DB does not exist')
   end
Else
   begin
   	Select @save_status = (select state_desc from master.sys.databases with (NOLOCK) where name = 'deplinfo')

	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('deplinfo', @save_status, 'pass', '')
   end

Select @save_DB_owner = (select suser_sname(owner_sid) from master.sys.databases with (NOLOCK) where name = 'deplinfo')
If @save_DB_owner = 'sa'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('deplinfo_owner', @save_DB_owner, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('deplinfo_owner', @save_DB_owner, 'fail', 'deplinfo owner should be "sa"')
   end


Select @save_RecoveryModel = (select recovery_model_desc from master.sys.databases with (NOLOCK) where name = 'deplinfo')
If @save_RecoveryModel = 'SIMPLE'
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('deplinfo_RecoveryModel', @save_RecoveryModel, 'pass', '')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('deplinfo_RecoveryModel', @save_RecoveryModel, 'fail', 'deplinfo recovery model should be SIMPLE')
   end



--  If production, skip the sql job stream check
If @save_envname = 'production'
   begin
	goto Skip_deplinfo_jobcheck
   end

--  If no DEPL related DB's exist, skip the sql job stream check
If (select count(*) from dbo.dba_dbinfo where SQLname = @@servername and DEPLstatus = 'y') = 0
   begin
	goto Skip_deplinfo_jobcheck
   end

   
   
Select @save_job_id = (select job_id from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_RD - 00 - Deployment Start') 
Select @save_lastrun = (select last_run_date from @xp_results where job_id = @save_job_id)
If not exists (select 1 from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_RD - 00 - Deployment Start')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_DEPL_RD_00_DeploymentStart', 'DEPL_RD - 00 - Deployment Start', 'fail', 'Standard DEPL_RD job not found')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_DEPL_RD_00_DeploymentStart', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'pass', '')
   end
   
   
Select @save_job_id = (select job_id from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_RD - 01 - Restore') 
Select @save_lastrun = (select last_run_date from @xp_results where job_id = @save_job_id)
If not exists (select 1 from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_RD - 01 - Restore')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_DEPL_RD_01_Restore', 'DEPL_RD - 01 - Restore', 'fail', 'Standard DEPL_RD job not found')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_DEPL_RD_01_Restore', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'pass', '')
   end


Select @save_job_id = (select job_id from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_RD - 51 - SQLDeploy') 
Select @save_lastrun = (select last_run_date from @xp_results where job_id = @save_job_id)
If not exists (select 1 from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_RD - 51 - SQLDeploy')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_DEPL_RD_51_SQLDeploy', 'DEPL_RD - 51 - SQLDeploy', 'fail', 'Standard DEPL_RD job not found')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_DEPL_RD_51_SQLDeploy', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'pass', '')
   end


Select @save_job_id = (select job_id from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_RD - 99 - Deployment End') 
Select @save_lastrun = (select last_run_date from @xp_results where job_id = @save_job_id)
If not exists (select 1 from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_RD - 99 - Deployment End')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_DEPL_RD_99_DeploymentEnd', 'DEPL_RD - 99 - Deployment End', 'fail', 'Standard DEPL_RD job not found')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_DEPL_RD_99_DeploymentEnd', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'pass', '')
   end


Select @save_job_id = (select job_id from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_ahp - SQL Deployment Process') 
Select @save_lastrun = (select last_run_date from @xp_results where job_id = @save_job_id)
If not exists (select 1 from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_ahp - SQL Deployment Process')
   begin
	exec DEPLinfo.dbo.dpsp_ahp_addjob
	Waitfor delay '00:00:05'
   end

If not exists (select 1 from msdb.dbo.sysjobs with (NOLOCK) where name = 'DEPL_ahp - SQL Deployment Process')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_DEPL_ahp_SQL_Deployment_Process', 'DEPL_ahp - SQL Deployment Process', 'fail', 'Standard DEPL_ahp job not found')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_DEPL_ahp_SQL_Deployment_Process', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'pass', '')
   end


Select @save_job_id = (select job_id from msdb.dbo.sysjobs with (NOLOCK) where name = 'BASE - Local Process') 
Select @save_lastrun = (select last_run_date from @xp_results where job_id = @save_job_id)
If not exists (select 1 from msdb.dbo.sysjobs with (NOLOCK) where name = 'BASE - Local Process')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_BASE_LocalProcess', 'BASE - Local Process', 'fail', 'Standard SQL Deployment job not found')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('DEPLinfo_job_BASE_LocalProcess', 'Last run ' + convert(nvarchar(10), @save_lastrun), 'pass', '')
   end




Skip_deplinfo_jobcheck:



Skip_deplinfo:


------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start verify standard shares
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start verify standard shares')



-- backup
Select @save_sharename = @save_servername2 + '_backup'
exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
If @share_outpath is null
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_backup', '', 'fail', 'The standard backup share does not exist')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_backup', @share_outpath, 'pass', '')
   end

select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
exec master.sys.xp_cmdshell @cmd, no_output 
select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
Delete from #ShareTempTable
Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

If exists (select 1 from #ShareTempTable where path like '%denied%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_backup_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
   end
Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_backup_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_backup_security', '', 'pass', '')
	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
   end



--dba_archive
Select @save_sharename = @save_servername2 + '_dba_archive'
exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
If @share_outpath is null
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dba_archive', '', 'fail', 'The standard dba_archive share does not exist')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dba_archive', @share_outpath, 'pass', '')
   end

select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
exec master.sys.xp_cmdshell @cmd, no_output 
select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
Delete from #ShareTempTable
Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

If exists (select 1 from #ShareTempTable where path like '%denied%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dba_archive_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
   end
Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dba_archive_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dba_archive_security', '', 'pass', '')
	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
   end




-- dbasql
Select @save_sharename = @save_servername2 + '_dbasql'
exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
If @share_outpath is null
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dbasql', '', 'fail', 'The standard dbasql share does not exist')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dbasql', @share_outpath, 'pass', '')
   end

select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
exec master.sys.xp_cmdshell @cmd, no_output 
select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
Delete from #ShareTempTable
Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

If exists (select 1 from #ShareTempTable where path like '%denied%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dbasql_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
   end
Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dbasql_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dbasql_security', '', 'pass', '')
	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
   end



-- ldf
Select @save_sharename = @save_servername2 + '_ldf'
exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
If @share_outpath is null
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_ldf', '', 'fail', 'The standard ldf share does not exist')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_ldf', @share_outpath, 'pass', '')
   end

select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
exec master.sys.xp_cmdshell @cmd, no_output 
select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
Delete from #ShareTempTable
Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

If exists (select 1 from #ShareTempTable where path like '%denied%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_ldf_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
   end
Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_ldf_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_ldf_security', '', 'pass', '')
	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
   end




--  mdf
Select @save_sharename = @save_servername2 + '_mdf'
exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
If @share_outpath is null
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_mdf', '', 'fail', 'The standard mdf share does not exist')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_mdf', @share_outpath, 'pass', '')
   end

select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
exec master.sys.xp_cmdshell @cmd, no_output 
select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
Delete from #ShareTempTable
Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

If exists (select 1 from #ShareTempTable where path like '%denied%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_mdf_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
   end
Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_mdf_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_mdf_security', '', 'pass', '')
	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
   end



--  log
Select @save_sharename = @save_servername2 + '_log'
exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
If @share_outpath is null
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_log', '', 'fail', 'The standard log share does not exist')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_log', @share_outpath, 'pass', '')
   end

select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
exec master.sys.xp_cmdshell @cmd, no_output 
select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
Delete from #ShareTempTable
Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

If exists (select 1 from #ShareTempTable where path like '%denied%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_log_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
   end
Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_log_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_log_security', '', 'pass', '')
	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
   end



--  SQLjob_logs
Select @save_sharename = @save_servername2 + '_SQLjob_logs'
exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
If @share_outpath is null
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_SQLjob_logs', '', 'fail', 'The standard SQLjob_logs share does not exist')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_SQLjob_logs', @share_outpath, 'pass', '')
   end

select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
exec master.sys.xp_cmdshell @cmd, no_output 
select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
Delete from #ShareTempTable
Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

If exists (select 1 from #ShareTempTable where path like '%denied%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_SQLjob_logs_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
   end
Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_SQLjob_logs_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_SQLjob_logs_security', '', 'pass', '')
	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
   end


--  Look for large files in SQLjob_logs
SELECT @cmd = 'DIR "\\' + @save_servername + '\' + @save_servername2 + '_SQLjob_logs" /-c /O-S'

Delete from #dir_results
INSERT #dir_results
EXEC ('master.sys.xp_cmdshell ''' + @cmd + '''')
delete from #dir_results where dir_row is null
delete from #dir_results where dir_row like '%Volume in drive%'
delete from #dir_results where dir_row like '%Volume Serial Number%'
delete from #dir_results where dir_row like '%Directory of%'
--select * from #dir_results

SELECT @save_text = (select top 1 dir_row FROM #dir_results)
SELECT @save_text = substring(@save_text, 21, 19) 
SELECT @file_size = ltrim(rtrim(@save_text))

If @file_size > 500000000 --500mb
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_SQLjob_logs-FileSize', '', 'fail', 'A large file exists in this share.')
   end


-- builds
Select @save_sharename = @save_servername + '_builds'
exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
If @share_outpath is null
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_builds', '', 'fail', 'The standard builds share does not exist')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_builds', @share_outpath, 'pass', '')
   end

select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
exec master.sys.xp_cmdshell @cmd, no_output 
select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
Delete from #ShareTempTable
Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

If exists (select 1 from #ShareTempTable where path like '%denied%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_builds_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
   end
Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_builds_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_builds_security', '', 'pass', '')
	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
   end



-- dba_mail
Select @save_sharename = @save_servername + '_dba_mail'
exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
If @share_outpath is null
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dba_mail', '', 'fail', 'The standard dba_mail share does not exist')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dba_mail', @share_outpath, 'pass', '')
   end

select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
exec master.sys.xp_cmdshell @cmd, no_output 
select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
Delete from #ShareTempTable
Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

If exists (select 1 from #ShareTempTable where path like '%denied%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dba_mail_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
   end
Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dba_mail_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_dba_mail_security', '', 'pass', '')
	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
   end



If exists (select 1 from master.sys.databases with (NOLOCK) where name in (select db_name from db_sequence))
   and @save_envname <> 'production'
   begin
	-- base
	Select @save_sharename = @save_servername + '_base'
	exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
	If @share_outpath is null
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_base', '', 'fail', 'The standard BASE share does not exist.  Creating share now.')
		exec dbo.dbasp_create_NXTshare
		goto skip_share_base
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_base', @share_outpath, 'pass', '')
	   end

	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
	select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	Delete from #ShareTempTable
	Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

	If exists (select 1 from #ShareTempTable where path like '%denied%')
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_base_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
	   end
	Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_base_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_base_security', '', 'pass', '')
		select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
		exec master.sys.xp_cmdshell @cmd, no_output 
	   end

	skip_share_base:


	-- nxt
	Select @save_sharename = @save_servername2 + '_nxt'
	exec dbo.dbasp_get_share_path @save_sharename, @share_outpath output
	If @share_outpath is null
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_nxt', '', 'fail', 'The standard NXT share does not exist.  Creating share now.')
		exec dbo.dbasp_create_NXTshare
		goto skip_share_nxt
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_nxt', @share_outpath, 'pass', '')
	   end

	select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	exec master.sys.xp_cmdshell @cmd, no_output 
	select @cmd = 'mkdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
	Delete from #ShareTempTable
	Insert into #ShareTempTable exec master.sys.xp_cmdshell @cmd

	If exists (select 1 from #ShareTempTable where path like '%denied%')
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_nxt_security', '', 'fail', 'xp_cmdshell unable to run mkdir')
	   end
	Else If exists (select 1 from #ShareTempTable where path like '%already exists%')
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_nxt_security', '', 'warning', 'test folder SQLHealthCheck54321 should be deleted.')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('share_nxt_security', '', 'pass', '')
		select @cmd = 'rmdir \\' + @save_servername + '\' + @save_sharename + '\SQLHealthCheck54321' + @save_sqlinstance
		exec master.sys.xp_cmdshell @cmd, no_output 
	   end

	skip_share_nxt:
   end


------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start verify Utilities
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start verify Utilities')

--rmtshare
Select @cmd = 'rmtshare /?'

delete from #miscTempTable
insert into #miscTempTable exec master.sys.xp_cmdshell @cmd
delete from #miscTempTable where cmdoutput is null
--select * from #regresults

If exists (select 1 from #miscTempTable where cmdoutput like '%is not recognized%')
   begin
	Insert into #temp_results
	OUTPUT		CAST('	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01) AS VarChar(100)) AS [check drive usage (history, growth rate, projected growth)]
	values ('utility_rmtshare', 'rmtshare is not recognized', 'fail', 'The rmtshare utility was not found in the default path')
   end
Else
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('utility_rmtshare', 'rmtshare utility found', 'pass', '')
   end


--winzip
Select @cmd = 'wzzip -a c:\test.zip c:\*.txxt'

delete from #miscTempTable
insert into #miscTempTable exec master.sys.xp_cmdshell @cmd
delete from #miscTempTable where cmdoutput is null
--select * from #miscTempTable

If exists (select 1 from #miscTempTable where cmdoutput like '%is not recognized%')
   begin
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('utility_winzip', 'winzip is not recognized', 'fail', 'The winzip utility was not found in the default path')
   end
Else
   begin
	Select @save_winzip_build = (Select top 1 cmdoutput from #miscTempTable where cmdoutput like '%build%')
	Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('utility_winzip', @save_winzip_build, 'pass', '')
   end



--redgate
If @save_Redgate_flag = 'y'
   begin
	If not exists (select 1 from master.sys.objects with (NOLOCK) where name = 'sqlbackup' and type = 'x')
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('utility_Redgate_version', 'Redgate is not installed', 'fail', 'The Redgate service was found but the extended sprocs in master were not found')
		goto Redgate_end
	   end
	Else
	   begin
		Select @save_rg_version = (select env_detail from dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'backup_rg_version')
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('utility_Redgate_version', @save_rg_version, 'pass', '')
	   end
	   
	   
	Select @save_rg_versiontype = (select env_detail from dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'backup_rg_versiontype')
	If @save_rg_versiontype like '%trial%'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('utility_Redgate_versiontype', @save_rg_versiontype, 'fail', 'Redgate Trial version found')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('utility_Redgate_versiontype', @save_rg_versiontype, 'pass', '')
	   end


	--  Further redgate settings to check
	delete from #miscTempTable
	insert into #miscTempTable exec master.dbo.sqbutility @Parameter1=1008,@Parameter2=@p2 output
	--select * from #miscTempTable
	--select @p2

	If @p2 like '%LogDelete=0%'
	   begin
		insert into #miscTempTable exec master.dbo.sqbutility @Parameter1=1041,@Parameter2=N'LogDelete',@Parameter3=1,@Parameter4=@p4 output
		insert into #miscTempTable exec master.dbo.sqbutility @Parameter1=1041,@Parameter2=N'LogDeleteHours',@Parameter3=168,@Parameter4=@p5 output
	   end
	   
	--  No tests set up for further redgate settings at this time (they would go here)	

   end
Else
   begin
	If exists (select 1 from dbo.Local_ServerEnviro with (NOLOCK) where env_type like 'backup_rg%')
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('utility_Redgate_Local_ServerEnviro', 'Redgate is not installed', 'fail', 'Entries for Redgate were found in the Local_ServerEnviro table')
		goto Redgate_end
	   end	
   end

   
Redgate_end:


------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start verify Backup Settings
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start verify Backup Settings')


If (select @@version) not like '%Server 2005%' and (select SERVERPROPERTY ('productversion')) > '10.50.0000'
   begin
	If exists (select 1 from dbaadmin.dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'backup_type')
	   begin
		Delete from dbaadmin.dbo.Local_ServerEnviro where env_type = 'backup_type'
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('default_backup_type', 'Standard', 'pass', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('default_backup_type', 'Standard', 'pass', '')
	   end
   end
Else If @save_Redgate_flag = 'y'
   begin
	If not exists (select 1 from dbaadmin.dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'backup_type' and Env_detail = 'RedGate')
	   begin
		Select @save_backuptype = (select Env_detail from dbaadmin.dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'backup_type')
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('default_backup_type', @save_backuptype, 'fail', 'Redgate is installed but not being used as the default')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('default_backup_type', 'Redgate', 'pass', '')
	   end
   end
Else 
   begin
	If exists (select 1 from dbaadmin.dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'backup_type')
	   begin
		Select @save_backuptype = (select Env_detail from dbaadmin.dbo.Local_ServerEnviro with (NOLOCK) where env_type = 'backup_type')
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('default_backup_type', @save_backuptype, 'fail', 'There should be no backup_type in the Local_ServerEnviro table for this instance')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('default_backup_type', 'Standard', 'pass', '')
	   end
   end



------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Start verify Databases
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start verify Databases')

delete from #miscTempTable
Insert into #miscTempTable select name from master.sys.databases where database_id > 4 and source_database_id is null
--select * from #miscTempTable
	
If (select count(*) from #miscTempTable) > 0
   begin
	start_databases:
	Select @save_DBname = (select top 1 cmdoutput from #miscTempTable order by cmdoutput)
	Select @save_DBname = rtrim(@save_DBname)
	
	INSERT INTO @OutputComments VALUES('	Start process for database ' + @save_DBname)

	--  Take a look at the nocheck table

	Select @nocheck_backup_flag = 'n'
	If exists (select 1 from dbo.no_check where NoCheck_type = 'backup' and detail01 = @save_DBname)
	   begin
		Select @nocheck_backup_flag = 'y'
	   end

	Select @nocheck_maint_flag = 'n'
	If exists (select 1 from dbo.no_check where NoCheck_type = 'maint' and detail01 = @save_DBname)
	   begin
		Select @nocheck_maint_flag = 'y'
	   end


	--  DB Settings
	--  check status
	select @save_check_type = 'Status'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))
	select @save_DBid = (select database_id from sys.databases where name = @save_DBname)

	If @save_check = 'RESTORING' and @save_DBname like '%[_]new%'
	   begin
		
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_status', @save_check, 'pass', @save_DBname+' This is a reporting copy of the database pending restore completion')
		goto skip_DB
	   end
	Else If @save_check = 'RESTORING' and exists (select 1 from master.sys.database_mirroring where database_id = @save_DBid and mirroring_guid is not null)
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_status', @save_check, 'pass', @save_DBname+' This is a mirrored copy of the database pending failover')
		goto skip_DB
	   end
	Else If @save_check = 'OFFLINE'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_status', @save_check, 'warning', @save_DBname+' is OFFLINE at this time')
		goto skip_DB
	   end
	Else If @save_check <> 'ONLINE'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_status', @save_check, 'fail', @save_DBname+' is not ONLINE at this time')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_status', @save_check, 'pass', '')
	   end


	--  check updateability
	select @save_check_type = 'Updateability'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end
	

	--  check Collation
	select @save_check_type = 'Collation'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end

	--  check ComparisonStyle
	select @save_check_type = 'ComparisonStyle'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsAnsiNullDefault
	select @save_check_type = 'IsAnsiNullDefault'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end
	

	--  check IsAnsiNullsEnabled
	select @save_check_type = 'IsAnsiNullsEnabled'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsAnsiPaddingEnabled
	select @save_check_type = 'IsAnsiPaddingEnabled'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end
	

	--  check IsAnsiWarningsEnabled
	select @save_check_type = 'IsAnsiWarningsEnabled'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	 end


	--  check IsArithmeticAbortEnabled
	select @save_check_type = 'IsArithmeticAbortEnabled'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsAutoClose
	select @save_check_type = 'IsAutoClose'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsAutoCreateStatistics
	select @save_check_type = 'IsAutoCreateStatistics'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsAutoShrink
	select @save_check_type = 'IsAutoShrink'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsAutoUpdateStatistics
	select @save_check_type = 'IsAutoUpdateStatistics'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsCloseCursorsOnCommitEnabled
	select @save_check_type = 'IsCloseCursorsOnCommitEnabled'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsInStandBy
	select @save_check_type = 'IsInStandBy'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsLocalCursorsDefault
	select @save_check_type = 'IsLocalCursorsDefault'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsMergePublished
	select @save_check_type = 'IsMergePublished'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsNullConcat
	select @save_check_type = 'IsNullConcat'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsNumericRoundAbortEnabled
	select @save_check_type = 'IsNumericRoundAbortEnabled'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsParameterizationForced
	select @save_check_type = 'IsParameterizationForced'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsPublished
	select @save_check_type = 'IsPublished'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsRecursiveTriggersEnabled
	select @save_check_type = 'IsRecursiveTriggersEnabled'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsSubscribed
	select @save_check_type = 'IsSubscribed'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsSyncWithBackup
	select @save_check_type = 'IsSyncWithBackup'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check IsTornPageDetectionEnabled
	select @save_check_type = 'IsTornPageDetectionEnabled'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check LCID
	select @save_check_type = 'LCID'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	--  check SQLSortOrder
	select @save_check_type = 'SQLSortOrder'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_check <> @save_old_check
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' ' + @save_check_type + ' setting has changed from '+@save_old_check)

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end


	      
	
	--  Security Settings
	Select @save_DB_owner = (select suser_sname(owner_sid) from master.sys.databases with (NOLOCK) where name = @save_DBname)

	If @save_DB_owner like '%' + @save_SQLSvcAcct + '%'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_owner', 'null', 'warning', @save_DBname+' owner is set to the SQL service account.  Updated to "sa"')

		select @cmd = 'ALTER AUTHORIZATION ON DATABASE::' + @save_DBname + ' TO sa;'
		--Print '		'+@cmd
		exec master.sys.sp_executeSQL @cmd
	   end
	If @save_DB_owner is null
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_owner', 'null', 'fail', @save_DBname+' owner is null - should be "sa"')
	   end
	Else If @save_DB_owner = 'sa'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_owner', @save_DB_owner, 'pass', '')
	   end
	Else If exists (select 1 from dbo.No_Check where NoCheck_type = 'DBowner' and Detail01 = @save_DBname and Detail02 = @save_DB_owner)
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_owner', @save_DB_owner, 'pass', '')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_owner', @save_DB_owner, 'fail', @save_DBname+' owner should be "sa"')
	   end
	   


	
	--  check UserAccess
	select @save_check_type = 'UserAccess'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))
	
	If @save_check <> 'MULTI_USER' and @save_DBname <> 'systeminfo'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'fail', @save_DBname+' is not set for MULTI_USER')

		update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end

			
	
	--  Recovery Model
	select @save_check_type = 'Recovery'
	select @save_check = (Select convert(sysname, DATABASEPROPERTYEX(@save_DBname, @save_check_type)))

	If not exists(select 1 from dbo.HealthCheck_current where DBname = @save_DBname and Check_type = @save_check_type)
	   begin
		insert into dbo.HealthCheck_current values (@save_DBname, @save_check_type, @save_check, @CheckDate)
	   end

	Select @save_old_check = (select top 1 Check_detail from dbo.HealthCheck_current with (NOLOCK) where DBname = @save_DBname and Check_type = @save_check_type)
	
	If @save_envname = 'production'
	   begin
		If @save_check <> @save_old_check
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'warning', @save_DBname+' recovery model has changed from '+@save_old_check)

			update dbo.HealthCheck_current set Check_detail = @save_check, check_date = @CheckDate where DBname = @save_DBname and Check_type = @save_check_type
		   end
		Else
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
		   end
	   end
	Else If @save_check = 'FULL'
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'fail', @save_DBname+' recovery model should be SIMPLE')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_'+@save_check_type, @save_check, 'pass', '')
	   end
	   
	
	
	--  Current backups
	If @save_envname = 'production' and @nocheck_backup_flag = 'n'
	   begin
		--  Get the backup time for the last full database backup
		select @hold_backup_start_date  = (select top 1 backup_start_date from msdb.dbo.backupset 
						    where database_name = @save_DBname
						    and backup_finish_date is not null
						    and type in ('D', 'F')
						    order by backup_start_date desc)
						    
		Select @save_backup_start_date = convert(nvarchar(30), @hold_backup_start_date, 121)	
	
		If @hold_backup_start_date is null
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_DBbackup', 'null', 'fail', @save_DBname+': No DBbackup found')
		   end
		Else If @hold_backup_start_date < @CheckDate-8
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_DBbackup', @save_backup_start_date, 'fail', @save_DBname+': No recent DBbackup found')
		   end
		Else
		   begin
			Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_DBbackup', @save_backup_start_date, 'pass', '')
		   end

	
		--  If the last DB backup time was older than the @backup_diff_dd_period limit, check for differentials
		If @hold_backup_start_date < @CheckDate-2 and databaseproperty(rtrim(@save_DBname), 'IsTrunclog') = 0
		   begin
			select @hold_backup_start_date  = (select top 1 backup_start_date from msdb.dbo.backupset 
							    where database_name = @save_DBname
							    and backup_finish_date is not null
							    and type = 'I'
							    order by backup_start_date desc)
	
			Select @save_backup_start_date = convert(nvarchar(30), @hold_backup_start_date, 121)	

			If @hold_backup_start_date is null
			   begin
				Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_DIFFbackup', 'null', 'fail', @save_DBname+': No Differential backup found')
			   end
			Else If @hold_backup_start_date < @CheckDate-8
			   begin
				Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_DIFFbackup', @save_backup_start_date, 'fail', @save_DBname+': No recent Differential backup found')
			   end
			Else
			   begin
				Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_DIFFbackup', @save_backup_start_date, 'pass', '')
			   end
		   end
	
	
		--  check for tranlog backups
		If databaseproperty(rtrim(@save_DBname), 'IsTrunclog') = 0
		   begin
			select @hold_backup_start_date  = (select top 1 backup_start_date from msdb.dbo.backupset 
							    where database_name = @save_DBname
							    and backup_finish_date is not null
							    and type = 'L'
							    order by backup_start_date desc)
	
			Select @save_backup_start_date = convert(nvarchar(30), @hold_backup_start_date, 121)	

			If @hold_backup_start_date is null
			   begin
				Insert into #temp_results 
				OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
				INTO		@OutputComments
				values		(@save_DBname+'_Tranlogbackup', 'null', 'fail', @save_DBname+': No Tranlog backup found')
			   end
			Else If @hold_backup_start_date < @CheckDate-1
			   begin
				Insert into #temp_results 
				OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
				INTO		@OutputComments
				values		(@save_DBname+'_Tranlogbackup', @save_backup_start_date, 'fail', @save_DBname+': No recent Tranlog backup found')
			   end
			Else
			   begin
				Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_Tranlogbackup', @save_backup_start_date, 'pass', '')
			   end
		   end
	   end
	
	------------------------------------
	--	PRINT OUTPUT
	------------------------------------
	SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
	FROM		@OutputComments
	IF @Verbose > 0 PRINT @OutputComment

	
	-----------------------------------------------------------------------------------------
	--  Process Orphaned Users
	-----------------------------------------------------------------------------------------
	SELECT		@OutputComment = ''
	DELETE		@OutputComments
	INSERT INTO @OutputComments VALUES('Process Orphaned Users')

	--  Double Check users marked as orphaned.  If any were marked in error, set delete flag to 'x'
	insert into #orphans 	Execute('select sid, name from [' + @save_DBname + '].sys.sysusers 
			    where sid not in (select sid from master.sys.syslogins where name is not null and sid is not null) 
			    and name not in (''guest'')
			    and sid is not null
			    and issqlrole = 0
			    ')

	Update dbo.Security_Orphan_Log set Delete_flag = 'x' 
				where Delete_flag = 'n' 
				and SOL_type = 'user' 
				and SOL_DBname = @save_DBname 
				and SOL_name not in (select orph_name from #orphans)


	--  Drop users orphaned for more than 7 days
	delete from #temp_tbl1
	insert #temp_tbl1(text01) SELECT SOL_name
	   From dbo.Security_Orphan_Log
	   Where Delete_flag = 'n' 
	   and SOL_type = 'user' 
	   and SOL_DBname = @save_DBname
	   and Initial_Date < @CheckDate-7
	delete from #temp_tbl1 where text01 is null


	------------------------------------
	--	PRINT OUTPUT
	------------------------------------
	SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
	FROM		@OutputComments
	IF @Verbose > 0 PRINT @OutputComment


	start_delete_DBusers:
	If (select count(*) from #temp_tbl1) > 0
	   begin

		-----------------------------------------------------------------------------------------
		--  Start verify (and cleanup) for Users
		-----------------------------------------------------------------------------------------
		SELECT		@OutputComment = ''
		DELETE		@OutputComments
		INSERT INTO @OutputComments VALUES('Start verify (and cleanup) for Users')

		Select @save_user_name = (select top 1 text01 from #temp_tbl1)
		INSERT INTO @OutputComments VALUES('	Processing User: ' + @save_user_name)

		select @cmd = N'select top 1 @save_user_sid = sid from [' + @save_DBname +'].[sys].[database_principals] where name = ''' + @save_user_name + ''''
		exec sp_executesql @cmd, N'@save_user_sid varchar(255) output', @save_user_sid = @save_user_sid output

		Delete from #Objects

		-- Checking for cases in sys.objects where ALTER AUTHORIZATION has been used
		SET @SQL = 'INSERT INTO #Objects (DatabaseName, UserName, ObjectName, ObjectType) 
		          SELECT ''' + @save_DBname + ''', dp.name, so.name, so.type_desc 
		          FROM [' + @save_DBname + '].sys.database_principals dp
		            JOIN [' + @save_DBname + '].sys.objects so 
		              ON dp.principal_id = so.principal_id
		          WHERE dp.sid = ''' + @save_user_sid + ''';';
		EXEC(@SQL); 

	       -- Checking for cases where the login owns one or more schema
	       SET @SQL = 'INSERT INTO #Objects (DatabaseName, UserName, ObjectName, ObjectType) 
			 SELECT ''' + @save_DBname + ''', dp.name, sch.name, ''SCHEMA'' 
			 FROM [' + @save_DBname + '].sys.database_principals dp
			   JOIN [' + @save_DBname + '].sys.schemas sch 
			     ON dp.principal_id = sch.principal_id
			 WHERE dp.sid = ''' + @save_user_sid + ''';'; 
	       EXEC(@SQL);

	       -- Checking for cases where the login owns assemblies
	       SET @SQL = 'INSERT INTO #Objects (DatabaseName, UserName, ObjectName, ObjectType) 
			 SELECT ''' + @save_DBname + ''', dp.name, assemb.name, ''Assembly'' 
			 FROM [' + @save_DBname + '].sys.database_principals dp
			   JOIN [' + @save_DBname + '].sys.assemblies assemb
			     ON dp.principal_id = assemb.principal_id
			 WHERE dp.sid = ''' + @save_user_sid + ''';'; 
	       EXEC(@SQL);
               
	       -- Checking for cases where the login owns asymmetric keys
	       SET @SQL = 'INSERT INTO #Objects (DatabaseName, UserName, ObjectName, ObjectType) 
			 SELECT ''' + @save_DBname + ''', dp.name, asym.name, ''Asymm. Key'' 
			 FROM [' + @save_DBname + '].sys.database_principals dp
			   JOIN [' + @save_DBname + '].sys.asymmetric_keys asym 
			     ON dp.principal_id = asym.principal_id
			 WHERE dp.sid = ''' + @save_user_sid + ''';'; 
	       EXEC(@SQL);
                   
	       -- Checking for cases where the login owns symmetric keys
	       SET @SQL = 'INSERT INTO #Objects (DatabaseName, UserName, ObjectName, ObjectType) 
			 SELECT ''' + @save_DBname + ''', dp.name, sym.name, ''Symm. Key'' 
			 FROM [' + @save_DBname + '].sys.database_principals dp
			   JOIN [' + @save_DBname + '].sys.symmetric_keys sym 
			     ON dp.principal_id = sym.principal_id
			 WHERE dp.sid = ''' + @save_user_sid + ''';'; 
	       EXEC(@SQL);
                      
	       -- Checking for cases where the login owns certificates
	       SET @SQL = 'INSERT INTO #Objects (DatabaseName, UserName, ObjectName, ObjectType) 
			 SELECT ''' + @save_DBname + ''', dp.name, cert.name, ''Certificate'' 
			 FROM [' + @save_DBname + '].sys.database_principals dp
			   JOIN [' + @save_DBname + '].sys.certificates cert
			     ON dp.principal_id = cert.principal_id
			 WHERE dp.sid = ''' + @save_user_sid + ''';'; 
		EXEC(@SQL);


		Delete from #Objects where ObjectName is null
		

		If (select count(*) from #Objects) > 0
		   begin

			Start_dbuser_alterauth:
			Select @save_ObjectName = (select top 1 ObjectName from #Objects)
			Select @save_ObjectType = (select top 1 ObjectType from #Objects where ObjectName = @save_ObjectName)

			If @save_ObjectType = 'SCHEMA'
			   begin
				Select @cmd = 'use [' + @save_DBname + '] ALTER AUTHORIZATION ON SCHEMA::[' + @save_ObjectName + '] TO dbo;'
				--Print '		'+@cmd
				Exec (@cmd)
			   end
			Else If @save_ObjectType = 'Assembly'
			   begin
				Select @cmd = 'use [' + @save_DBname + '] ALTER AUTHORIZATION ON Assembly::[' + @save_ObjectName + '] TO dbo;'
				--Print '		'+@cmd
				Exec (@cmd)
			   end
			Else If @save_ObjectType = 'Symm. Key'
			   begin
				Select @cmd = 'use [' + @save_DBname + '] ALTER AUTHORIZATION ON SYMMETRIC KEY::[' + @save_ObjectName + '] TO dbo;'
				--Print '		'+@cmd
				Exec (@cmd)
			   end
			Else If @save_ObjectType = 'Certificate'
			   begin
				Select @cmd = 'use [' + @save_DBname + '] ALTER AUTHORIZATION ON Certificate::[' + @save_ObjectName + '] TO dbo;'
				--Print '		'+@cmd
				Exec (@cmd)
			   end
			Else
			   begin
				Select @cmd = 'use [' + @save_DBname + '] ALTER AUTHORIZATION ON OBJECT::[' + @save_ObjectName + '] TO dbo;'
				--Print '		'+@cmd
				Exec (@cmd)
			   end
		   end		


		Delete from #Objects where ObjectName = @save_ObjectName and ObjectType = @save_ObjectType
		If (select count(*) from #Objects) > 0
		   begin
			goto Start_dbuser_alterauth
		   end			
			
		--  GET OBJECT COUNTS FOR ALL SCHEMAS
		Select @cmd = 'Use [' + @save_DBname + '];
		TRUNCATE TABLE #SchemaObjCounts;
		INSERT INTO	#SchemaObjCounts
		select		ss.name
					,COUNT(so.object_id) as objCount 
		From		sys.schemas ss WITH(NOLOCK) 
		LEFT JOIN	sys.objects so WITH(NOLOCK) 
				ON	so.schema_id = ss.schema_id 
		GROUP BY	ss.name'
	        --Print '		'+@cmd
	        Exec (@cmd)

		--  LIST ALL CURRENT SCHEMAS AND OBJECT COUNTS UNDER THEM
		--SELECT * FROM #SchemaObjCounts

		--  DROP SCHEMA IF IT EXISTS AND NO OBJECTS ARE USING IT.
		Select @cmd = 'Use [' + @save_DBname + ']; IF EXISTS(SELECT 1 FROM #SchemaObjCounts where SchemaName ='''+@save_user_name+''' and objCount = 0) DROP SCHEMA [' + @save_user_name + '];'
	        --Print '		'+@cmd
	        Exec (@cmd)
	        
		--  DROP USER IF IT STILL EXISTS
		Select @cmd = 'Use [' + @save_DBname + ']; IF User_ID('''+@save_user_name+''') IS NOT NULL DROP User [' + @save_user_name + '];'
	        --Print '		'+@cmd
	        Exec (@cmd)



		Update dbo.Security_Orphan_Log set Delete_flag = 'y' 
				where Delete_flag = 'n' 
				and SOL_name = @save_user_name
				and SOL_DBname = @save_DBname


		--  Loop to process more logins
		Delete from #temp_tbl1 where text01 = @save_user_name
		goto start_delete_DBusers
	   end

	------------------------------------
	--	PRINT OUTPUT
	------------------------------------
	SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
	FROM		@OutputComments
	IF @Verbose > 0 PRINT @OutputComment

	
	-----------------------------------------------------------------------------------------
	--  Check for orphaned Users
	-----------------------------------------------------------------------------------------
	SELECT		@OutputComment = ''
	DELETE		@OutputComments
	INSERT INTO @OutputComments VALUES('Check for orphaned Users')


	If exists (select 1 from dbo.Security_Orphan_Log where Delete_flag = 'n' and SOL_DBname = @save_DBname and Initial_Date < @CheckDate-7)
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Orphaned_status', '', 'fail', 'Orphaned User found (not auto-cleaned).  Run: select * from dbaadmin.dbo.Security_Orphan_Log where Delete_flag = ''n''')
	   end
	Else If exists (select 1 from dbo.Security_Orphan_Log where Delete_flag = 'n' and SOL_DBname = @save_DBname)
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		('Orphaned_status', '', 'pass', 'Warning: Orphaned Users exist and have not yet been auto-cleaned.')
	   end


	------------------------------------
	--	PRINT OUTPUT
	------------------------------------
	SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
	FROM		@OutputComments
	IF @Verbose > 0 PRINT @OutputComment

	
	-----------------------------------------------------------------------------------------
	--  Check for Build Tables
	-----------------------------------------------------------------------------------------
	SELECT		@OutputComment = ''
	DELETE		@OutputComments
	INSERT INTO @OutputComments VALUES('Check for Build Tables')	


	If not exists(select 1 from dbo.db_sequence where db_name = @save_DBname)
	   begin
		goto skip_build_table_check
	   end

	Select @cmd = 'USE [' + @save_DBname + ']  SELECT @doesexist = OBJECT_ID(''Build'')'
	--Print '		'+@cmd

	EXEC sp_executesql @cmd, N'@doesexist int output', @doesexist output

	If @doesexist is null
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_Build_table_check', '', 'fail', 'Build table not found.')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_Build_table_check', '', 'pass', '')
	   end


	Select @cmd = 'USE [' + @save_DBname + ']  SELECT @doesexist = OBJECT_ID(''BuildDetail'')'
	--Print '		'+@cmd

	EXEC sp_executesql @cmd, N'@doesexist int output', @doesexist output

	If @doesexist is null
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_BuildDetail_table_check', '', 'fail', 'BuildDetail table not found.')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_BuildDetail_table_check', '', 'pass', '')
	   end

	------------------------------------
	--	PRINT OUTPUT
	------------------------------------
	SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
	FROM		@OutputComments
	IF @Verbose > 0 PRINT @OutputComment
	
	skip_build_table_check:

	-----------------------------------------------------------------------------------------
	--  Check for Autogrowth
	-----------------------------------------------------------------------------------------
	SELECT		@OutputComment = ''
	DELETE		@OutputComments
	INSERT INTO @OutputComments VALUES('Check for Autogrowth')	

	If exists (select 1 from dbo.no_check where NoCheck_type = 'SQLHealth' and detail01 = 'DBautogrowth' and detail02 = @save_DBname)
	   begin
		goto skip_DBautogrowth_skip
	   end
	
	Select @cmd = 'USE [' + @save_DBname + ']  SELECT @doesexist = (select distinct 1 from sys.database_files where type = 0 and growth > 0)'
	--Print '		'+@cmd
	EXEC sp_executesql @cmd, N'@doesexist int output', @doesexist output
	
	If @doesexist is null
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_DataFileGrowth_check', '', 'fail', 'No data file enabled for growth.')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_DataFileGrowth_check', '', 'pass', '')
	   end

	Select @cmd = 'USE [' + @save_DBname + ']  SELECT @doesexist = (select distinct 1 from sys.database_files where type = 1 and growth > 0)'
	--Print '		'+@cmd
	EXEC sp_executesql @cmd, N'@doesexist int output', @doesexist output
		
	If @doesexist is null
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_LogFileGrowth_check', '', 'fail', 'No log file enabled for growth.')
	   end
	Else
	   begin
		Insert into #temp_results 
		OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
		INTO		@OutputComments
		values		(@save_DBname+'_LogFileGrowth_check', '', 'pass', '')
	   end
	
	------------------------------------
	--	PRINT OUTPUT
	------------------------------------
	SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
	FROM		@OutputComments
	IF @Verbose > 0 PRINT @OutputComment
	
	skip_DBautogrowth_skip:
		
-----------------------------------------------------------------------------------------
--  Last DBCC
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('check Last DBCC')	

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment
	
	
-----------------------------------------------------------------------------------------
--  Active in past 30 days
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('check Active in past 30 days')	

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Check DB file size limits
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('check DB file size limits')	

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  Check Growth Rate changes
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('check Growth Rate changes')	
	
------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


	
-----------------------------------------------------------------------------------------
--  Check for ability to grow
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('check for ability to grow')	
	
------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


	skip_DB:


	--  check for more rows to process
	Delete from #miscTempTable where cmdoutput = @save_DBname
	If (select count(*) from #miscTempTable) > 0
	   begin
		goto start_databases
	   end
	

   end

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment



-----------------------------------------------------------------------------------------
--  verify Logins
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Start verify (and cleanup) for Logins')


--  Double Check logins marked as orphaned.  If any were marked in error, set delete flag to 'x'
insert into #orphans exec master.sys.sp_validatelogins

Update dbo.Security_Orphan_Log set Delete_flag = 'x' 
			where Delete_flag = 'n' 
			and SOL_type = 'login' 
			and SOL_name not in (select orph_name from #orphans)


--  Drop logins orphaned for more than 7 days
delete from #temp_tbl1
insert #temp_tbl1(text01) SELECT SOL_name
   From dbo.Security_Orphan_Log
   Where Delete_flag = 'n' 
   and SOL_type = 'login' 
   and Initial_Date < @CheckDate-7
delete from #temp_tbl1 where text01 is null

start_delete_logins:
If (select count(*) from #temp_tbl1) > 0
   begin
	Select @save_login_name = (select top 1 text01 from #temp_tbl1)
	
	Select @cmd = 'DROP Login [' + @save_login_name + '];'
        INSERT INTO @OutputComments VALUES('		--'+@cmd)
        Exec (@cmd)

	If not exists (select 1 from sys.server_principals where name = @save_login_name)
	   begin
		Update dbo.Security_Orphan_Log set Delete_flag = 'y' 
				where Delete_flag = 'n' 
				and SOL_name = @save_login_name
	   end

	--  Loop to process more logins
	Delete from #temp_tbl1 where text01 = @save_login_name
	goto start_delete_logins
   end


--  Check for orphaned logins
If exists (select 1 from dbo.Security_Orphan_Log where SOL_type = 'login' and Delete_flag = 'n' and Initial_Date < @CheckDate-7)
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values ('Orphaned_status', '', 'fail', 'Orphaned Login found (not auto-cleaned).  Run: select * from dbaadmin.dbo.Security_Orphan_Log where Delete_flag = ''n''')
   end
Else If exists (select 1 from dbo.Security_Orphan_Log where Delete_flag = 'n')
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('Orphaned_status', '', 'pass', 'Warning: Orphaned Logins exist and have not yet been auto-cleaned.')
   end
------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  CHECK DISK FORECAST
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('check drive forecast status')


-- IF FORECAST DATA IS MORE THAN A DAY OLD THEN REPROCESS IT
IF (SELECT DATEDIFF(day,MIN(CheckDate),@CheckDate) FROM [DBAperf].[dbo].[DMV_DiskSpaceForecast]) > 1
BEGIN
	INSERT INTO @OutputComments VALUES('	-- Drive forecast too old, Recalculating...')
	EXEC dbaperf.dbo.dbasp_DiskSpaceCheck_CaptureAndExport
END

-- GENERATE RESULTS
-- DECLARE @CheckDate DateTime; SET @CheckDate = getdate()
;WITH		DriveData
			AS
			(
			SELECT [SQLName]
				  ,REPLACE([Unit],'DRIVE_','') AS [Drive]
				  ,[Period]
				  ,DATEADD(week,CAST(REPLACE([Period],LEFT([Period],CHARINDEX('-',[Period]+'-')-1)+'-','') AS INT)-1,DATEADD(day,(DATEPART(weekday,CAST(LEFT([Period],CHARINDEX('-',[Period]+'-')-1)+'0101' AS DateTime))-1)*(-1),CAST(LEFT([Period],CHARINDEX('-',[Period]+'-')-1)+'0101' AS DateTime))) AS [Time]
				  ,COALESCE([Forecast],0) AS [Value]
				  ,[LimitDataSizeMB] AS [MAX]
			FROM	[DBAperf].[dbo].[DMV_DiskSpaceForecast]
			WHERE	COALESCE(CAST([Forecast] AS INT),0) != 0
			)
			,DrivesInDanger
			AS
			(
			SELECT [SQLName]
				  ,REPLACE([Unit],'DRIVE_','') AS [Drive]
				  ,MIN([Period]) [Period]
				  ,MIN(DATEADD(week,CAST(REPLACE([Period],LEFT([Period],CHARINDEX('-',[Period]+'-')-1)+'-','') AS INT)-1,DATEADD(day,(DATEPART(weekday,CAST(LEFT([Period],CHARINDEX('-',[Period]+'-')-1)+'0101' AS DateTime))-1)*(-1),CAST(LEFT([Period],CHARINDEX('-',[Period]+'-')-1)+'0101' AS DateTime)))) AS [Time]
			FROM	[DBAperf].[dbo].[DMV_DiskSpaceForecast]
			WHERE	COALESCE(CAST([Forecast] AS INT),0) != 0
				AND COALESCE(CAST([Forecast] AS INT),0) >= CAST([LimitDataSizeMB] AS INT)
			GROUP BY	[SQLName]
						,REPLACE([Unit],'DRIVE_','')
			)
			,AlertSummary
			AS
			(
			SELECT		DriveData.SQLName
						,DriveData.Drive
						,COALESCE(DATEDIFF(Week,@CheckDate,MIN(DrivesInDanger.Time)),999) [WeeksTillFull]
						,CAST((MAX(DriveData.Value) - MIN(DriveData.Value))/(DATEDIFF(week,MIN(DriveData.Time),MAX(DriveData.Time)))AS INT) GrowthPerWeek_MB
			FROM		DriveData
			LEFT JOIN	DrivesInDanger
					ON	DrivesInDanger.SQLName	= DriveData.SQLName
					AND	DrivesInDanger.Drive	= DriveData.Drive
			GROUP BY	DriveData.SQLName
						,DriveData.Drive
			)
			
INSERT INTO	#temp_results
OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
INTO		@OutputComments
SELECT		'Drive_growth_rateMB_'+Drive
			,convert(nvarchar(10), [GrowthPerWeek_MB])+'MB'
			,CASE WHEN [WeeksTillFull] < 13 THEN 'fail' ELSE 'pass' END
			,CASE WHEN [WeeksTillFull] < 13 THEN 'Drive will be out of space in ' + convert(nvarchar(10),[WeeksTillFull]) + ' weeks at current growth rate.' ELSE '' END
FROM		AlertSummary	

SELECT		@OutputComment = ''
------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment


-----------------------------------------------------------------------------------------
--  CHECK SQLmail
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = ''
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('Check for unprocessed *.sml files')


Select @save_dba_mail_path = (select env_detail from local_serverenviro where env_type = 'dba_mail_path')
select @cmd = 'forfiles /P '+@save_dba_mail_path+' /M *.sml -d -1'
--Print '		'+@cmd	

Delete from #dir_results
Insert into #dir_results(dir_row) exec master.sys.xp_cmdshell @cmd
delete from #dir_results where dir_row is null
delete from #dir_results where dir_row like '%No files found%'
delete from #dir_results where dir_row like '%,TRUE%'
delete from #dir_results where dir_row like '%DS_Store%'
--select * from #dir_results

If (select count(*) from #dir_results) > 0
   begin
	--select * from #dir_results
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('SQL Mail files (sml)', '', 'fail', 'Unprocessed SQL mail files (*.sml) found.')
   end
Else
   begin
	Insert into #temp_results 
	OUTPUT		'	-- '+CAST(INSERTED.Subject01 AS CHAR(80))+'	-- '+UPPER(INSERTED.grade01)
	INTO		@OutputComments
	values		('SQL Mail files (sml)', '', 'pass', '')
   end

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > 0 PRINT @OutputComment

-----------------------------------------------------------------------------------------
--  OUTPUT ALL FAILURES
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
DELETE		@OutputComments
INSERT INTO @OutputComments VALUES('List of All Failed Tests:')
INSERT INTO @OutputComments VALUES('')

INSERT INTO @OutputComments
SELECT		'	'
			+UPPER(grade01)
			+':	'
			+LEFT(CAST(Subject01 AS CHAR(100)),(SELECT MAX(LEN(Subject01))+2 FROM #temp_results WHERE grade01 Like '%fail%'))
			+' ('
			+LEFT(CAST(value01+')' AS CHAR(100)),(SELECT MAX(LEN(Value01))+3 FROM #temp_results WHERE grade01 Like '%fail%'))
			+' ' + notes01
FROM		#temp_results
WHERE		grade01 Like '%fail%'

------------------------------------
--	PRINT OUTPUT
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose >= 0 PRINT @OutputComment

-----------------------------------------------------------------------------------------
--  GENERATE REPORT AND UPDATE FILE
-----------------------------------------------------------------------------------------
SELECT		@OutputComment = CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
DELETE		@OutputComments

If (select count(*) from #temp_results) > 0
	BEGIN

		SELECT		@ColumnWrapCnt =((	SELECT	MAX(LEN(subject01))+2 
												+MAX(LEN(value01))+2	
												+MAX(LEN(notes01))	
										from	#temp_results) 
										/
										(@PrintWidth-(SELECT MAX(LEN(grade01))+2 from #temp_results))
										) + 1

		INSERT INTO	@Report
		---------------------------
		-- COLUMN TITLES
		---------------------------
		SELECT		'' as [subject]
					,'' as [value]
					,'' as [grade]
					,'' as [notes]
					,CAST(LEFT(CAST(REPLICATE(' ',(MaxLen_Subject-7)/2)+'SUBJECT' AS CHAR(200)),MaxLen_Subject)	+'  '
					+LEFT(CAST(REPLICATE(' ',(MaxLen_Value-5)/2)+'VALUE'	 AS CHAR(200)),MaxLen_Value)	+'  '
					+LEFT(CAST(REPLICATE(' ',(MaxLen_Grade-5)/2)+'GRADE'	 AS CHAR(200)),MaxLen_Grade)	+'  '
					+LEFT(CAST(REPLICATE(' ',(MaxLen_Notes-5)/2)+'NOTES'	 AS CHAR(200)),MaxLen_Notes) AS VarChar(MAX)) AS [OutputComment]	
		FROM		(
					SELECT		 MAX(LEN(subject01)) /@ColumnWrapCnt MaxLen_Subject
								,MAX(LEN(value01))   /@ColumnWrapCnt MaxLen_Value
								,MAX(LEN(grade01))   MaxLen_Grade
								,MAX(LEN(notes01))   /@ColumnWrapCnt MaxLen_Notes
					from		#temp_results
					) T2
		UNION ALL
		---------------------------
		-- COLUMN TITLE UNDER LINES
		---------------------------
		SELECT		'' as [subject]
					,'' as [value]
					,'' as [grade]
					,'' as [notes]
					,REPLICATE('=',MaxLen_Subject)	+'  '
					+REPLICATE('=',MaxLen_Value)	+'  '
					+REPLICATE('=',MaxLen_Grade)	+'  '
					+REPLICATE('=',MaxLen_Notes)
		FROM		(
					SELECT		 MAX(LEN(subject01)) /@ColumnWrapCnt MaxLen_Subject
								,MAX(LEN(value01))   /@ColumnWrapCnt MaxLen_Value
								,MAX(LEN(grade01))   MaxLen_Grade
								,MAX(LEN(notes01))   /@ColumnWrapCnt MaxLen_Notes
					from		#temp_results
					) T2
		UNION ALL
		---------------------------
		-- COLUMN DATA
		---------------------------
		SELECT		subject01 as [subject]
					,value01 as [value]
					,grade01 as [grade]
					,notes01 as [notes]
					,REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
					LEFT(CAST(dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(subject01,MaxLen_Subject,'_',default),1)+'   ' AS CHAR(8000)),MaxLen_Subject+2)
					+LEFT(CAST(dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(value01,MaxLen_Value,'_',default),1)   +'   ' AS CHAR(8000)),MaxLen_Value+2)
					+LEFT(CAST(dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(grade01,MaxLen_Grade,'_',default),1)   +'   ' AS CHAR(8000)),MaxLen_Grade+2)
					+LEFT(CAST(dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(notes01,MaxLen_Notes,'_',default),1)   +'   ' AS CHAR(8000)),MaxLen_Notes+2) 
					+ISNULL(@CRLF+NULLIF(CAST(
					 LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(subject01,MaxLen_Subject,'_',default),2)+' ' AS CHAR(8000)),MaxLen_Subject+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(value01,MaxLen_Value,'_',default),2)+' '	 AS CHAR(8000)),MaxLen_Value+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(grade01,MaxLen_Grade,'_',default),2)+' '	 AS CHAR(8000)),MaxLen_Grade+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(notes01,MaxLen_Notes,'_',default),2)+' '	 AS CHAR(8000)),MaxLen_Notes+2) AS VarChar(max)),''),'')
					+ISNULL(@CRLF+NULLIF(CAST(
					 LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(subject01,MaxLen_Subject,'_',default),3)+' ' AS CHAR(8000)),MaxLen_Subject+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(value01,MaxLen_Value,'_',default),3)+' '	 AS CHAR(8000)),MaxLen_Value+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(grade01,MaxLen_Grade,'_',default),3)+' '	 AS CHAR(8000)),MaxLen_Grade+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(notes01,MaxLen_Notes,'_',default),3)+' '	 AS CHAR(8000)),MaxLen_Notes+2) AS VarChar(max)),''),'')
					+ISNULL(@CRLF+NULLIF(CAST(
					 LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(subject01,MaxLen_Subject,'_',default),4)+' ' AS CHAR(8000)),MaxLen_Subject+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(value01,MaxLen_Value,'_',default),4)+' '	 AS CHAR(8000)),MaxLen_Value+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(grade01,MaxLen_Grade,'_',default),4)+' '	 AS CHAR(8000)),MaxLen_Grade+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(notes01,MaxLen_Notes,'_',default),4)+' '	 AS CHAR(8000)),MaxLen_Notes+2) AS VarChar(max)),''),'')
					+ISNULL(@CRLF+NULLIF(CAST(
					 LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(subject01,MaxLen_Subject,'_',default),5)+' ' AS CHAR(8000)),MaxLen_Subject+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(value01,MaxLen_Value,'_',default),5)+' '	 AS CHAR(8000)),MaxLen_Value+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(grade01,MaxLen_Grade,'_',default),5)+' '	 AS CHAR(8000)),MaxLen_Grade+2)
					+LEFT(CAST('  '+dbaadmin.dbo.dbaudf_ReturnLine(dbaadmin.dbo.dbaudf_WordWrap(notes01,MaxLen_Notes,'_',default),5)+' '	 AS CHAR(8000)),MaxLen_Notes+2) AS VarChar(max)),''),'')
					,@CRLF+@CRLF,@CRLF),@CRLF+' '+@CRLF,@CRLF),@CRLF+'  '+@CRLF,@CRLF),@CRLF+'   '+@CRLF,@CRLF),@CRLF+'    '+@CRLF,@CRLF)
		from		#temp_results
		CROSS JOIN	(
					SELECT		 MAX(LEN(subject01)) /@ColumnWrapCnt MaxLen_Subject
								,MAX(LEN(value01))   /@ColumnWrapCnt MaxLen_Value
								,MAX(LEN(grade01))   MaxLen_Grade
								,MAX(LEN(notes01))   /@ColumnWrapCnt MaxLen_Notes
					from		#temp_results
					) Lengths


		SELECT		@PrintWidth
					=(MAX(LEN(subject01)) /@ColumnWrapCnt) 
					+(MAX(LEN(value01))   /@ColumnWrapCnt) 
					+(MAX(LEN(grade01)))   
					+(MAX(LEN(notes01))   /@ColumnWrapCnt)
					+ 6 
		from		#temp_results


		-- WRITE HEADDER LINE TO REPORT WITH OVERWRITE TO EMPTY EXISTING REPORT
		SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
		SELECT @MSG='CREATING REPORT FILE AT '+@ReportPath+@ReportFileName,@MSG=REPLICATE(' ',(@PrintWidth-LEN(@MSG))/2)+@MSG;EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
		SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint

		SELECT		@ReportText=REPLICATE(' ',(@PrintWidth-LEN(@Subject))/2)+@Subject+@CRLF+@CRLF+@CRLF
			EXEC	dbaadmin.dbo.dbasp_FileAccess_Write @ReportText,@ReportPath,@ReportFileName,0

		-- WRITE HEADDER LINE TO UPDATE FILE WITH OVERWRITE TO EMPTY EXISTING REPORT
		SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
		SELECT @MSG='CREATING UPDATE FILE AT '+@ReportPath+@updatefile_name,@MSG=REPLICATE(' ',(@PrintWidth-LEN(@MSG))/2)+@MSG;EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
		SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint

		SELECT		@ReportText='-- SQLHealthReport Updated Generated on ' + CAST(@CheckDate AS VarChar(max))+@CRLF+@CRLF+@CRLF
			EXEC	dbaadmin.dbo.dbasp_FileAccess_Write @ReportText,@ReportPath,@updatefile_name,0


		-- WRITE HEADDER LINE TO REPORT WITH OVERWRITE TO EMPTY EXISTING REPORT
		SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
		SELECT @MSG='WRITING TO REPORT FILE AT '+@ReportPath+@ReportFileName,@MSG=REPLICATE(' ',(@PrintWidth-LEN(@MSG))/2)+@MSG;EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
		SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint

		SELECT		@ReportText='Report Generated: ' + convert(varchar(30),@CheckDate,9),@ReportText=REPLICATE(' ',(@PrintWidth-LEN(@ReportText))/2)+@ReportText+@CRLF
			EXEC	dbaadmin.dbo.dbasp_FileAccess_Write @ReportText,@ReportPath,@ReportFileName,1




		SET @ReportText = @CRLF+@CRLF+REPLICATE('=',@PrintWidth)+@CRLF+@CRLF
		DECLARE ResultsCursor CURSOR
		FOR
		SELECT [subject],[value],[grade],[notes],REPLACE(REPLACE(REPLACE(REPLACE(RTRIM(CAST(OutputComment AS VarChar(MAX)))+'|',@CRLF+'|','')+'|',@CRLF+'|','')+'|','||',''),'|','')
		FROM @Report

		OPEN ResultsCursor
		FETCH NEXT FROM ResultsCursor INTO @save_subject01,@save_value01,@save_grade01,@save_notes01,@OutputComment
		WHILE (@@fetch_status <> -1)
		BEGIN
			IF (@@fetch_status <> -2) AND @OutputComment IS NOT NULL 
			BEGIN

				
				EXEC dbaadmin.dbo.dbasp_Print @OutputComment,@NestLevel,0,@StatusPrint

				SET		@ReportText = @ReportText + @OutputComment + @CRLF
				
				--  write to the update file if this check failed
				If @save_grade01 like '%fail%'
				   begin
					Select @fail_flag = 'y'
					Select @message = 'insert into DBAcentral.dbo.SQLHealth_Central values(''' + @@servername + ''', ''' 
									+ COALESCE(@save_domain,'<DOMAIN_NAME>') + ''', ''' + COALESCE(@save_envname,'<ENV_NAME>') + ''', '''
									+ COALESCE(@save_subject01,'<SUBJECT>') + ''', '''
									+ COALESCE(@save_value01,'<VALUE>') + ''', '''
									+ COALESCE(@save_grade01,'<GRADE>') + ''', '''
									+ COALESCE(@save_notes01,'<NOTES>') + ''', '''
									+ convert(nvarchar(30), @CheckDate, 121) + ''')'
									
					
					-- WRITE UPDATE LINE TO UPDATE FILE
					SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
					SELECT @MSG='WRITING UPDATE :'+@message;EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
					SELECT @MSG=REPLICATE('-',@PrintWidth);EXEC dbaadmin.dbo.dbasp_Print @MSG,@NestLevel,1,@StatusPrint
					
					SELECT @message = @message + @CRLF +'GO' + @CRLF 
					EXEC	dbaadmin.dbo.dbasp_FileAccess_Write @message,@ReportPath,@updatefile_name,1
				   end				

			END
			FETCH NEXT FROM ResultsCursor INTO @save_subject01,@save_value01,@save_grade01,@save_notes01,@OutputComment
		END
		CLOSE ResultsCursor
		DEALLOCATE ResultsCursor

		EXEC	dbaadmin.dbo.dbasp_FileAccess_Write @ReportText,@ReportPath,@ReportFileName,1

 end

DELETE	@OutputComments
SET		@OutputComment = ''


If @fail_flag = 'n'
   begin
    INSERT INTO	@OutputComments
	values		(CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)+'----------- STATUS PASS -----------')
	
	Select @message = 'insert into DBAcentral.dbo.SQLHealth_Central values(''' + @@servername + ''', ''' 
					+ @save_domain + ''', ''' + @save_envname + ''', ''All Health Checks Pass'', '' '', '' '', '' '', ''' + convert(nvarchar(30), @CheckDate, 121) + ''')'
	--Print  @message
	Select @cmd = 'echo ' + @message + '>>' + @updatefile_path
	EXEC master.sys.xp_cmdshell @cmd, no_output
	
	Select @message = 'go'
	Select @cmd = 'echo ' + @message + '>>' + @updatefile_path
	EXEC master.sys.xp_cmdshell @cmd, no_output

	Select @message = '.'
	Select @cmd = 'echo' + @message + '>>' + @updatefile_path
	EXEC master.sys.xp_cmdshell @cmd, no_output
   end
ELSE
   begin
	INSERT INTO	@OutputComments
	values		(CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)+'----------- STATUS FAIL -----------')   
   end
   
--select * from dbo.HealthCheck_current
insert into dbo.HealthCheck_log select * from dbo.HealthCheck_current
delete from dbo.HealthCheck_log where check_date < @CheckDate-8
--select * from dbo.HealthCheck_log



--  Copy the file to the central server
Select @cmd = 'xcopy /Y /R "' + rtrim(@updatefile_path) + '" "\\' + rtrim(@central_server) + '\DBA_SQL_Register"'
--Print '		'+@cmd
EXEC master.sys.xp_cmdshell @cmd, no_output 

If (select top 1 env_detail from dbo.Local_ServerEnviro where env_type = 'domain') not in ('production', 'stage')
   begin
	Select @cmd = 'xcopy /Y /R "' + rtrim(@updatefile_path) + '" "\\seapsqldba01\DBA_SQL_Register"'
	--Print '		'+@cmd
	EXEC master.sys.xp_cmdshell @cmd, no_output 
   end
Else --If (select datepart(dw, @CheckDate)) in (5)  --Thursday
   begin
	Select @hold_source_path = '\\' + upper(@save_servername) + '\' + upper(@save_servername2) + '_dbasql\dba_reports'
	
	--SELECT CAST(Value AS INT) FROM fn_listextendedproperty('EnableCodeComments', default, default, default, default, default, default)
	
	SET		@SQL	= 'exec dbaadmin.dbo.dbasp_File_Transit'+CHAR(13)+CHAR(10)
					+ '	@source_name = '''+@updatefile_name+''''+CHAR(13)+CHAR(10)
					+ '	,@source_path = '''+@hold_source_path+''''+CHAR(13)+CHAR(10)
					+ '	,@target_env = ''AMER'''+CHAR(13)+CHAR(10)
					+ '	,@target_server = ''seapsqldba01'''+CHAR(13)+CHAR(10)
					+ '	,@target_share = ''DBA_SQL_Register'''+CHAR(13)+CHAR(10)

	EXEC	-- RUN: SCRIPT FILE									
		@Result =	[dbo].[dbasp_RunTSQL]	-- RUN SQL FILE
						@Name				= NULL
						,@DBName			= 'dbaadmin'
						,@Server			= @@Servername
						,@OutputPath		= NULL
						,@StartNestLevel	= 2
						,@OutputText		= @OutputComment OUT
						,@OutputMatrix		= 4
						,@TSQL				= @SQL
						
		IF (@Result > 0 or @Verbose > 1) AND @Verbose > -1
			PRINT REPLICATE('-',80)+CHAR(13)+CHAR(10)+@OutputComment+CHAR(13)+CHAR(10)+REPLICATE('-',80)
   end

If @fail_flag = 'y'
   begin
	Select @message = 'SQL Health Report for server ' + @@servername
	EXEC dbaadmin.dbo.dbasp_sendmail 
		@recipients = @rpt_recipient,  
		@subject = @message ,
		@message = @message ,
	   	@attachments = @reportfile_path		
   end

------------------------------------
--	PRINT OUTPUT ** FINAL OUTPUT IGNORES VERBOSE FLAG **
------------------------------------
SELECT		@OutputComment = @OutputComment + OutputComment +CHAR(13)+CHAR(10)
FROM		@OutputComments
IF @Verbose > -1 PRINT @OutputComment


EXEC sys.sp_updateextendedproperty @Name = 'EnableCodeComments', @value = @save_EnableCodeComments


goto label99


---------------------------  Finalization for process  -----------------------
label99:

drop table #temp_tbl1
drop table #temp_results
drop table #miscTempTable
drop table #seceditTempTable
drop table #showgrps
drop table #ShareTempTable
drop table #scTempTable
drop table #scTempTable2
drop table #loginconfig
drop table #dir_results
drop table #orphans
drop table #Objects
DROP TABLE #SchemaObjCounts
 
GO


--EXEC dbaadmin.[dbo].[dbasp_check_SQLhealth] @Verbose = 0
--GO



 
