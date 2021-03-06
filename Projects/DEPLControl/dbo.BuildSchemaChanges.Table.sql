USE [DEPLcontrol]
GO
/****** Object:  Table [dbo].[BuildSchemaChanges]    Script Date: 10/4/2013 11:02:04 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[BuildSchemaChanges](
	[LogId] [bigint] IDENTITY(1,1) NOT NULL,
	[EventType] [sysname] NOT NULL,
	[DatabaseName] [sysname] NULL,
	[SchemaName] [sysname] NULL,
	[ObjectName] [sysname] NULL,
	[ObjectType] [sysname] NULL,
	[SqlCommand] [varchar](max) NULL,
	[EventDate] [datetime] NOT NULL,
	[LoginName] [sysname] NULL,
	[UserName] [sysname] NULL,
	[VC_DatabaseName] [sysname] NULL,
	[VC_SchemaName] [sysname] NULL,
	[VC_ObjectType] [sysname] NULL,
	[VC_ObjectName] [sysname] NULL,
	[VC_Version] [sysname] NULL,
	[VC_CreatedBy] [sysname] NULL,
	[VC_CreatedOn] [datetime] NULL,
	[VC_ModifiedBy] [sysname] NULL,
	[VC_ModifiedOn] [sysname] NULL,
	[VC_Purpose] [sysname] NULL,
	[VC_BuildApp] [sysname] NULL,
	[VC_BuildBrnch] [sysname] NULL,
	[VC_BuildNum] [sysname] NULL,
	[DB_BuildApp] [sysname] NULL,
	[DB_BuildBrnch] [sysname] NULL,
	[DB_BuildNum] [sysname] NULL,
	[DEPLInstanceID] [uniqueidentifier] NULL,
	[DEPLFileName] [sysname] NULL,
	[Status] [varchar](2000) NULL,
 CONSTRAINT [PK_BuildSchemaChanges] PRIMARY KEY CLUSTERED 
(
	[LogId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
ALTER TABLE [dbo].[BuildSchemaChanges] ADD  CONSTRAINT [DF_BuildSchemaChanges_EventDate]  DEFAULT (getdate()) FOR [EventDate]
GO
ALTER TABLE [dbo].[BuildSchemaChanges] ADD  CONSTRAINT [DF_BuildSchemaChanges_DEPLInstanceID]  DEFAULT ([dbo].[GetDEPLInstanceID]()) FOR [DEPLInstanceID]
GO
EXEC sys.sp_addextendedproperty @name=N'Version', @value=N'1.6.3' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'BuildSchemaChanges'
GO
