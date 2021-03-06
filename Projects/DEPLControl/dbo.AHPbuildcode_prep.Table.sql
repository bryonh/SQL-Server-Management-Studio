USE [DEPLcontrol]
GO
/****** Object:  Table [dbo].[AHPbuildcode_prep]    Script Date: 10/4/2013 11:02:04 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[AHPbuildcode_prep](
	[bc_id] [int] IDENTITY(1,1) NOT NULL,
	[BuildLabel] [sysname] NOT NULL,
	[ReleaseNum] [sysname] NULL,
	[TargetPath] [nvarchar](500) NULL,
	[Status] [sysname] NULL,
	[CreateDate] [datetime] NOT NULL,
	[InWorkDate] [datetime] NULL,
	[CompletedDate] [datetime] NULL
) ON [PRIMARY]

GO
