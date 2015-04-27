-- Version 7

DECLARE @ObjectID int
    ,@DB_ID int

SELECT @ObjectID = OBJECT_ID('DownloadDetail')
    ,@DB_ID = db_id()

IF OBJECT_ID('tempdb..#IndexBaseLine') IS NOT NULL
    DROP TABLE #IndexBaseLine

CREATE TABLE #IndexBaseLine
    (
    row_id int IDENTITY(1,1)
    ,server_name sysname
    ,database_name sysname
    ,database_id INT
    ,index_action varchar(10)
    ,schema_id int
    ,schema_name sysname
    ,object_id int
    ,table_name sysname
    ,index_id int
    ,index_name nvarchar(128)
    ,is_unique bit DEFAULT(0)
    ,has_unique bit DEFAULT(0)
    ,type_desc nvarchar(67)
    ,partition_number int
    ,reserved_page_count bigint
    ,page_count bigint
    ,max_key_size int
    ,size_in_mb decimal(12, 2)
    ,buffered_page_count int
    ,buffer_mb decimal(12, 2)
    ,pct_in_buffer decimal(12, 2)
    ,table_buffer_mb decimal(12, 2)
    ,row_count bigint
    ,impact int
    ,existing_ranking bigint
    ,user_total_read bigint
    ,user_total_read_pct decimal(6, 2)
    ,estimated_user_total_read_pct decimal(6, 2)
    ,user_total_write bigint
    ,user_total_write_pct decimal(6,2)
    ,estimated_user_total_write_pct decimal(6,2)
    ,index_read_pct decimal(6,2)
    ,index_write_pct decimal(6,2)
    ,user_seeks bigint
    ,user_scans bigint
    ,user_lookups bigint
    ,user_updates bigint
    ,row_lock_count bigint
    ,row_lock_wait_count bigint
    ,row_lock_wait_in_ms bigint
    ,row_block_pct decimal(6, 2)
    ,avg_row_lock_waits_ms bigint
    ,page_lock_count bigint
    ,page_lock_wait_count bigint
    ,page_lock_wait_in_ms bigint
    ,page_block_pct decimal(6, 2)
    ,avg_page_lock_waits_ms bigint
    ,splits bigint
    ,indexed_columns nvarchar(max)
    ,indexed_column_count int
    ,included_columns nvarchar(max)
    ,included_column_count int
    ,indexed_columns_compare nvarchar(max)
    ,included_columns_compare nvarchar(max)
    ,duplicate_indexes nvarchar(max)
    ,overlapping_indexes nvarchar(max)
    ,related_foreign_keys nvarchar(max)
    ,related_foreign_keys_xml xml
    )

IF OBJECT_ID('tempdb..#ForeignKeys') IS NOT NULL
    DROP TABLE #ForeignKeys

CREATE TABLE #ForeignKeys
    (
    foreign_key_name sysname
    ,object_id int
    ,fk_columns nvarchar(max)
    ,fk_columns_compare nvarchar(max)
    )

;WITH	AllocationUnits
	AS	(
		SELECT	p.object_id
			,p.index_id
			,p.partition_number 
			,au.allocation_unit_id
		FROM	sys.allocation_units AS au
		JOIN	sys.partitions AS p 
		 ON	au.container_id = p.hobt_id 
		 AND	(au.type = 1 OR au.type = 3)
		UNION ALL
		SELECT	p.object_id
			,p.index_id
			,p.partition_number 
			,au.allocation_unit_id
		FROM	sys.allocation_units AS au
		JOIN	sys.partitions AS p 
		 ON	au.container_id = p.partition_id 
		 AND	au.type = 2
		)
	,MemoryBuffer
	AS	(
		SELECT	au.object_id
			,au.index_id
			,au.partition_number
			,COUNT(*)AS buffered_page_count
			,CONVERT(decimal(12,2), CAST(COUNT(*) as bigint)*CAST(8 as float)/1024) as buffer_mb
		FROM	sys.dm_os_buffer_descriptors AS bd 
		JOIN	AllocationUnits au ON bd.allocation_unit_id = au.allocation_unit_id
		WHERE	bd.database_id = db_id()
		GROUP BY au.object_id, au.index_id, au.partition_number
		)
INSERT INTO #IndexBaseLine
    (server_name, database_name, database_id, schema_id, schema_name, object_id, table_name, index_id, index_name, is_unique, type_desc, partition_number, reserved_page_count, size_in_mb, buffered_page_count, buffer_mb, pct_in_buffer, row_count, page_count, existing_ranking
    , user_total_read, user_total_read_pct
    , user_total_write, user_total_write_pct
    , user_seeks, user_scans, user_lookups,user_updates
    , row_lock_count, row_lock_wait_count, row_lock_wait_in_ms, row_block_pct, avg_row_lock_waits_ms
    , page_lock_count, page_lock_wait_count, page_lock_wait_in_ms, page_block_pct, avg_page_lock_waits_ms
    , splits, indexed_columns, included_columns, indexed_columns_compare, included_columns_compare)
SELECT	@@SERVERNAME
	,DB_Name(@DB_ID)
	,@DB_ID 
	,s.schema_id
	,s.name as schema_name
	,t.object_id
	,t.name as table_name
	,i.index_id
	,COALESCE(i.name, 'N/A') as index_name
	,i.is_unique
	,CASE WHEN i.is_unique = 1 THEN 'UNIQUE ' ELSE '' END + i.type_desc as type_desc
	,ps.partition_number
	,ps.reserved_page_count 
	,CAST(reserved_page_count * CAST(8 as float) / 1024 as decimal(12,2)) as size_in_mb
	,mb.buffered_page_count
	,mb.buffer_mb
	,CAST(100*buffer_mb/NULLIF(CAST(reserved_page_count * CAST(8 as float) / 1024 as decimal(12,2)),0) AS decimal(12,2)) as pct_in_buffer
	,row_count
	,used_page_count
	,ROW_NUMBER()
		OVER (PARTITION BY i.object_id ORDER BY i.is_primary_key desc, ius.user_seeks + ius.user_scans + ius.user_lookups desc) as existing_ranking

	,ius.user_seeks + ius.user_scans + ius.user_lookups as user_total_read
	,COALESCE(CAST(100 * (ius.user_seeks + ius.user_scans + ius.user_lookups)
		/(NULLIF(SUM(ius.user_seeks + ius.user_scans + ius.user_lookups) 
		OVER(PARTITION BY i.object_id), 0) * 1.) as decimal(6,2)),0) as user_total_read_pct

	,ius.user_updates as user_total_write
	,COALESCE(CAST(100 * (ius.user_updates)
		/(NULLIF(SUM(ius.user_updates) 
		OVER(PARTITION BY i.object_id), 0) * 1.) as decimal(6,2)),0) as user_total_write_pct
		
	,ius.user_seeks
	,ius.user_scans
	,ius.user_lookups
	,ius.user_updates

	,ios.row_lock_count 
	,ios.row_lock_wait_count 
	,ios.row_lock_wait_in_ms 
	,CAST(100.0 * ios.row_lock_wait_count/NULLIF(ios.row_lock_count, 0) AS decimal(12,2)) AS row_block_pct 
	,CAST(1. * ios.row_lock_wait_in_ms /NULLIF(ios.row_lock_wait_count, 0) AS decimal(12,2)) AS avg_row_lock_waits_ms 

	,ios.page_lock_count 
	,ios.page_lock_wait_count 
	,ios.page_lock_wait_in_ms 
	,CAST(100.0 * ios.page_lock_wait_count/NULLIF(ios.page_lock_count, 0) AS decimal(12,2)) AS page_block_pct 
	,CAST(1. * ios.page_lock_wait_in_ms /NULLIF(ios.page_lock_wait_count, 0) AS decimal(12,2)) AS avg_page_lock_waits_ms 

	,ios.leaf_allocation_count + ios.nonleaf_allocation_count AS [Splits]

	,STUFF((SELECT ', ' + QUOTENAME(c.name)
            FROM sys.index_columns ic
                INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE i.object_id = ic.object_id
            AND i.index_id = ic.index_id
            AND is_included_column = 0
            ORDER BY key_ordinal ASC
            FOR XML PATH('')), 1, 2, '') AS indexed_columns
    ,STUFF((SELECT ', ' + QUOTENAME(c.name)
            FROM sys.index_columns ic
                INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE i.object_id = ic.object_id
            AND i.index_id = ic.index_id
            AND is_included_column = 1
            ORDER BY key_ordinal ASC
            FOR XML PATH('')), 1, 2, '') AS included_columns
    ,(SELECT QUOTENAME(ic.column_id,'(')
            FROM sys.index_columns ic
            WHERE i.object_id = ic.object_id
            AND i.index_id = ic.index_id
            AND is_included_column = 0
            ORDER BY key_ordinal ASC
            FOR XML PATH('')) AS indexed_columns_compare
    ,COALESCE((SELECT QUOTENAME(ic.column_id, '(')
            FROM sys.index_columns ic
            WHERE i.object_id = ic.object_id
            AND i.index_id = ic.index_id
            AND is_included_column = 1
            ORDER BY key_ordinal ASC
            FOR XML PATH('')), SPACE(0)) AS included_columns_compare
FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.indexes i ON t.object_id = i.object_id
    INNER JOIN sys.dm_db_partition_stats ps ON i.object_id = ps.object_id AND i.index_id = ps.index_id
    LEFT OUTER JOIN sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id AND ius.database_id = db_id()
    LEFT OUTER JOIN sys.dm_db_index_operational_stats(@DB_ID, NULL, NULL, NULL) ios ON ps.object_id = ios.object_id AND ps.index_id = ios.index_id AND ps.partition_number = ios.partition_number
    LEFT OUTER JOIN MemoryBuffer mb ON ps.object_id = mb.object_id AND ps.index_id = mb.index_id AND ps.partition_number = mb.partition_number
WHERE t.object_id = @ObjectID OR @ObjectID IS NULL

INSERT INTO #IndexBaseLine
    (server_name, database_name, database_id, schema_id, schema_name, object_id, table_name, index_name
    , type_desc, impact, existing_ranking, user_total_read, user_seeks, user_scans, user_lookups, indexed_columns
    , indexed_column_count, included_columns, included_column_count)
SELECT	@@Servername
	,db_name(mid.database_id)
	,mid.database_id
	,s.schema_id
	,s.name AS schema_name
	,t.object_id
	,t.name AS table_name
	,'--MISSING--' AS index_name
	,'--NONCLUSTERED--' AS type_desc
	,(migs.user_seeks + migs.user_scans) * migs.avg_user_impact as impact
	,0 AS existing_ranking
	,migs.user_seeks + migs.user_scans as user_total_read
	,migs.user_seeks 
	,migs.user_scans
	,0 as user_lookups
	,COALESCE(equality_columns + ', ', SPACE(0)) + COALESCE(inequality_columns, SPACE(0)) as indexed_columns
	,(LEN(COALESCE(equality_columns + ', ', SPACE(0)) + COALESCE(inequality_columns, SPACE(0))) - LEN(REPLACE(COALESCE(equality_columns + ', ', SPACE(0)) + COALESCE(inequality_columns, SPACE(0)),'[',''))) indexed_column_count
	,included_columns
	,(LEN(included_columns) - LEN(REPLACE(included_columns,'[',''))) included_column_count
FROM	sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.dm_db_missing_index_details mid ON t.object_id = mid.object_id
    INNER JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
    INNER JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
WHERE mid.database_id = @DB_ID
AND (mid.object_id = @ObjectID OR @ObjectID IS NULL)


DECLARE		@Fill_Factor int
SET		@Fill_Factor = 98

UPDATE		T1
	SET	size_in_mb = 
				[dbaperf].[dbo].[fn_GetLeafLevelIndexSpace] 
				(
				T1.indexed_column_count
				,0
				,0
				,T3.TotalIndexKeySize
				,@Fill_Factor
				,T2.row_count)/1000.00/1000.00
				+
				[dbaperf].[dbo].[fn_getIndexSpace] (
				T1.indexed_column_count
				,0
				,0
				,T3.TotalIndexKeySize
				,T2.row_count)/1000.00/1000.00
		,max_key_size = T3.TotalIndexKeySize
FROM		#IndexBaseLine T1
JOIN		#IndexBaseLine T2
	ON	T1.object_id = T2.Object_id
	AND	T2.type_desc IN ('CLUSTERED', 'HEAP', 'UNIQUE CLUSTERED')
JOIN		(
		Select		T1.row_id
				,SUM(T3.max_length)AS TotalIndexKeySize
		FROM		#IndexBaseLine	T1
		CROSS APPLY	dbaadmin.dbo.dbaudf_split(indexed_columns,',') T2
		JOIN		sys.columns T3
			ON	ltrim(rtrim(t2.SplitValue)) = QUOTENAME(T3.name)
			AND	T1.object_id = T3.object_id
		WHERE index_name = '--MISSING--'
		GROUP BY	T1.row_id
		) T3
	ON	T1.row_id = T3.row_id


INSERT INTO #ForeignKeys
    (foreign_key_name, object_id, fk_columns, fk_columns_compare)
SELECT fk.name + '|PARENT' AS foreign_key_name
    ,fkc.parent_object_id AS object_id
    ,STUFF((SELECT ', ' + QUOTENAME(c.name)
            FROM sys.foreign_key_columns ifkc
                INNER JOIN sys.columns c ON ifkc.parent_object_id = c.object_id AND ifkc.parent_column_id = c.column_id
            WHERE fk.object_id = ifkc.constraint_object_id
            ORDER BY ifkc.constraint_column_id
            FOR XML PATH('')), 1, 2, '') AS fk_columns
    ,(SELECT QUOTENAME(ifkc.parent_column_id,'(')
            FROM sys.foreign_key_columns ifkc
            WHERE fk.object_id = ifkc.constraint_object_id
            ORDER BY ifkc.constraint_column_id
            FOR XML PATH('')) AS fk_columns_compare
FROM sys.foreign_keys fk
    INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
WHERE fkc.constraint_column_id = 1
AND (fkc.parent_object_id = @ObjectID OR @ObjectID IS NULL)
UNION ALL
SELECT fk.name + '|REFERENCED' as foreign_key_name
    ,fkc.referenced_object_id AS object_id
    ,STUFF((SELECT ', ' + QUOTENAME(c.name)
            FROM sys.foreign_key_columns ifkc
                INNER JOIN sys.columns c ON ifkc.referenced_object_id = c.object_id AND ifkc.referenced_column_id = c.column_id
            WHERE fk.object_id = ifkc.constraint_object_id
            ORDER BY ifkc.constraint_column_id
            FOR XML PATH('')), 1, 2, '') AS fk_columns
    ,(SELECT QUOTENAME(ifkc.referenced_column_id,'(')
            FROM sys.foreign_key_columns ifkc
            WHERE fk.object_id = ifkc.constraint_object_id
            ORDER BY ifkc.constraint_column_id
            FOR XML PATH('')) AS fk_columns_compare
FROM sys.foreign_keys fk
    INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
WHERE fkc.constraint_column_id = 1
AND (fkc.referenced_object_id = @ObjectID OR @ObjectID IS NULL)

UPDATE ibl
SET duplicate_indexes = STUFF((SELECT ', ' + index_name AS [data()]
            FROM #IndexBaseLine iibl
            WHERE ibl.object_id = iibl.object_id
            AND ibl.index_id <> iibl.index_id
            AND ibl.indexed_columns_compare = iibl.indexed_columns_compare
            AND ibl.included_columns_compare = iibl.included_columns_compare
            FOR XML PATH('')), 1, 2, '')
    ,overlapping_indexes = STUFF((SELECT ', ' + index_name AS [data()]
            FROM #IndexBaseLine iibl
            WHERE ibl.object_id = iibl.object_id
            AND ibl.index_id <> iibl.index_id
            AND (ibl.indexed_columns_compare LIKE iibl.indexed_columns_compare + '%' 
                OR iibl.indexed_columns_compare LIKE ibl.indexed_columns_compare + '%')
            AND ibl.indexed_columns_compare <> iibl.indexed_columns_compare 
            FOR XML PATH('')), 1, 2, '')
    ,related_foreign_keys = STUFF((SELECT ', ' + foreign_key_name AS [data()]
            FROM #ForeignKeys ifk
            WHERE ifk.object_id = ibl.object_id
            AND ibl.indexed_columns_compare LIKE ifk.fk_columns_compare + '%'
            FOR XML PATH('')), 1, 2, '')
    ,related_foreign_keys_xml = CAST((SELECT foreign_key_name
            FROM #ForeignKeys ForeignKeys
            WHERE ForeignKeys.object_id = ibl.object_id
            AND ibl.indexed_columns_compare LIKE ForeignKeys.fk_columns_compare + '%'
            FOR XML AUTO) as xml) 
FROM #IndexBaseLine ibl

INSERT INTO #IndexBaseLine
    (server_name, database_name, database_id, schema_id, schema_name, object_id, table_name, index_name, type_desc, existing_ranking, indexed_columns)
SELECT	@@ServerName
	,DB_Name(@DB_ID)
	,@DB_ID
	,s.schema_id
	,s.name AS schema_name
	,t.object_id
	,t.name AS table_name
	,fk.foreign_key_name AS index_name
	,'--MISSING FOREIGN KEY--' as type_desc
	,9999
	,fk.fk_columns
FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN #ForeignKeys fk ON t.object_id = fk.object_id
    LEFT OUTER JOIN #IndexBaseLine ia ON fk.object_id = ia.object_id AND ia.indexed_columns_compare LIKE fk.fk_columns_compare + '%'
WHERE ia.index_name IS NULL





;WITH	ReadAggregation
	AS	(
		SELECT	row_id
			,CAST(100. * (user_seeks + user_scans + user_lookups)
			    /(NULLIF(SUM(user_seeks + user_scans + user_lookups) 
			    OVER(PARTITION BY schema_name, table_name), 0) * 1.) as decimal(12,2)) AS estimated_user_total_pct
			,SUM(buffer_mb) OVER(PARTITION BY schema_name, table_name) as table_buffer_mb
		FROM	#IndexBaseLine 
		)
	,WriteAggregation
	AS	(
		SELECT	row_id
			,CAST((100.00 * user_updates)
			    /(NULLIF(SUM(user_updates) 
			    OVER(PARTITION BY schema_name, table_name), 0) * 1.) as decimal(12,2)) AS estimated_user_total_pct
		FROM	#IndexBaseLine 
		)
UPDATE ibl
SET	estimated_user_total_read_pct = COALESCE(r.estimated_user_total_pct, 0.00)
	,estimated_user_total_write_pct = COALESCE(w.estimated_user_total_pct, 0.00)
	,table_buffer_mb = r.table_buffer_mb
	,index_read_pct = (COALESCE(user_total_read,0.00) * 100.00) / CASE WHEN COALESCE(user_total_read,0.00) + COALESCE(user_total_write,0.00) = 0.00 THEN 1.00 ELSE COALESCE(user_total_read,0.00) + COALESCE(user_total_write,0.00) END
	,index_write_pct = (COALESCE(user_total_write,0.00) * 100.00) / CASE WHEN COALESCE(user_total_read,0.00) + COALESCE(user_total_write,0.00) = 0.00 THEN 1.00 ELSE COALESCE(user_total_read,0.00) + COALESCE(user_total_write,0.00) END
FROM #IndexBaseLine ibl
    INNER JOIN ReadAggregation r ON ibl.row_id = r.row_id
    INNER JOIN WriteAggregation w ON ibl.row_id = w.row_id


;WITH IndexAction
AS (
    SELECT row_id
        ,CASE WHEN user_lookups > user_seeks AND type_desc IN ('CLUSTERED', 'HEAP', 'UNIQUE CLUSTERED') THEN 'REALIGN'
            WHEN type_desc = '--MISSING FOREIGN KEY--' THEN 'CREATE'
            WHEN type_desc = 'XML' THEN '---'
            WHEN is_unique = 1 THEN '---'
            WHEN type_desc = '--NONCLUSTERED--' AND ROW_NUMBER() OVER (PARTITION BY table_name ORDER BY user_total_read desc) <= 10 AND estimated_user_total_read_pct > 1 THEN 'CREATE'
            WHEN type_desc = '--NONCLUSTERED--' THEN 'BLEND'
            WHEN ROW_NUMBER() OVER (PARTITION BY table_name ORDER BY user_total_read desc, existing_ranking) > 10 THEN 'DROP' 
            WHEN user_total_read = 0 THEN 'DROP' 
            ELSE '---' END AS index_action
    FROM #IndexBaseLine
)
UPDATE ibl
SET index_action = ia.index_action
FROM #IndexBaseLine ibl INNER JOIN IndexAction ia
ON ibl.row_id = ia.row_id

UPDATE ibl
SET has_unique = 1
FROM #IndexBaseLine ibl
    INNER JOIN (SELECT DISTINCT object_id FROM sys.indexes i WHERE i.is_unique = 1) x ON ibl.object_id = x.object_id

SELECT	server_name
	,database_name
	,database_id
	,schema_name + '.' + table_name as object_name
	,has_unique
	,table_buffer_mb
	,index_action
	,index_name
	,is_unique
	,type_desc
	,impact
	,size_in_mb
	,buffer_mb
	,pct_in_buffer
	,row_count
	,page_count
	,max_key_size
	,user_total_read
	,user_total_read_pct
	,estimated_user_total_read_pct
	,user_total_write
	,user_total_write_pct
	,estimated_user_total_write_pct
	,index_read_pct
	,index_write_pct
	,user_seeks
	,user_scans
	,user_lookups
	,user_updates
	,row_lock_count
	,row_lock_wait_count
	,row_lock_wait_in_ms
	,row_block_pct
	,avg_row_lock_waits_ms
	,page_lock_count
	,page_lock_wait_count
	,page_lock_wait_in_ms
	,page_block_pct
	,avg_page_lock_waits_ms
	,splits
	,indexed_columns
	,indexed_column_count
	,included_columns
	,included_column_count
	,duplicate_indexes
	,overlapping_indexes
	,related_foreign_keys
	,related_foreign_keys_xml 
FROM	#IndexBaseLine
ORDER BY table_buffer_mb DESC, object_id, user_total_read DESC