USE msdb;
GO

-- Check if SQL Agent is running
DECLARE @AgentStatus INT;
EXEC master.dbo.xp_servicecontrol 'querystate', 'SQLSERVERAGENT', @AgentStatus OUTPUT;

IF @AgentStatus = 1 -- Running
BEGIN
    -- Delete existing job if it exists
    IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = 'Import_Ontario511_Daily')
    BEGIN
        -- First detach any schedules
        DECLARE @schedule_id INT;
        SELECT @schedule_id = schedule_id 
        FROM dbo.sysjobschedules js
        JOIN dbo.sysjobs j ON js.job_id = j.job_id
        WHERE j.name = 'Import_Ontario511_Daily';
        
        IF @schedule_id IS NOT NULL
        BEGIN
            EXEC dbo.sp_detach_schedule 
                @job_name = 'Import_Ontario511_Daily',
                @schedule_id = @schedule_id;
        END
        
        -- Now delete the job
        EXEC dbo.sp_delete_job
            @job_name = 'Import_Ontario511_Daily',
            @delete_unused_schedule = 1;
    END

    -- Delete duplicate schedules if they exist
    DECLARE @schedule_count INT;
    SELECT @schedule_count = COUNT(*) 
    FROM dbo.sysschedules 
    WHERE name = 'ToutesLes2Heures';
    
    IF @schedule_count > 0
    BEGIN
        DECLARE schedule_cursor CURSOR FOR
        SELECT schedule_id FROM dbo.sysschedules WHERE name = 'ToutesLes2Heures';
        
        DECLARE @current_schedule_id INT;
        OPEN schedule_cursor;
        FETCH NEXT FROM schedule_cursor INTO @current_schedule_id;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                EXEC dbo.sp_delete_schedule
                    @schedule_id = @current_schedule_id;
            END TRY
            BEGIN CATCH
                PRINT 'Error deleting schedule ID ' + CAST(@current_schedule_id AS VARCHAR) + 
                      ': ' + ERROR_MESSAGE();
            END CATCH
            
            FETCH NEXT FROM schedule_cursor INTO @current_schedule_id;
        END
        
        CLOSE schedule_cursor;
        DEALLOCATE schedule_cursor;
    END

    -- Create the job
    EXEC dbo.sp_add_job
        @job_name = 'Import_Ontario511_Daily',
        @enabled = 1;

    -- Add job steps
    EXEC sp_add_jobstep
        @job_name = 'Import_Ontario511_Daily',
        @step_name = 'Import Evenements',
        @subsystem = 'TSQL',
        @database_name = 'ontario511',
        @command = 'EXEC ImporterDonneesDepuisTemp ''evenements'';',
        @on_success_action = 3;

    EXEC sp_add_jobstep
        @job_name = 'Import_Ontario511_Daily',
        @step_name = 'Archiver Evenements',
        @subsystem = 'TSQL',
        @database_name = 'ontario511',
        @command = 'EXEC ArchiverEvenementsObsoletes;',
        @on_success_action = 3;

    EXEC sp_add_jobstep
        @job_name = 'Import_Ontario511_Daily',
        @step_name = 'Calculer KPI',
        @subsystem = 'TSQL',
        @database_name = 'ontario511',
        @command = 'EXEC CalculerIndicateursKPI;';

    -- Create new schedule with unique name
    DECLARE @new_schedule_name VARCHAR(128);
    SET @new_schedule_name = 'ToutesLes2Heures_' + REPLACE(CONVERT(VARCHAR, GETDATE(), 112) + 
                            REPLACE(CONVERT(VARCHAR, GETDATE(), 108), ':', ''), ' ', '_');

    EXEC sp_add_schedule
        @schedule_name = @new_schedule_name,
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 8,
        @freq_subday_interval = 2;

    EXEC sp_attach_schedule
        @job_name = 'Import_Ontario511_Daily',
        @schedule_name = @new_schedule_name;

    EXEC sp_add_jobserver
        @job_name = 'Import_Ontario511_Daily';

    PRINT 'Job created successfully with schedule: ' + @new_schedule_name;
END
ELSE
BEGIN
    PRINT 'SQL Server Agent is not running. Job cannot be created or started.';
    PRINT 'Please start SQL Server Agent service and try again.';
    PRINT 'Note: Starting the service may require administrator privileges.';
END
GO