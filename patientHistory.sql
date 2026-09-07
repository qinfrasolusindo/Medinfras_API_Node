/* =====================================================================================

    [HG] 20260904 

    untuk pembuatan MCP
   Catatan  : - Asumsi IsFromMigration selalu 0 tetap dipakai (branch vPastMedical
                sengaja tidak diimplementasikan, sesuai query asli kamu).
              - Kode SUBJECTIVE_NOTES di-hardcode 'X011^007' sesuai hasil auto-lookup
                kamu sebelumnya. Kalau environment lain beda, tinggal ganti nilai
                @SubjectiveNotesCode di bawah.
              - EARLY_DIAGNOSIS_CODE, PHYSICIAN_CODE, dan status appointment
                deleted/cancelled MASIH placeholder seperti di query asli -- belum
                di-resolve, jadi behaviour-nya sama seperti sebelumnya (lihat NOTE
                di masing-masing bagian).
   ===================================================================================== */

CREATE OR ALTER PROCEDURE [dbo].[GetPatientHistoryMCP]
(
    @MRN            VARCHAR(50)  = NULL,   -- MRN exact match
    @PatientName    VARCHAR(200) = NULL,   -- partial match (LIKE '%...%')
    @VisitDateFrom  DATE         = NULL,
    @VisitDateTo    DATE         = NULL,
    @LastNVisits    INT          = NULL    -- ambil N kunjungan terakhir PER MRN
)
AS

BEGIN
    
    SET NOCOUNT ON;

    /* ---- Guard wajib: minimal salah satu identitas pasien harus diisi ---- */
    IF (@MRN IS NULL OR LTRIM(RTRIM(@MRN)) = '')
       AND (@PatientName IS NULL OR LTRIM(RTRIM(@PatientName)) = '')
    BEGIN
        RAISERROR('MRN atau PatientName wajib diisi salah satu. Query dibatalkan untuk mencegah full scan.', 16, 1);
        RETURN;
    END

    DECLARE @SubjectiveNotesCode VARCHAR(20) = 'X011^007';

    /* =================================================================================
       1) VISIT HEADER (sudah difilter MRN/Nama/Tanggal/LastNVisits)
       ================================================================================= */
    IF OBJECT_ID('tempdb..#VisitHeaderRaw') IS NOT NULL DROP TABLE #VisitHeaderRaw;
    IF OBJECT_ID('tempdb..#VisitHeader')    IS NOT NULL DROP TABLE #VisitHeader;

    SELECT
        v4.VisitID,
        v4.RegistrationID,
        v4.RegistrationNo,
        v4.MRN,
        v4.PatientName,
        v4.DateOfBirth,
        v4.Gender,
        v4.VisitDate,
        v4.VisitTime,
        v4.DepartmentID,
        v4.ServiceUnitName,
        v4.ParamedicName                         AS AttendingPhysicianName,
        v4.ClassName,
        v4.GCVisitStatus,
        v4.GCCaseType,
        v4.CaseType                              AS CaseTypeText,
        v4.VisitReason,
        v4.HospitalizationIndication,
        v5.PhysicianName                         AS DPJPName,
        v5.DischargeDate,
        v5.DischargeTime,
        v5.GCDischargeCondition,
        v5.DischargeCondition                    AS DischargeConditionText,
        v5.GCDischargeMethod,
        v5.DischargeMethod                       AS DischargeMethodText,
        v5.DischargeRemarks,
        v5.DateOfDeath,
        v5.TimeOfDeath,
        v5.LOSInDay,
        v5.ReferrerName,
        v5.ReferralToName,
        v4.IsPreventiveCare,
        v4.IsCurativeCare,
        v4.IsRehabilitationCare,
        v4.IsPalliativeCare,
        ROW_NUMBER() OVER (PARTITION BY v4.MRN ORDER BY v4.VisitDate DESC, v4.VisitTime DESC) AS rn
    INTO #VisitHeaderRaw
    FROM vConsultVisit4 v4
    LEFT JOIN vConsultVisit5 v5 ON v5.VisitID = v4.VisitID
    WHERE v4.GCVisitStatus <> 'X020^006'
      AND (
            (@MRN IS NOT NULL AND LTRIM(RTRIM(@MRN)) <> '' AND v4.MRN = @MRN)
            OR
            (@PatientName IS NOT NULL AND LTRIM(RTRIM(@PatientName)) <> '' AND v4.PatientName LIKE '%' + @PatientName + '%')
          )
      AND (@VisitDateFrom IS NULL OR v4.VisitDate >= @VisitDateFrom)
      AND (@VisitDateTo   IS NULL OR v4.VisitDate <= @VisitDateTo);

    SELECT
        VisitID, RegistrationID, RegistrationNo, MRN, PatientName, DateOfBirth, Gender,
        VisitDate, VisitTime, DepartmentID, ServiceUnitName, AttendingPhysicianName,
        ClassName, GCVisitStatus, GCCaseType, CaseTypeText, VisitReason,
        HospitalizationIndication, DPJPName, DischargeDate, DischargeTime,
        GCDischargeCondition, DischargeConditionText, GCDischargeMethod,
        DischargeMethodText, DischargeRemarks, DateOfDeath, TimeOfDeath, LOSInDay,
        ReferrerName, ReferralToName, IsPreventiveCare, IsCurativeCare,
        IsRehabilitationCare, IsPalliativeCare
    INTO #VisitHeader
    FROM #VisitHeaderRaw
    WHERE (@LastNVisits IS NULL OR rn <= @LastNVisits);

    IF NOT EXISTS (SELECT 1 FROM #VisitHeader)
    BEGIN
        SELECT CAST(N'{"Visits":[]}' AS NVARCHAR(MAX)) AS JsonResult;
        RETURN;
    END

    /* =================================================================================
       2) SECTION-LEVEL CONTENT (identik dengan query asli, hanya sumbernya #VisitHeader
          yang sudah kepasangkan filter di atas)
       ================================================================================= */
    IF OBJECT_ID('tempdb..#EhrSection') IS NOT NULL DROP TABLE #EhrSection;
    CREATE TABLE #EhrSection
    (
        MRN             VARCHAR(50),
        VisitID         INT,
        SectionType     VARCHAR(30),
        SourceID        VARCHAR(50) NULL,
        SectionDate     VARCHAR(20) NULL,
        SectionTime     VARCHAR(20) NULL,
        AuthorName      VARCHAR(200) NULL,
        DiagnosisType   VARCHAR(100) NULL,
        IsAbnormal      BIT NULL,
        SectionText     NVARCHAR(MAX)
    );

    -- 2a. Chief Complaint / HPI
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
    SELECT
        cc.MRN, cc.VisitID, 'ChiefComplaint',
        CONVERT(VARCHAR(50), cc.ID),
        CONVERT(VARCHAR(20), cc.ObservationDate, 23),
        cc.ObservationTime,
        cc.ParamedicName,
        CONCAT(
            N'Keluhan Utama: ', ISNULL(cc.ChiefComplaintText, N''),
            CASE WHEN cc.HPISummary IS NOT NULL AND cc.HPISummary <> N''
                 THEN CONCAT(N' | RPS (HPI): ', cc.HPISummary) ELSE N'' END,
            CASE WHEN cc.PastMedicalHistory IS NOT NULL AND cc.PastMedicalHistory <> N''
                 THEN CONCAT(N' | Riwayat Penyakit Dahulu: ', cc.PastMedicalHistory) ELSE N'' END,
            CASE WHEN cc.FamilyHistory IS NOT NULL AND cc.FamilyHistory <> N''
                 THEN CONCAT(N' | Riwayat Keluarga: ', cc.FamilyHistory) ELSE N'' END,
            CASE WHEN cc.DiagnosticResultSummary IS NOT NULL AND cc.DiagnosticResultSummary <> N''
                 THEN CONCAT(N' | Catatan Hasil Pemeriksaan Penunjang: ', cc.DiagnosticResultSummary) ELSE N'' END,
            CASE WHEN cc.PlanningSummary IS NOT NULL AND cc.PlanningSummary <> N''
                 THEN CONCAT(N' | Catatan Tindakan: ', cc.PlanningSummary) ELSE N'' END
        )
    FROM vChiefComplaint cc
    WHERE cc.IsDeleted = 0
      AND EXISTS (SELECT 1 FROM #VisitHeader vh WHERE vh.VisitID = cc.VisitID);

    -- Fallback: visit tanpa vChiefComplaint -> pakai SUBJECTIVE_NOTES
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
    SELECT
        vh.MRN, pvn.VisitID, 'ChiefComplaint',
        CONVERT(VARCHAR(50), pvn.ID),
        CONVERT(VARCHAR(20), pvn.NoteDate, 23),
        pvn.NoteTime,
        CONCAT(pvn.ParamedicName, N' (Entried By: ', pvn.CreatedByName, N')'),
        pvn.NoteText
    FROM vPatientVisitNote pvn
    INNER JOIN #VisitHeader vh ON vh.VisitID = pvn.VisitID
    WHERE @SubjectiveNotesCode IS NOT NULL
      AND pvn.IsDeleted = 0
      AND pvn.GCPatientNoteType = @SubjectiveNotesCode
      AND pvn.NoteText IS NOT NULL AND pvn.NoteText <> N''
      AND NOT EXISTS (SELECT 1 FROM vChiefComplaint cc WHERE cc.VisitID = pvn.VisitID AND cc.IsDeleted = 0);

    -- 2b. Review of System
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
    SELECT
        vh.MRN, hd.VisitID, 'ReviewOfSystem',
        CONVERT(VARCHAR(50), hd.ID),
        CONVERT(VARCHAR(20), hd.ObservationDate, 23),
        hd.ObservationTime,
        hd.ParamedicName,
        STUFF((
            SELECT CONCAT(
                N'; ', dt.ROSystem, N': ',
                CASE
                    WHEN dt.IsNotExamined = 1 THEN 'Not Examined'
                    WHEN dt.IsNormal = 1 THEN 'Normal'
                    WHEN dt.IsOther = 1 THEN 'Other'
                    ELSE 'Abnormal'
                END
                + CASE WHEN ISNULL(dt.Remarks, '') <> '' THEN CONCAT(' : ', dt.Remarks) ELSE '' END
            )
            FROM vReviewOfSystemDt dt
            WHERE dt.ID = hd.ID AND dt.IsDeleted = 0
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, '')
    FROM vReviewOfSystemHd hd
    INNER JOIN #VisitHeader vh ON vh.VisitID = hd.VisitID
    WHERE hd.IsDeleted = 0;

    -- 2c. Vital Signs
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
    SELECT
        vh.MRN, hd.VisitID, 'VitalSign',
        CONVERT(VARCHAR(50), hd.ID),
        CONVERT(VARCHAR(20), hd.ObservationDate, 23),
        hd.ObservationTime,
        hd.ParamedicName,
        STUFF((
            SELECT CONCAT(
                N'; ', dt.VitalSignLabel, N': ',
                CASE
                    WHEN ISNULL(dt.VitalSignValue, '') = '' THEN '-'
                    WHEN dt.GCValueType = 'X103^001' THEN CONCAT(dt.VitalSignValue, ' ', dt.ValueUnit)
                    ELSE dt.VitalSignValue
                END
            )
            FROM vVitalSignDt dt
            WHERE dt.ID = hd.ID AND dt.IsDeleted = 0
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, '')
    FROM vVitalSignHd hd
    INNER JOIN #VisitHeader vh ON vh.VisitID = hd.VisitID
    WHERE hd.IsDeleted = 0;

    -- 2d. Diagnosis
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, DiagnosisType, SectionText)
    SELECT
        pd.MRN, pd.VisitID, 'Diagnosis',
        CONVERT(VARCHAR(50), pd.ID),
        CONVERT(VARCHAR(20), pd.DifferentialDate, 23),
        pd.DifferentialTime,
        CASE WHEN pd.GCDiagnoseType = 'X029^000' THEN NULL ELSE pd.ParamedicName END,
        pd.DiagnoseType,
        CONCAT(
            N'Diagnosis (', ISNULL(pd.DiagnoseType, N'-'), N'): ', ISNULL(pd.DiagnosisText, N''),
            CASE WHEN pd.DiagnoseName IS NOT NULL THEN CONCAT(N' [', pd.DiagnoseName, N']') ELSE N'' END,
            CASE WHEN pd.FinalDiagnosisText IS NOT NULL AND pd.FinalDiagnosisText <> N''
                 THEN CONCAT(N' | Diagnosis Akhir: ', pd.FinalDiagnosisText) ELSE N'' END
        )
    FROM vPatientDiagnosis pd
    INNER JOIN #VisitHeader vh ON vh.VisitID = pd.VisitID
    WHERE pd.IsDeleted = 0;
    -- NOTE: 'EARLY_DIAGNOSIS_CODE' belum di-resolve (lihat query asli, README 5.2) -- masih placeholder.

    -- 2e. Laboratory
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, IsAbnormal, SectionText)
    SELECT
        lab.MRN, lab.VisitID, 'Laboratory',
        CONVERT(VARCHAR(50), lab.TransactionID),
        CONVERT(VARCHAR(20), lab.TransactionDate, 23),
        lab.TransactionTime,
        lab.ParamedicName,
        CAST(MAX(CASE WHEN dt.ResultFlag IS NOT NULL AND dt.ResultFlag <> 'N' THEN 1 ELSE 0 END) AS BIT),
        CONCAT(
            lab.ItemName1, N': ',
            STUFF((
                SELECT CONCAT(
                    N'; ', d.FractionName1, N' = ',
                    ISNULL(d.TextValue, CONVERT(NVARCHAR(50), d.MetricResultValue)), ' ',
                    ISNULL(d.MetricUnit, N''),
                    CASE WHEN d.ResultFlag IS NOT NULL AND d.ResultFlag <> 'N'
                         THEN CONCAT(N' (', d.ResultFlag, N')') ELSE N'' END,
                    CASE
                        WHEN ISNULL(d.ReferenceRange, '') <> ''
                            THEN CONCAT(N' [ref: ', d.ReferenceRange, N']')
                        WHEN d.GCLabTestResultType = 'NUMERIC'
                            THEN CONCAT(N' [ref: ', CONVERT(NVARCHAR(50), d.MinMetricNormalValue), ' - ', CONVERT(NVARCHAR(50), d.MaxMetricNormalValue), ']')
                        ELSE CONCAT(N' [ref: ', ISNULL(d.TextNormalValue, ''), ']')
                    END
                )
                FROM vLaboratoryResultDt d
                WHERE d.ChargeTransactionID = lab.TransactionID AND d.ItemID = lab.ItemID
                ORDER BY d.ItemDisplayOrder, d.FractionDisplayOrder
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)'), 1, 2, '')
        )
    FROM vPatientVisitLaboratory lab
    INNER JOIN #VisitHeader vh ON vh.VisitID = lab.VisitID
    LEFT JOIN vLaboratoryResultDt dt ON dt.ChargeTransactionID = lab.TransactionID AND dt.ItemID = lab.ItemID
    WHERE lab.IsDeleted = 0
    GROUP BY lab.MRN, lab.VisitID, lab.TransactionID, lab.TransactionDate, lab.TransactionTime,
             lab.ParamedicName, lab.ItemName1, lab.ItemID;

    -- 2f. Imaging / Radiologi
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
    SELECT
        img.MRN, img.VisitID, 'Imaging',
        CONVERT(VARCHAR(50), img.TransactionID),
        CONVERT(VARCHAR(20), img.TransactionDate, 23),
        img.TransactionTime,
        img.ParamedicName,
        CONCAT(
            img.ItemName1, N': ',
            STUFF((
                SELECT CONCAT(N'; ', d.TestResult1)
                FROM vImagingResultDt d
                WHERE d.ID IN (SELECT ID FROM ImagingResultHd WHERE ChargeTransactionID = img.TransactionID)
                  AND d.ItemID = img.ItemID
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)'), 1, 2, '')
        )
    FROM vPatientVisitImaging img
    INNER JOIN #VisitHeader vh ON vh.VisitID = img.VisitID
    WHERE img.IsDeleted = 0;

    -- 2g. Medication
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
    SELECT
        vh.MRN, rx.VisitID, 'Medication',
        CONVERT(VARCHAR(50), rx.PrescriptionOrderDetailID),
        NULL, NULL, NULL,
        CASE WHEN rx.IsCompound = 1 THEN
            CONCAT(N'Racikan: ', rx.CompoundDrugname, N' -> ', rx.MedicationLine)
        ELSE
            CONCAT(
                rx.DrugName, N' ', CONVERT(NVARCHAR(30), rx.Dose), N' ', ISNULL(rx.DoseUnit, N''),
                N', ', ISNULL(rx.DosingFrequency, N''),
                N', Rute: ', ISNULL(rx.Route, N''),
                N', Jumlah: ', CONVERT(NVARCHAR(30), rx.NumberOfDosageInString), N' ', ISNULL(rx.DosingUnit, N'')
            )
        END
    FROM vPatientVisitPrescription rx
    INNER JOIN #VisitHeader vh ON vh.VisitID = rx.VisitID;

    -- 2h. Physician & Nursing Notes
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
    SELECT
        vh.MRN, n.VisitID,
        CASE WHEN n.GCParamedicMasterType = 'X019^001' THEN 'PhysicianNote' ELSE 'NursingNote' END,
        CONVERT(VARCHAR(50), n.ID),
        CONVERT(VARCHAR(20), n.NoteDate, 23),
        n.NoteTime,
        n.ParamedicName,
        n.NoteText
    FROM vPatientVisitNote n
    INNER JOIN #VisitHeader vh ON vh.VisitID = n.VisitID
    WHERE n.IsDeleted = 0
      AND n.GCNoteType IS NULL
      AND n.NoteText IS NOT NULL AND n.NoteText <> N'';
    -- NOTE: 'PHYSICIAN_CODE' belum di-resolve -- semua note masih jatuh ke 'NursingNote'.

    -- 2i. Procedure / Tindakan
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
    SELECT
        pp.MRN, pp.VisitID, 'Procedure',
        CONVERT(VARCHAR(50), pp.ID),
        CONVERT(VARCHAR(20), pp.ProcedureDate, 23),
        pp.ProcedureTime,
        pp.ParamedicName,
        CONCAT(ISNULL(pp.ProcedureName, N''), N': ', ISNULL(pp.ProcedureText, N''))
    FROM vPatientProcedure pp
    INNER JOIN #VisitHeader vh ON vh.VisitID = pp.VisitID
    WHERE pp.IsDeleted = 0;

    -- 2j. Discharge
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
    SELECT
        vh.MRN, v5.VisitID, 'Discharge',
        CONVERT(VARCHAR(50), v5.VisitID),
        CONVERT(VARCHAR(20), v5.DischargeDate, 23),
        v5.DischargeTime,
        v5.PhysicianDischargedByName,
        CONCAT(
            N'Kondisi Keluar: ', ISNULL(v5.DischargeCondition, N''),
            N' | Cara Keluar: ', ISNULL(v5.DischargeMethod, N''),
            CASE WHEN v5.DischargeRemarks IS NOT NULL AND v5.DischargeRemarks <> N''
                 THEN CONCAT(N' | Keterangan: ', v5.DischargeRemarks) ELSE N'' END,
            CASE WHEN v5.DateOfDeath IS NOT NULL
                 THEN CONCAT(N' | Meninggal: ', CONVERT(VARCHAR(20), v5.DateOfDeath, 23), ' ', ISNULL(v5.TimeOfDeath,'')) ELSE N'' END
        )
    FROM vConsultVisit5 v5
    INNER JOIN #VisitHeader vh ON vh.VisitID = v5.VisitID
    WHERE v5.DischargeDate IS NOT NULL;

    -- 2k. Follow-up appointment
    INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
    SELECT
        vh.MRN, ap.FromVisitID, 'FollowUp',
        CONVERT(VARCHAR(50), ap.AppointmentID),
        CONVERT(VARCHAR(20), ap.StartDate, 23),
        CONVERT(VARCHAR(20), ap.StartTime, 8),
        ap.ParamedicName,
        CONCAT(N'Kontrol berikutnya: ', ap.VisitTypeName, N' dengan ', ap.ParamedicName,
               CASE WHEN ap.Notes IS NOT NULL AND ap.Notes <> N'' THEN CONCAT(N' - ', ap.Notes) ELSE N'' END)
    FROM vAppointment ap
    INNER JOIN #VisitHeader vh ON vh.VisitID = ap.FromVisitID
    WHERE ap.GCAppointmentStatus NOT IN ('0278^004','0278^001');
    -- NOTE: 'DELETED_CODE'/'CANCELLED_CODE' belum di-resolve -- filter ini efektif no-op,
    -- follow-up yang deleted/cancelled masih IKUT ke hasil. Perbaiki sebelum production.

    /* Bersihkan section kosong / '-' seperti di query asli */
    DELETE FROM #EhrSection
    WHERE SectionText IS NULL OR LTRIM(RTRIM(SectionText)) IN (N'', N'-');

    /* =================================================================================
       3) OUTPUT: 1 JSON bertingkat (Visits[].Sections[])
       ================================================================================= */
    SELECT
        vh.VisitID, vh.RegistrationID, vh.RegistrationNo, vh.MRN, vh.PatientName,
        vh.DateOfBirth, vh.Gender, vh.VisitDate, vh.VisitTime, vh.DepartmentID,
        vh.ServiceUnitName, vh.AttendingPhysicianName, vh.ClassName, vh.GCVisitStatus,
        vh.GCCaseType, vh.CaseTypeText, vh.VisitReason, vh.HospitalizationIndication,
        vh.DPJPName, vh.DischargeDate, vh.DischargeTime, vh.GCDischargeCondition,
        vh.DischargeConditionText, vh.GCDischargeMethod, vh.DischargeMethodText,
        vh.DischargeRemarks, vh.DateOfDeath, vh.TimeOfDeath, vh.LOSInDay,
        vh.ReferrerName, vh.ReferralToName, vh.IsPreventiveCare, vh.IsCurativeCare,
        vh.IsRehabilitationCare, vh.IsPalliativeCare,
        JSON_QUERY((
            SELECT es.SectionType, es.SourceID, es.SectionDate, es.SectionTime,
                   es.AuthorName, es.DiagnosisType, es.IsAbnormal, es.SectionText
            FROM #EhrSection es
            WHERE es.VisitID = vh.VisitID
            ORDER BY es.SectionType, es.SectionDate, es.SectionTime
            FOR JSON PATH
        )) AS Sections
    INTO #VisitJson
    FROM #VisitHeader vh;

    SELECT (
        SELECT
            vj.VisitID,
            vj.RegistrationID,
            vj.RegistrationNo,
            vj.MRN,
            vj.PatientName,
            vj.DateOfBirth,
            vj.Gender,
            vj.VisitDate,
            vj.VisitTime,
            vj.DepartmentID,
            vj.ServiceUnitName,
            vj.AttendingPhysicianName,
            vj.ClassName,
            vj.GCVisitStatus,
            vj.GCCaseType,
            vj.CaseTypeText,
            vj.VisitReason,
            vj.HospitalizationIndication,
            vj.DPJPName,
            vj.DischargeDate,
            vj.DischargeTime,
            vj.GCDischargeCondition,
            vj.DischargeConditionText,
            vj.GCDischargeMethod,
            vj.DischargeMethodText,
            vj.DischargeRemarks,
            vj.DateOfDeath,
            vj.TimeOfDeath,
            vj.LOSInDay,
            vj.ReferrerName,
            vj.ReferralToName,
            vj.IsPreventiveCare,
            vj.IsCurativeCare,
            vj.IsRehabilitationCare,
            vj.IsPalliativeCare,
            JSON_QUERY(vj.Sections) AS Sections
        FROM #VisitJson vj
        ORDER BY vj.MRN, vj.VisitDate DESC
        FOR JSON PATH, ROOT('Visits')
    ) AS JsonResult;

    DROP TABLE #VisitHeaderRaw;
    DROP TABLE #VisitHeader;
    DROP TABLE #EhrSection;
    DROP TABLE #VisitJson;
END
GO

/* =====================================================================================
   CONTOH PEMANGGILAN (dari MCP tool)
   =====================================================================================
   -- 1. By MRN, semua riwayat
   EXEC dbo.usp_GetPatientHistoryForRAG @MRN = '7263';

   -- 2. By nama (partial match), 6 bulan terakhir
   EXEC dbo.usp_GetPatientHistoryForRAG
        @PatientName   = 'Budi Santoso',
        @VisitDateFrom = '2026-03-01';

   -- 3. By MRN, 3 kunjungan terakhir saja
   EXEC dbo.usp_GetPatientHistoryForRAG @MRN = '7263', @LastNVisits = 3;

   -- 4. Tanpa MRN & tanpa nama -> akan RAISERROR, tidak akan jalan
   EXEC dbo.usp_GetPatientHistoryForRAG @VisitDateFrom = '2026-01-01';
   ===================================================================================== */