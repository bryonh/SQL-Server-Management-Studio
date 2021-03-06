--USE [dbaadmin]
--GO
--/****** Object:  StoredProcedure [dbo].[dbasp_autorestore]    Script Date: 07/27/2011 13:47:58 ******/
--SET ANSI_NULLS ON
--GO
--SET QUOTED_IDENTIFIER ON
--GO


--ALTER PROCEDURE [dbo].[dbasp_autorestore] ( @full_path nvarchar(500) = null, 
--					@dbname sysname = null,
--					@ALTdbname sysname = null,
--					@backupname sysname = null, 
--					@backmidmask sysname = '_db_2', 
--					@diffmidmask sysname = '_dfntl_2', 
--					@datapath nvarchar(100) = null, 
--					@data2path nvarchar(100) = null, 
--					@logpath nvarchar(100) = null, 
--					@sourcepath char(1) = 'n',
--					@force_newldf char(1) = 'n',
--					@drop_dbFlag char(1) = 'n',
--					@differential_flag char(1) = 'n',
--					@db_norecovOnly_flag char(1) = 'n',
--					@db_diffOnly_flag char(1) = 'n',
--					@post_shrink char(1) = 'n',
--					@complete_on_diffOnly_fail char(1) = 'n',
--					@script_out char(1) = 'y',
--					@DTstmp_in_DBfilenames char(1) = 'n',
--					@partial_flag char(1) = 'n',
--		 			@filegroup_name sysname = '',
--		 			@file_name nvarchar(500) = '')

--/*********************************************************
-- **  Stored Procedure dbasp_autorestore                  
-- **  Written by Jim Wilson, Getty Images                
-- **  September 21, 2001                                      
-- **  
-- **  This procedure is used for automated database
-- **  restore processing.
-- **
-- **  This proc accepts the following input parms:
-- **  - @full_path is the path where the backup file can be found
-- **    example - "\\seafresqlwcds\seafresqlwcds_dbasql"
-- **  - @dbname is the name of the database being restored.
-- **  - @ALTdbname is the "new" name of the database being restored (if you need a different DB name).
-- **  - @backupname is the name pattern of the backup file to be restored.
-- **  - @backmidmask is the mask for the midpart of the backup file name (i.e. '_db_2')
-- **  - @diffmidmask is the mask for the midpart of the differential file name (i.e. '_dfntl_2')
-- **  - @datapath is the target path for the data files (optional)
-- **  - @logpath is the target path for the log files (optional)
-- **  - @sourcepath is a flag to force the usage of the file paths
-- **    designated in the source backup.  Specify "y" to set on.
-- **  - @force_newldf is a flag to force the creation of a new ldf file
-- **  - @drop_dbFlag is a flag to force a drop of the DB prior to restore.
-- **  - @differential_flag is a flag to indicate a recovery for a 
-- **    DB backup followed by a differential backup.
-- **  - @db_norecovOnly_flag indicates a DB recovery with the norecovery parm,
-- **    which should be followed later by a differential only restore.
-- **  - @db_diffOnly_flag indicates a differential only restore. 
-- **  - @post_shrink is for a post restore file shrink (y or n)
-- **  - @complete_on_diffOnly_fail will finish the restore of a DB after a failed 
-- **    differential restore'
-- **  - @script_out will either script out the restore commands or run the restore
-- **    within the context of the sproc.
-- **  - @DTstmp_in_DBfilenames will add a time stamp to the DB physical file names (y or n).  
-- **  - @partial_flag = 'y' if you want to restore just a single file group.  
-- **  - @filegroup_name if a file group restore is requested.  
-- **  - @file_name if a file name restore is requested.  
-- ***************************************************************/
--  as
--  SET NOCOUNT ON

----	======================================================================================
----	Revision History
----	Date		Author     		Desc
----	==========	====================	=============================================
----	04/26/2002	Jim Wilson		Revision History added
----	06/10/2002	Jim Wilson		Changed isql to osql
----	07/29/2002	Jim Wilson		Set default path by looking at the path for the 
----						master DB files.
----	09/24/2002	Jim Wilson		Modified output share example 
----	12/23/2002	Jim Wilson		Added backup name parm 
----	01/08/2003	Jim Wilson		Added flag for forcing a new ldf file 
----	04/14/2003	Jim Wilson		Fixed shrink ldf file process (detach and reatach) 
----	10/13/2003	Jim Wilson		The process will now still work if multiple backup
----						files are found.  Newest file is used.  The default 
----						backup name was chaged so that dbname_DB anywhere in
----						the backup file name will work. 
----						Added drop DB flag.
----	06/14/2004	Jim Wilson		Added differential restore process
----	07/20/2004	Jim Wilson		New split processing (DB restore with norecovery or
----						differential only)
----	08/10/2004	Jim Wilson		New set standard mdf file name process
----	08/16/2004	Jim Wilson		Fixed time stamp for just after midnight(12am to 00am)
----	08/18/2005	Jim Wilson		Added code for LiteSpeed processing.
----	08/19/2005	Jim Wilson		Added retry for the 'dir' command.
----	12/13/2005	Jim Wilson		Removed order by for differential files in the cursor.
----	06/22/2006	Jim Wilson		Updated for SQL 2005.
----	07/28/2006	Jim Wilson		Change filelist table for Litespeed backup header.
----	12/06/2006	Jim Wilson		Added 2 masks for non-standard backup and differentail file names.
----	03/23/2007	Jim Wilson		Leading underscore for input parm @diffmidmask was missing.
----	07/25/2007	Jim Wilson		Added code for RedGate processing.
----	11/12/2007	Jim Wilson		Added support for type 'F' files.
----	05/27/2008	Jim Wilson		New shrink DB process using @force_newldf = 'x'
----	05/27/2008	Jim Wilson		Added data2path and post_restore shrink.
----	07/23/2008	Jim Wilson		Major revisions; added input parms @complete_on_diffOnly_fail and
----						@script_out.  Now retores can be done within the context of this sproc.
----	07/28/2008	Jim Wilson		Added if scriptout='n' at end.
----	08/05/2008	Jim Wilson		Modified error checking for Redgate restores.
----	08/06/2008	Jim Wilson		Post file shrink is now just for LDF files.  Also
----						added time stamp to data file names, new ability to
----						restore to alternate DBname, and alter DB options after restore.
----	03/30/2009	Jim Wilson		Change path to \\localhost for local restores to unc.
----	04/16/2009	Jim Wilson		Removed \\localhostcode and added code to get the driveletter path.
----	05/19/2009	Jim Wilson		Added @partial_flag and @filegroup_name input parms.
----	05/28/2009	Jim Wilson		Added @file_name input parms.
----	06/16/2009	Jim Wilson		Fixed bug with standard restore for RESTORE DATABASE line.
----	07/07/2009	Jim Wilson		Removed filegroup parm from redgate diff restore syntax.
----	04/20/2011	Jim Wilson		Added TDEThumbprint column to filelist temp table.  Now works for 2005 and 2008.
----	======================================================================================


--/***
--Declare @full_path nvarchar(100)
--Declare @dbname sysname
--Declare @ALTdbname sysname
--Declare @backupname sysname
--Declare @backmidmask sysname
--Declare @diffmidmask sysname 
--Declare @datapath nvarchar(100)
--Declare @data2path nvarchar(100)
--Declare @logpath nvarchar(100)
--Declare @sourcepath char(1)
--Declare @force_newldf char(1)
--Declare @drop_dbFlag char(1)
--Declare @differential_flag char(1)
--Declare @db_norecovOnly_flag char(1)
--Declare @db_diffOnly_flag char(1)
--Declare @post_shrink char(1)
--Declare @complete_on_diffOnly_fail char(1)
--Declare @script_out char(1)
--Declare @DTstmp_in_DBfilenames char(1)
--Declare @partial_flag char(1)
--Declare @filegroup_name sysname
--Declare @file_name nvarchar(500)


--select @full_path = '\\SQLDEPLOYER04\SQLDEPLOYER04_restore\BNDL'
--select @dbname = 'Bundle'
----select @ALTdbname = 'ArtistListing_new'
----Select @backupname = 'dbaadmin_db'
--Select @backmidmask = '_db_2' 
--Select @diffmidmask = '_dfntl_2' 
--select @datapath = 'd:\mssql.1\data'
----select @data2path = 'e:\mssql.1\data'
--select @logpath = 'd:\mssql.1\data'
--select @sourcepath = 'n' 
--select @force_newldf = 'n' 
--select @drop_dbFlag = 'n'
--select @differential_flag = 'n'
--select @db_norecovOnly_flag = 'n'
--select @db_diffOnly_flag = 'n'
--Select @post_shrink = 'n'
--Select @complete_on_diffOnly_fail = 'n'
--Select @script_out = 'y'
--Select @DTstmp_in_DBfilenames = 'y'
--Select @partial_flag = 'n'
--Select @filegroup_name = ''
--Select @file_name = ''
----***/



-------------------  declares  ------------------
--DECLARE
--	 @miscprint			nvarchar(4000)
--	,@error_count			int
--	,@retry_count			int
--	,@cmd 				nvarchar(4000)
--	,@Restore_cmd			nvarchar(4000)
--	,@retcode 			int
--	,@filecount			smallint
--	,@filename_wild			nvarchar(100)
--	,@diffname_wild			nvarchar(100)
--	,@charpos			int
--	,@query 			nvarchar(4000)
--	,@mssql_data_path		nvarchar(255)
--	,@savePhysicalNamePart		nvarchar(260)
--	,@savefilepath			nvarchar(260)
--	,@hold_filedate			nvarchar(12)
--	,@save_filedate			nvarchar(12)
--	,@save_fileYYYY			nvarchar(4)
--	,@save_fileMM			nvarchar(2)
--	,@save_fileDD			nvarchar(2)
--	,@save_fileHH			nvarchar(2)
--	,@save_fileMN			nvarchar(2)
--	,@save_fileAMPM			nvarchar(1)
--	,@save_LogicalName		sysname
--	,@save_cmdoutput		nvarchar(255)
--	,@save_subject			sysname
--	,@save_message			nvarchar(500)
--	,@hold_ldfpath			nvarchar(260)
--	,@hold_backupfilename		sysname
--	,@hold_diff_file_name		sysname
--	,@fileseq			smallint
--	,@fileseed			smallint
--	,@diffname			sysname
--	,@BkUpMethod			nvarchar(5)
--	,@detach_cmd			sysname
--	,@deleteLDF_cmd			sysname
--	,@attach_cmd			sysname
--	,@DateStmp 			nvarchar(15)
--	,@Hold_hhmmss			nvarchar(8)
--	,@drop_dbname			sysname
--	,@check_dbname 			sysname
--	,@save_servername		sysname
--	,@save_servername2		sysname
--	,@save_localservername_mask	sysname
--	,@save_alt_full_path		nvarchar(500)
--	,@outpath			nvarchar(500)
--	,@save_fg_name			nvarchar(500)
--	,@save_fn_name			nvarchar(500)


	
--DECLARE
--	 @cu11cmdoutput			nvarchar(255)

--DECLARE
--	 @cu12fileid			smallint
--	,@cu12name			nvarchar(128)
--	,@cu12filename			nvarchar(260)

--DECLARE
--	 @cu21LogicalName		nvarchar(128)
--	,@cu21PhysicalName		nvarchar(260)
--	,@cu21Type			char(1)
--	,@cu21FileGroupName		nvarchar(128)

--DECLARE
--	 @cu22LogicalName		nvarchar(128)
--	,@cu22PhysicalName		nvarchar(260)
--	,@cu22Type			char(1)
--	,@cu22FileGroupName		nvarchar(128)

--DECLARE
--	 @cu25cmdoutput			nvarchar(255)



------------------  initial values  -------------------
--Select @retry_count = 0
--Select @error_count = 0
--Select @hold_filedate = '200001010001'
--Select @BkUpMethod = 'MS'
--select @filename_wild = ''
--select @diffname_wild = ''
--select @DateStmp = ''

--Select @save_servername	= @@servername
--Select @save_servername2 = @@servername

--Select @charpos = charindex('\', @save_servername)
--IF @charpos <> 0
--   begin
--	Select @save_servername = substring(@@servername, 1, (CHARINDEX('\', @@servername)-1))

--	Select @save_servername2 = stuff(@save_servername2, @charpos, 1, '$')
--   end

--Select @save_localservername_mask = '\\' + @save_servername + '%'


--If @ALTdbname is not null and @ALTdbname <> ''
--   begin
--	Select @check_dbname = @ALTdbname 
--   end
--Else
--   begin
--	Select @check_dbname = @dbname 
--   end



--If @DTstmp_in_DBfilenames = 'y'
--   begin
--	Set @Hold_hhmmss = convert(varchar(8), getdate(), 8)
--	Set @DateStmp = '_' + convert(char(8), getdate(), 112) + substring(@Hold_hhmmss, 1, 2) + substring(@Hold_hhmmss, 4, 2) + substring(@Hold_hhmmss, 7, 2) 
--   end


--create table #db_files(fileid smallint
--			,name nvarchar(128)
--			,filename nvarchar(260))


--create table #DirectoryTempTable(cmdoutput nvarchar(255) null)
--create table #filelist(LogicalName nvarchar(128) null, 
--						PhysicalName nvarchar(260) null, 
--						Type char(1), 
--						FileGroupName nvarchar(128) null, 
--						Size numeric(20,0), 
--						MaxSize numeric(20,0),
--						FileId bigint,
--						CreateLSN numeric(25,0),
--						DropLSN numeric(25,0),
--						UniqueId uniqueidentifier,
--						ReadOnlyLSN numeric(25,0),
--						ReadWriteLSN numeric(25,0),
--						BackupSizeInBytes bigint,
--						SourceBlockSize int,
--						FileGroupId int,
--						LogGroupGUID uniqueidentifier null,
--						DifferentialBaseLSN numeric(25,0),
--						DifferentialBaseGUID uniqueidentifier,
--						IsReadOnly bit,
--						IsPresent bit,
--						TDEThumbprint varbinary(32) null
--						)

--create table #filelist_ls (LogicalName nvarchar(128) null, 
--						PhysicalName nvarchar(260) null, 
--						Type char(1), 
--						FileGroupName nvarchar(128) null, 
--						Size numeric(20,0), 
--						MaxSize numeric(20,0)
--						)

--create table #filelist_rg(LogicalName nvarchar(128) null, 
--						PhysicalName nvarchar(260) null, 
--						Type char(1), 
--						FileGroupName nvarchar(128) null, 
--						Size numeric(20,0), 
--						MaxSize numeric(20,0),
--						FileId bigint,
--						CreateLSN numeric(25,0),
--						DropLSN numeric(25,0),
--						UniqueId uniqueidentifier,
--						ReadOnlyLSN numeric(25,0),
--						ReadWriteLSN numeric(25,0),
--						BackupSizeInBytes bigint,
--						SourceBlockSize int,
--						FileGroupId int,
--						LogGroupGUID sysname null,
--						DifferentialBaseLSN numeric(25,0),
--						DifferentialBaseGUID uniqueidentifier,
--						IsReadOnly bit,
--						IsPresent bit
--						)



----  Check input parms
--if @full_path is null or @full_path = ''
--   BEGIN
--	Select @miscprint = 'DBA WARNING: Invalid parameters to dbasp_autorestore - @full_path must be specified.' 
--	Print @miscprint
--	Select @error_count = @error_count + 1
--	goto label99
--   END

--if @dbname is null or @dbname = ''
--   BEGIN
--	Select @miscprint = 'DBA WARNING: Invalid parameters to dbasp_autorestore - @dbname must be specified.' 
--	Print @miscprint
--	Select @error_count = @error_count + 1
--	goto label99
--   END

--if @db_norecovOnly_flag = 'y' and @db_diffOnly_flag = 'y'
--   BEGIN
--	Select @miscprint = 'DBA WARNING: Invalid parameters - @db_norecovOnly_flag and @db_diffOnly_flag cannot both be selected' 
--	Print @miscprint
--	Select @error_count = @error_count + 1
--	goto label99
--   END

--if @db_diffOnly_flag = 'y' and @differential_flag <> 'y'
--   BEGIN
--	Select @miscprint = 'DBA WARNING: Invalid parameters - @differential_flag must = ''y'' if @db_diffOnly_flag is selected' 
--	Print @miscprint
--	Select @error_count = @error_count + 1
--	goto label99
--   END

--If @force_newldf = 'y' and @db_norecovOnly_flag = 'y'
--   BEGIN
--	Select @miscprint = 'DBA WARNING: Invalid parameters - @force_newldf and @db_diffOnly_flag cannot both be selected' 
--	Print @miscprint
--	Select @error_count = @error_count + 1
--	goto label99
--   END


--If @script_out <> 'y'
--   begin
--	select @miscprint = 'DBA Message:  This restore will be done within the context of the stored procedure execution for database [' + @check_dbname + ']'
--	print  @miscprint
--	print  ''
--   end

--If @backupname is null or @backupname = ''
--   begin
--	select @filename_wild = @filename_wild + @dbname + @backmidmask + '*'
--	select @diffname_wild = @diffname_wild + @dbname + @diffmidmask + '*'
--   end
--Else
--   begin
--	Select @diffname = REPLACE(@backupname, '_db_', '_dfntl_')
--	select @filename_wild = @filename_wild + @backupname
--	select @diffname_wild = @diffname_wild + @diffname
--   end



--If @data2path is null
--   begin
--	select @data2path = @datapath
--   end

----  Set path for local restores
--If @full_path like @save_localservername_mask and @full_path like '\\%' and @full_path not like '%$%'
--   begin
--	--  Get the path to the source file share
--	Select @save_alt_full_path = replace(@full_path, '\\', '')
	 

--	Select @charpos = charindex('\', @save_alt_full_path)
--	IF @charpos <> 0
--	   begin
--		Select @save_alt_full_path = substring(@save_alt_full_path, @charpos+1, 255)
--		Select @save_alt_full_path = ltrim(rtrim(@save_alt_full_path))
--	   end

--	exec dbaadmin.dbo.dbasp_get_share_path @save_alt_full_path, @outpath output
--	If @outpath is not null
--	   begin
--		select @full_path = @outpath
--	   end

--   end



--/****************************************************************
-- *                MainLine
-- ***************************************************************/

--If @script_out = 'y'
--   begin
--	select @miscprint = 'Use Master'
--	print  @miscprint
--	select @miscprint = 'go'
--	print  @miscprint
--	print  ' '
--   end

----  If this is for a differential only restore, jump to that section
--If @db_diffOnly_flag = 'y'
--   begin
--	goto label12
--   end

--select @cmd = 'dir ' + @full_path + '\' + @filename_wild
----print @cmd

--start_dir:
--insert into #DirectoryTempTable exec master.sys.xp_cmdshell @cmd
--delete from #DirectoryTempTable where cmdoutput is null
--delete from #DirectoryTempTable where cmdoutput like '%<DIR>%'
--delete from #DirectoryTempTable where cmdoutput like '%Directory of%'
--delete from #DirectoryTempTable where cmdoutput like '% File(s) %'
--delete from #DirectoryTempTable where cmdoutput like '% Dir(s) %'
--delete from #DirectoryTempTable where cmdoutput like '%Volume in drive%'
--delete from #DirectoryTempTable where cmdoutput like '%Volume Serial Number%'
----select * from #DirectoryTempTable

--select @filecount = (select count(*) from #DirectoryTempTable)

--If @filecount < 1
--   BEGIN
--	If @retry_count < 5
--	   begin
--		Select @retry_count = @retry_count + 1
--		Waitfor delay '00:00:10'
--		delete from #DirectoryTempTable
--		goto start_dir
--	   end
--	Else
--	   begin
--		Select @miscprint = 'DBA WARNING: No files found for dbasp_autorestore at ' + @full_path + ' using mask "' + @filename_wild + '"'
--		Print @miscprint
--		Select @error_count = @error_count + 1
--		goto label99
--	   end
--   END
--Else
 --  BEGIN
	--Start_cmdoutput01:
	--Select @save_cmdoutput = (Select top 1 cmdoutput from #DirectoryTempTable order by cmdoutput)
	--Select @cu11cmdoutput = @save_cmdoutput

	--select @save_fileYYYY = substring(@cu11cmdoutput, 7, 4)
	--select @save_fileMM = substring(@cu11cmdoutput, 1, 2)
	--select @save_fileDD = substring(@cu11cmdoutput, 4, 2)
	--select @save_fileHH = substring(@cu11cmdoutput, 13, 2)
	--Select @save_fileAMPM = substring(@cu11cmdoutput, 18, 1)
	--If @save_fileAMPM = 'a' and @save_fileHH = '12'
	--   begin
	--	Select @save_fileHH = '00'
	--   end
	--Else If @save_fileAMPM = 'p' and @save_fileHH <> '12'
	--   begin
	--	Select @save_fileHH = @save_fileHH + 12
	--   end
	--select @save_fileMN = substring(@cu11cmdoutput, 16, 2)
	--Select @save_filedate = @save_fileYYYY + @save_fileMM + @save_fileDD + @save_fileHH + @save_fileMN

	--If @hold_filedate < @save_filedate
	--   begin
	--	select @hold_backupfilename = ltrim(rtrim(substring(@cu11cmdoutput, 40, 200)))
	--   end

	--Delete from #DirectoryTempTable where cmdoutput = @save_cmdoutput
	--If (select count(*) from #DirectoryTempTable) > 0
	--   begin
	--	goto Start_cmdoutput01
	--   end
 --  END


----  Check file name to determin if we can process the file
--If @hold_backupfilename like '%.bkp'
--   begin
--	If exists (select 1 from master.sys.objects where name = 'xp_backup_database' and type = 'x')
--	   begin
--		Print '--  Note:  LiteSpeed Syntax will be used for this request'
--		Print ' '
--		Select @BkUpMethod = 'LS'
--	   end
--	Else
--	   begin
--		Select @miscprint = 'DBA WARNING: LiteSpeed backups cannot be processed by dbasp_autorestore on this server. ' + @full_path + '\' + @hold_backupfilename 
--		Print @miscprint
--		Select @error_count = @error_count + 1
--		goto label99
--	   end
--   end

--If @hold_backupfilename like '%.SQB%'
--   begin
--	If exists (select 1 from master.sys.objects where name = 'sqlbackup' and type = 'x')
--	   begin
--		Print '--  Note:  RedGate Syntax will be used for this request'
--		Print ' '
--		Select @BkUpMethod = 'RG'
--	   end
--	Else
--	   begin
--		Select @miscprint = 'DBA WARNING: RedGate backups cannot be processed by dbasp_autorestore on this server. ' + @full_path + '\' + @hold_backupfilename 
--		Print @miscprint
--		Select @error_count = @error_count + 1
--		goto label99
--	   end
--   end



--If @drop_dbFlag = 'y'
--   begin
--	If @ALTdbname is not null and @ALTdbname <> ''
--	   begin
--		Select @drop_dbname = @ALTdbname 
--	   end
--	Else
--	   begin
--		Select @drop_dbname = @ALTdbname 
--	   end

--	If @script_out = 'y'
--	   begin
--		select @miscprint = 'DROP DATABASE ' + @drop_dbname 
--		print  @miscprint
--		select @miscprint = 'go'
--		print  @miscprint
--		print  ' '
--		select @miscprint = 'Waitfor delay ''00:00:10'''
--		print  @miscprint
--		select @miscprint = 'go'
--		print  @miscprint
--		Print  ' '
--		Print  ' '
--	   end
--	Else
--	   begin
--		If exists (select 1 from master.sys.databases where name = @drop_dbname)
--		   begin
--			Select @cmd = 'drop database [' + @drop_dbname + ']'
--			Print  @cmd
--			Exec(@cmd)

--			waitfor delay '00:00:05'
--		   end

		----  Verify the DB no longer exists
		--If exists (select 1 from master.sys.databases where name = @drop_dbname)
		--   BEGIN
		--	Select @miscprint = 'DBA ERROR: Unable to drop database ' + @drop_dbname + '.  The autorestore process is not able to continue.' 
		--	Print  @miscprint
		--	Select @error_count = @error_count + 1
		--	goto label99
		--   END
	 --  end
  -- end
	
	
If @BkUpMethod = 'LS'
   begin
	select @miscprint = 'EXEC master.dbo.xp_restore_database'
	print  @miscprint
	If @ALTdbname is not null and @ALTdbname <> ''
	   begin
		select @miscprint = '  @database =  ''' + @ALTdbname + ''''
		print  @miscprint
	   end
	Else
	   begin
		select @miscprint = '  @database =  ''' + @dbname + ''''
		print  @miscprint
	   end
	select @miscprint = ', @filename = ''' + @full_path + '\' + @hold_backupfilename + ''''
	print  @miscprint

	select @Restore_cmd = ''
	select @Restore_cmd = @Restore_cmd + 'EXEC master.dbo.xp_restore_database'
	select @Restore_cmd = @Restore_cmd + '  @database =  ''' + @check_dbname + ''''
	select @Restore_cmd = @Restore_cmd + ', @filename = ''' + @full_path + '\' + @hold_backupfilename + ''''


	If @differential_flag = 'y' or @db_norecovOnly_flag = 'y'
	   begin
		select @miscprint = ', @with = NORECOVERY'
		print  @miscprint
		select @miscprint = ', @with = ''REPLACE'''
		print  @miscprint

		select @Restore_cmd = @Restore_cmd + ', @with = NORECOVERY'
		select @Restore_cmd = @Restore_cmd + ', @with = ''REPLACE'''
	   end	
	Else
	   begin
		select @miscprint = ', @with = RECOVERY'
		print  @miscprint
		select @miscprint = ', @with = ''REPLACE'''
		print  @miscprint

		select @Restore_cmd = @Restore_cmd + ', @with = RECOVERY'
		select @Restore_cmd = @Restore_cmd + ', @with = ''REPLACE'''
	   end	

	delete from #filelist_ls

	Select @query = 'EXEC master.dbo.xp_restore_filelistonly @filename = ''' + rtrim(@full_path) + '\' + rtrim(@hold_backupfilename) + ''''
	insert into #filelist_ls exec (@query)
	If (select count(*) from #filelist_ls) = 0
	   begin
		Select @miscprint = 'DBA Error: Unable to process LiteSpeed filelistonly for file ' + @full_path + '\' + @hold_backupfilename 
		Print @miscprint
		Select @error_count = @error_count + 1
		goto label99
	   end

	--  set the default path just in case we need it
	Select @mssql_data_path = (select filename from master.sys.sysfiles where fileid = 1)
	select @charpos = charindex('master', @mssql_data_path)
	select @mssql_data_path = left(@mssql_data_path, @charpos-1)
	select @fileseq = 1


	EXECUTE('DECLARE cu21_cursor Insensitive Cursor For ' +
	  'SELECT f.LogicalName, f.PhysicalName, f.Type, f.FileGroupName
	   From #filelist_ls   f ' +
	  'for Read Only')

	OPEN cu21_cursor
	
	WHILE (21=21)
	 Begin
		FETCH Next From cu21_cursor Into @cu21LogicalName, @cu21PhysicalName, @cu21Type, @cu21FileGroupName
		IF (@@fetch_status < 0)
	           begin
	              CLOSE cu21_cursor
		      BREAK
	           end


		select @savePhysicalNamePart = @cu21PhysicalName
		label01:

		select @charpos = charindex('\', @savePhysicalNamePart)
		IF @charpos <> 0
		   begin
  		    select @savePhysicalNamePart = substring(@savePhysicalNamePart, @charpos + 1, 100)
		   end	
	
		select @charpos = charindex('\', @savePhysicalNamePart)
		IF @charpos <> 0
		   begin
		    goto label01
 		   end


		If @DTstmp_in_DBfilenames = 'y'
		   begin
			If @savePhysicalNamePart like '%.mdf'
			   begin		
				Select @savePhysicalNamePart = replace(@savePhysicalNamePart, '.mdf', @DateStmp + '.mdf')
			   end
			Else If @savePhysicalNamePart like '%.ndf'
			   begin		
				Select @savePhysicalNamePart = replace(@savePhysicalNamePart, '.ndf', @DateStmp + '.ndf')
			   end
			Else If @savePhysicalNamePart like '%.ldf'
			   begin		
				Select @savePhysicalNamePart = replace(@savePhysicalNamePart, '.ldf', @DateStmp + '.ldf')
			   end
			Else
			   begin		
				Select @savePhysicalNamePart = @savePhysicalNamePart + @DateStmp
			   end
		   end


		If @sourcepath = 'y'
		   begin
			Select @savefilepath = @cu21PhysicalName
		   end
		Else If @datapath is not null and @cu21Type in ('D', 'F')
		   begin
			If @savePhysicalNamePart not like '%mdf' and @data2path is not null
			   begin
				Select @savefilepath = @data2path + '\' + @savePhysicalNamePart
			   end
			Else
			   begin
				Select @savefilepath = @datapath + '\' + @savePhysicalNamePart
			   end
		   end
		Else IF @logpath is not null and @cu21Type = 'L'
		   begin
			Select @savefilepath = @logpath + '\' + @savePhysicalNamePart
		   end
		Else
		   begin
			Select @savefilepath = @mssql_data_path + @savePhysicalNamePart
		   end


		select @miscprint = ', @with = ''MOVE "' + @cu21LogicalName + '" to "' + @savefilepath + '"'''
		print  @miscprint

		select @Restore_cmd = @Restore_cmd + ', @with = ''MOVE "' + @cu21LogicalName + '" to "' + @savefilepath + '"'''


		--  capture ldf info if needed
		If @force_newldf = 'y'
		   begin
			select @charpos = charindex('.ldf', @savefilepath)
			IF @charpos <> 0
			   begin
				select @hold_ldfpath = @savefilepath
			   end
			Else
			   begin
				insert #db_files values (@fileseq, @cu21LogicalName, @savefilepath)
			   end
		   end

		select @fileseq = @fileseq + 1



	End  -- loop 21
	DEALLOCATE cu21_cursor



	select @miscprint = ', @with = ''stats'''
	print  @miscprint
	select @miscprint = 'go'
	print  @miscprint
	Print ' '

	select @Restore_cmd = @Restore_cmd + ', @with = ''stats'''


	If @script_out <> 'y'
	   begin
		-- Restore the database
		select @cmd = @Restore_cmd
		Print 'Here is the restore command being executed;'
		Print @cmd
		raiserror('', -1,-1) with nowait

		Exec (@cmd)

		If @@error<> 0
		   begin
			Print 'DBA Error:  Restore Failure (LiteSpeed) for command ' + @cmd
			Select @error_count = @error_count + 1
			goto label99
		   end
	   end



	If @db_norecovOnly_flag = 'y'
	   begin
		Print ' '
		select @miscprint = '--  Note:  This will leave the database in recovery pending mode.'
		print  @miscprint
		goto label99
	
	   end
   end



If @BkUpMethod = 'RG'
   begin
	select @miscprint = 'Declare @cmd nvarchar(4000)'
	print  @miscprint

	select @miscprint = 'Select @cmd = ''-SQL "RESTORE DATABASE [' + @check_dbname + ']'

	If @partial_flag = 'y' and @filegroup_name is not null and @filegroup_name <> ''
	   begin
		Select @charpos = charindex(',', @filegroup_name)
		IF @charpos <> 0
		   begin
			start_fg_multi:
			select @save_fg_name = substring(@filegroup_name, 1, @charpos-1)
			Select @save_fg_name = ltrim(rtrim(@save_fg_name))
			Select @filegroup_name = substring(@filegroup_name, @charpos+1, 500)

			select @miscprint = @miscprint + ' FILEGROUP=''''' + @filegroup_name + ''''''

			Select @charpos = charindex(',', @filegroup_name)
			IF @charpos <> 0
			   begin
				select @miscprint = @miscprint + ','
				goto start_fg_multi
			   end
		   end
		Else
		   begin
			select @miscprint = @miscprint + ' FILEGROUP=''''' + @filegroup_name + ''''''
		   end
	   end

	If @partial_flag = 'y' and @file_name is not null and @file_name <> ''
	   begin
		If @miscprint like '%FILEGROUP=%'
		   begin
			select @miscprint = @miscprint + ','
		   end

		Select @charpos = charindex(',', @file_name)
		IF @charpos <> 0
		   begin
			start_fn_multi:
			select @save_fn_name = substring(@file_name, 1, @charpos-1)
			Select @save_fn_name = ltrim(rtrim(@save_fn_name))
			Select @file_name = substring(@file_name, @charpos+1, 500)

			select @miscprint = @miscprint + ' FILE=''''' + @file_name + ''''''

			Select @charpos = charindex(',', @file_name)
			IF @charpos <> 0
			   begin
				select @miscprint = @miscprint + ','
				goto start_fn_multi
			   end
		   end
		Else
		   begin
			select @miscprint = @miscprint + ' FILE=''''' + @file_name + ''''''
		   end
	   end

	print  @miscprint

	select @miscprint = '	 FROM DISK = ''''' + @full_path + '\' + @hold_backupfilename + ''''''
	print  @miscprint



	select @Restore_cmd = '-SQL "RESTORE DATABASE [' + @check_dbname + ']'

	If @partial_flag = 'y' and @filegroup_name is not null and @filegroup_name <> ''
	   begin
		Select @charpos = charindex(',', @filegroup_name)
		IF @charpos <> 0
		   begin
			start_fg_multi02:
			select @save_fg_name = substring(@filegroup_name, 1, @charpos-1)
			Select @save_fg_name = ltrim(rtrim(@save_fg_name))
			Select @filegroup_name = substring(@filegroup_name, @charpos+1, 500)

			select @Restore_cmd = @Restore_cmd + ' FILEGROUP=''' + @filegroup_name + ''''

			Select @charpos = charindex(',', @filegroup_name)
			IF @charpos <> 0
			   begin
				select @Restore_cmd = @Restore_cmd + ','
				goto start_fg_multi02
			   end
		   end
		Else
		   begin
			select @Restore_cmd = @Restore_cmd + ' FILEGROUP=''' + @filegroup_name + ''''
		   end
	   end


	If @partial_flag = 'y' and @file_name is not null and @file_name <> ''
	   begin
		If @miscprint like '%FILEGROUP=%'
		   begin
			select @Restore_cmd = @Restore_cmd + ','
		   end

		Select @charpos = charindex(',', @file_name)
		IF @charpos <> 0
		   begin
			start_fn_multi02:
			select @save_fn_name = substring(@file_name, 1, @charpos-1)
			Select @save_fn_name = ltrim(rtrim(@save_fn_name))
			Select @file_name = substring(@file_name, @charpos+1, 500)

			select @Restore_cmd = @Restore_cmd + ' FILE=''' + @file_name + ''''

			Select @charpos = charindex(',', @file_name)
			IF @charpos <> 0
			   begin
				select @Restore_cmd = @Restore_cmd + ','
				goto start_fn_multi02
			   end
		   end
		Else
		   begin
			select @Restore_cmd = @Restore_cmd + ' FILE=''' + @file_name + ''''
		   end
	   end


	select @Restore_cmd = @Restore_cmd + ' FROM DISK = ''' + @full_path + '\' + @hold_backupfilename + ''''


	If @differential_flag = 'y' or @db_norecovOnly_flag = 'y'
	   begin
		If @partial_flag = 'y' and @filegroup_name is not null and @filegroup_name <> ''
		   begin
			select @miscprint = '	 WITH PARTIAL, NORECOVERY'
			print  @miscprint

			select @Restore_cmd = @Restore_cmd + ' WITH PARTIAL, NORECOVERY'
		   end
		Else
		   begin
			select @miscprint = '	 WITH NORECOVERY'
			print  @miscprint

			select @Restore_cmd = @Restore_cmd + ' WITH NORECOVERY'
		   end
	   end	
	Else
	   begin
		If @partial_flag = 'y' and @filegroup_name is not null and @filegroup_name <> ''
		   begin
			select @miscprint = '	 WITH PARTIAL, RECOVERY'
			print  @miscprint

			select @Restore_cmd = @Restore_cmd + ' WITH PARTIAL, RECOVERY'
		   end
		Else
		   begin
			select @miscprint = '	 WITH RECOVERY'
			print  @miscprint

			select @Restore_cmd = @Restore_cmd + ' WITH RECOVERY'
		   end
	   end


	-- Get file header info from the SQB backup file
	delete from #filelist_rg

	Select @query = 'Exec master.dbo.sqlbackup ''-SQL "RESTORE FILELISTONLY FROM DISK = ''''' + rtrim(@full_path) + '\' + rtrim(@hold_backupfilename) + '''''"'''
	insert into #filelist_rg exec (@query)
	If (select count(*) from #filelist_rg) = 0
	   begin
		Select @miscprint = 'DBA Error: Unable to process RedGate filelistonly for file ' + @full_path + '\' + @hold_backupfilename 
		Print @miscprint
		Select @error_count = @error_count + 1
		goto label99
	   end

	--  set the default path just in case we need it
	Select @mssql_data_path = (select filename from master.sys.sysfiles where fileid = 1)
	select @charpos = charindex('master', @mssql_data_path)
	select @mssql_data_path = left(@mssql_data_path, @charpos-1)
	select @fileseq = 1


	EXECUTE('DECLARE cu21_cursor Insensitive Cursor For ' +
	  'SELECT f.LogicalName, f.PhysicalName, f.Type, f.FileGroupName
	   From #filelist_rg   f ' +
	  'for Read Only')

	OPEN cu21_cursor
	
	WHILE (21=21)
	 Begin
		FETCH Next From cu21_cursor Into @cu21LogicalName, @cu21PhysicalName, @cu21Type, @cu21FileGroupName
		IF (@@fetch_status < 0)
	           begin
	              CLOSE cu21_cursor
		      BREAK
	           end


		select @savePhysicalNamePart = @cu21PhysicalName
		label02:
			select @charpos = charindex('\', @savePhysicalNamePart)
			IF @charpos <> 0
			   begin
	  		    select @savePhysicalNamePart = substring(@savePhysicalNamePart, @charpos + 1, 100)
			   end	
	
			select @charpos = charindex('\', @savePhysicalNamePart)
			IF @charpos <> 0
			   begin
			    goto label02
	 		   end


		If @DTstmp_in_DBfilenames = 'y'
		   begin
			If @savePhysicalNamePart like '%.mdf'
			   begin		
				Select @savePhysicalNamePart = replace(@savePhysicalNamePart, '.mdf', @DateStmp + '.mdf')
			   end
			Else If @savePhysicalNamePart like '%.ndf'
			   begin		
				Select @savePhysicalNamePart = replace(@savePhysicalNamePart, '.ndf', @DateStmp + '.ndf')
			   end
			Else If @savePhysicalNamePart like '%.ldf'
			   begin		
				Select @savePhysicalNamePart = replace(@savePhysicalNamePart, '.ldf', @DateStmp + '.ldf')
			   end
			Else
			   begin		
				Select @savePhysicalNamePart = @savePhysicalNamePart + @DateStmp
			   end
		   end



		If @sourcepath = 'y'
		   begin
			Select @savefilepath = @cu21PhysicalName
		   end
		Else If @datapath is not null and @cu21Type in ('D', 'F')
		   begin
			If @savePhysicalNamePart not like '%mdf' and @data2path is not null
			   begin
				Select @savefilepath = @data2path + '\' + @savePhysicalNamePart
			   end
			Else
			   begin
				Select @savefilepath = @datapath + '\' + @savePhysicalNamePart
			   end
		   end
		Else IF @logpath is not null and @cu21Type = 'L'
		   begin
			Select @savefilepath = @logpath + '\' + @savePhysicalNamePart
		   end
		Else
		   begin
			Select @savefilepath = @mssql_data_path + @savePhysicalNamePart
		   end


		select @miscprint = '	,MOVE ''''' + rtrim(@cu21LogicalName) + ''''' to ''''' + rtrim(@savefilepath) + ''''''
		print  @miscprint

		select @Restore_cmd = @Restore_cmd + ', MOVE ''' + rtrim(@cu21LogicalName) + ''' to ''' + rtrim(@savefilepath) + ''''



		--  capture ldf info if needed
		If @force_newldf = 'y'
		   begin
			select @charpos = charindex('.ldf', @savefilepath)
			IF @charpos <> 0
			   begin
				select @hold_ldfpath = @savefilepath
			   end
			Else
			   begin
				insert #db_files values (@fileseq, @cu21LogicalName, @savefilepath)
			   end
		   end

		select @fileseq = @fileseq + 1



	End  -- loop 21
	DEALLOCATE cu21_cursor



	select @miscprint = '	,REPLACE"'''
	print  @miscprint
	select @miscprint = 'SET @cmd = REPLACE(@cmd,CHAR(9),'''')'
	print  @miscprint
	select @miscprint = 'SET @cmd = REPLACE(@cmd,CHAR(13)+char(10),'' '')'
	print  @miscprint
	select @miscprint = 'Exec master.dbo.sqlbackup @cmd'
	print  @miscprint
	select @miscprint = 'go'
	print  @miscprint
	Print ' '

	select @Restore_cmd = @Restore_cmd + ' ,REPLACE"'


	If @script_out <> 'y'
	   begin
		-- Restore the database
		select @cmd = 'Exec master.dbo.sqlbackup ' + @Restore_cmd
		Print 'Here is the restore command being executed;'
		Print @cmd
		raiserror('', -1,-1) with nowait

		Exec master.dbo.sqlbackup @Restore_cmd

		If @db_norecovOnly_flag = 'y' and DATABASEPROPERTYEX (@check_dbname,'status') <> 'RESTORING'
		   begin
			select @miscprint = 'DBA Error:  Restore Failure (Redgate partial restore) for command ' + @cmd
			print  @miscprint
			Select @error_count = @error_count + 1
			goto label99
		   end
		Else If @db_norecovOnly_flag <> 'y' and @differential_flag = 'n' and DATABASEPROPERTYEX (@check_dbname,'status') <> 'ONLINE'
		   begin
			select @miscprint = 'DBA Error:  Restore Failure (Redgate complete restore) for command ' + @cmd
			print  @miscprint
			Select @error_count = @error_count + 1
			goto label99
		   end
	   end


	If @db_norecovOnly_flag = 'y'
	   begin
		Print ' '
		select @miscprint = '--  Note:  This will leave the database in recovery pending mode.'
		print  @miscprint
		goto label99
	   end
   end


--  If not a LiteSpeed or RedGate file ----
If @BkUpMethod = 'MS'
   begin
	select @miscprint = 'RESTORE DATABASE ' + @check_dbname

	select @Restore_cmd = ''
	select @Restore_cmd = @Restore_cmd + 'RESTORE DATABASE ' + @check_dbname

	If @partial_flag = 'y' and @filegroup_name is not null and @filegroup_name <> ''
	   begin
		Select @charpos = charindex(',', @filegroup_name)
		IF @charpos <> 0
		   begin
			start_fg_multi03:
			select @save_fg_name = substring(@filegroup_name, 1, @charpos-1)
			Select @save_fg_name = ltrim(rtrim(@save_fg_name))
			Select @filegroup_name = substring(@filegroup_name, @charpos+1, 500)

			select @miscprint = @miscprint + ' FILEGROUP=''' + @filegroup_name + ''''
			select @Restore_cmd = @Restore_cmd + ' FILEGROUP=''' + @filegroup_name + ''''

			Select @charpos = charindex(',', @filegroup_name)
			IF @charpos <> 0
			   begin
				select @miscprint = @miscprint + ','
				select @Restore_cmd = @Restore_cmd + ','
				goto start_fg_multi03
			   end
		   end
		Else
		   begin
			select @miscprint = @miscprint + ' FILEGROUP=''' + @filegroup_name + ''''
			select @Restore_cmd = @Restore_cmd + ' FILEGROUP=''' + @filegroup_name + ''''
		   end
	   end

	If @partial_flag = 'y' and @file_name is not null and @file_name <> ''
	   begin
		If @miscprint like '%FILEGROUP=%'
		   begin
			select @miscprint = @miscprint + ','
			select @Restore_cmd = @Restore_cmd + ','
		   end

		Select @charpos = charindex(',', @file_name)
		IF @charpos <> 0
		   begin
			start_fn_multi04:
			select @save_fn_name = substring(@file_name, 1, @charpos-1)
			Select @save_fn_name = ltrim(rtrim(@save_fn_name))
			Select @file_name = substring(@file_name, @charpos+1, 500)

			select @miscprint = @miscprint + ' FILE=''''' + @file_name + ''''''
			select @Restore_cmd = @Restore_cmd + ' FILE=''''' + @file_name + ''''''

			Select @charpos = charindex(',', @file_name)
			IF @charpos <> 0
			   begin
				select @miscprint = @miscprint + ','
				select @Restore_cmd = @Restore_cmd + ','
				goto start_fn_multi04
			   end
		   end
		Else
		   begin
			select @miscprint = @miscprint + ' FILE=''''' + @file_name + ''''''
			select @Restore_cmd = @Restore_cmd + ' FILE=''''' + @file_name + ''''''
		   end
	   end

	print  @miscprint

	select @miscprint = 'FROM DISK = ''' + @full_path + '\' + @hold_backupfilename + ''''
	print  @miscprint

	select @Restore_cmd = @Restore_cmd + ' FROM DISK = ''' + @full_path + '\' + @hold_backupfilename + ''''


	If @differential_flag = 'y' or @db_norecovOnly_flag = 'y'
	   begin
		If @partial_flag = 'y' and @filegroup_name is not null and @filegroup_name <> ''
		   begin
			select @miscprint = 'WITH PARTIAL, NORECOVERY,'
			print  @miscprint
			select @miscprint = 'REPLACE,'
			print  @miscprint

			select @Restore_cmd = @Restore_cmd + ' WITH PARTIAL, NORECOVERY,'
			select @Restore_cmd = @Restore_cmd + ' REPLACE,'
		   end
		Else
		   begin
			select @miscprint = 'WITH NORECOVERY,'
			print  @miscprint
			select @miscprint = 'REPLACE,'
			print  @miscprint

			select @Restore_cmd = @Restore_cmd + ' WITH NORECOVERY,'
			select @Restore_cmd = @Restore_cmd + ' REPLACE,'
		   end
	   end	
	Else
	   begin
		If @partial_flag = 'y' and @filegroup_name is not null and @filegroup_name <> ''
		   begin
			select @miscprint = 'WITH PARTIAL, REPLACE,'
			print  @miscprint

			select @Restore_cmd = @Restore_cmd + ' WITH PARTIAL, REPLACE,'
		   end
		Else
		   begin
			select @miscprint = 'WITH REPLACE,'
			print  @miscprint

			select @Restore_cmd = @Restore_cmd + ' WITH REPLACE,'
		   end
	   end	

	delete from #filelist

	select @query = 'RESTORE FILELISTONLY FROM Disk = ''' + @full_path + '\' + @hold_backupfilename + ''''
	If (select @@version) not like '%Server 2005%' and (select SERVERPROPERTY ('productversion')) > '10.00.0000' --sql2008 or higher
	   begin
		insert into #filelist exec (@query)
	   end
	Else
	   begin
		insert into #filelist (LogicalName
			, PhysicalName
			, Type
			, FileGroupName
			, Size
			, MaxSize
			, FileId
			, CreateLSN
			, DropLSN
			, UniqueId
			, ReadOnlyLSN
			, ReadWriteLSN
			, BackupSizeInBytes
			, SourceBlockSize
			, FileGroupId
			, LogGroupGUID
			, DifferentialBaseLSN
			, DifferentialBaseGUID
			, IsReadOnly
			, IsPresent)
		exec (@query)
	   end
	--select * from #filelist
	If (select count(*) from #filelist) = 0
	   begin
		Select @miscprint = 'DBA Error: Unable to process standard filelistonly for file ' + @full_path + '\' + @hold_backupfilename 
		Print @miscprint
		Select @error_count = @error_count + 1
		goto label99
	   end


	--  set the default path just in case we need it
	Select @mssql_data_path = (select filename from master.sys.sysfiles where fileid = 1)
	select @charpos = charindex('master', @mssql_data_path)
	select @mssql_data_path = left(@mssql_data_path, @charpos-1)
	select @fileseq = 1


	EXECUTE('DECLARE cu22_cursor Insensitive Cursor For ' +
	  'SELECT f.LogicalName, f.PhysicalName, f.Type, f.FileGroupName
	   From #filelist   f ' +
	  'for Read Only')

	OPEN cu22_cursor
	
	WHILE (22=22)
	 Begin
		FETCH Next From cu22_cursor Into @cu22LogicalName, @cu22PhysicalName, @cu22Type, @cu22FileGroupName
		IF (@@fetch_status < 0)
	           begin
	              CLOSE cu22_cursor
		      BREAK
	           end


		select @savePhysicalNamePart = @cu22PhysicalName
		label03:
			select @charpos = charindex('\', @savePhysicalNamePart)
			IF @charpos <> 0
			   begin
	  		    select @savePhysicalNamePart = substring(@savePhysicalNamePart, @charpos + 1, 100)
			   end	
	
			select @charpos = charindex('\', @savePhysicalNamePart)
			IF @charpos <> 0
			   begin
			    goto label03
	 		   end


		If @DTstmp_in_DBfilenames = 'y'
		   begin
			If @savePhysicalNamePart like '%.mdf'
			   begin		
				Select @savePhysicalNamePart = replace(@savePhysicalNamePart, '.mdf', @DateStmp + '.mdf')
			   end
			Else If @savePhysicalNamePart like '%.ndf'
			   begin		
				Select @savePhysicalNamePart = replace(@savePhysicalNamePart, '.ndf', @DateStmp + '.ndf')
			   end
			Else If @savePhysicalNamePart like '%.ldf'
			   begin		
				Select @savePhysicalNamePart = replace(@savePhysicalNamePart, '.ldf', @DateStmp + '.ldf')
			   end
			Else
			   begin		
				Select @savePhysicalNamePart = @savePhysicalNamePart + @DateStmp
			   end
		   end


		If @sourcepath = 'y'
		   begin
			Select @savefilepath = @cu22PhysicalName
		   end
		Else If @datapath is not null and @cu22Type in ('D', 'F')
		   begin
			If @savePhysicalNamePart not like '%mdf' and @data2path is not null
			   begin
				Select @savefilepath = @data2path + '\' + @savePhysicalNamePart
			   end
			Else
			   begin
				Select @savefilepath = @datapath + '\' + @savePhysicalNamePart
			   end
		   end
		Else IF @logpath is not null and @cu22Type = 'L'
		   begin
			Select @savefilepath = @logpath + '\' + @savePhysicalNamePart
		   end
		Else
		   begin
			Select @savefilepath = @mssql_data_path + @savePhysicalNamePart
		   end

		select @miscprint = 'MOVE ''' + @cu22LogicalName + ''' to ''' + @savefilepath + ''','
		print  @miscprint

		select @Restore_cmd = @Restore_cmd + ' MOVE ''' + @cu22LogicalName + ''' to ''' + @savefilepath + ''','


		--  capture ldf info if needed
		If @force_newldf = 'y'
		   begin
			select @charpos = charindex('.ldf', @savefilepath)
			IF @charpos <> 0
			   begin
				select @hold_ldfpath = @savefilepath
			   end
			Else
			   begin
				insert #db_files values (@fileseq, @cu22LogicalName, @savefilepath)
			   end
		   end

		select @fileseq = @fileseq + 1



	End  -- loop 22
	DEALLOCATE cu22_cursor


	select @miscprint = 'stats'
	print  @miscprint
	select @miscprint = 'go'
	print  @miscprint
	Print ' '

	select @Restore_cmd = @Restore_cmd + ' stats'


	If @script_out <> 'y'
	   begin
		-- Restore the database
		select @cmd = @Restore_cmd
		Print 'Here is the restore command being executed;'
		Print @cmd
		raiserror('', -1,-1) with nowait

		Exec (@cmd)

		If @@error<> 0
		   begin
			Print 'DBA Error:  Restore Failure (Standard Restore) for command ' + @cmd
			Select @error_count = @error_count + 1
			goto label99
		   end
	   end



	If @db_norecovOnly_flag = 'y'
	   begin
		Print ' '
		select @miscprint = '--  Note:  This will leave the database in recovery pending mode.'
		print  @miscprint
		goto label99
	
	   end

   end


label12:


-- Differentail Processing
If @differential_flag = 'y'
   begin

	If @db_diffOnly_flag = 'y' and DATABASEPROPERTYEX (@check_dbname,'status') <> 'RESTORING'
	   begin
		select @miscprint = 'DBA ERROR:  A differential only restore was requested but the database is not in ''RESTORING'' mode.'
		print  @miscprint
		Select @error_count = @error_count + 1
		goto label99
	   end


	select @cmd = 'dir ' + @full_path + '\' + @diffname_wild
	--print @cmd

	Delete from #DirectoryTempTable
	insert into #DirectoryTempTable exec master.sys.xp_cmdshell @cmd
	delete from #DirectoryTempTable where cmdoutput is null
	delete from #DirectoryTempTable where cmdoutput like '%<DIR>%'
	delete from #DirectoryTempTable where cmdoutput like '%Directory of%'
	delete from #DirectoryTempTable where cmdoutput like '% File(s) %'
	delete from #DirectoryTempTable where cmdoutput like '% Dir(s) %'
	delete from #DirectoryTempTable where cmdoutput like '%Volume in drive%'
	delete from #DirectoryTempTable where cmdoutput like '%Volume Serial Number%'
	--select * from #DirectoryTempTable

	select @filecount = (select count(*) from #DirectoryTempTable)

	if @filecount < 1
	   BEGIN
		Select @miscprint = 'DBA WARNING: No differential files found for dbasp_autorestore at ' + @full_path 
		Print @miscprint
		Select @error_count = @error_count + 1
		goto label99
	   END


	Start_cmdoutput02:
	Select @save_cmdoutput = (Select top 1 cmdoutput from #DirectoryTempTable order by cmdoutput)
	Select @cu25cmdoutput = @save_cmdoutput

	select @save_fileYYYY = substring(@cu25cmdoutput, 7, 4)
	select @save_fileMM = substring(@cu25cmdoutput, 1, 2)
	select @save_fileDD = substring(@cu25cmdoutput, 4, 2)
	select @save_fileHH = substring(@cu25cmdoutput, 13, 2)
	Select @save_fileAMPM = substring(@cu25cmdoutput, 18, 1)
	If @save_fileAMPM = 'a' and @save_fileHH = '12'
	   begin
		Select @save_fileHH = '00'
	   end
	Else If @save_fileAMPM = 'p' and @save_fileHH <> '12'
	   begin
		Select @save_fileHH = @save_fileHH + 12
	   end
	select @save_fileMN = substring(@cu25cmdoutput, 16, 2)
	Select @save_filedate = @save_fileYYYY + @save_fileMM + @save_fileDD + @save_fileHH + @save_fileMN

	If @hold_filedate < @save_filedate
	   begin
		select @hold_diff_file_name = ltrim(rtrim(substring(@cu25cmdoutput, 40, 200)))
	   end

	Delete from #DirectoryTempTable where cmdoutput = @save_cmdoutput
	If (select count(*) from #DirectoryTempTable) > 0
	   begin
		goto Start_cmdoutput02
	   end



	If @hold_diff_file_name is null or @hold_diff_file_name = ''
	   BEGIN
		Select @miscprint = 'DBA ERROR: Unable to determine differential file for dbasp_autorestore at ' + @full_path 
		Print @miscprint
		Select @error_count = @error_count + 1
		goto label99
	   END


	If @hold_diff_file_name like '%.DFL'
	   begin
		--  This code is for LiteSpeed files
		select @miscprint = 'EXEC master.dbo.xp_restore_database'
		print  @miscprint
		select @miscprint = '  @database = ''' + @check_dbname + ''''
		print  @miscprint
		select @miscprint = ', @filename = ''' + @full_path + '\' + @hold_diff_file_name + ''''
		print  @miscprint
		select @miscprint = ', @with = RECOVERY'
		print  @miscprint
		select @miscprint = ', @with = ''stats'''
		print  @miscprint
		select @miscprint = 'go'
		print  @miscprint
		Print ' '

		select @Restore_cmd = ''
		select @Restore_cmd = @Restore_cmd + 'EXEC master.dbo.xp_restore_database'
		select @Restore_cmd = @Restore_cmd + '  @database = ''' + @check_dbname + ''''
		select @Restore_cmd = @Restore_cmd + ', @filename = ''' + @full_path + '\' + @hold_diff_file_name + ''''
		select @Restore_cmd = @Restore_cmd + ', @with = RECOVERY'
		select @Restore_cmd = @Restore_cmd + ', @with = ''stats'''

		If @script_out <> 'y'
		   begin
			-- Restore the differential
			select @cmd = @Restore_cmd
			Print 'Here is the restore command being executed;'
			Print @cmd
			raiserror('', -1,-1) with nowait

			Exec (@cmd)

			If DATABASEPROPERTYEX (@check_dbname,'status') <> 'ONLINE'
			   begin
				If @complete_on_diffOnly_fail = 'y'
				   begin
					--  finish the restore and send the DBA's an email
					Select @save_subject = 'DBAADMIN:  AutoRestore Failure for server ' + @@servername
					Select @save_message = 'Unable to restore the differential file for database ''' + @check_dbname + ''', the restore will be completed without the differential.'
					EXEC dbaadmin.dbo.dbasp_sendmail 
						@recipients = 'jim.wilson@gettyimages.com',  
						--@recipients = 'tssqldba@gettyimages.com',  
						@subject = @save_subject,
						@message = @save_message

					select @Restore_cmd = ''
					select @Restore_cmd = @Restore_cmd + 'RESTORE DATABASE ' + @check_dbname + ' WITH RECOVERY'

					select @cmd = @Restore_cmd
					Print 'The differential restore failed.  Completing restore for just the database using the following command;'
					Print @cmd
					raiserror('', -1,-1) with nowait

					Exec (@cmd)

					If DATABASEPROPERTYEX (@check_dbname,'status') <> 'ONLINE'
					   begin
						Print 'DBA Error:  Restore Failure (LiteSpeed DFL restore - Unable to finish restore without the DFL) for command ' + @cmd
						Select @error_count = @error_count + 1
						goto label99
					   end
				   end
				Else
				   begin
					Print 'DBA Error:  Restore Failure (LiteSpeed DFL restore) for command ' + @cmd
					Select @error_count = @error_count + 1
					goto label99
				   end
			   end
		   end
	   end
	Else If @hold_diff_file_name like '%.SQD'
	   begin
		--  This code is for RedGate files
		select @miscprint = 'Declare @cmd nvarchar(4000)'
		print  @miscprint

		select @miscprint = 'Select @cmd = ''-SQL "RESTORE DATABASE [' + @check_dbname + ']'
		print  @miscprint
		select @miscprint = ' FROM DISK = ''''' + @full_path + '\' + @hold_diff_file_name + ''''''
		print  @miscprint
		select @miscprint = ' WITH RECOVERY"'''
		print  @miscprint
		select @miscprint = 'SET @cmd = REPLACE(@cmd,CHAR(9),'''')'
		print  @miscprint
		select @miscprint = 'SET @cmd = REPLACE(@cmd,CHAR(13)+char(10),'' '')'
		print  @miscprint
		select @miscprint = 'Exec master.dbo.sqlbackup @cmd'
		print  @miscprint
		select @miscprint = 'go'
		print  @miscprint
		Print ' '

		select @Restore_cmd = ''

		select @Restore_cmd = @Restore_cmd + '-SQL "RESTORE DATABASE [' + @check_dbname + ']'
		select @Restore_cmd = @Restore_cmd + ' FROM DISK = ''' + @full_path + '\' + @hold_diff_file_name + ''''
		select @Restore_cmd = @Restore_cmd + ' WITH RECOVERY"'


		If @script_out <> 'y'
		   begin
			-- Restore the differential
			select @cmd = 'Exec master.dbo.sqlbackup ' + @Restore_cmd
			Print 'Here is the restore command being executed;'
			Print @cmd
			raiserror('', -1,-1) with nowait

			Exec master.dbo.sqlbackup @Restore_cmd

			If DATABASEPROPERTYEX (@check_dbname,'status') <> 'ONLINE'
			   begin
				If @complete_on_diffOnly_fail = 'y'
				   begin
					--  finish the restore and send the DBA's an email
					Select @save_subject = 'DBAADMIN:  AutoRestore Failure for server ' + @@servername
					Select @save_message = 'Unable to restore the differential file for database ''' + @check_dbname + ''', the restore will be completed without the differential.'
					EXEC dbaadmin.dbo.dbasp_sendmail 
						@recipients = 'jim.wilson@gettyimages.com',  
						--@recipients = 'tssqldba@gettyimages.com',  
						@subject = @save_subject,
						@message = @save_message

					select @Restore_cmd = ''
					select @Restore_cmd = @Restore_cmd + 'RESTORE DATABASE ' + @check_dbname + ' WITH RECOVERY'

					select @cmd = @Restore_cmd
					Print 'The differential restore failed.  Completing restore for just the database using the following command;'
					Print @cmd
					raiserror('', -1,-1) with nowait

					Exec (@cmd)

					If DATABASEPROPERTYEX (@check_dbname,'status') <> 'ONLINE'
					   begin
						Print 'DBA Error:  Restore Failure (Redgate SQD restore - Unable to finish restore without the SQD) for command ' + @cmd
						Select @error_count = @error_count + 1
						goto label99
					   end
				   end
				Else
				   begin
					Print 'DBA Error:  Restore Failure (Redgate SQD restore) for command ' + @cmd
					Select @error_count = @error_count + 1
					goto label99
				   end
			   end
		   end
	   end
	Else
	   begin
		--  This code is for non-LiteSpeed and non-RadGate files
		select @miscprint = 'RESTORE DATABASE ' + @check_dbname
		print  @miscprint
		select @miscprint = 'FROM DISK = ''' + @full_path + '\' + @hold_diff_file_name + ''''
		print  @miscprint
		select @miscprint = 'WITH RECOVERY,'
		print  @miscprint
		select @miscprint = 'stats'
		print  @miscprint
		select @miscprint = 'go'
		print  @miscprint
		Print ' '

		select @Restore_cmd = ''
		select @Restore_cmd = @Restore_cmd + 'RESTORE DATABASE ' + @check_dbname
		select @Restore_cmd = @Restore_cmd + ' FROM DISK = ''' + @full_path + '\' + @hold_diff_file_name + ''''
		select @Restore_cmd = @Restore_cmd + ' WITH RECOVERY,'
		select @Restore_cmd = @Restore_cmd + ' stats'


		If @script_out <> 'y'
		   begin
			-- Restore the differential
			select @cmd = @Restore_cmd
			Print 'Here is the restore command being executed;'
			Print @cmd
			raiserror('', -1,-1) with nowait

			Exec (@cmd)

			If DATABASEPROPERTYEX (@check_dbname,'status') <> 'ONLINE'
			   begin
				If @complete_on_diffOnly_fail = 'y'
				   begin
					--  finish the restore and send the DBA's an email
					Select @save_subject = 'DBAADMIN:  AutoRestore Failure for server ' + @@servername
					Select @save_message = 'Unable to restore the differential file for database ''' + @check_dbname + ''', the restore will be completed without the differential.'
					EXEC dbaadmin.dbo.dbasp_sendmail 
						@recipients = 'jim.wilson@gettyimages.com',  
						--@recipients = 'tssqldba@gettyimages.com',  
						@subject = @save_subject,
						@message = @save_message

					select @Restore_cmd = ''
					select @Restore_cmd = @Restore_cmd + 'RESTORE DATABASE ' + @check_dbname + ' WITH RECOVERY'

					select @cmd = @Restore_cmd
					Print 'The differential restore failed.  Completing restore for just the database using the following command;'
					Print @cmd
					raiserror('', -1,-1) with nowait

					Exec (@cmd)

					If DATABASEPROPERTYEX (@check_dbname,'status') <> 'ONLINE'
					   begin
						Print 'DBA Error:  Restore Failure (Standard DIF restore - Unable to finish restore without the DIF) for command ' + @cmd
						Select @error_count = @error_count + 1
						goto label99
					   end
				   end
				Else
				   begin
					Print 'DBA Error:  Restore Failure (Standard DIF restore) for command ' + @cmd
					Select @error_count = @error_count + 1
					goto label99
				   end
			   end
		   end
	   end
   end


--  Trun off auto shrink and auto stats for ALTdbname restores
If @ALTdbname is not null and @ALTdbname <> ''
   begin
	select @miscprint = '--  ALTER DATABASE OPTIONS'
	Print @miscprint
	select @miscprint = 'ALTER DATABASE [' + @ALTdbname + '] SET AUTO_CREATE_STATISTICS OFF WITH NO_WAIT'
	Print @miscprint
	Print ''
	select @miscprint = 'ALTER DATABASE [' + @ALTdbname + '] SET AUTO_UPDATE_STATISTICS OFF WITH NO_WAIT'
	Print @miscprint
	Print ''
	select @miscprint = 'ALTER DATABASE [' + @ALTdbname + '] SET AUTO_SHRINK OFF WITH NO_WAIT'
	Print @miscprint
	Print ''


	If @script_out <> 'y'
	   begin
		Print 'Here are the Alter Database Option commands being executed;'
		select @cmd = 'ALTER DATABASE [' + @ALTdbname + '] SET AUTO_CREATE_STATISTICS OFF WITH NO_WAIT'
		Print @cmd
		raiserror('', -1,-1) with nowait

		Exec (@cmd)

		select @cmd = 'ALTER DATABASE [' + @ALTdbname + '] SET AUTO_UPDATE_STATISTICS OFF WITH NO_WAIT'
		Print @cmd
		raiserror('', -1,-1) with nowait

		Exec (@cmd)

		select @cmd = 'ALTER DATABASE [' + @ALTdbname + '] SET AUTO_SHRINK OFF WITH NO_WAIT'
		Print @cmd
		raiserror('', -1,-1) with nowait

		Exec (@cmd)
	   end
   end


-- New LDF if requested
If @force_newldf = 'y' and (@ALTdbname is null or @ALTdbname = '')
   begin
	Print '--NOTE:  New Log file (LDF) was requested'
	Print ' '

	select @miscprint = 'Waitfor delay ''00:00:05'''
	print  @miscprint
	select @miscprint = 'go'
	print  @miscprint
	Print ' '

	select @miscprint = 'exec master.sys.sp_detach_db ''' + rtrim(@dbname) + ''', @skipchecks = ''true'''
	print  @miscprint
	select @miscprint = 'go'
	print  @miscprint
	Print ' '

	Select @detach_cmd = 'exec master.sys.sp_detach_db ''' + rtrim(@dbname) + ''', @skipchecks = ''true'''

	select @miscprint = 'Waitfor delay ''00:00:05'''
	print  @miscprint
	select @miscprint = 'go'
	print  @miscprint
	Print ' '

	select @miscprint = 'Declare @cmd varchar(500)'
	print  @miscprint
	select @miscprint = 'Select @cmd = ''Del ' + @hold_ldfpath + ''''
	print  @miscprint
	select @miscprint = 'EXEC master.sys.xp_cmdshell @cmd, no_output'
	print  @miscprint
	select @miscprint = 'go'
	print  @miscprint
	Print ' '

	Select @deleteLDF_cmd = 'Del ' + @hold_ldfpath


	select @miscprint = 'Waitfor delay ''00:00:05'''
	print  @miscprint
	select @miscprint = 'go'
	print  @miscprint
	Print ' '


	Select @miscprint = 'CREATE DATABASE [' + rtrim(@dbname) + '] ON'  
	Print  @miscprint

	Select @attach_cmd = 'CREATE DATABASE [' + rtrim(@dbname) + '] ON'  

	Select @fileseed = 1

	--------------------  Cursor for 12DB  -----------------------
	EXECUTE('DECLARE cu12_file Insensitive Cursor For ' + 
	  'SELECT f.fileid, f.name, f.filename
	   From #db_files  f ' + 
	  'Order By f.fileid For Read Only')

	OPEN cu12_file

	WHILE (12=12)
	   Begin
		FETCH Next From cu12_file Into @cu12fileid, @cu12name, @cu12filename 
		IF (@@fetch_status < 0)
	           begin
	              CLOSE cu12_file
		      BREAK
	           end
		

		If @fileseed = 1
		   begin
			Select @miscprint = '     (FILENAME = ''' + rtrim(@cu12filename) + ''')'  
			Print  @miscprint

			Select @attach_cmd = @attach_cmd + ' (FILENAME = ''' + rtrim(@cu12filename) + ''')'

		   end
		Else
		   begin
			Select @miscprint = '    ,(FILENAME = ''' + rtrim(@cu12filename) + ''')'  
			Print  @miscprint

			Select @attach_cmd = @attach_cmd + ' ,(FILENAME = ''' + rtrim(@cu12filename) + ''')'
		   end
	
		Select @fileseed = @fileseed + 1

	   End  -- loop 12
	   DEALLOCATE cu12_file

	Print  'FOR ATTACH;'
	Print  'go'
	Print  ' '
	Print  ' '

	Select @attach_cmd = @attach_cmd + ' FOR ATTACH;'

	If @script_out <> 'y' and DATABASEPROPERTYEX (@dbname,'status') = 'ONLINE'
	   begin
		-- detach the DB
		Print 'Here is the Detach command being executed;'
		Print @detach_cmd
		raiserror('', -1,-1) with nowait

		Exec (@detach_cmd)

		If @@error<> 0
		   begin
			select @miscprint = 'DBA Error:  Detach failure for command ' + @detach_cmd
			print  @miscprint
			Select @error_count = @error_count + 1
			goto label99
		   end

		-- delete the old ldf file
		Print 'Here is the del LDF file command being executed;'
		Print @deleteLDF_cmd
		raiserror('', -1,-1) with nowait

		Exec master.sys.xp_cmdshell @deleteLDF_cmd


		-- reattach the DB
		Print 'Here is the Attach command being executed;'
		Print @attach_cmd
		raiserror('', -1,-1) with nowait

		Exec (@attach_cmd)

		If @@error<> 0
		   begin
			select @miscprint = 'DBA Error:  ReAttach Failure for command ' + @attach_cmd
			print  @miscprint
			Select @error_count = @error_count + 1
			goto label99
		   end
	   end
   end


-- Shrink DB LDF Files if requested
If @post_shrink = 'y'
   begin
	Print '--NOTE:  Post Restore LDF file shrink was requested'
	Print ' '

	Select @miscprint = 'exec dbaadmin.dbo.dbasp_ShrinkLDFFiles @DBname = ''' + @check_dbname + ''''
	print  @miscprint
	Select @cmd = 'exec dbaadmin.dbo.dbasp_ShrinkLDFFiles @DBname = ''' + @check_dbname + ''''

	select @miscprint = 'go'
	print  @miscprint
	Print ' '


	If @script_out <> 'y'
	   begin
		If DATABASEPROPERTYEX (@check_dbname,'status') = 'ONLINE'
		   begin
			select @miscprint = 'Shrink file using command: ' + @cmd
			print  @miscprint
			exec(@cmd)
		   end
	   end

   end




-------------------   end   --------------------------

label99:

--  Check to make sure the DB is in 'restoring' mode if requested
If @script_out = 'n'
   begin
	If @db_norecovOnly_flag = 'y' and DATABASEPROPERTYEX (@check_dbname,'status') <> 'RESTORING'
	   begin
		select @miscprint = 'DBA ERROR:  A norecovOnly restore was requested and the database is not in ''RESTORING'' mode.'
		print  @miscprint
		Select @error_count = @error_count + 1
	   end

	If @error_count = 0 and @db_norecovOnly_flag = 'n' and DATABASEPROPERTYEX (@check_dbname,'status') <> 'ONLINE'
	   begin
		select @miscprint = 'DBA ERROR:  The AutoRestore process has failed for database ' + @check_dbname + '.  That database is not ''ONLINE'' at this time.'
		print  @miscprint
		Select @error_count = @error_count + 1
	   end
   end

drop table #DirectoryTempTable
drop table #db_files
drop table #filelist
drop table #filelist_ls
drop table #filelist_rg






If @error_count > 0
   begin
	raiserror(@miscprint,16,-1) with log
	RETURN (1)
   end
Else
   begin
	RETURN (0)
   end


 
 
 
 
 
