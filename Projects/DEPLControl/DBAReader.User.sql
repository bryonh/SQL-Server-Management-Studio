USE [DEPLcontrol]
GO
/****** Object:  User [DBAReader]    Script Date: 10/4/2013 11:02:04 AM ******/
CREATE USER [DBAReader] FOR LOGIN [DBAReader] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [aspnet_ChangeNotification_ReceiveNotificationsOnlyAccess] ADD MEMBER [DBAReader]
GO
ALTER ROLE [db_owner] ADD MEMBER [DBAReader]
GO
