
-- Do not lock anything, and do not get held up by any locks. 
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET	NOCOUNT ON

	-- RESET HISTORY MAXIMUMS FOR AUTO PRUNING AS SAFETY NET
	EXEC msdb.dbo.sp_set_sqlagent_properties
			@jobhistory_max_rows			= 50000
			,@jobhistory_max_rows_per_job	= 1500

	-- SAVE BEFORE COUNTS
	SELECT		[job_id]
				,(SELECT name from [msdb].[dbo].sysjobs where job_id = T1.job_id ) [job_name]
				,COUNT(*) [rows]
				,COUNT(case when step_id = 0 then 1 end) [executions]
	INTO		#JobHistoryCounts		
	  FROM [msdb].[dbo].[sysjobhistory] T1
	  GROUP BY [job_id]
	  WITH ROLLUP
	  ORDER BY 2 
	GO

	-- DELETE RECORDS  
	;WITH		JobStepCount
				AS
				(
				SELECT		job_id
							,count(*) job_steps
				FROM		msdb.dbo.sysjobsteps
				GROUP BY	job_id			
				)
				,RankedHistory
				AS
				(
				SELECT		row_number() OVER(PARTITION BY H.job_id ORDER BY H.instance_id desc)	AS InstanceRank
							,H.*
				FROM		[msdb].[dbo].[sysjobhistory] H
				)
	DELETE		H 
		OUTPUT	'SET IDENTITY_INSERT msdb.dbo.sysjobhistory ON;INSERT INTO [msdb].[dbo].[sysjobhistory]([instance_id],[job_id],[step_id],[step_name],[sql_message_id],[sql_severity],[message],[run_status],[run_date],[run_time],[run_duration],[operator_id_emailed],[operator_id_netsent],[operator_id_paged],[retries_attempted],[server]) VALUES('
				+CAST(COALESCE(DELETED.instance_id,'') AS VarChar(max))+','	
				+QUOTENAME(CAST(COALESCE(DELETED.job_id,'') AS VarChar(max)),'''')+','
				+CAST(COALESCE(DELETED.step_id,'') AS VarChar(max))+','
				+QUOTENAME(CAST(COALESCE(DELETED.step_name,'') AS VarChar(max)),'''')+','
				+CAST(COALESCE(DELETED.sql_message_id,'') AS VarChar(max))+','
				+CAST(COALESCE(DELETED.sql_severity,'') AS VarChar(max))+','
				+COALESCE(QUOTENAME(CAST(COALESCE(DELETED.message,'') AS VarChar(max)),''''),'''''')+','
				+CAST(COALESCE(DELETED.run_status,'') AS VarChar(max))+','
				+CAST(COALESCE(DELETED.run_date,'') AS VarChar(max))+','
				+CAST(COALESCE(DELETED.run_time,'') AS VarChar(max))+','
				+CAST(COALESCE(DELETED.run_duration,'') AS VarChar(max))+','
				+CAST(COALESCE(DELETED.operator_id_emailed,'') AS VarChar(max))+','
				+CAST(COALESCE(DELETED.operator_id_netsent,'') AS VarChar(max))+','
				+CAST(COALESCE(DELETED.operator_id_paged,'') AS VarChar(max))+','
				+CAST(COALESCE(DELETED.retries_attempted,'') AS VarChar(max))+','
				+QUOTENAME(CAST(COALESCE(DELETED.server,'') AS VarChar(max)),'''')+');SET IDENTITY_INSERT msdb.dbo.sysjobhistory OFF;' AS [-- Execute This Command To Replace Removed Records]
	--SELECT		H.*	
	FROM		RankedHistory H
	JOIN		JobStepCount S 
			ON	S.job_id = H.job_id
	WHERE		--DATEDIFF(HOUR,msdb.dbo.agent_datetime(H.run_date,H.run_time),GETDATE())> 24 -- USE TO BASE ON START TIME INSTEAD OF END TIME
				DATEDIFF(HOUR,DATEADD(s,DATEDIFF(s,msdb.dbo.agent_datetime(run_date,0),msdb.dbo.agent_datetime(run_date,run_duration%240000)+(run_duration/240000)),msdb.dbo.agent_datetime(run_date,run_time)),GETDATE())> 24
			AND H.InstanceRank > (S.job_steps+1)*100
	GO

	-- CALCULATE AND REPORT WHAT JOBS GOT HISTORY PRUNED
	SELECT		T1.job_name
				,t1.rows						AS rows_before
				,t2.rows						AS rows_after
				,t1.rows - t2.rows				AS rows_diff
				,t1.executions					AS execs_before
				,t2.executions					AS execs_after
				,t1.executions - t2.executions	AS execs_diff
	FROM		#JobHistoryCounts T1
	LEFT JOIN	(
				SELECT		[job_id]
							,(SELECT name from [msdb].[dbo].sysjobs where job_id = T1.job_id ) [job_name]
							,COUNT(*) [rows]
							,COUNT(case when step_id = 0 then 1 end) [executions]
				  FROM [msdb].[dbo].[sysjobhistory] T1
				  GROUP BY [job_id]
				  WITH ROLLUP
				) T2
			ON	T2.job_id = T1.job_id
	WHERE		t1.rows != t2.rows
			OR	t1.executions != t2.executions		
	ORDER BY	1
	GO
		DROP TABLE #JobHistoryCounts
	GO	




