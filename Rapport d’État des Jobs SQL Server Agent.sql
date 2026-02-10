USE msdb;
GO

SELECT
    -- Nom du job
    j.name AS [Nom du Job],

    -- Statut global du job
    CASE 
        WHEN j.enabled = 1 THEN 'Activé'
        ELSE 'Désactivé'
    END AS [Statut Job],

    -- Dernier résultat d'exécution
    CASE h.run_status
        WHEN 0 THEN 'Échec'
        WHEN 1 THEN 'Réussi'
        WHEN 2 THEN 'Réessayer'
        WHEN 3 THEN 'Annulé'
        WHEN 4 THEN 'En cours'
        ELSE 'Inconnu'
    END AS [Dernier Résultat],

    -- Date et heure de la dernière exécution
    CASE 
        WHEN h.run_date = 0 THEN 'Jamais exécuté'
        ELSE 
            CONVERT(VARCHAR, 
                DATEADD(
                    SECOND, 
                    (h.run_time % 100) + ((h.run_time / 100) % 100) * 60 + (h.run_time / 10000) * 3600,
                    CAST(
                        STUFF(STUFF(CAST(h.run_date AS VARCHAR(8)), 5, 0, '-'), 8, 0, '-') + ' 00:00:00' 
                        AS DATETIME
                    )
                ), 
                120
            )
    END AS [Date Dernière Exécution],

    -- Message de sortie
    ISNULL(LEFT(h.message, 255), 'Aucun message') AS [Message Dernière Exécution],

    -- Durée de la dernière exécution (format HH:MM:SS)
    RIGHT('0' + CAST((h.run_duration / 10000) AS VARCHAR), 2) + ':' +
    RIGHT('0' + CAST((h.run_duration / 100) % 100 AS VARCHAR), 2) + ':' +
    RIGHT('0' + CAST(h.run_duration % 100 AS VARCHAR), 2) AS [Durée Dernière Exécution],

    -- Fréquence
    CASE s.freq_type
        WHEN 1 THEN 'Une fois'
        WHEN 4 THEN 'Quotidien'
        WHEN 8 THEN 'Hebdomadaire (toutes les ' + CAST(s.freq_interval AS VARCHAR) + ' semaines)'
        WHEN 16 THEN 'Tous les ' + CAST(s.freq_interval AS VARCHAR) + ' jours'
        WHEN 32 THEN 'Mensuel (relatif)'
        WHEN 64 THEN 'Au démarrage du serveur'
        WHEN 128 THEN 'Lorsque l''UC est inoccupée'
        ELSE 'Personnalisé'
    END AS [Fréquence],

    -- Intervalle (ex: toutes les 2 heures)
    CASE 
        WHEN s.freq_subday_type = 1 THEN 'Une fois à l''heure spécifiée'
        WHEN s.freq_subday_type = 4 THEN 'Toutes les ' + CAST(s.freq_subday_interval AS VARCHAR) + ' minutes'
        WHEN s.freq_subday_type = 8 THEN 'Toutes les ' + CAST(s.freq_subday_interval AS VARCHAR) + ' heures'
        ELSE 'Non récurrent'
    END AS [Intervalle],

    -- Prochaine exécution prévue
    CASE 
        WHEN js.next_run_date = 0 THEN 'Aucune planification active'
        ELSE 
            CONVERT(VARCHAR, 
                DATEADD(
                    SECOND, 
                    (js.next_run_time % 100) + ((js.next_run_time / 100) % 100) * 60 + (js.next_run_time / 10000) * 3600,
                    CAST(
                        STUFF(STUFF(CAST(js.next_run_date AS VARCHAR(8)), 5, 0, '-'), 8, 0, '-') + ' 00:00:00' 
                        AS DATETIME
                    )
                ), 
                120
            )
    END AS [Prochaine Exécution]

FROM 
    dbo.sysjobs j
    LEFT JOIN (
        -- Dernière exécution de chaque job (step_id = 0 = job global)
        SELECT 
            job_id,
            run_status,
            run_date,
            run_time,
            message,
            run_duration,
            ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
        FROM dbo.sysjobhistory 
        WHERE step_id = 0
    ) h ON j.job_id = h.job_id AND h.rn = 1

    LEFT JOIN dbo.sysjobschedules js ON j.job_id = js.job_id
    LEFT JOIN dbo.sysschedules s ON js.schedule_id = s.schedule_id

ORDER BY 
    [Nom du Job];