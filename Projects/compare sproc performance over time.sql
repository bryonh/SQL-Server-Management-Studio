
--SELECT MIN([rundate])			FromTime
--	,MAX([rundate])			ToTime
--	,SUM([delta_worker_time])		[worker_time]
--      ,AVG([Avg_CPU_Time_MS])		[Avg_CPU_Time_MS]
--      ,SUM([delta_elapsed_time])	[elapsed_time]
--      ,AVG([Avg_Elapsed_Time_MS])	[Avg_Elapsed_Time_MS]
--      ,SUM([delta_physical_reads])	[physical_reads]
--      ,SUM([delta_logical_reads])	[logical_reads]
--      ,AVG([Avg_Logical_Reads])		[Avg_Logical_Reads]
--      ,SUM([delta_logical_writes])	[logical_writes]
--      ,AVG([Avg_Logical_Writes])	[Avg_Logical_Writes]
--      ,SUM([execution_count])		[execution_count]
--  FROM [dbaperf].[dbo].[DMV_QueryStats_log]
--  WHERE [QueryText] = 'AssetKeyword.dbo.SaveAssetBundles'
--	AND [rundate] >= '2012-11-13 13:30:00'
--	AND [rundate] <  '2012-11-13 14:30:00'
	
--UNION ALL	

SELECT	DATEPART(YEAR,[rundate])	[YEAR]
	,DATEPART(MONTH,[rundate])	[Month]
	,DATEPART(DAY,[rundate])	[Day]
	,DATEPART(HOUR,[rundate])	[Hour]
	,SUM([delta_worker_time])	[worker_time]
      ,AVG([Avg_CPU_Time_MS])		[Avg_CPU_Time_MS]
      ,SUM([delta_elapsed_time])	[elapsed_time]
      ,AVG([Avg_Elapsed_Time_MS])	[Avg_Elapsed_Time_MS]
      ,SUM([delta_physical_reads])	[physical_reads]
      ,SUM([delta_logical_reads])	[logical_reads]
      ,AVG([Avg_Logical_Reads])		[Avg_Logical_Reads]
      ,SUM([delta_logical_writes])	[logical_writes]
      ,AVG([Avg_Logical_Writes])	[Avg_Logical_Writes]
      ,SUM([execution_count])		[execution_count]
  FROM [dbaperf].[dbo].[DMV_QueryStats_log]
  WHERE [QueryText] = 'VocabularyTool.dbo.mrtGetTermListAncestorsAndCategories'
	--AND [rundate] >= '2012-11-13 15:30:00'
	--AND [rundate] <  '2012-11-13 16:30:00'
GROUP BY	DATEPART(YEAR,[rundate])		
,DATEPART(MONTH,[rundate])	
,DATEPART(DAY,[rundate])	
,DATEPART(HOUR,[rundate])	

ORDER BY	1,2,3,4