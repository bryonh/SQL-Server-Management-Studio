USE [DEPLcontrol]
GO
/****** Object:  Table [dbo].[db_sequence]    Script Date: 10/4/2013 11:02:05 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[db_sequence](
	[seq_id] [int] NOT NULL,
	[DBname] [sysname] NOT NULL
) ON [PRIMARY]

GO
