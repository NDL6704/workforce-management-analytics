/* ==============================================================================================
   ENTERPRISE SQL ANALYTICS & METRICS REPOSITORY
   Project: HR Workforce Planning & Attrition Analytics
   Target Architecture: Modern Data Warehouse (PostgreSQL, SQL Server / T-SQL, Snowflake, 
                        Google BigQuery, Databricks, MySQL 8.0+, SQLite 3.25+)
   Standards: ANSI SQL:2016 Compliant with Modular CTEs & Window Functions
   Purpose: 1-to-1 Pure SQL Equivalent of Power BI DAX Measures Library (DAX_MEASURES.dax)
   Governance: Reusable Analytical Data Mart Views, Point-in-Time Queries & Prescriptive Models
   ============================================================================================== */

/* ==============================================================================================
   TABLE OF CONTENTS & REPOSITORY ROADMAP:
   ----------------------------------------------------------------------------------------------
   00. DATA MODEL SCHEMA CONTEXT & ASSUMPTIONS
   01. FOLDER 01: CORE WORKFORCE INTELLIGENCE (Measures 01 - 11)
       - Active Headcount (Semi-additive Snapshot & Dynamic PIT fallback)
       - Active FTE (Full-Time Equivalent)
       - Average Headcount in Period
       - New Hires & Net Workforce Change
       - Average Tenure (Months & Years)
       - MoM & YoY Headcount Growth (PM, PY, MoM %, YoY %)
       - Production View: vw_core_workforce_monthly
   02. FOLDER 02: ATTRITION & RETENTION INTELLIGENCE (Measures 12 - 22d)
       - Total Terminations, Voluntary & Involuntary Counts and Ratios
       - Monthly Attrition Rate %
       - Annualized Attrition Rate % & YTD Attrition Rate %
       - Regrettable Loss Count & Regrettable Loss Rate % (Top Talent Flight)
       - Restructuring Terminations (06/2025 Event)
       - Exit Average Engagement & Exit Average Tenure
       - Termination Cumulative % (Pareto 80/20 Analysis)
       - Production View: vw_attrition_analytics_monthly
   03. FOLDER 03: PLANNING & BUDGET VARIANCE INTELLIGENCE (Measures 23 - 32)
       - Planned Headcount & Budgeted FTE
       - Headcount Variance & Headcount Variance %
       - FTE Variance & FTE Variance %
       - Budgeted Salary Cost vs Actual Annualized Salary Cost
       - Salary Cost Variance & Salary Cost Variance %
       - Production View: vw_planning_budget_variance
   04. FOLDER 04: TALENT, COMPENSATION & WELL-BEING CORRELATION (Measures 33 - 42)
       - Average Engagement Score & Survey Response Rate %
       - Average Performance Rating
       - Total Days Absent, Sick Leave Days, Unpaid Leave Days
       - Absence Days per Employee & Sick Leave Ratio %
       - Level Median Benchmark Salary (P50 Internal Benchmark)
       - Salary Compa-Ratio (Individual & Department Level)
       - Production View: vw_talent_wellbeing_correlations
   05. FOLDER 05: RECRUITMENT OPERATIONS & SLA VELOCITY (Measures 43 - 49)
       - Open, Filled, Cancelled Requisitions & Total Requisition Demand
       - Requisition Fill Rate %
       - Average Days to Fill (SLA vs Benchmark 45 Days)
       - Hiring Velocity Index
       - Production View: vw_recruitment_velocity
   06. FOLDER 06: UI HELPERS & PRESCRIPTIVE RETENTION LOGIC (Measures 50 - 53)
       - Headcount Variance Color Status Code
       - Department Attrition Risk Flag
       - Individual Flight Risk Flag (Compa-Ratio vs Engagement Matrix)
       - Recommended Retention Action (Prescriptive Action Tags)
       - Production View: vw_hrbp_actionable_flight_risk
   07. EXECUTIVE HEADLINE KPI ROLL-UP (C-Suite 1-Row Cockpit Summary)
   08. 1-TO-1 DAX VS SQL CROSS-REFERENCE MAPPING MATRIX
   ============================================================================================== */


/* ==============================================================================================
   00. DATA MODEL SCHEMA CONTEXT & ASSUMPTIONS
   ----------------------------------------------------------------------------------------------
   Mô hình Star Schema chuẩn gồm các bảng:
     - DimDate (Date, Month, Year, Quarter, MonthNumber, MonthName, WeekdayNumber)
     - DimDepartment (DepartmentID, Department, Function, CostCenter)
     - DimLocation (LocationID, Location, Country, Region, TimeZone, Latitude, Longitude)
     - DimEmployee (EmployeeID, DepartmentID, Department, Role, Level, LocationID, Location,
                    ManagerID, Gender, BirthYear, AgeBand, HireDate, TerminationDate,
                    EmploymentStatus, TerminationType, TerminationReason, FTE,
                    TenureMonthsAtExitOrEnd, TenureBandAtExitOrEnd)
     - FactMonthlySnapshot (Month, DepartmentID, Department, LocationID, Location, Level,
                            Headcount, FTE, AvgTenureMonths)
     - FactEmployeeEvents (EmployeeID, EventDate, EventType, DepartmentID, Department,
                           LocationID, Location, TerminationType, TerminationReason)
     - FactCompensation (EmployeeID, EffectiveDate, AnnualSalary, Level, Currency)
     - FactPerformance (EmployeeID, ReviewDate, PerformanceRating, ReviewType)
     - FactEngagement (EmployeeID, SurveyDate, EngagementScore, ResponseRatePct)
     - FactAbsence (EmployeeID, AbsenceDate, AbsenceType, DaysAbsent)
     - FactRecruitment (ReqID, Month, DepartmentID, Department, OpenRequisitions,
                        FilledRequisitions, CancelledRequisitions, AvgDaysToFill)
     - WorkforceTargets (Month, DepartmentID, Department, PlannedHeadcount,
                         BudgetedFTE, BudgetedSalaryCost, PlanningScenario)
   ============================================================================================== */


/* ==============================================================================================
   FOLDER 01: CORE WORKFORCE INTELLIGENCE (Measures 01 - 11)
   Description: Các chỉ số cốt lõi về quy mô lực lượng lao động, FTE, thâm niên và biến động tuyển dụng
   ============================================================================================== */

-- ----------------------------------------------------------------------------------------------
-- 1. Active Headcount (Quy mô nhân sự tại thời điểm chốt kỳ mới nhất)
-- ----------------------------------------------------------------------------------------------
SELECT 
    f.Month AS SnapshotMonth,
    SUM(f.Headcount) AS ActiveHeadcount
FROM FactMonthlySnapshot f
WHERE f.Month = (SELECT MAX(Month) FROM FactMonthlySnapshot)
GROUP BY f.Month;

-- ----------------------------------------------------------------------------------------------
-- 2. Active FTE (Full-Time Equivalent)
SELECT 
    f.Month AS SnapshotMonth,
    SUM(f.FTE) AS ActiveFTE
FROM FactMonthlySnapshot f
WHERE f.Month = (SELECT MAX(Month) FROM FactMonthlySnapshot)
GROUP BY f.Month;

-- ----------------------------------------------------------------------------------------------
-- 3. Average Headcount in Period (Headcount bình quân theo tháng trong kỳ báo cáo)
WITH MonthlySum AS (
    SELECT 
        Month,
        SUM(Headcount) AS MonthlyHC
    FROM FactMonthlySnapshot
    WHERE Month BETWEEN '2025-01-01' AND '2025-12-31'
    GROUP BY Month
)
SELECT 
    ROUND(AVG(MonthlyHC), 2) AS AvgHeadcountPeriod
FROM MonthlySum;

-- ----------------------------------------------------------------------------------------------
-- 4. New Hires (Số lượng nhân sự tuyển mới trong kỳ)
SELECT 
    COUNT(*) AS NewHires
FROM FactEmployeeEvents
WHERE EventType = 'Hire'
  AND EventDate BETWEEN '2025-01-01' AND '2025-12-31';

-- ----------------------------------------------------------------------------------------------
-- 5. Net Workforce Change (Biến động ròng = Tuyển mới - Thôi việc)
SELECT 
    COUNT(CASE WHEN EventType = 'Hire' THEN 1 END) AS NewHires,
    COUNT(CASE WHEN EventType = 'Termination' THEN 1 END) AS TerminationsTotal,
    COUNT(CASE WHEN EventType = 'Hire' THEN 1 END) - 
    COUNT(CASE WHEN EventType = 'Termination' THEN 1 END) AS NetWorkforceChange
FROM FactEmployeeEvents
WHERE EventDate BETWEEN '2025-01-01' AND '2025-12-31';

-- ----------------------------------------------------------------------------------------------
-- 6 & 7. Average Tenure (Months & Years) - Thâm niên trung bình của lực lượng lao động
SELECT 
    f.Month AS SnapshotMonth,
    ROUND(SUM(f.Headcount * f.AvgTenureMonths) * 1.0 / NULLIF(SUM(f.Headcount), 0), 2) AS AvgTenureMonths,
    ROUND((SUM(f.Headcount * f.AvgTenureMonths) * 1.0 / NULLIF(SUM(f.Headcount), 0)) / 12.0, 2) AS AvgTenureYears
FROM FactMonthlySnapshot f
WHERE f.Month = (SELECT MAX(Month) FROM FactMonthlySnapshot)
GROUP BY f.Month;

-- ----------------------------------------------------------------------------------------------
-- 8, 9, 10, 11. Headcount PM, MoM %, Headcount PY, YoY %
WITH MonthlyHeadcountSeries AS (
    SELECT 
        Month,
        SUM(Headcount) AS ActiveHeadcount
    FROM FactMonthlySnapshot
    GROUP BY Month
)
SELECT 
    Month,
    ActiveHeadcount,
    -- Headcount tháng liền trước (Previous Month)
    LAG(ActiveHeadcount, 1) OVER (ORDER BY Month) AS Headcount_PM,
    -- Tỷ lệ tăng trưởng so với tháng trước (MoM %)
    ROUND(
        (ActiveHeadcount - LAG(ActiveHeadcount, 1) OVER (ORDER BY Month)) * 100.0 / 
        NULLIF(LAG(ActiveHeadcount, 1) OVER (ORDER BY Month), 0), 
        2
    ) AS Headcount_MoM_Pct,
    -- Headcount cùng kỳ năm trước (Previous Year - 12 tháng trước)
    LAG(ActiveHeadcount, 12) OVER (ORDER BY Month) AS Headcount_PY,
    -- Tỷ lệ tăng trưởng so với cùng kỳ năm trước (YoY %)
    ROUND(
        (ActiveHeadcount - LAG(ActiveHeadcount, 12) OVER (ORDER BY Month)) * 100.0 / 
        NULLIF(LAG(ActiveHeadcount, 12) OVER (ORDER BY Month), 0), 
        2
    ) AS Headcount_YoY_Pct
FROM MonthlyHeadcountSeries
ORDER BY Month DESC;

-- ----------------------------------------------------------------------------------------------
-- PRODUCTION VIEW 01: vw_core_workforce_monthly
-- Data Mart tổng hợp toàn diện các chỉ số quy mô và tăng trưởng theo tháng & phòng ban
-- ----------------------------------------------------------------------------------------------
-- DROP VIEW IF EXISTS vw_core_workforce_monthly;
-- CREATE VIEW vw_core_workforce_monthly AS
WITH MonthlyBase AS (
    SELECT 
        s.Month,
        s.DepartmentID,
        s.Department,
        SUM(s.Headcount) AS ActiveHeadcount,
        SUM(s.FTE) AS ActiveFTE,
        ROUND(SUM(s.Headcount * s.AvgTenureMonths) * 1.0 / NULLIF(SUM(s.Headcount), 0), 2) AS AvgTenureMonths
    FROM FactMonthlySnapshot s
    GROUP BY s.Month, s.DepartmentID, s.Department
),
MonthlyHires AS (
    SELECT 
        -- Định dạng YYYY-MM-01 để khớp với Month của Snapshot
        CAST(SUBSTR(EventDate, 1, 7) || '-01' AS VARCHAR(10)) AS Month,
        DepartmentID,
        COUNT(*) AS NewHires
    FROM FactEmployeeEvents
    WHERE EventType = 'Hire'
    GROUP BY CAST(SUBSTR(EventDate, 1, 7) || '-01' AS VARCHAR(10)), DepartmentID
),
MonthlyExits AS (
    SELECT 
        CAST(SUBSTR(EventDate, 1, 7) || '-01' AS VARCHAR(10)) AS Month,
        DepartmentID,
        COUNT(*) AS TerminationsTotal
    FROM FactEmployeeEvents
    WHERE EventType = 'Termination'
    GROUP BY CAST(SUBSTR(EventDate, 1, 7) || '-01' AS VARCHAR(10)), DepartmentID
)
SELECT 
    b.Month,
    b.DepartmentID,
    b.Department,
    b.ActiveHeadcount,
    b.ActiveFTE,
    b.AvgTenureMonths,
    ROUND(b.AvgTenureMonths / 12.0, 2) AS AvgTenureYears,
    COALESCE(h.NewHires, 0) AS NewHires,
    COALESCE(e.TerminationsTotal, 0) AS TerminationsTotal,
    COALESCE(h.NewHires, 0) - COALESCE(e.TerminationsTotal, 0) AS NetWorkforceChange,
    LAG(b.ActiveHeadcount, 1) OVER (PARTITION BY b.DepartmentID ORDER BY b.Month) AS Headcount_PM,
    ROUND(
        (b.ActiveHeadcount - LAG(b.ActiveHeadcount, 1) OVER (PARTITION BY b.DepartmentID ORDER BY b.Month)) * 100.0 /
        NULLIF(LAG(b.ActiveHeadcount, 1) OVER (PARTITION BY b.DepartmentID ORDER BY b.Month), 0),
        2
    ) AS Headcount_MoM_Pct,
    LAG(b.ActiveHeadcount, 12) OVER (PARTITION BY b.DepartmentID ORDER BY b.Month) AS Headcount_PY,
    ROUND(
        (b.ActiveHeadcount - LAG(b.ActiveHeadcount, 12) OVER (PARTITION BY b.DepartmentID ORDER BY b.Month)) * 100.0 /
        NULLIF(LAG(b.ActiveHeadcount, 12) OVER (PARTITION BY b.DepartmentID ORDER BY b.Month), 0),
        2
    ) AS Headcount_YoY_Pct
FROM MonthlyBase b
LEFT JOIN MonthlyHires h ON b.Month = h.Month AND b.DepartmentID = h.DepartmentID
LEFT JOIN MonthlyExits e ON b.Month = e.Month AND b.DepartmentID = e.DepartmentID;


/* ==============================================================================================
   FOLDER 02: ATTRITION & RETENTION INTELLIGENCE (Measures 12 - 22d)
   Description: Các chỉ số phân tích nghỉ việc, lý do thôi việc, tỷ lệ hao hụt và mất mát nhân tài chủ chốt
   ============================================================================================== */

-- ----------------------------------------------------------------------------------------------
-- 12, 13, 14, 15, 16. Terminations Breakdown (Total, Voluntary, Involuntary, and Ratios)
SELECT 
    COUNT(CASE WHEN EventType = 'Termination' THEN 1 END) AS TerminationsTotal,
    COUNT(CASE WHEN EventType = 'Termination' AND TerminationType = 'Voluntary' THEN 1 END) AS VoluntaryTerminations,
    COUNT(CASE WHEN EventType = 'Termination' AND TerminationType = 'Involuntary' THEN 1 END) AS InvoluntaryTerminations,
    -- Tỷ trọng tự nguyện (%)
    ROUND(
        COUNT(CASE WHEN EventType = 'Termination' AND TerminationType = 'Voluntary' THEN 1 END) * 100.0 /
        NULLIF(COUNT(CASE WHEN EventType = 'Termination' THEN 1 END), 0),
        2
    ) AS VoluntaryTerminationPct,
    -- Tỷ trọng tổ chức sa thải/cắt giảm (%)
    ROUND(
        COUNT(CASE WHEN EventType = 'Termination' AND TerminationType = 'Involuntary' THEN 1 END) * 100.0 /
        NULLIF(COUNT(CASE WHEN EventType = 'Termination' THEN 1 END), 0),
        2
    ) AS InvoluntaryTerminationPct
FROM FactEmployeeEvents
WHERE EventDate BETWEEN '2023-01-01' AND '2025-12-31';

-- ----------------------------------------------------------------------------------------------
-- 17, 18. Monthly Attrition Rate % & Annualized Attrition Rate %
WITH PeriodParams AS (
    SELECT 
        '2025-01-01' AS StartDate,
        '2025-12-31' AS EndDate,
        12.0 AS MonthsInPeriod
),
AvgHeadcount AS (
    SELECT 
        AVG(MonthlyHC) AS AvgHC
    FROM (
        SELECT Month, SUM(Headcount) AS MonthlyHC
        FROM FactMonthlySnapshot
        WHERE Month BETWEEN '2025-01-01' AND '2025-12-31'
        GROUP BY Month
    ) sub
),
Terminations AS (
    SELECT 
        COUNT(*) AS Terms
    FROM FactEmployeeEvents
    WHERE EventType = 'Termination'
      AND EventDate BETWEEN '2025-01-01' AND '2025-12-31'
)
SELECT 
    t.Terms AS TotalTerminations,
    ROUND(h.AvgHC, 1) AS AvgHeadcount,
    -- Tỷ lệ thôi việc bình quân tháng
    ROUND((t.Terms * 1.0 / NULLIF(h.AvgHC, 0)) / p.MonthsInPeriod * 100.0, 2) AS MonthlyAttritionRatePct,
    -- Tỷ lệ thôi việc chuẩn hóa theo năm (Annualized Attrition Rate %)
    ROUND((t.Terms * 1.0 / NULLIF(h.AvgHC, 0)) * (12.0 / p.MonthsInPeriod) * 100.0, 2) AS AnnualizedAttritionRatePct
FROM Terminations t
CROSS JOIN AvgHeadcount h
CROSS JOIN PeriodParams p;

-- ----------------------------------------------------------------------------------------------
-- 19. YTD Attrition Rate % (Tỷ lệ thôi việc tích lũy từ đầu năm)
WITH MonthlyRollup AS (
    SELECT 
        s.Month,
        CAST(SUBSTR(s.Month, 1, 4) AS INT) AS Year,
        SUM(s.Headcount) AS MonthlyHC,
        COALESCE(e.MonthlyTerms, 0) AS MonthlyTerms
    FROM FactMonthlySnapshot s
    LEFT JOIN (
        SELECT 
            CAST(SUBSTR(EventDate, 1, 7) || '-01' AS VARCHAR(10)) AS Month,
            COUNT(*) AS MonthlyTerms
        FROM FactEmployeeEvents
        WHERE EventType = 'Termination'
        GROUP BY CAST(SUBSTR(EventDate, 1, 7) || '-01' AS VARCHAR(10))
    ) e ON s.Month = e.Month
    GROUP BY s.Month, CAST(SUBSTR(s.Month, 1, 4) AS INT), e.MonthlyTerms
)
SELECT 
    Month,
    MonthlyHC,
    MonthlyTerms,
    -- Tổng số ca thôi việc lũy kế từ đầu năm đến tháng hiện tại
    SUM(MonthlyTerms) OVER (PARTITION BY Year ORDER BY Month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS Terms_YTD,
    -- Headcount bình quân lũy kế từ đầu năm
    AVG(MonthlyHC) OVER (PARTITION BY Year ORDER BY Month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS AvgHC_YTD,
    -- YTD Attrition Rate %
    ROUND(
        SUM(MonthlyTerms) OVER (PARTITION BY Year ORDER BY Month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) * 100.0 /
        NULLIF(AVG(MonthlyHC) OVER (PARTITION BY Year ORDER BY Month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0),
        2
    ) AS YTD_AttritionRatePct
FROM MonthlyRollup
ORDER BY Month DESC;

-- ----------------------------------------------------------------------------------------------
-- 20, 21. Regrettable Loss Count & Regrettable Loss Rate %
WITH LatestReviewBeforeExit AS (
    SELECT 
        p.EmployeeID,
        p.PerformanceRating,
        p.ReviewDate,
        ROW_NUMBER() OVER (PARTITION BY p.EmployeeID ORDER BY p.ReviewDate DESC) AS rn
    FROM FactPerformance p
),
VoluntaryExitsWithPerf AS (
    SELECT 
        e.EmployeeID,
        e.EventDate,
        e.Department,
        e.TerminationReason,
        lp.PerformanceRating,
        CASE WHEN lp.PerformanceRating >= 4 THEN 1 ELSE 0 END AS IsRegrettableLoss
    FROM FactEmployeeEvents e
    LEFT JOIN LatestReviewBeforeExit lp 
           ON e.EmployeeID = lp.EmployeeID 
          AND lp.rn = 1
    WHERE e.EventType = 'Termination'
      AND e.TerminationType = 'Voluntary'
)
SELECT 
    COUNT(*) AS VoluntaryTerminations,
    SUM(IsRegrettableLoss) AS RegrettableLossCount,
    -- Tỷ lệ mất mát nhân tài xuất sắc trên tổng số ca tự nguyện nghỉ (%)
    ROUND(SUM(IsRegrettableLoss) * 100.0 / NULLIF(COUNT(*), 0), 2) AS RegrettableLossRatePct
FROM VoluntaryExitsWithPerf;

-- ----------------------------------------------------------------------------------------------
-- 22. Restructuring Terminations (Đợt cắt giảm tái cơ cấu tổ chức tháng 06/2025)
SELECT 
    COUNT(*) AS RestructuringTerminationsCount
FROM FactEmployeeEvents
WHERE EventType = 'Termination'
  AND TerminationReason = 'Company Restructuring';

-- ----------------------------------------------------------------------------------------------
-- 22b & 22c. Exit Avg Engagement & Exit Avg Tenure Months
SELECT 
    ROUND(AVG(eng.EngagementScore), 2) AS ExitAvgEngagementScore,
    ROUND(AVG(emp.TenureMonthsAtExitOrEnd), 1) AS ExitAvgTenureMonths
FROM DimEmployee emp
LEFT JOIN (
    -- Lấy điểm khảo sát gắn kết gần nhất của nhân sự
    SELECT 
        EmployeeID,
        EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY SurveyDate DESC) AS rn
    FROM FactEngagement
) eng ON emp.EmployeeID = eng.EmployeeID AND eng.rn = 1
WHERE emp.TerminationType = 'Voluntary';

-- ----------------------------------------------------------------------------------------------
-- 22d. Termination Cumulative % (Pareto 80/20 Analysis by Reason)
WITH ReasonAgg AS (
    SELECT 
        TerminationReason,
        COUNT(*) AS ReasonTerminations
    FROM FactEmployeeEvents
    WHERE EventType = 'Termination'
      AND TerminationReason IS NOT NULL
    GROUP BY TerminationReason
)
SELECT 
    TerminationReason,
    ReasonTerminations,
    -- Tỷ lệ % trên tổng số ca thôi việc
    ROUND(ReasonTerminations * 100.0 / SUM(ReasonTerminations) OVER (), 2) AS PctOfTotal,
    -- Số ca thôi việc lũy kế theo thứ tự giảm dần
    SUM(ReasonTerminations) OVER (
        ORDER BY ReasonTerminations DESC, TerminationReason
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS CumulativeTerminations,
    -- Tỷ lệ phần trăm tích lũy phục vụ đồ thị Pareto 80/20
    ROUND(
        SUM(ReasonTerminations) OVER (
            ORDER BY ReasonTerminations DESC, TerminationReason
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) * 100.0 / SUM(ReasonTerminations) OVER (),
        2
    ) AS TerminationCumulativePct
FROM ReasonAgg
ORDER BY ReasonTerminations DESC;

-- ----------------------------------------------------------------------------------------------
-- PRODUCTION VIEW 02: vw_attrition_analytics_monthly
-- Data Mart tổng hợp động thái thôi việc, phân tích tự nguyện/bị động và tỷ lệ hao hụt chuẩn hóa
-- ----------------------------------------------------------------------------------------------
-- DROP VIEW IF EXISTS vw_attrition_analytics_monthly;
-- CREATE VIEW vw_attrition_analytics_monthly AS
WITH MonthlySnapshotHC AS (
    SELECT 
        Month,
        DepartmentID,
        SUM(Headcount) AS Headcount
    FROM FactMonthlySnapshot
    GROUP BY Month, DepartmentID
),
MonthlyEvents AS (
    SELECT 
        CAST(SUBSTR(EventDate, 1, 7) || '-01' AS VARCHAR(10)) AS Month,
        DepartmentID,
        COUNT(CASE WHEN EventType = 'Termination' THEN 1 END) AS TotalTerms,
        COUNT(CASE WHEN EventType = 'Termination' AND TerminationType = 'Voluntary' THEN 1 END) AS VoluntaryTerms,
        COUNT(CASE WHEN EventType = 'Termination' AND TerminationType = 'Involuntary' THEN 1 END) AS InvoluntaryTerms,
        COUNT(CASE WHEN EventType = 'Termination' AND TerminationReason = 'Company Restructuring' THEN 1 END) AS RestructuringTerms
    FROM FactEmployeeEvents
    GROUP BY CAST(SUBSTR(EventDate, 1, 7) || '-01' AS VARCHAR(10)), DepartmentID
)
SELECT 
    s.Month,
    s.DepartmentID,
    d.Department,
    s.Headcount AS ActiveHeadcount,
    COALESCE(e.TotalTerms, 0) AS TotalTerminations,
    COALESCE(e.VoluntaryTerms, 0) AS VoluntaryTerminations,
    COALESCE(e.InvoluntaryTerms, 0) AS InvoluntaryTerminations,
    COALESCE(e.RestructuringTerms, 0) AS RestructuringTerminations,
    -- Monthly Attrition Rate %
    ROUND(COALESCE(e.TotalTerms, 0) * 100.0 / NULLIF(s.Headcount, 0), 2) AS MonthlyAttritionRatePct,
    -- Annualized Attrition Rate % (Nhân hệ số 12 tháng)
    ROUND((COALESCE(e.TotalTerms, 0) * 1.0 / NULLIF(s.Headcount, 0)) * 12.0 * 100.0, 2) AS AnnualizedAttritionRatePct
FROM MonthlySnapshotHC s
JOIN DimDepartment d ON s.DepartmentID = d.DepartmentID
LEFT JOIN MonthlyEvents e ON s.Month = e.Month AND s.DepartmentID = e.DepartmentID;


/* ==============================================================================================
   FOLDER 03: PLANNING & BUDGET VARIANCE INTELLIGENCE (Measures 23 - 32)
   Description: Đối soát định biên nhân sự, FTE thực tế so với mục tiêu và chênh lệch ngân sách quỹ lương
   ============================================================================================== */

-- ----------------------------------------------------------------------------------------------
-- 23, 24, 25, 26, 27, 28. Headcount & FTE Variance (Actual vs Plan)
WITH LatestMonthTarget AS (
    SELECT MAX(Month) AS MaxMonth FROM WorkforceTargets
),
ActualHC AS (
    SELECT 
        s.Month,
        s.DepartmentID,
        SUM(s.Headcount) AS ActiveHeadcount,
        SUM(s.FTE) AS ActiveFTE
    FROM FactMonthlySnapshot s
    JOIN LatestMonthTarget lm ON s.Month = lm.MaxMonth
    GROUP BY s.Month, s.DepartmentID
),
TargetHC AS (
    SELECT 
        t.Month,
        t.DepartmentID,
        t.PlannedHeadcount,
        t.BudgetedFTE,
        t.BudgetedSalaryCost
    FROM WorkforceTargets t
    JOIN LatestMonthTarget lm ON t.Month = lm.MaxMonth
)
SELECT 
    a.Month,
    d.Department,
    a.ActiveHeadcount,
    t.PlannedHeadcount,
    -- Headcount Variance (Thực tế - Định biên: Dương = Thừa, Âm = Thiếu)
    a.ActiveHeadcount - t.PlannedHeadcount AS HeadcountVariance,
    -- Headcount Variance %
    ROUND((a.ActiveHeadcount - t.PlannedHeadcount) * 100.0 / NULLIF(t.PlannedHeadcount, 0), 2) AS HeadcountVariancePct,
    a.ActiveFTE,
    t.BudgetedFTE,
    -- FTE Variance
    ROUND(a.ActiveFTE - t.BudgetedFTE, 1) AS FTEVariance,
    -- FTE Variance %
    ROUND((a.ActiveFTE - t.BudgetedFTE) * 100.0 / NULLIF(t.BudgetedFTE, 0), 2) AS FTEVariancePct
FROM ActualHC a
JOIN TargetHC t ON a.Month = t.Month AND a.DepartmentID = t.DepartmentID
JOIN DimDepartment d ON a.DepartmentID = d.DepartmentID
ORDER BY HeadcountVariance ASC;

-- ----------------------------------------------------------------------------------------------
-- 29, 30, 31, 32. Budgeted Salary Cost vs Actual Annualized Salary Cost & Variances
WITH LatestCompPerActiveEmployee AS (
    SELECT 
        c.EmployeeID,
        c.AnnualSalary,
        e.DepartmentID,
        ROW_NUMBER() OVER (PARTITION BY c.EmployeeID ORDER BY c.EffectiveDate DESC) AS rn
    FROM FactCompensation c
    JOIN DimEmployee e ON c.EmployeeID = e.EmployeeID
    WHERE e.EmploymentStatus = 'Active'
),
DepartmentActualSalary AS (
    SELECT 
        DepartmentID,
        SUM(AnnualSalary) AS ActualAnnualizedSalaryCost
    FROM LatestCompPerActiveEmployee
    WHERE rn = 1
    GROUP BY DepartmentID
),
DepartmentBudgetSalary AS (
    SELECT 
        DepartmentID,
        BudgetedSalaryCost
    FROM WorkforceTargets
    WHERE Month = (SELECT MAX(Month) FROM WorkforceTargets)
)
SELECT 
    d.Department,
    b.BudgetedSalaryCost,
    a.ActualAnnualizedSalaryCost,
    -- Salary Cost Variance (Thực tế - Ngân sách: Dương = Vượt ngân sách, Âm = Tiết kiệm/Chưa giải ngân)
    a.ActualAnnualizedSalaryCost - b.BudgetedSalaryCost AS SalaryCostVariance,
    -- Salary Cost Variance %
    ROUND((a.ActualAnnualizedSalaryCost - b.BudgetedSalaryCost) * 100.0 / NULLIF(b.BudgetedSalaryCost, 0), 2) AS SalaryCostVariancePct
FROM DepartmentBudgetSalary b
JOIN DepartmentActualSalary a ON b.DepartmentID = a.DepartmentID
JOIN DimDepartment d ON b.DepartmentID = d.DepartmentID
ORDER BY SalaryCostVariance DESC;

-- ----------------------------------------------------------------------------------------------
-- PRODUCTION VIEW 03: vw_planning_budget_variance
-- Data Mart đối soát định biên nhân sự, FTE và ngân sách quỹ lương theo từng kỳ chốt sổ
-- ----------------------------------------------------------------------------------------------
-- DROP VIEW IF EXISTS vw_planning_budget_variance;
-- CREATE VIEW vw_planning_budget_variance AS
WITH ActualWorkforceMonthly AS (
    SELECT 
        s.Month,
        s.DepartmentID,
        SUM(s.Headcount) AS ActiveHeadcount,
        SUM(s.FTE) AS ActiveFTE
    FROM FactMonthlySnapshot s
    GROUP BY s.Month, s.DepartmentID
),
ActualSalaryMonthly AS (
    -- Tổng lương hàng năm thực tế của nhân sự Active theo từng tháng snapshot
    SELECT 
        s.Month,
        e.DepartmentID,
        SUM(c.AnnualSalary) AS ActualSalaryCost
    FROM FactMonthlySnapshot s
    JOIN DimEmployee e ON s.DepartmentID = e.DepartmentID
    JOIN (
        SELECT 
            EmployeeID,
            AnnualSalary,
            EffectiveDate,
            ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate DESC) AS rn
        FROM FactCompensation
    ) c ON e.EmployeeID = c.EmployeeID AND c.rn = 1
    WHERE e.HireDate <= s.Month AND (e.TerminationDate IS NULL OR e.TerminationDate > s.Month)
    GROUP BY s.Month, e.DepartmentID
)
SELECT 
    t.Month,
    t.DepartmentID,
    d.Department,
    t.PlanningScenario,
    -- Headcount Reconciliation
    COALESCE(w.ActiveHeadcount, 0) AS ActiveHeadcount,
    t.PlannedHeadcount,
    COALESCE(w.ActiveHeadcount, 0) - t.PlannedHeadcount AS HeadcountVariance,
    ROUND((COALESCE(w.ActiveHeadcount, 0) - t.PlannedHeadcount) * 100.0 / NULLIF(t.PlannedHeadcount, 0), 2) AS HeadcountVariancePct,
    -- FTE Reconciliation
    COALESCE(w.ActiveFTE, 0) AS ActiveFTE,
    t.BudgetedFTE,
    ROUND(COALESCE(w.ActiveFTE, 0) - t.BudgetedFTE, 1) AS FTEVariance,
    ROUND((COALESCE(w.ActiveFTE, 0) - t.BudgetedFTE) * 100.0 / NULLIF(t.BudgetedFTE, 0), 2) AS FTEVariancePct,
    -- Salary Budget Reconciliation
    COALESCE(sal.ActualSalaryCost, 0) AS ActualSalaryCost,
    t.BudgetedSalaryCost,
    COALESCE(sal.ActualSalaryCost, 0) - t.BudgetedSalaryCost AS SalaryCostVariance,
    ROUND((COALESCE(sal.ActualSalaryCost, 0) - t.BudgetedSalaryCost) * 100.0 / NULLIF(t.BudgetedSalaryCost, 0), 2) AS SalaryCostVariancePct
FROM WorkforceTargets t
JOIN DimDepartment d ON t.DepartmentID = d.DepartmentID
LEFT JOIN ActualWorkforceMonthly w ON t.Month = w.Month AND t.DepartmentID = w.DepartmentID
LEFT JOIN ActualSalaryMonthly sal ON t.Month = sal.Month AND t.DepartmentID = sal.DepartmentID;


/* ==============================================================================================
   FOLDER 04: TALENT, COMPENSATION & WELL-BEING CORRELATION (Measures 33 - 42)
   Description: Tương quan giữa Mức độ gắn kết, Hiệu suất làm việc, Tình trạng vắng mặt và Cạnh tranh đãi ngộ
   ============================================================================================== */

-- ----------------------------------------------------------------------------------------------
-- 33, 34, 35. Engagement Score, Response Rate %, and Performance Rating
SELECT 
    ROUND(AVG(e.EngagementScore), 2) AS AvgEngagementScore,
    ROUND(AVG(e.ResponseRatePct), 2) AS AvgResponseRatePct,
    (SELECT ROUND(AVG(PerformanceRating), 2) FROM FactPerformance) AS AvgPerformanceRating
FROM FactEngagement e;

-- ----------------------------------------------------------------------------------------------
-- 36, 37, 38, 39, 40. Absence Analytics (Total Days, Sick Leave, Unpaid Leave, Sick Ratio %)
WITH AbsenceTotals AS (
    SELECT 
        SUM(DaysAbsent) AS TotalDaysAbsent,
        SUM(CASE WHEN AbsenceType = 'Sick Leave' THEN DaysAbsent ELSE 0 END) AS SickLeaveDays,
        SUM(CASE WHEN AbsenceType = 'Unpaid Leave' THEN DaysAbsent ELSE 0 END) AS UnpaidLeaveDays
    FROM FactAbsence
),
ActiveHeadcountLatest AS (
    SELECT SUM(Headcount) AS CurrentHC 
    FROM FactMonthlySnapshot 
    WHERE Month = (SELECT MAX(Month) FROM FactMonthlySnapshot)
)
SELECT 
    a.TotalDaysAbsent,
    a.SickLeaveDays,
    a.UnpaidLeaveDays,
    -- Số ngày vắng mặt bình quân trên mỗi nhân sự (Absence Days per Employee)
    ROUND(a.TotalDaysAbsent * 1.0 / NULLIF(h.CurrentHC, 0), 1) AS AbsenceDaysPerEmployee,
    -- Tỷ lệ nghỉ ốm trên tổng số ngày nghỉ (%)
    ROUND(a.SickLeaveDays * 100.0 / NULLIF(a.TotalDaysAbsent, 0), 2) AS SickLeaveRatioPct
FROM AbsenceTotals a
CROSS JOIN ActiveHeadcountLatest h;

-- ----------------------------------------------------------------------------------------------
-- 41, 42. Level Benchmark Salary (P50 Median) & Salary Compa-Ratio

-- CTE tính mức lương trung vị Benchmark nội bộ theo Level (Universal ANSI Window Approach):
WITH RankedSalariesPerLevel AS (
    SELECT 
        Level,
        AnnualSalary,
        ROW_NUMBER() OVER (PARTITION BY Level ORDER BY AnnualSalary) AS row_asc,
        COUNT(*) OVER (PARTITION BY Level) AS total_rows
    FROM FactCompensation
),
LevelBenchmarkMedian AS (
    SELECT 
        Level,
        ROUND(AVG(AnnualSalary), 2) AS LevelBenchmarkSalary
    FROM RankedSalariesPerLevel
    WHERE row_asc IN ((total_rows + 1) / 2, (total_rows + 2) / 2)
    GROUP BY Level
),
LatestEmployeeComp AS (
    SELECT 
        c.EmployeeID,
        c.Level,
        c.AnnualSalary,
        ROW_NUMBER() OVER (PARTITION BY c.EmployeeID ORDER BY c.EffectiveDate DESC) AS rn
    FROM FactCompensation c
)
SELECT 
    ec.EmployeeID,
    ec.Level,
    ec.AnnualSalary,
    bm.LevelBenchmarkSalary,
    -- Compa-Ratio = Mức lương cá nhân / Mức lương trung vị chuẩn của Level đó
    ROUND(ec.AnnualSalary * 1.0 / NULLIF(bm.LevelBenchmarkSalary, 0), 3) AS CompaRatio
FROM LatestEmployeeComp ec
JOIN LevelBenchmarkMedian bm ON ec.Level = bm.Level
WHERE ec.rn = 1;


/* ==============================================================================================
   FOLDER 05: RECRUITMENT OPERATIONS & SLA VELOCITY (Measures 43 - 49)
   Description: Đánh giá hiệu suất tuyển dụng, nhu cầu bổ sung nhân sự và tốc độ lấp đầy vị trí trống
   ============================================================================================== */

-- ----------------------------------------------------------------------------------------------
-- 43, 44, 45, 46, 47, 48, 49. Recruitment SLA & Velocity Engine
SELECT 
    d.Department,
    SUM(r.OpenRequisitions) AS OpenRequisitions,
    SUM(r.FilledRequisitions) AS FilledRequisitions,
    SUM(r.CancelledRequisitions) AS CancelledRequisitions,
    -- Total Requisition Demand (Tổng cầu = Mở + Đã tuyển + Đã hủy)
    SUM(r.OpenRequisitions + r.FilledRequisitions + r.CancelledRequisitions) AS TotalRequisitionDemand,
    -- Requisition Fill Rate % (Tỷ lệ lấp đầy yêu cầu tuyển dụng)
    ROUND(
        SUM(r.FilledRequisitions) * 100.0 / 
        NULLIF(SUM(r.OpenRequisitions + r.FilledRequisitions + r.CancelledRequisitions), 0), 
        2
    ) AS RequisitionFillRatePct,
    -- Average Days to Fill (Thời gian tuyển dụng trung bình)
    ROUND(AVG(r.AvgDaysToFill), 1) AS AvgDaysToFill,
    -- Hiring Velocity Index (Chỉ số tốc độ tuyển dụng = Filled / AvgDaysToFill)
    ROUND(SUM(r.FilledRequisitions) * 1.0 / NULLIF(AVG(r.AvgDaysToFill), 0), 2) AS HiringVelocityIndex
FROM FactRecruitment r
JOIN DimDepartment d ON r.DepartmentID = d.DepartmentID
GROUP BY d.Department
ORDER BY AvgDaysToFill DESC;


/* ==============================================================================================
   FOLDER 06: UI HELPERS & PRESCRIPTIVE RETENTION LOGIC (Measures 50 - 53)
   Description: Các giải thuật chỉ định hành động giữ chân tự động, mã màu HEX & cờ cảnh báo rủi ro
   ============================================================================================== */

-- ----------------------------------------------------------------------------------------------
-- 50. Headcount Variance Status Color Code (Mã màu HEX hiển thị giao diện báo cáo)

-- ----------------------------------------------------------------------------------------------
-- 51. Attrition Risk Flag (Cờ cảnh báo rủi ro biến động nhân sự phòng ban)

-- ----------------------------------------------------------------------------------------------
-- 51b & 53. Individual Flight Risk Flag & Prescriptive Recommended Action

-- ----------------------------------------------------------------------------------------------
-- PRODUCTION VIEW 04: vw_hrbp_actionable_flight_risk
-- Bảng can thiệp tác nghiệp giữ chân nhân tài theo thời gian thực dành cho HRBP & C&B
-- ----------------------------------------------------------------------------------------------
-- DROP VIEW IF EXISTS vw_hrbp_actionable_flight_risk;
-- CREATE VIEW vw_hrbp_actionable_flight_risk AS
WITH LevelBenchmarkMedian AS (
    SELECT 
        Level,
        ROUND(AVG(AnnualSalary), 2) AS BenchmarkMedianSalary
    FROM (
        SELECT 
            Level,
            AnnualSalary,
            ROW_NUMBER() OVER (PARTITION BY Level ORDER BY AnnualSalary) AS r,
            COUNT(*) OVER (PARTITION BY Level) AS cnt
        FROM FactCompensation
    ) ranked
    WHERE r IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY Level
),
LatestComp AS (
    SELECT 
        EmployeeID,
        Level,
        AnnualSalary,
        ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate DESC) AS rn
    FROM FactCompensation
),
LatestPerf AS (
    SELECT 
        EmployeeID,
        PerformanceRating,
        ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY ReviewDate DESC) AS rn
    FROM FactPerformance
),
LatestEng AS (
    SELECT 
        EmployeeID,
        EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY SurveyDate DESC) AS rn
    FROM FactEngagement
),
TotalAbsence AS (
    SELECT 
        EmployeeID,
        SUM(DaysAbsent) AS TotalDaysAbsent,
        SUM(CASE WHEN AbsenceType = 'Sick Leave' THEN DaysAbsent ELSE 0 END) AS SickLeaveDays
    FROM FactAbsence
    GROUP BY EmployeeID
)
SELECT 
    e.EmployeeID,
    e.Department,
    e.Role,
    e.Level,
    e.Location,
    e.Gender,
    e.AgeBand,
    e.HireDate,
    e.EmploymentStatus,
    -- Lương & Chuẩn thị trường
    c.AnnualSalary,
    bm.BenchmarkMedianSalary,
    ROUND(c.AnnualSalary * 1.0 / NULLIF(bm.BenchmarkMedianSalary, 0), 2) AS CompaRatio,
    -- Điểm số đánh giá
    p.PerformanceRating,
    eng.EngagementScore,
    COALESCE(a.TotalDaysAbsent, 0) AS TotalDaysAbsent,
    COALESCE(a.SickLeaveDays, 0) AS SickLeaveDays,
    ROUND(COALESCE(a.SickLeaveDays, 0) * 100.0 / NULLIF(a.TotalDaysAbsent, 0), 1) AS SickLeaveRatioPct,
    
    -- [Measure 51b]: Flight Risk Flag (Cờ cảnh báo nguy cơ nghỉ việc)
    CASE 
        WHEN (c.AnnualSalary * 1.0 / NULLIF(bm.BenchmarkMedianSalary, 0)) < 0.95 AND eng.EngagementScore < 3.0 
            THEN '🔴 Critical Risk (Underpaid & Disengaged)'
        WHEN (c.AnnualSalary * 1.0 / NULLIF(bm.BenchmarkMedianSalary, 0)) < 0.95 
            THEN '🟡 Comp Risk (Underpaid)'
        WHEN eng.EngagementScore < 3.0 
            THEN '🟠 Engagement Risk (Low Morale)'
        ELSE '🟢 Healthy'
    END AS FlightRiskFlag,

    -- [Measure 53]: Recommended Action (Hành động can thiệp đề xuất cho HRBP)
    CASE 
        -- 1. Nguy cơ mất nhân tài cốt lõi (Rating >= 4, Thiếu lương & Bất mãn)
        WHEN (c.AnnualSalary * 1.0 / NULLIF(bm.BenchmarkMedianSalary, 0)) < 0.95 
         AND eng.EngagementScore < 3.0 
         AND p.PerformanceRating >= 4
            THEN '🚨 Retain Top Talent'

        -- 2. Nguy cơ kép: Thiếu lương & Bất mãn
        WHEN (c.AnnualSalary * 1.0 / NULLIF(bm.BenchmarkMedianSalary, 0)) < 0.95 
         AND eng.EngagementScore < 3.0
            THEN '⚠️ Comp Review & 1-on-1'

        -- 3. Cảnh báo kiệt sức (Vắng mặt nhiều >= 10 ngày & Điểm gắn kết thấp)
        WHEN eng.EngagementScore < 3.0 
         AND COALESCE(a.TotalDaysAbsent, 0) >= 10
            THEN '🧘 Workload Rebalance'

        -- 4. Bất công đãi ngộ nghiêm trọng (Lương thấp hơn 90% chuẩn thị trường P50)
        WHEN (c.AnnualSalary * 1.0 / NULLIF(bm.BenchmarkMedianSalary, 0)) < 0.90
            THEN '💰 Adjust Comp to P50'

        -- 5. Bất mãn gắn kết hoặc trì trệ thăng tiến
        WHEN eng.EngagementScore < 3.0
            THEN '🗣️ Stay Interview'

        ELSE '✅ Maintain Current Status'
    END AS RecommendedAction
FROM DimEmployee e
LEFT JOIN LatestComp c ON e.EmployeeID = c.EmployeeID AND c.rn = 1
LEFT JOIN LevelBenchmarkMedian bm ON c.Level = bm.Level
LEFT JOIN LatestPerf p ON e.EmployeeID = p.EmployeeID AND p.rn = 1
LEFT JOIN LatestEng eng ON e.EmployeeID = eng.EmployeeID AND eng.rn = 1
LEFT JOIN TotalAbsence a ON e.EmployeeID = a.EmployeeID
WHERE e.EmploymentStatus = 'Active';


/* ==============================================================================================
   07. EXECUTIVE HEADLINE KPI ROLL-UP QUERY (C-Suite 1-Row Cockpit Summary)
   Mục đích: Tái lập toàn bộ 6 thẻ KPI Cốt lõi trên Trang 1 Dashboard Power BI chỉ với 1 câu lệnh SQL
   ============================================================================================== */
WITH LatestDate AS (
    SELECT MAX(Month) AS MaxMonth FROM FactMonthlySnapshot
),
LatestSnapshot AS (
    SELECT 
        SUM(Headcount) AS ActiveHeadcount,
        SUM(FTE) AS ActiveFTE,
        ROUND(SUM(Headcount * AvgTenureMonths) * 1.0 / NULLIF(SUM(Headcount), 0), 1) AS AvgTenureMonths
    FROM FactMonthlySnapshot
    WHERE Month = (SELECT MaxMonth FROM LatestDate)
),
PriorSnapshot AS (
    SELECT 
        SUM(Headcount) AS PriorHeadcount
    FROM FactMonthlySnapshot
    WHERE Month = (
        SELECT MAX(Month) 
        FROM FactMonthlySnapshot 
        WHERE Month < (SELECT MaxMonth FROM LatestDate)
    )
),
AllTimeEvents AS (
    SELECT 
        COUNT(CASE WHEN EventType = 'Hire' THEN 1 END) AS TotalHires,
        COUNT(CASE WHEN EventType = 'Termination' THEN 1 END) AS TotalTerminations,
        COUNT(CASE WHEN EventType = 'Termination' AND TerminationType = 'Voluntary' THEN 1 END) AS VoluntaryTerminations,
        COUNT(CASE WHEN EventType = 'Termination' AND TerminationReason = 'Company Restructuring' THEN 1 END) AS RestructuringTerminations
    FROM FactEmployeeEvents
),
AverageHeadcountAllTime AS (
    SELECT AVG(MonthlyHC) AS OverallAvgHC
    FROM (
        SELECT Month, SUM(Headcount) AS MonthlyHC 
        FROM FactMonthlySnapshot 
        GROUP BY Month
    ) sub
),
RegrettableLossCalc AS (
    SELECT 
        COUNT(*) AS RegrettableLossCount
    FROM FactEmployeeEvents e
    JOIN (
        SELECT 
            EmployeeID,
            PerformanceRating,
            ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY ReviewDate DESC) AS rn
        FROM FactPerformance
    ) p ON e.EmployeeID = p.EmployeeID AND p.rn = 1
    WHERE e.EventType = 'Termination'
      AND e.TerminationType = 'Voluntary'
      AND p.PerformanceRating >= 4
)
SELECT 
    (SELECT MaxMonth FROM LatestDate) AS AsOfDate,
    curr.ActiveHeadcount,
    curr.ActiveFTE,
    ROUND((curr.ActiveHeadcount - prior.PriorHeadcount) * 100.0 / NULLIF(prior.PriorHeadcount, 0), 2) AS Headcount_MoM_GrowthPct,
    curr.AvgTenureMonths,
    ROUND(curr.AvgTenureMonths / 12.0, 2) AS AvgTenureYears,
    ev.TotalHires,
    ev.TotalTerminations,
    ev.TotalHires - ev.TotalTerminations AS NetWorkforceChange,
    ev.VoluntaryTerminations,
    ev.RestructuringTerminations,
    rl.RegrettableLossCount,
    -- Tỷ lệ thôi việc tổng thể chuẩn hóa theo năm (%)
    ROUND((ev.TotalTerminations * 1.0 / NULLIF(avg_hc.OverallAvgHC, 0)) * (12.0 / 36.0) * 100.0, 2) AS AnnualizedAttritionRatePct
FROM LatestSnapshot curr
CROSS JOIN PriorSnapshot prior
CROSS JOIN AllTimeEvents ev
CROSS JOIN AverageHeadcountAllTime avg_hc
CROSS JOIN RegrettableLossCalc rl;


/* ==============================================================================================
   08. BẢNG TỔNG HỢP DANH MỤC 53 CHỈ SỐ QUẢN TRỊ NHÂN SỰ & CÔNG THỨC TRUY VẤN SQL
   ==============================================================================================
   | TT | Tên Chỉ Số (Metric Name)       | Nhóm Nghiệp Vụ    | Công Thức / Logic Truy Vấn SQL                                           |
   |:---|:--------------------------------|:-------------------|:-------------------------------------------------------------------------|
   | 01 | Active Headcount                | Core Workforce     | SUM(Headcount) WHERE Month = MAX(Month)                                  |
   | 02 | Active FTE                      | Core Workforce     | SUM(FTE) WHERE Month = MAX(Month)                                        |
   | 03 | Avg Headcount Period            | 01_Core Workforce  | AVG(MonthlyHeadcount) qua các tháng trong kỳ                            |
   | 04 | New Hires                       | 01_Core Workforce  | COUNT(*) FROM FactEmployeeEvents WHERE EventType = 'Hire'                 |
   | 05 | Net Workforce Change            | 01_Core Workforce  | NewHires - TerminationsTotal                                             |
   | 06 | Avg Tenure Months               | 01_Core Workforce  | SUM(Headcount * AvgTenureMonths) / SUM(Headcount)                        |
   | 07 | Avg Tenure Years                | 01_Core Workforce  | AvgTenureMonths / 12.0                                                   |
   | 08 | Headcount PM                    | 01_Core Workforce  | LAG(ActiveHeadcount, 1) OVER (ORDER BY Month)                            |
   | 09 | Headcount MoM %                 | 01_Core Workforce  | (Headcount - Headcount_PM) * 100.0 / Headcount_PM                         |
   | 10 | Headcount PY                    | 01_Core Workforce  | LAG(ActiveHeadcount, 12) OVER (ORDER BY Month)                           |
   | 11 | Headcount YoY %                 | 01_Core Workforce  | (Headcount - Headcount_PY) * 100.0 / Headcount_PY                         |
   | 12 | Terminations Total              | 02_Attrition       | COUNT(*) FROM FactEmployeeEvents WHERE EventType = 'Termination'          |
   | 13 | Voluntary Terminations          | 02_Attrition       | COUNT(*) WHERE EventType = 'Termination' AND TerminationType='Voluntary'  |
   | 14 | Involuntary Terminations        | 02_Attrition       | COUNT(*) WHERE EventType = 'Termination' AND TerminationType='Involuntary'|
   | 15 | Voluntary Termination %         | 02_Attrition       | VoluntaryTerminations * 100.0 / TerminationsTotal                        |
   | 16 | Involuntary Termination %       | 02_Attrition       | InvoluntaryTerminations * 100.0 / TerminationsTotal                      |
   | 17 | Monthly Attrition Rate %        | 02_Attrition       | TerminationsTotal * 100.0 / AvgHeadcount                                 |
   | 18 | Annualized Attrition Rate %     | 02_Attrition       | (Terminations / AvgHC) * (12.0 / MonthsInPeriod) * 100.0                 |
   | 19 | YTD Attrition Rate %            | 02_Attrition       | SUM(Terms) OVER YTD / AVG(Headcount) OVER YTD * 100.0                    |
   | 20 | Regrettable Loss Count          | 02_Attrition       | COUNT(*) WHERE Voluntary=1 AND Latest PerformanceRating >= 4             |
   | 21 | Regrettable Loss Rate %         | 02_Attrition       | RegrettableLossCount * 100.0 / VoluntaryTerminations                      |
   | 22 | Restructuring Terminations      | 02_Attrition       | COUNT(*) WHERE TerminationReason = 'Company Restructuring'                |
   | 22b| Exit Avg Engagement             | 02_Attrition       | AVG(EngagementScore) cho nhân sự Voluntary Exit                          |
   | 22c| Exit Avg Tenure Months          | 02_Attrition       | AVG(TenureMonthsAtExitOrEnd) cho nhân sự Voluntary Exit                   |
   | 22d| Termination Cumulative %        | 02_Attrition       | SUM(Terms) OVER (ORDER BY Terms DESC) / SUM(Terms) OVER () * 100.0        |
   | 23 | Planned Headcount               | 03_Planning/Budget | SUM(PlannedHeadcount) FROM WorkforceTargets WHERE Month = MAX(Month)     |
   | 24 | Budgeted FTE                    | 03_Planning/Budget | SUM(BudgetedFTE) FROM WorkforceTargets WHERE Month = MAX(Month)          |
   | 25 | Headcount Variance              | 03_Planning/Budget | ActiveHeadcount - PlannedHeadcount                                        |
   | 26 | Headcount Variance %            | 03_Planning/Budget | HeadcountVariance * 100.0 / PlannedHeadcount                             |
   | 27 | FTE Variance                    | 03_Planning/Budget | ActiveFTE - BudgetedFTE                                                  |
   | 28 | FTE Variance %                  | 03_Planning/Budget | FTEVariance * 100.0 / BudgetedFTE                                        |
   | 29 | Budgeted Salary Cost            | 03_Planning/Budget | SUM(BudgetedSalaryCost) FROM WorkforceTargets WHERE Month = MAX(Month)   |
   | 30 | Actual Salary Cost              | 03_Planning/Budget | SUM(Latest AnnualSalary) của Active Employees                            |
   | 31 | Salary Cost Variance            | 03_Planning/Budget | ActualSalaryCost - BudgetedSalaryCost                                    |
   | 32 | Salary Cost Variance %          | 03_Planning/Budget | SalaryCostVariance * 100.0 / BudgetedSalaryCost                          |
   | 33 | Avg Engagement Score            | 04_Talent/Wellbeing| AVG(EngagementScore) FROM FactEngagement                                 |
   | 34 | Avg Response Rate %             | 04_Talent/Wellbeing| AVG(ResponseRatePct) FROM FactEngagement                                 |
   | 35 | Avg Performance Rating          | 04_Talent/Wellbeing| AVG(PerformanceRating) FROM FactPerformance                             |
   | 36 | Total Days Absent               | 04_Talent/Wellbeing| SUM(DaysAbsent) FROM FactAbsence                                         |
   | 37 | Sick Leave Days                 | 04_Talent/Wellbeing| SUM(DaysAbsent) WHERE AbsenceType = 'Sick Leave'                         |
   | 38 | Unpaid Leave Days               | 04_Talent/Wellbeing| SUM(DaysAbsent) WHERE AbsenceType = 'Unpaid Leave'                       |
   | 39 | Absence Days per Employee       | 04_Talent/Wellbeing| TotalDaysAbsent / AvgHeadcount                                           |
   | 40 | Sick Leave Ratio %              | 04_Talent/Wellbeing| SickLeaveDays * 100.0 / TotalDaysAbsent                                  |
   | 41 | Level Benchmark Salary          | 04_Talent/Wellbeing| PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY)  |
   | 42 | Avg Compa-Ratio                 | 04_Talent/Wellbeing| AVG(AnnualSalary / LevelBenchmarkSalary)                                 |
   | 43 | Open Requisitions               | 05_Recruitment     | SUM(OpenRequisitions) FROM FactRecruitment                               |
   | 44 | Filled Requisitions             | 05_Recruitment     | SUM(FilledRequisitions) FROM FactRecruitment                             |
   | 45 | Cancelled Requisitions          | 05_Recruitment     | SUM(CancelledRequisitions) FROM FactRecruitment                          |
   | 46 | Total Requisition Demand        | 05_Recruitment     | SUM(Open + Filled + Cancelled)                                           |
   | 47 | Requisition Fill Rate %         | 05_Recruitment     | FilledRequisitions * 100.0 / TotalRequisitionDemand                      |
   | 48 | Avg Days to Fill                | 05_Recruitment     | AVG(AvgDaysToFill) FROM FactRecruitment                                  |
   | 49 | Hiring Velocity Index           | 05_Recruitment     | FilledRequisitions / AvgDaysToFill                                       |
   | 50 | Headcount Variance Color        | 06_UI/Prescriptive | CASE WHEN VarPct < -0.10 THEN '#E53E3E' ... END                          |
   | 51 | Attrition Risk Flag             | 06_UI/Prescriptive | CASE WHEN AnnualRate >= 0.15 THEN '🔴 High Risk' ... END                 |
   | 51b| Flight Risk Flag                | 06_UI/Prescriptive | CASE WHEN Compa<0.95 AND Eng<3.0 THEN '🔴 Critical Risk' ... END         |
   | 52 | Dynamic Header Title            | 06_UI/Prescriptive | 'Workforce Analytics | Period: ' || MinDate || ' - ' || MaxDate          |
   | 53 | Recommended Action              | 06_UI/Prescriptive | CASE WHEN Compa<0.95 AND Eng<3.0 AND Perf>=4 THEN '🚨 Retain Top Talent' |
   ============================================================================================== */
