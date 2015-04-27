/****** Script for SelectTopNRows command from SSMS  ******/
SELECT TOP 1000 [rundate]
      ,[ServerName]
      ,[DatabaseName]
      ,[SchemaName]
      ,[TableName]
      ,[blitz_result_id]
      ,[check_id]
      ,[findings_group]
      ,[finding]
      ,[URL]
      ,[details]
      ,[index_definition]
      ,[secret_columns]
      ,[index_usage_summary]
      ,[index_size_summary]
      ,[create_tsql]
      ,[more_info]
      ,[database_id]
      ,[object_id]
      ,[index_id]
      ,[index_type]
      ,[database_name]
      ,[schema_name]
      ,[object_name]
      ,[index_name]
      ,[key_column_names]
      ,[key_column_names_with_sort_order]
      ,[key_column_names_with_sort_order_no_types]
      ,[count_key_columns]
      ,[include_column_names]
      ,[include_column_names_no_types]
      ,[count_included_columns]
      ,[partition_key_column_name]
      ,[filter_definition]
      ,[is_indexed_view]
      ,[is_unique]
      ,[is_primary_key]
      ,[is_XML]
      ,[is_spatial]
      ,[is_NC_columnstore]
      ,[is_CX_columnstore]
      ,[is_disabled]
      ,[is_hypothetical]
      ,[is_padded]
      ,[fill_factor]
      ,[user_seeks]
      ,[user_scans]
      ,[user_lookups]
      ,[user_updates]
      ,[last_user_seek]
      ,[last_user_scan]
      ,[last_user_lookup]
      ,[last_user_update]
      ,[is_referenced_by_foreign_key]
      ,[secret_columns_2]
      ,[count_secret_columns]
      ,[create_date]
      ,[modify_date]
      ,[create_tsql_2]
      ,[stat_date]
  FROM [DBAperf_reports].[dbo].[IndexHealth_Results]
  WHERE ServerName = 'G1SQLA\A' AND DatabaseName = 'WCDS' AND rundate = '2014-09-19 00:00:00.000' AND finding = 'Unused NC index'
