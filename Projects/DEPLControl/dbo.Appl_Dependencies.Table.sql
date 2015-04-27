USE [DEPLcontrol]
GO
/****** Object:  Table [dbo].[Appl_Dependencies]    Script Date: 10/4/2013 11:02:04 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Appl_Dependencies](
	[ad_id] [int] IDENTITY(1,1) NOT NULL,
	[APPLname_primary] [sysname] NOT NULL,
	[APPLname_dependent_on] [sysname] NOT NULL,
	[dependency_type] [sysname] NOT NULL
) ON [PRIMARY]

GO
