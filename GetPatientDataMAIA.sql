

CREATE   PROCEDURE [dbo].[GetPatientDataMAIA]  
(  
    @limit            INT  = NULL,   -- MRN exact match  
    @last_visit_id    INT  = NULL
)  
AS  
BEGIN

SET NOCOUNT ON;

-- =========================================================
-- 1. BUILD VISIT HEADER
-- =========================================================
IF OBJECT_ID('tempdb..#VisitHeader') IS NOT NULL DROP TABLE #VisitHeader;
SELECT 
    v4.VisitID, v4.RegistrationID, v4.RegistrationNo, v4.MRN,
    v4.DateOfBirth, v4.Gender, v4.VisitDate, v4.VisitTime,
    v4.DepartmentID, v4.ServiceUnitName,
    v4.ParamedicName AS AttendingPhysicianName,
    v4.ClassName, v4.GCVisitStatus, v4.CaseType AS CaseTypeText,
    v5.PhysicianName AS DPJPName, v5.DischargeDate, v5.DischargeTime,
    v5.DischargeCondition AS DischargeConditionText,
    v5.DischargeMethod AS DischargeMethodText,
    v5.DateOfDeath, v5.TimeOfDeath, v5.LOSInDay,
    v4.IsPreventiveCare, v4.IsCurativeCare, v4.IsRehabilitationCare, v4.IsPalliativeCare,
    R.GCTriage AS TriageLevel,
    R.IsPregnant AS IsPregnantPatient,
    R.AgeInYear,
    (
        SELECT MAX(CASE WHEN BusinessPartnerName LIKE '%BPJS KESEHATAN%' AND CustomerType = 'BPJS' THEN 1 ELSE 0 END)
        FROM vConsultVisit VC
        WHERE VC.RegistrationNo = v4.RegistrationNo
    ) AS IsBPJS
INTO #VisitHeader
FROM vConsultVisit4 v4
LEFT JOIN vConsultVisit5 v5 ON v5.VisitID = v4.VisitID
LEFT JOIN Registration R ON R.RegistrationNo = v4.RegistrationNo
WHERE v4.VisitID IN (
SELECT TOP (@limit) VisitID 
FROM ConsultVisit 
WHERE VisitID > ISNULL(@last_visit_id,0) 
ORDER BY VisitID ASC) AND v4.GCVisitStatus <> 'X020^006';

-- =========================================================
-- 2. BUILD EHR SECTIONS
-- =========================================================
IF OBJECT_ID('tempdb..#EhrSection') IS NOT NULL DROP TABLE #EhrSection;
CREATE TABLE #EhrSection (
    MRN NVARCHAR(50),
    VisitID BIGINT,
    SectionType VARCHAR(50),
    SourceID VARCHAR(50),
    SectionDate VARCHAR(20),
    SectionTime DATETIME,
    AuthorName NVARCHAR(100),
    IsAbnormal BIT DEFAULT 0,
    DiagnosisType NVARCHAR(50),
    SectionText NVARCHAR(MAX)
);

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

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
SELECT vh.MRN, hd.VisitID, 'ReviewOfSystem', CONVERT(VARCHAR(50), hd.ID), CONVERT(VARCHAR(20), hd.ObservationDate, 23), hd.ObservationTime, hd.ParamedicName,
       STUFF((SELECT CONCAT(N'; ', dt.ROSystem, N': ', CASE WHEN dt.IsNotExamined = 1 THEN 'Not Examined' WHEN dt.IsNormal = 1 THEN 'Normal' WHEN dt.IsOther = 1 THEN 'Other' ELSE 'Abnormal' END, CASE WHEN ISNULL(dt.Remarks, '') <> '' THEN CONCAT(' : ', dt.Remarks) ELSE '' END) FROM vReviewOfSystemDt dt WHERE dt.ID = hd.ID AND dt.IsDeleted = 0 FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '')
FROM vReviewOfSystemHd hd INNER JOIN #VisitHeader vh ON vh.VisitID = hd.VisitID WHERE hd.IsDeleted = 0;

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
SELECT vh.MRN, hd.VisitID, 'VitalSign', CONVERT(VARCHAR(50), hd.ID), CONVERT(VARCHAR(20), hd.ObservationDate, 23), hd.ObservationTime, hd.ParamedicName,
       STUFF((SELECT CONCAT(N'; ', dt.VitalSignLabel, N': ', CASE WHEN ISNULL(dt.VitalSignValue, '') = '' THEN '-' WHEN dt.GCValueType = 'X103^001' THEN CONCAT(dt.VitalSignValue, ' ', dt.ValueUnit) ELSE dt.VitalSignValue END) FROM vVitalSignDt dt WHERE dt.ID = hd.ID AND dt.IsDeleted = 0 FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '')
FROM vVitalSignHd hd INNER JOIN #VisitHeader vh ON vh.VisitID = hd.VisitID WHERE hd.IsDeleted = 0;

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, DiagnosisType, SectionText)
SELECT pd.MRN, pd.VisitID, 'Diagnosis', CONVERT(VARCHAR(50), pd.ID), CONVERT(VARCHAR(20), pd.DifferentialDate, 23), pd.DifferentialTime, pd.ParamedicName, pd.DiagnoseType,
       CONCAT(N'Diagnosis (', ISNULL(pd.DiagnoseType, N'-'), N'): ', ISNULL(pd.DiagnosisText, N''), CASE WHEN pd.DiagnoseName IS NOT NULL THEN CONCAT(N' [', pd.DiagnoseName, N']') ELSE N'' END)
FROM vPatientDiagnosis pd INNER JOIN #VisitHeader vh ON vh.VisitID = pd.VisitID WHERE pd.IsDeleted = 0;

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, IsAbnormal, SectionText)
SELECT lab.MRN, lab.VisitID, 'Laboratory', CONVERT(VARCHAR(50), lab.TransactionID), CONVERT(VARCHAR(20), lab.TransactionDate, 23), lab.TransactionTime, lab.ParamedicName, 0,
       CONCAT(lab.ItemName1, N': ', STUFF((SELECT CONCAT(N'; ', d.FractionName1, N' = ', ISNULL(d.TextValue, CONVERT(NVARCHAR(50), d.MetricResultValue)), ' ', ISNULL(d.MetricUnit, N''), CASE WHEN d.ResultFlag IS NOT NULL AND d.ResultFlag <> 'N' THEN CONCAT(N' (', d.ResultFlag, N')') ELSE N'' END) FROM vLaboratoryResultDt d WHERE d.ChargeTransactionID = lab.TransactionID AND d.ItemID = lab.ItemID ORDER BY d.ItemDisplayOrder FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, ''))
FROM vPatientVisitLaboratory lab INNER JOIN #VisitHeader vh ON vh.VisitID = lab.VisitID WHERE lab.IsDeleted = 0 GROUP BY lab.MRN, lab.VisitID, lab.TransactionID, lab.TransactionDate, lab.TransactionTime, lab.ParamedicName, lab.ItemName1, lab.ItemID;

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
SELECT img.MRN, img.VisitID, 'Imaging', CONVERT(VARCHAR(50), img.TransactionID), CONVERT(VARCHAR(20), img.TransactionDate, 23), img.TransactionTime, img.ParamedicName,
       CONCAT(img.ItemName1, N': ', STUFF((SELECT CONCAT(N'; ', d.TestResult1) FROM vImagingResultDt d WHERE d.ID IN (SELECT ID FROM ImagingResultHd WHERE ChargeTransactionID = img.TransactionID) AND d.ItemID = img.ItemID FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, ''))
FROM vPatientVisitImaging img INNER JOIN #VisitHeader vh ON vh.VisitID = img.VisitID WHERE img.IsDeleted = 0;

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionText)
SELECT vh.MRN, rx.VisitID, 'Medication', CONVERT(VARCHAR(50), rx.PrescriptionOrderDetailID),
       CASE WHEN rx.IsCompound = 1 THEN CONCAT(N'Racikan: ', rx.CompoundDrugname, N' -> ', rx.MedicationLine) ELSE CONCAT(rx.DrugName, N' ', CONVERT(NVARCHAR(30), rx.Dose), N' ', ISNULL(rx.DoseUnit, N''), N', ', ISNULL(rx.DosingFrequency, N'')) END
FROM vPatientVisitPrescription rx INNER JOIN #VisitHeader vh ON vh.VisitID = rx.VisitID;

INSERT INTO #EhrSection (
    MRN,
    VisitID,
    SectionType,
    SourceID,
    SectionDate,
    SectionTime,
    AuthorName,
    SectionText
)
SELECT
    pp.MRN,
    pp.VisitID,
    'Procedure',
    CONVERT(VARCHAR(50), pp.ID),
    CONVERT(VARCHAR(20), pp.ProcedureDate, 23),

    CASE
        WHEN ISDATE(REPLACE(pp.ProcedureTime, '.', ':')) = 1
        THEN CONVERT(DATETIME, REPLACE(pp.ProcedureTime, '.', ':'))
        ELSE NULL
    END,

    pp.ParamedicName,
    CONCAT(
        ISNULL(pp.ProcedureName, N''),
        N': ',
        ISNULL(pp.ProcedureText, N'')
    )
FROM vPatientProcedure pp
WHERE pp.VisitID = 552
  AND pp.IsDeleted = 0;

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


INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
SELECT vh.MRN, v5.VisitID, 'Discharge', CONVERT(VARCHAR(50), v5.VisitID), CONVERT(VARCHAR(20), v5.DischargeDate, 23), v5.DischargeTime, v5.PhysicianDischargedByName, CONCAT(N'Kondisi Keluar: ', ISNULL(v5.DischargeCondition, N''))
FROM vConsultVisit5 v5 INNER JOIN #VisitHeader vh ON vh.VisitID = v5.VisitID WHERE v5.DischargeDate IS NOT NULL;

-- =========================================================
-- 3. INJEKSI DOMAIN TAMBAHAN
-- =========================================================
INSERT INTO #EhrSection (MRN, VisitID, SectionType, SectionText)
SELECT vh.MRN, vh.VisitID, 'Allergy', CONCAT('Alergi: ', STUFF((SELECT '; ' + CAST(Allergen AS NVARCHAR(MAX)) FROM PatientAllergy WHERE MRN = vh.MRN AND (IsDeleted = 0 OR IsDeleted IS NULL) FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, ''))
FROM #VisitHeader vh WHERE EXISTS (SELECT 1 FROM PatientAllergy WHERE MRN = vh.MRN AND (IsDeleted = 0 OR IsDeleted IS NULL));

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
SELECT vh.MRN, S.VisitID, 'Surgery', CONVERT(VARCHAR(50), S.PatientSurgeryID), CONVERT(VARCHAR(20), S.ReportDate, 23), S.ReportTime, S.ParamedicName, 
       CONCAT(N'Tindakan Operasi: ', ISNULL(S.PreOperativeDiagnosisText, '-'), N' -> ', ISNULL(S.PostOperativeDiagnosisText, '-'), N'. Bius: ', ISNULL(S.AnesthesiaType, '-'), N'. Perdarahan: ', ISNULL(CAST(S.Hemorrhage AS VARCHAR(50)), '-'), N'cc. Laporan: ', ISNULL(S.ReferralSummary, '-'))
FROM vPatientSurgery S INNER JOIN #VisitHeader vh ON vh.VisitID = S.VisitID WHERE S.IsDeleted = 0;

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
SELECT vh.MRN, RT.VisitID, 'Radiotherapy', CONVERT(VARCHAR(50), RT.ProgramID), CONVERT(VARCHAR(20), RT.ProgramDate, 23), RT.ProgramTime, NULL, 
       CONCAT(N'Radioterapi: Stadium ', ISNULL(CAST(RT.CancerStaging AS VARCHAR(50)), '-'), N' | Total Dosis: ', ISNULL(CAST(RT.TotalDosage1 AS VARCHAR(50)), '-'))
FROM vRadiotheraphyProgram RT INNER JOIN #VisitHeader vh ON vh.VisitID = RT.VisitID WHERE RT.IsDeleted = 0;

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
SELECT vh.MRN, HD.VisitID, 'Hemodialysis', CONVERT(VARCHAR(50), HD.ID), CONVERT(VARCHAR(20), HD.AssessmentDate, 23), HD.AssessmentTime, HD.ParamedicName, 
       CONCAT(N'Hemodialisis: Metode ', ISNULL(HD.HDMethod, '-'), N' selama ', ISNULL(CAST(HD.HDDuration AS VARCHAR(50)), '-'), N' jam | Tarikan Cairan (UF): ', ISNULL(CAST(HD.TotalUF AS VARCHAR(50)), '-'))
FROM vPreHDAssessment HD INNER JOIN #VisitHeader vh ON vh.VisitID = HD.VisitID WHERE HD.IsDeleted = 0;

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
SELECT vh.MRN, GZ.VisitID, 'Nutrition', CONVERT(VARCHAR(50), GZ.NutritionOrderHdID), CONVERT(VARCHAR(20), GZ.NutritionOrderDate, 23), GZ.NutritionOrderTime, GZ.ParamedicName, 
       CONCAT(N'Instruksi Gizi: Kalori ', ISNULL(CAST(GZ.NumberOfCalories AS NVARCHAR(50)), '-'), N' kkal, Protein ', ISNULL(CAST(GZ.NumberOfProtein AS NVARCHAR(50)), '-'), N' g | Menu: ', STUFF((SELECT ', ' + ISNULL(DT.MealTime, 'Makan') + ': ' + ISNULL(DT.MealPlanName, '-') FROM vNutritionOrderDt DT WHERE DT.NutritionOrderHdID = GZ.NutritionOrderHdID FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, ''))
FROM vNutritionOrderHd GZ INNER JOIN #VisitHeader vh ON vh.VisitID = GZ.VisitID WHERE GZ.VoidReason IS NULL;

-- =========================================================
-- 4. HASIL (RESULT SET) DALAM BENTUK JSON BERSARANG
-- =========================================================
-- Satu baris JSON per visit, dengan "sections" sebagai array di dalamnya.
-- Catatan:
--   * JSON_QUERY() dipakai supaya hasil subquery FOR JSON PATH tidak
--     di-escape jadi string, melainkan disisipkan sebagai JSON asli.
--   * registration_date di bawah menggabungkan VisitDate + VisitTime.
--     Sesuaikan tipe data VisitTime (TIME/VARCHAR) dengan skema Anda;
--     kalau VisitTime sudah berupa DATETIME/TIME, blok DATEADD ini aman.
--   * Kalau tidak butuh nested JSON (misal backend yang assemble),
--     tinggal balikin ke 2 result set seperti versi asli.

SELECT(
SELECT
    vh.VisitID                         AS [visit_id],
    vh.RegistrationNo                  AS [registration_no],
    vh.MRN                              AS [mrn],
    vh.AttendingPhysicianName          AS [paramedic_name],
    CONVERT(
        VARCHAR(19),
        DATEADD(
            SECOND,
            DATEDIFF(SECOND, 0, TRY_CAST(vh.VisitTime AS TIME)),
            CAST(vh.VisitDate AS DATETIME)
        ),
        126
    )                                    AS [registration_date],
    vh.IsBPJS                           AS [is_bpjs],
    JSON_QUERY((
        SELECT
            es.SectionType   AS [SectionType],
            es.SectionDate   AS [SectionDate],
            es.AuthorName    AS [AuthorName],
            es.SectionText   AS [SectionText]
        FROM #EhrSection es
        WHERE es.VisitID = vh.VisitID
          AND es.SectionText IS NOT NULL
          AND LTRIM(RTRIM(es.SectionText)) NOT IN (N'', N'-')
        ORDER BY es.SectionType
        FOR JSON PATH
    ))                                   AS [sections]
FROM #VisitHeader vh
ORDER BY vh.VisitID
FOR JSON PATH) AS JsonResult;

-- Bersihkan Temp Table
DROP TABLE #VisitHeader;
DROP TABLE #EhrSection;

END 