SELECT SQLNAME,port From dba_serverinfo where servername IN
(
'FREBGMSSQLA01',
'FREBGMSSQLB01',
'FREBASPSQL01',
'FREBSHWSQL01'
)