USE [DEPLcontrol]
GO
/****** Object:  StoredProcedure [dbo].[dpsp_Script_PreRelease]    Script Date: 10/07/2010 10:45:38 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[dpsp_Script_PreRelease]
	(
	@gears_id	int	= null
	)
as
set nocount on

--	dpsp_Script_PreRelease
--
--	======================================================================================
--	Revision History
--
--	Date		Author     		Desc
--	==========	====================	=============================================
--	12/14/2009	Steve Ledridge		New process.
--	10/07/2010	Steve Ledridge		Modified for SQLCMD Script
--	======================================================================================
--	INPUT PARAMETERS
--		@gears_id	INT	is the Gears ID for a specific request
--	======================================================================================
--	NOTES
--
--	This generates a script to be used to start the Pre-Release Backups on each server
--	referenced in the specified Gears Ticket. This script is in SQLCMD format and will
--	requior that "SQLCMD MODE" be enabled in SSMS. This script refernces several static
--	SQLCMD files located in \\SEAFRESQLDBA01\DBA_Docs\SQLCMD Scripts so you must be able
--	to connect to that share and all referenced servers within the specified ticket at
--	the workstation running the results of this sproc.
--	======================================================================================
--	DEPENDENCIES 
--		To RUN SPROC:	MUST BE RUN IN DEPLControl on SEAFRESQLDBA01
--
--		TO RUN OUTPUT:	Only Direct refernces are identified, each referenced file
--				could reference other files.
--
--		\\SEAFRESQLDBA01\DBA_Docs\SQLCMD Scripts\SQLCMD_Header.sql
--		\\SEAFRESQLDBA01\DBA_Docs\SQLCMD Scripts\Release Toolkit\PreReleaseBackup.sql
--

--	======================================================================================
--					TEST PARAMETERS
--	======================================================================================
/***
Declare @gears_id int
Select @gears_id = 41496
--***/

--	======================================================================================
--					Initialization
--	======================================================================================


--	======================================================================================
--					DECLARE VARIABLES
--	======================================================================================

DECLARE	@miscprint		nvarchar(2000)
	,@cmd			nvarChar(4000)


--	======================================================================================
--					VERIFY INPUT PARAMETERS
--	======================================================================================

If @gears_id is null
   begin
	Select @miscprint = 'Error: No Gears ID specified.' 
	Print  @miscprint
	Print ''

	exec dbo.dpsp_Status @report_only = 'y'

	goto label99
   end


--	======================================================================================
--					MAIN LINE
--	======================================================================================

	-----------------------------------------------------------
	-- CREATE HEADER SECTION
	-----------------------------------------------------------
	PRINT	':r "\\SEAFRESQLDBA01\DBA_Docs\SQLCMD Scripts\SQLCMD_Header.sql"'
	PRINT	''
	PRINT	'PRINT	''PRE-RELEASE BACKUP SCRIPT GENERATED FOR TICKET NUMBER '+CAST(@gears_id AS VarChar(20))+' ON ' + CAST(GetDate() AS VarChar(50)) +''''
	PRINT	''
	PRINT	':SETVAR PreReleaseBackup_Overide "NONE"'
	PRINT	''
	PRINT	'--	======================================================================================'
	PRINT	'--	NOTES'
	PRINT	'--'
	PRINT	'--	This script is to be used to start the Pre-Release Backups on each server'
	PRINT	'--	referenced in the specified Gears Ticket('+CAST(@gears_id AS VarChar(20))+'). This script is in SQLCMD format and will'
	PRINT	'--	requior that "SQLCMD MODE" be enabled in SSMS. This script refernces several static'
	PRINT	'--	SQLCMD files located in "\\SEAFRESQLDBA01\DBA_Docs\SQLCMD Scripts" so you must be able'
	PRINT	'--	to connect to that share and all referenced servers within the specified ticket at'
	PRINT	'--	the workstation running the results of this sproc.'
	PRINT	'--	======================================================================================'
	PRINT	'--	DEPENDENCIES '
	PRINT	'--		GENERAL SQLCMD:'
	PRINT	'--			SQLCMD_UserSettings:	"{User Profile Directory}\SQLCMD_UserSettings.sql"'
	PRINT	'--						Your User Profile Directory is usualy c:\users\{loginName}'
	PRINT	'--						This file should contain your SQL DBAxxxx Login Name and Password'
	PRINT	'--'
	PRINT	'--			SQLCMD_GlobalSettings:	"\\seafresqldba01\DBA_Docs\SQLCMD Scripts\SQLCMD_GlobalSettings.sql"'
	PRINT	'--						This file contains settings for the central servers and other'
	PRINT	'--						global settings'
	PRINT	'--'
	PRINT	'--'
	PRINT	'--		TO RUN OUTPUT:	Only Direct refernces are identified, each referenced file'
	PRINT	'--				could reference other files.'
	PRINT	'--'
	PRINT	'--		\\SEAFRESQLDBA01\DBA_Docs\SQLCMD Scripts\SQLCMD_Header.sql'
	PRINT	'--		\\SEAFRESQLDBA01\DBA_Docs\SQLCMD Scripts\Release Toolkit\PreReleaseBackup.sql'
	PRINT	'--'
	PRINT	'--	======================================================================================'
	PRINT	''
	PRINT	''

	-----------------------------------------------------------
	-- CREATE AMER SECTION
	-----------------------------------------------------------
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	'--	AMER'
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	':SETVAR ConnectScript "Connect_CurrentServerName_Trusted.sql"'
	PRINT	'  PRINT '''''
	PRINT	'  PRINT ''-- STARTING BATCH > PERFORMING PRE RELEASE BACKUPS IN AMER...'''
	PRINT	'  PRINT '''''
	PRINT	'  GO'

	SET    @cmd		= ''
	
	select @cmd		= @cmd	+ '  -------------------------------------------------------------------------------------' + CHAR(13) + CHAR(10)
					+ '  --	' + d.SQLname + CHAR(13) + CHAR(10)
					+ '  -------------------------------------------------------------------------------------' + CHAR(13) + CHAR(10)
					+ '  :SETVAR CurrentServerName	"' + d.SQLname + '"' + CHAR(13) + CHAR(10)
					+ '--:SETVAR PreReleaseBackup_Overide "FORCE"' + CHAR(13) + CHAR(10)
					+ '--:SETVAR PreReleaseBackup_Overide "STOP"' + CHAR(13) + CHAR(10)
					+ '  :r "\\SEAFRESQLDBA01\DBA_Docs\SQLCMD Scripts\Release Toolkit\PreReleaseBackup.sql"' + CHAR(13) + CHAR(10)
					+ '  GO' + CHAR(13) + CHAR(10)
	FROM		(
			SELECT	DISTINCT
				SQLname
			From	dbo.Request_detail d
			WHERE	gears_id = @gears_id
			AND	Domain = 'AMER'
			) d

	PRINT	(@CMD)               

	PRINT	'  -------------------------------------------------------------------------------------'	
	PRINT	'  -------------------------------------------------------------------------------------'
	PRINT	'  PRINT ''-- DONE...'''
	PRINT	'  PRINT '''''
	PRINT	'GO'
	PRINT	''
	-----------------------------------------------------------
	-- CREATE STAGE SECTION
	-----------------------------------------------------------
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	'--	STAGE'
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	':SETVAR ConnectScript "Connect_CurrentServerName_NonTrusted.sql"'
	PRINT	'  PRINT '''''
	PRINT	'  PRINT ''-- STARTING BATCH > PERFORMING PRE RELEASE BACKUPS IN AMER...'''
	PRINT	'  PRINT '''''
	PRINT	'  GO'

	SET    @cmd		= ''
	
	select @cmd		= @cmd	+ '  -------------------------------------------------------------------------------------' + CHAR(13) + CHAR(10)
					+ '  --	' + d.SQLname + CHAR(13) + CHAR(10)
					+ '  -------------------------------------------------------------------------------------' + CHAR(13) + CHAR(10)
					+ '  :SETVAR CurrentServerName	"' + d.SQLname + '"' + CHAR(13) + CHAR(10)
					+ '--:SETVAR PreReleaseBackup_Overide "FORCE"' + CHAR(13) + CHAR(10)
					+ '--:SETVAR PreReleaseBackup_Overide "STOP"' + CHAR(13) + CHAR(10)
					+ '  :r "\\SEAFRESQLDBA01\DBA_Docs\SQLCMD Scripts\Release Toolkit\PreReleaseBackup.sql"' + CHAR(13) + CHAR(10)
					+ '  GO' + CHAR(13) + CHAR(10)
	FROM		(
			SELECT	DISTINCT
				SQLname
			From	dbo.Request_detail d
			WHERE	gears_id = @gears_id
			AND	Domain = 'STAGE'
			) d

	PRINT	(@CMD)               

	PRINT	'  -------------------------------------------------------------------------------------'	
	PRINT	'  -------------------------------------------------------------------------------------'
	PRINT	'  PRINT ''-- DONE...'''
	PRINT	'  PRINT '''''
	PRINT	'GO'
	PRINT	''
	-----------------------------------------------------------
	-- CREATE PROD SECTION
	-----------------------------------------------------------
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	'--	PROD'
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	'-------------------------------------------------------------------------------------'
	PRINT	':SETVAR ConnectScript "Connect_CurrentServerName_NonTrusted.sql"'
	PRINT	'  PRINT '''''
	PRINT	'  PRINT ''-- STARTING BATCH > PERFORMING PRE RELEASE BACKUPS IN AMER...'''
	PRINT	'  PRINT '''''
	PRINT	'  GO'

	SET    @cmd		= ''
	
	select @cmd		= @cmd	+ '  -------------------------------------------------------------------------------------' + CHAR(13) + CHAR(10)
					+ '  --	' + d.SQLname + CHAR(13) + CHAR(10)
					+ '  -------------------------------------------------------------------------------------' + CHAR(13) + CHAR(10)
					+ '  :SETVAR CurrentServerName	"' + d.SQLname + '"' + CHAR(13) + CHAR(10)
					+ '--:SETVAR PreReleaseBackup_Overide "FORCE"' + CHAR(13) + CHAR(10)
					+ '--:SETVAR PreReleaseBackup_Overide "STOP"' + CHAR(13) + CHAR(10)
					+ '  :r "\\SEAFRESQLDBA01\DBA_Docs\SQLCMD Scripts\Release Toolkit\PreReleaseBackup.sql"' + CHAR(13) + CHAR(10)
					+ '  GO' + CHAR(13) + CHAR(10)
	FROM		(
			SELECT	DISTINCT
				SQLname
			From	dbo.Request_detail d
			WHERE	gears_id = @gears_id
			AND	Domain = 'PRODUCTION'
			) d

	PRINT	(@CMD)               

	PRINT	'  -------------------------------------------------------------------------------------'	
	PRINT	'  -------------------------------------------------------------------------------------'
	PRINT	'  PRINT ''-- DONE...'''
	PRINT	'  PRINT '''''
	PRINT	'GO'
	PRINT	''

	GOTO	CleanExit

--	======================================================================================
--					Finalizations
--	======================================================================================

label99:

	Print  ' '
	Print  ' '
	Select @miscprint = '--Here is a sample execute command for this sproc:'
	Print  @miscprint
	Print  ' '
	Select @miscprint = 'exec DEPLcontrol.dbo.dpsp_Script_PreRelease @gears_id = 12345'
	Print  @miscprint
	Print  'go'
	Print  ' '

   
--	======================================================================================
--					CLEAN EXIT
--	======================================================================================
CleanExit:   


