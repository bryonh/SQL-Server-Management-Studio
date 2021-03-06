USE [DEPLcontrol]
GO
/****** Object:  StoredProcedure [dbo].[dpsp_ahp_RequestInsertCentral]    Script Date: 10/4/2013 11:02:04 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[dpsp_ahp_RequestInsertCentral] (@RequestID int
						,@BuildLabel nvarchar(500)
						,@TargetSQLname sysname
						,@DBnames_restore nvarchar(500)
						,@DBnames_deploy nvarchar(500)
						,@BaseName sysname
						,@Deploy_type sysname
						,@Request_type sysname = 'normal'
						,@ReleaseNum sysname = null)

/*********************************************************
 **  Stored Procedure dpsp_ahp_RequestInsertCentral                  
 **  Written by Jim Wilson, Getty Images                
 **  October 22, 2010                                      
 **  
 **  This sproc will process deployment requests from AHP
 **  and insert that information into the AHP_Import_Requests
 **  table on the central server.
 **
 **  @Request_type = 'normal', 'restore', 'deploy', 'sprocs_only'
 **
 **  @deploy_type = 'auto, 'manual'
 ***************************************************************/
  as
set nocount on

--	======================================================================================
--	Revision History
--	Date		Author     		Desc
--	==========	====================	=============================================
--	10/22/2010	Jim Wilson		New process.
--	11/02/2010	Jim Wilson		Added CreateDate.
--	11/19/2010	Jim Wilson		Added input parm @DBnames_deploy.
--	03/01/2011	Jim Wilson		Added Release Num input parm.
--	03/04/2011	Jim Wilson		Added input parm @Deploy_type.
--	======================================================================================


/***
Declare @RequestID int
Declare @BuildLabel nvarchar(500)
Declare @TargetSQLname sysname
Declare @DBnames_restore nvarchar(500)
Declare @DBnames_deploy nvarchar(500)
Declare @BaseName sysname
Declare @Deploy_type sysname
Declare @Request_type sysname
Declare @ReleaseNum sysname

Select @RequestID = 42
Select @BuildLabel = 'TranscoderDB_14.0_bTranscoderDB_Main_20101108.3899'
Select @TargetSQLname = 'fredrztsql01\A01'
Select @DBnames_restore = 'Transcoder'
Select @DBnames_deploy = 'Transcoder'
Select @BaseName = 'TXC'
Select @Deploy_type = 'auto'
Select @Request_type = 'normal'
Select @ReleaseNum = '14.0'
--***/

-----------------  declares  ------------------

DECLARE
	 @miscprint			nvarchar(2000)
	,@query				nvarchar(2000)
	,@cmd				nvarchar(4000)
	,@charpos			int
	,@hold_DBname_restore		nvarchar(500)
	,@hold_DBname_deploy		nvarchar(500)
	,@hold_DBname			sysname
	,@save_DBname			sysname
	,@save_servername		sysname
	,@save_servername2		sysname
	,@save_servername3		sysname
	,@save_ProjectName		sysname
	,@save_Buildnum			sysname
	,@save_ReleaseNum		sysname
	,@file_path			nvarchar(500)
	,@save_version			sysname
	,@save_MajorVersion		sysname
	,@save_MinorVersion		sysname
	,@save_CreateDate		datetime
	,@working_BuildLabel		nvarchar(500)
	,@save_Request_type		sysname





/*********************************************************************
 *                Initialization
 ********************************************************************/
Select @save_CreateDate = getdate()

Select @save_servername		= @@servername
Select @save_servername2	= @@servername
Select @save_servername3	= @@servername

Select @charpos = charindex('\', @save_servername)
IF @charpos <> 0
   begin
	Select @save_servername = substring(@@servername, 1, (CHARINDEX('\', @@servername)-1))

	Select @save_servername2 = stuff(@save_servername2, @charpos, 1, '$')

	select @save_servername3 = stuff(@save_servername3, @charpos, 1, '(')
	select @save_servername3 = @save_servername3 + ')'
   end


--  Create temp tables
create table #file_Info(detail nvarchar(4000) null)

create table #restore_names(dbname sysname null)

create table #deploy_names(dbname sysname null)

If @DBnames_restore is null
   begin
	Select @DBnames_restore = ''
   end

If @DBnames_deploy is null
   begin
	Select @DBnames_deploy = ''
   end


----------------------  Print the headers  ----------------------

Print  ' '
Select @miscprint = 'SQL AHP Request Insert to Central for Server: ' + @@servername
Print  @miscprint
Select @miscprint = '-- Process run: ' + convert(varchar(30),getdate())
Print  @miscprint
Print  ' '
raiserror('', -1,-1) with nowait




/****************************************************************
 *                MainLine
 ***************************************************************/


--  Initial insert into dbo.AHP_Import_Requests for the handshake process
If not exists (select 1 from dbo.AHP_Import_Requests where Request_id = @RequestID and TargetSQLname = @TargetSQLname and Request_Type = 'handshake')
   begin
	Select @working_BuildLabel = @BuildLabel
	
	
	--  get the project name and build number
	Select @save_ProjectName = 'unknown'
	Select @charpos = charindex('_', @working_BuildLabel)
	IF @charpos <> 0
	   begin
		Select @save_ProjectName = substring(@working_BuildLabel, 1, @charpos-1)
		Select @save_Buildnum = substring(@working_BuildLabel, @charpos+1, len(@working_BuildLabel)-@charpos)
	   end


	--  get the release version
	If @ReleaseNum is not null
	   begin
		Select @save_version = @ReleaseNum
	   end 
	Else
	   begin
		Select @save_version = (select top 1 releasenum from dbo.AHPbuildcode_prep where BuildLabel = @BuildLabel)
	   end
	
	Select @save_MajorVersion = 'unknown'
	Select @charpos = charindex('.', @save_version)
	IF @charpos <> 0
	   begin
		Select @save_MajorVersion = substring(@save_version, 1, @charpos-1)
		Select @save_MinorVersion = substring(@save_version, @charpos+1, len(@save_version)-@charpos)
	   end

	   	   
	Select @miscprint = 'Insert handshake row for Request_id ' + convert(nvarchar(20), @RequestID) + ' and target server [' + @TargetSQLname + '].'
	Print  @miscprint
	Print  ' '

	insert into dbo.AHP_Import_Requests (Request_id, Request_Type, Request_Status, BuildLabel, ProjectName, ReleaseNum, TargetSQLname, Buildnum, CreateDate)
			values (@RequestID, 'handshake', 'initializing', @BuildLabel, @save_ProjectName, @save_version, @TargetSQLname, @save_Buildnum, @save_CreateDate)
   end



Select @save_ReleaseNum = (select top 1 ReleaseNum from dbo.AHP_Import_Requests where Request_id = @RequestID and TargetSQLname = @TargetSQLname and Request_Type = 'handshake')
Select @save_Buildnum = (select top 1 Buildnum from dbo.AHP_Import_Requests where Request_id = @RequestID and TargetSQLname = @TargetSQLname and Request_Type = 'handshake')


--  Load temp tables
Select @hold_DBname_restore = @DBnames_restore
Delete from #restore_names

If @Request_type like '%sprocs%' or @Request_type like '%deploy%'
   begin
	goto skip_restore_names
   end

start_dbname_restore:
If @hold_DBname_restore like '%,%'
   begin
	Select @charpos = charindex(',', @hold_DBname_restore)
	IF @charpos <> 0
	   begin
		Select @save_DBname = substring(@hold_DBname_restore, 1, @charpos-1)
		Select @save_DBname = ltrim(rtrim(@save_DBname))
		insert into #restore_names values (@save_DBname)
		Select @hold_DBname_restore = substring(@hold_DBname_restore, @charpos+1, 500)
		Select @hold_DBname_restore = ltrim(rtrim(@hold_DBname_restore))
	   end
   end
Else
   begin
	Select @save_DBname = @hold_DBname_restore
	Select @save_DBname = ltrim(rtrim(@save_DBname))
	insert into #restore_names values (@save_DBname)
	Select @hold_DBname_restore = ''
   end

--  Check for more DBnames to process
If @hold_DBname_restore <> ''
   begin
	goto start_dbname_restore
   end


skip_restore_names:




If @Request_type like '%restore%'
   begin
	goto skip_deploy_names
   end


Select @hold_DBname_deploy = @DBnames_deploy
Delete from #deploy_names

start_dbname_deploy:
If @hold_DBname_deploy like '%,%'
   begin
	Select @charpos = charindex(',', @hold_DBname_deploy)
	IF @charpos <> 0
	   begin
		Select @save_DBname = substring(@hold_DBname_deploy, 1, @charpos-1)
		Select @save_DBname = ltrim(rtrim(@save_DBname))
		insert into #deploy_names values (@save_DBname)
		Select @hold_DBname_deploy = substring(@hold_DBname_deploy, @charpos+1, 500)
		Select @hold_DBname_deploy = ltrim(rtrim(@hold_DBname_deploy))
	   end
   end
Else
   begin
	Select @save_DBname = @hold_DBname_deploy
	Select @save_DBname = ltrim(rtrim(@save_DBname))
	insert into #deploy_names values (@save_DBname)
	Select @hold_DBname_deploy = ''
   end

--  Check for more DBnames to process
If @hold_DBname_deploy <> ''
   begin
	goto start_dbname_deploy
   end


skip_deploy_names:



--  Loop for the database restores
If (select count(*) from #restore_names) > 0
   begin
	start_dbname1:
	
	Select @save_DBname = (select top 1 dbname from #restore_names)


	If not exists (select 1 from dbo.AHP_Import_Requests where Request_id = @RequestID and TargetSQLname = @TargetSQLname and DBname = @save_DBname)
	   begin
	   	Select @miscprint = 'Insert row for Request_id ' + convert(nvarchar(20), @RequestID) + ', target server [' + @TargetSQLname + '] and DBname [' + @save_DBname + '].'
		Print  @miscprint
		Print  ' '

		insert into dbo.AHP_Import_Requests (Request_id, Request_Type, Request_Status, BuildLabel, ProjectName, ReleaseNum, TargetSQLname, DBname, BaseName, Buildnum, CreateDate)
				values (@RequestID, 'restore', 'initializing', @BuildLabel, @save_ProjectName, @save_ReleaseNum, @TargetSQLname, @save_DBname, @BaseName, @save_Buildnum, @save_CreateDate)
	   end
   

	--  Check for more DBnames to process
	Delete from #restore_names where dbname = @save_DBname
	If (select count(*) from #restore_names) > 0
	   begin
		goto start_dbname1
	   end


   end



If (select count(*) from #deploy_names) > 0
   begin
	start_dbname2:
	
	Select @save_DBname = (select top 1 dbname from #deploy_names)
	If @Request_type = 'sprocs_only'
	   begin
		Select @save_Request_type = 'sprocs_only'
	   end
	Else
	   begin
		Select @save_Request_type = 'deploy'
	   end


	If not exists (select 1 from dbo.AHP_Import_Requests where Request_id = @RequestID and TargetSQLname = @TargetSQLname and DBname = @save_DBname and Request_Type <> 'restore')
	   begin
	   	Select @miscprint = 'Insert row for Request_id ' + convert(nvarchar(20), @RequestID) + ', target server [' + @TargetSQLname + '] and DBname [' + @save_DBname + '].'
		Print  @miscprint
		Print  ' '

		insert into dbo.AHP_Import_Requests (Request_id, Request_Type, Request_Status, BuildLabel, ProjectName, ReleaseNum, TargetSQLname, DBname, BaseName, Buildnum, CreateDate)
				values (@RequestID, @save_Request_type, 'initializing', @BuildLabel, @save_ProjectName, @save_ReleaseNum, @TargetSQLname, @save_DBname, @BaseName, @save_Buildnum, @save_CreateDate)
	   end
   

	--  Check for more DBnames to process
	Delete from #deploy_names where dbname = @save_DBname
	If (select count(*) from #deploy_names) > 0
	   begin
		goto start_dbname2
	   end

   end




--  Set rows for this request to Central_Inserted
If @Deploy_type = 'auto'
   begin
	Update dbo.AHP_Import_Requests set Request_Status = 'Central_Inserted' 
			where Request_id = @RequestID 
			 and TargetSQLname = @TargetSQLname
   end
Else
   begin
	Update dbo.AHP_Import_Requests set Request_Status = 'Central_Inserted_manual' 
			where Request_id = @RequestID 
			 and TargetSQLname = @TargetSQLname
   end





-----------------  Finalizations  ------------------

label99:


drop table #file_Info
drop table #restore_names
drop table #deploy_names









GO
