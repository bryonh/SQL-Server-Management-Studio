with XMLNAMESPACES 
('http://schemas.microsoft.com/sqlserver/2004/07/showplan' as sql)
select
total_worker_time/execution_count AS AvgCPU
, total_elapsed_time/execution_count AS AvgDuration
, (total_logical_reads+total_physical_reads)/execution_count AS AvgReads
, execution_count
, SUBSTRING(st.TEXT, (qs.statement_start_offset/2)+1 , ((CASE
qs.statement_end_offset WHEN -1 THEN datalength(st.TEXT) ELSE
qs.statement_end_offset END - qs.statement_start_offset)/2) + 1) AS txt
, qs.max_elapsed_time
, db_name(qp.dbid) as database_name
, quotename(object_schema_name(qp.objectid, qp.dbid)) + N'.' + 
quotename(object_name(qp.objectid, qp.dbid)) as obj_name
, qp.query_plan.value( 
N'(/sql:ShowPlanXML/sql:BatchSequence/sql:Batch/sql:Statements/sql:StmtSimple[@StatementType 
= 
"SELECT"]/sql:QueryPlan/sql:RelOp/descendant::*/sql:ScalarOperator[contains(@ScalarString, 
"CONVERT_IMPLICIT")])[1]/@ScalarString', 'nvarchar(4000)' ) as scalar_string
, qp.query_plan
from sys.dm_exec_query_stats as qs
cross apply sys.dm_exec_query_plan(qs.plan_handle) as qp
cross apply sys.dm_exec_sql_text(qs.sql_handle) st
where qp.query_plan.exist( 
N'/sql:ShowPlanXML/sql:BatchSequence/sql:Batch/sql:Statements/sql:StmtSimple[@StatementType 
= 
"SELECT"]/sql:QueryPlan/sql:RelOp/sql:IndexScan/descendant::*/sql:ScalarOperator[contains(@ScalarString, 
"CONVERT_IMPLICIT")]' ) = 1;
