/****************************************************************************************
NAME:	DATABASE I/O STATISTICS

BY:	MARK JONES
DATE:	19-02-2008

PURPOSE: Provides useful statistics about Database I/O requests. Uses the function
	 ::fn_virtualfilestats to retreieve all the database file statistics includeing
	 log files for all databases on a server. A number of Result sets are generated
	 which detail:
		-ALL I/O STATS FOR ALL DATABASES
		-TOP 5 DABATASES BASED ON READS + WRITES
		-TOP 5 DABATASES BASED ON BYTESREAD + BYTESWRITTEN
		-TOP 5 DABATASES BASED ON IoStallMS
		-TOP 5 DABATASES IO STALL RATIO TO IO REQUESTS RATIO

USE:	Run Against any SQL SERVER 2000 Database. (2005 not tested)

REVISION HISTORY
Date		Developer	Details
19/02/08	Mark Jones	Created

*****************************************************************************************/

----------------------------------------------------------------
-- DECLARATIONS
----------------------------------------------------------------
SET NOCOUNT ON
USE TEMPDB

----------------------------------------------------------------
-- BODY
----------------------------------------------------------------

-- Create tbale to store file I/O statistics
IF NOT EXISTS ( SELECT 1 FROM tempdb.dbo.sysobjects WHERE name = 'tbl_DatabaseFileStats' AND
			type = 'U')
	CREATE TABLE tempdb.dbo.tbl_DatabaseFileStats
	(
		DatabaseName	varchar(255),
		FileName	varchar(255),
		TimeStamp	numeric(18,0),
		NumberReads	numeric(18,0),
		NumberWrites	numeric(18,0),
		BytesRead	numeric(18,0),
		BytesWritten	numeric(18,0),
		IOStallMS	numeric(18,0)
	)
ELSE
	TRUNCATE TABLE dbo.tbl_DatabaseFileStats

-- Use sp_MSForEachDB to scroll through each db to obtain the DBID
-- to run as a parameter in the function fn_virtualfilestats
-- Insert results into results table.
EXECUTE master.dbo.sp_msforeachdb '
	DECLARE @DBID	int;
	USE [?]; 
	SET @DBID = DB_ID();
	INSERT INTO tempdb.dbo.tbl_DatabaseFileStats
	SELECT 
		DB_NAME(DBID) AS DatabaseName,
		FILE_NAME(FileID) AS FileName,
		TimeStamp,
		NumberReads,
		NumberWrites,
		BytesRead,
		BytesWritten,
		IoStallMS
	FROM ::fn_virtualfilestats(@DBID, -1);'


----------------------------------------------------------------
-- RESULTS
----------------------------------------------------------------
-- GET ALL RESULTS
SELECT '<< ALL DATABASES >>'

SELECT *
FROM 
	tempdb.dbo.tbl_DatabaseFileStats
ORDER BY
	1,2

-- TOP 5 DABATASES BASED ON READS + WRITES
SELECT '<< TOP 5 DABATASES BASED ON READS + WRITES >>'

SELECT TOP 5 
		DataBaseName,
		TimeStamp,
		SUM(NumberReads) + SUM(NumberWrites) AS 'NumberRead/Writes', 
		SUM(BytesRead) AS BytesRead,
		SUM(BytesWritten) AS BytesWritten,
		SUM(IoStallMS) AS IoStallMS
FROM
	tempdb.dbo.tbl_DatabaseFileStats
GROUP BY
	DataBaseName,TimeStamp
ORDER BY
	[NumberRead/Writes] DESC

-- TOP 5 DABATASES BASED ON BYTESREAD + BYTESWRITTEN
SELECT '<< TOP 5 DABATASES BASED ON BYTESREAD + BYTESWRITTEN >>'
SELECT TOP 5 
		DataBaseName,
		TimeStamp,
		SUM(NumberReads) AS NumberReads,
		SUM(NumberWrites)AS NumberWrites,  
		SUM(BytesRead) + SUM(BytesWritten) AS 'BytesRead/Written',
		SUM(IoStallMS) AS IoStallMS
FROM
	tempdb.dbo.tbl_DatabaseFileStats
GROUP BY 
	DataBaseName,TimeStamp
ORDER BY
	[BytesRead/Written] DESC

-- TOP 5 DABATASES BASED ON IoStallMS
SELECT '<< TOP 5 DABATASES BASED ON IO STALL >>'
SELECT TOP 5 
		DataBaseName,
		TimeStamp,
		SUM(NumberReads) AS NumberReads,
		SUM(NumberWrites)AS NumberWrites,  
		SUM(BytesRead)AS BytesRead,
		SUM(BytesWritten) AS BytesWritten,
		SUM(IoStallMS) AS IoStallMS
FROM
	tempdb.dbo.tbl_DatabaseFileStats
GROUP BY 
	DataBaseName,TimeStamp
ORDER BY
	IoStallMS DESC

-- TOP 5 DABATASES IO STALL RATIO TO IO REQUESTS RATIO
SELECT '<< TOP 5 DABATASES IO STALL TO IO REQUESTS RATIO >>'
SELECT TOP 5 
		DataBaseName,
		TimeStamp,
		SUM(BytesRead) + SUM(BytesWritten) AS IORequests,
		SUM(IoStallMS) AS IoStallMS,
		SUM(IoStallMS) / (SUM(BytesRead) + SUM(BytesWritten)) AS IOStallRatio
FROM
	tempdb.dbo.tbl_DatabaseFileStats
GROUP BY 
	DataBaseName,TimeStamp
ORDER BY
	IOStallRatio DESC

----------------------------------------------------------------
-- CLEANUP & EXIT
----------------------------------------------------------------
DROP TABLE tempdb.dbo.tbl_DatabaseFileStats



