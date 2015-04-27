USE [DEPLcontrol]
GO
/****** Object:  Table [dbo].[db_BaseLocation]    Script Date: 10/4/2013 11:02:05 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[db_BaseLocation](
	[seq_id] [int] IDENTITY(1,1) NOT NULL,
	[db_name] [sysname] NOT NULL,
	[companionDB_name] [sysname] NULL,
	[RSTRfolder] [sysname] NULL,
	[baseline_srvname] [sysname] NULL
) ON [PRIMARY]

GO
