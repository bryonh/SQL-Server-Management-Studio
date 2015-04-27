  
SELECT		sdb.name
			,bl.*
from		master..sysdatabases sdb
JOIN		[deplinfo].[dbo].[db_BaseLocation] bl
	ON		bl.[db_name] = sdb.name
	AND		DB_ID(COALESCE(nullif([companionDB_name],''),[db_name])) IS NOT NULL






