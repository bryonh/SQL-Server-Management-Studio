USE [DEPLcontrol]
GO
/****** Object:  User [DEPLMaster]    Script Date: 10/4/2013 11:02:04 AM ******/
CREATE USER [DEPLMaster] FOR LOGIN [DEPLMaster] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [DEPLMaster]
GO
