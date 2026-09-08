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
  
CREATE   PROCEDURE [dbo].[GetPatientHistoryMCP]  
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

-- =========================================================
-- 0. VISIT ID LIST -- filter di TABEL DASAR dulu (sargable, murah)
--    Ini menggantikan pola TOP(@limit)/@last_visit_id yang lama.
--    !!! SESUAIKAN nama tabel/kolom di bawah dengan skema Anda !!!
--    Asumsi: ConsultVisit punya MRN, RegistrationNo, VisitDate,
--    VisitTime, GCVisitStatus. Untuk PatientName, diasumsikan perlu
--    join ke Registration (ganti kalau ternyata sudah ada di ConsultVisit).
-- =========================================================
IF OBJECT_ID('tempdb..#VisitIDList') IS NOT NULL DROP TABLE #VisitIDList;

-- Dibuat eksplisit SEKALI di luar IF/ELSE. Kalau pakai SELECT...INTO di
-- kedua branch, SQL Server error 2714 ("There is already an object named
-- '#VisitIDList'...") karena struktur tabel di-resolve saat parsing,
-- bukan saat runtime -- walau cuma satu branch yang benar-benar jalan.
CREATE TABLE #VisitIDList
(
    VisitID INT NOT NULL,
    rn      INT NOT NULL
);

-- Catatan skema (dari definisi vConsultVisit4):
--   * MRN ada di tabel Registration, join-nya: Registration.RegistrationID = ConsultVisit.RegistrationID
--   * PatientName TIDAK ada sebagai kolom asli. View menghitungnya:
--       - kalau Registration.MRN diisi -> nama diambil dari Patient.FullName (join by MRN)
--       - kalau tidak (pasien "guest")  -> nama diambil dari Guest.FullName (join by GuestID)
--     Jadi pencarian PatientName perlu cek ke Patient DAN Guest.

IF (@MRN IS NOT NULL AND LTRIM(RTRIM(@MRN)) <> '')
BEGIN
    INSERT INTO #VisitIDList (VisitID, rn)
    SELECT 
        c.VisitID,
        ROW_NUMBER() OVER (PARTITION BY r.MRN ORDER BY c.VisitDate DESC, c.VisitTime DESC) AS rn
    FROM ConsultVisit c
    INNER JOIN Registration r ON r.RegistrationID = c.RegistrationID
    WHERE r.MRN = @MRN
      AND c.GCVisitStatus <> 'X020^006'
      AND (@VisitDateFrom IS NULL OR c.VisitDate >= @VisitDateFrom)
      AND (@VisitDateTo   IS NULL OR c.VisitDate <= @VisitDateTo);
END
ELSE
BEGIN
    INSERT INTO #VisitIDList (VisitID, rn)
    SELECT 
        c.VisitID,
        -- Partition pakai MRN kalau ada, kalau guest (MRN NULL) pakai GuestID
        -- supaya LastNVisits tetap dihitung per-identitas pasien yang benar.
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(CAST(r.MRN AS VARCHAR(50)), CONCAT('GUEST-', r.GuestID))
            ORDER BY c.VisitDate DESC, c.VisitTime DESC
        ) AS rn
    FROM ConsultVisit c
    INNER JOIN Registration r ON r.RegistrationID = c.RegistrationID
    LEFT JOIN Patient p ON p.MRN = r.MRN
    LEFT JOIN Guest g  ON g.GuestID = r.GuestID
    WHERE (
            (r.MRN IS NOT NULL AND p.FullName LIKE '%' + @PatientName + '%')
            OR
            (r.MRN IS NULL AND g.FullName LIKE '%' + @PatientName + '%')
          )
      AND c.GCVisitStatus <> 'X020^006'
      AND (@VisitDateFrom IS NULL OR c.VisitDate >= @VisitDateFrom)
      AND (@VisitDateTo   IS NULL OR c.VisitDate <= @VisitDateTo);
END

-- Terapkan LastNVisits per MRN (kalau diisi)
DELETE FROM #VisitIDList WHERE @LastNVisits IS NOT NULL AND rn > @LastNVisits;

CREATE CLUSTERED INDEX IX_TmpVisitIDList ON #VisitIDList (VisitID);

IF NOT EXISTS (SELECT 1 FROM #VisitIDList)
BEGIN
    SELECT CAST(N'[]' AS NVARCHAR(MAX)) AS JsonResult;
    RETURN;
END

-- =========================================================
-- 1. BUILD VISIT HEADER -- view di-JOIN hanya untuk VisitID yang lolos filter
-- =========================================================
IF OBJECT_ID('tempdb..#VisitHeader') IS NOT NULL DROP TABLE #VisitHeader;
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
WHERE v4.VisitID IN (SELECT VisitID FROM #VisitIDList);
-- Catatan: GCVisitStatus & rentang tanggal tidak perlu difilter ulang di sini
-- karena #VisitIDList sudah memuat VisitID yang lolos filter tersebut.

-- =========================================================
-- 2. BUILD EHR SECTIONS  (tidak berubah dari versi asli)
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

INSERT INTO #EhrSection (MRN, VisitID, SectionType, SourceID, SectionDate, SectionTime, AuthorName, SectionText)
SELECT img.MRN, img.VisitID, 'Imaging', CONVERT(VARCHAR(50), img.TransactionID), CONVERT(VARCHAR(20), img.TransactionDate, 23), img.TransactionTime, img.ParamedicName,
       CONCAT(img.ItemName1, N': ', STUFF((SELECT CONCAT(N'; ', d.TestResult1) FROM vImagingResultDt d WHERE d.ID IN (SELECT ID FROM ImagingResultHd WHERE ChargeTransactionID = img.TransactionID) AND d.ItemID = img.ItemID FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, ''))
FROM vPatientVisitImaging img INNER JOIN #VisitHeader vh ON vh.VisitID = img.VisitID WHERE img.IsDeleted = 0;

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
INNER JOIN #VisitHeader vh ON vh.VisitID = pp.VisitID
WHERE pp.IsDeleted = 0;
-- Catatan: pada query asli baris ini di-hardcode "WHERE pp.VisitID = 552"
-- (kelihatannya sisa debugging). Saya kembalikan jadi generik: JOIN ke
-- #VisitHeader + IsDeleted = 0, konsisten dengan section lain. Kalau
-- ternyata hardcode itu memang disengaja, kabari saya.

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

-- =========================================================
-- 3. INJEKSI DOMAIN TAMBAHAN  (tidak berubah dari versi asli)
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
-- 4. HASIL (RESULT SET) DALAM BENTUK JSON BERSARANG  (tidak berubah dari versi asli)
-- =========================================================
SELECT (
    SELECT
        vh.VisitID,
        vh.RegistrationID,
        vh.RegistrationNo,
        vh.MRN,
        vh.PatientName,
        vh.DateOfBirth,
        vh.Gender,
        vh.VisitDate,
        vh.VisitTime,
        vh.DepartmentID,
        vh.ServiceUnitName,
        vh.AttendingPhysicianName,
        vh.ClassName,
        vh.GCVisitStatus,
        vh.GCCaseType,
        vh.CaseTypeText,
        vh.VisitReason,
        vh.HospitalizationIndication,
        vh.DPJPName,
        vh.DischargeDate,
        vh.DischargeTime,
        vh.GCDischargeCondition,
        vh.DischargeConditionText,
        vh.GCDischargeMethod,
        vh.DischargeMethodText,
        vh.DischargeRemarks,
        vh.DateOfDeath,
        vh.TimeOfDeath,
        vh.LOSInDay,
        vh.ReferrerName,
        vh.ReferralToName,
        vh.IsPreventiveCare,
        vh.IsCurativeCare,
        vh.IsRehabilitationCare,
        vh.IsPalliativeCare,

        CONVERT(
            VARCHAR(19),
            DATEADD(
                SECOND,
                DATEDIFF(
                    SECOND,
                    0,
                    TRY_CAST(vh.VisitTime AS TIME)
                ),
                CAST(vh.VisitDate AS DATETIME)
            ),
            126
        ) AS registration_date,

        vh.IsBPJS AS is_bpjs,

        JSON_QUERY((
            SELECT
                es.SectionType,
                es.SourceID,
                es.SectionDate,
                es.SectionTime,
                es.AuthorName,
                es.DiagnosisType,
                es.IsAbnormal,
                es.SectionText
            FROM #EhrSection es
            WHERE es.VisitID = vh.VisitID
              AND es.SectionText IS NOT NULL
              AND LTRIM(RTRIM(es.SectionText)) NOT IN (N'', N'-')
            ORDER BY
                es.SectionType,
                es.SectionDate,
                es.SectionTime
            FOR JSON PATH
        )) AS sections

    FROM #VisitHeader vh

    -- samakan dengan ordering lama
    ORDER BY
        vh.MRN,
        vh.VisitDate DESC

    FOR JSON PATH,
        ROOT('Visits')
) AS JsonResult;

-- Bersihkan Temp Table
DROP TABLE #VisitIDList;
DROP TABLE #VisitHeader;
DROP TABLE #EhrSection;

END  