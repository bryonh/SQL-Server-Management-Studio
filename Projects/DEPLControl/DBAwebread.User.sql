USE [DEPLcontrol]
GO
/****** Object:  User [DBAwebread]    Script Date: 10/4/2013 11:02:04 AM ******/
CREATE USER [DBAwebread] FOR LOGIN [DBAwebread] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [aspnet_ChangeNotification_ReceiveNotificationsOnlyAccess] ADD MEMBER [DBAwebread]
GO
ALTER ROLE [db_datareader] ADD MEMBER [DBAwebread]
GO
ALTER ROLE [db_datawriter] ADD MEMBER [DBAwebread]
GO
