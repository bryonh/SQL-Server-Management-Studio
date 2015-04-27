USE [DEPLcontrol]
GO
/****** Object:  Table [dbo].[email_errors]    Script Date: 10/4/2013 11:02:05 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[email_errors](
	[ee_id] [int] IDENTITY(1,1) NOT NULL,
	[Gears_id] [int] NOT NULL,
	[SQLname] [sysname] NOT NULL,
	[status] [nvarchar](10) NULL,
	[createdate] [datetime] NOT NULL
) ON [PRIMARY]

GO
