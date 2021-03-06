	/*
Script: Build Tableau Extract for EPAs Dashboard
Author: THarpin
Date: 5/7/2019
*/

/*
Declare variables for script use
*/
DECLARE @current_year_id INT
DECLARE @roster_date DATE
DECLARE @current_term VARCHAR(15)

-- Used to pull rosters at snapshot dates for teacher goal purposes
DECLARE @snapshot_dates TABLE (
	year_id INT
	,snapshot_date VARCHAR(10)
)
DECLARE @snapshot_date VARCHAR(10)
DECLARE @snapshot_year_id INT


SET @current_year_id = CASE
							WHEN MONTH(GETDATE()) BETWEEN 7 AND 12 THEN YEAR(GETDATE()) - 1990
							ELSE YEAR(GETDATE()) - 1991
						END

SET @roster_date = CASE
						WHEN MONTH(GETDATE()) BETWEEN 5 AND 7 THEN DATEFROMPARTS(YEAR(GETDATE()), '05', '1')
						ELSE GETDATE()
					END

SET @current_term = CASE
						 WHEN MONTH(GETDATE()) BETWEEN 8 AND 12 THEN 'Fall'
						 WHEN MONTH(GETDATE()) BETWEEN 1 AND 3 THEN 'Winter'
						 WHEN MONTH(GETDATE()) BETWEEN 4 AND 5 THEN 'Spring'
					 END

INSERT INTO @snapshot_dates
SELECT yearid
	   ,snapshotdate

  FROM ODS_CPS.DAT.SnapshotDate

 WHERE yearid BETWEEN (@current_year_id - 2) AND @current_year_id


IF OBJECT_ID('tempdb..#temp_vstudent') IS NOT NULL DROP TABLE #temp_vstudent
SELECT *

  INTO #temp_vstudent

  FROM ODS_CPS.rpt.vStudent

IF OBJECT_ID('tempdb..#temp_vroster') IS NOT NULL DROP TABLE #temp_vroster
SELECT *

  INTO #temp_vroster

  FROM ODS_CPS.rpt.vRoster


/*
Pull unofficial results for year 28+
*/
IF OBJECT_ID('tempdb..#unofficial_raw_results') IS NOT NULL DROP TABLE #unofficial_raw_results
SELECT year_id
	   ,local_id
	   ,academic_term
	   ,print_date AS test_date
	   ,test_type
	   ,'Unofficial' AS result_type
	   ,test_subject
	   ,scale_score
	   ,NULL AS test_percentile --Placeholder for subtest percentile
	   ,composite_score
	   ,NULL AS composite_percentile --Placeholder for composite percentile
	   ,question_num
	   ,response
	   ,correct_value
	   ,correct

  INTO #unofficial_raw_results

  FROM eduphoria.dat.unofficial_EPAs_results AS r

 WHERE year_id BETWEEN (@current_year_id - 2) AND @current_year_id


/*
Pull official results for current + previous two years
*/
IF OBJECT_ID('tempdb..#official_spring_raw_results') IS NOT NULL DROP TABLE #official_spring_raw_results
CREATE TABLE #official_spring_raw_results (
	year_id INT
	,local_id VARCHAR(10)
	,academic_term VARCHAR(20)
	,test_date DATE
	,test_type VARCHAR(15)
	,result_type VARCHAR(25)
	,test_subject VARCHAR(25)
	,scale_score INT
	,test_percentile INT
	,composite_score INT
	,composite_percentile INT
	,question_number INT
	,response VARCHAR(1)
	,correct_response VARCHAR(1)
	,correct_flag INT
)

INSERT INTO #official_spring_raw_results
SELECT year_id
	   ,local_id
	   ,academic_term
	   ,test_date
	   ,'PreACT'
	   ,'Official'
	   ,test_subject
	   ,scale_score
	   ,natl_percentile
	   ,composite_scale_score
	   ,composite_percentile
	   ,question_number
	   ,response
	   ,correct_response
	   ,correct_flag

  FROM ODS_CPS.DAT.official_preact_results

 WHERE academic_term = 'Spring'
   AND year_id BETWEEN (@current_year_id - 2) AND @current_year_id
 UNION
SELECT year_id
	   ,local_id
	   ,academic_term
	   ,test_date
	   ,'ACT'
	   ,'Official'
	   ,test_subject
	   ,scale_score
	   ,subject_percentile
	   ,composite_score
	   ,composite_percentile
	   ,NULL -- Placeholder for lack of question-level data
	   ,NULL -- Placeholder for lack of question-level data
	   ,NULL -- Placeholder for lack of question-level data
	   ,NULL -- Placeholder for lack of question-level data

  FROM ODS_CPS.DAT.official_act_results
 
 WHERE academic_term = 'Spring'
   AND year_id BETWEEN (@current_year_id - 2) AND @current_year_id


 /*
 Union Official and unofficial results into single table
 */
IF OBJECT_ID('tempdb..#unioned_results') IS NOT NULL DROP TABLE #unioned_results
SELECT * 
  
  INTO #unioned_results 
  
  FROM #official_spring_raw_results
UNION
SELECT *

  FROM #unofficial_raw_results


/*
Join student info at time of test (grade/school etc) to raw results
*/
IF OBJECT_ID('tempdb..#final_results') IS NOT NULL DROP TABLE #final_results
SELECT u.year_id
	   ,u.local_id
	   ,s.StudentName AS scholar_name
	   ,u.academic_term
	   ,u.test_date
	   ,u.test_type
	   ,u.result_type
	   ,s.GradeLevel AS grade_level
	   ,u.test_subject
	   ,c.college_ready_score
	   ,u.scale_score
	   ,u.test_percentile
	   ,u.composite_score
	   ,u.composite_percentile
	   ,u.question_number
	   ,u.response
	   ,u.correct_response
	   ,u.correct_flag

  INTO #final_results

  FROM #unioned_results AS u

  JOIN #temp_vstudent AS s
	ON u.local_id = CAST(CAST(s.StudentID AS BIGINT) AS VARCHAR(10))
		AND u.test_date BETWEEN s.SchoolEntryDate AND s.SchoolExitDate

  JOIN ODS_CPS.DAT.EPAS_CR_lookup AS c
	ON u.test_type = c.test_type
		AND u.test_subject = c.test_subject
		AND (
				(
				  u.test_type = 'PreACT' AND s.GradeLevel = c.grade_level
				)
			OR
				u.test_type = 'ACT'
		    )


/*
Find goal score for each year_id by isolating fall results and applying uplift goal logic to them
*/
IF OBJECT_ID('tempdb..#unofficial_goal_scores') IS NOT NULL DROP TABLE #unofficial_goal_scores
SELECT r.year_id
	   ,r.local_id
	   ,r.grade_level
	   ,r.test_type
	   ,r.test_subject
	   ,r.college_ready_score

	   --This goal logic set by Chris Davis. May change in the future
	   ,CASE
			WHEN MAX(r.scale_score) IS NULL THEN NULL
			WHEN r.test_type = 'PreACT' AND MAX(r.scale_score) = 35 THEN MAX(r.scale_score)
			WHEN r.test_type = 'ACT' AND MAX(r.scale_score) = 36 THEN MAX(r.scale_score)
			WHEN MAX(r.scale_score) < r.college_ready_score THEN MAX(r.scale_score) + 2
			WHEN MAX(r.scale_score) >= r.college_ready_score THEN MAX(r.scale_score) + 1
		END AS goal_score

  INTO #unofficial_goal_scores

  FROM #final_results AS r

 WHERE r.academic_term = 'Fall'
   AND r.result_type = 'Unofficial'

GROUP BY r.year_id
		 ,r.grade_level
		 ,r.local_id
		 ,r.test_type
		 ,r.test_subject
		 ,r.college_ready_score


IF OBJECT_ID('tempdb..#join_goal_scores') IS NOT NULL DROP TABLE #join_goal_scores
SELECT u.year_id
	   ,u.local_id
	   ,u.scholar_name
	   ,u.academic_term
	   ,u.test_date
	   ,u.test_type
	   ,u.result_type
	   ,u.grade_level
	   ,u.test_subject
	   ,u.scale_score
	   ,u.college_ready_score

	   ,CASE
			WHEN u.scale_score IS NULL THEN NULL
			WHEN u.scale_score >= u.college_ready_score THEN 1.0
			WHEN u.scale_score < u.college_ready_score THEN 0.0
			ELSE NULL
		END AS college_ready_indicator

	   ,g.goal_score

	   ,CASE
			WHEN u.academic_term = 'Spring' AND u.scale_score >= g.goal_score THEN 1.0
			ELSE 0.0
		END AS goal_met_indicator

	   ,u.test_percentile
	   ,u.composite_score
	   ,u.composite_percentile
	   ,u.question_number
	   ,u.response
	   ,u.correct_response
	   ,u.correct_flag

  INTO #join_goal_scores

  FROM #final_results AS u

LEFT JOIN #unofficial_goal_scores AS g
	ON g.year_id = u.year_id
		AND g.local_id = u.local_id
		AND g.test_type = u.test_type
		AND g.test_subject = u.test_subject


/*
Join roster + demographic to scholar IDs for current teacher access
*/
IF OBJECT_ID('tempdb..#current_scholar_list') IS NOT NULL DROP TABLE #current_scholar_list
SELECT DISTINCT local_id

  INTO #current_scholar_list

  FROM #unofficial_goal_scores

 WHERE year_id = @current_year_id


IF OBJECT_ID('tempdb..#access_roster_and_demographic') IS NOT NULL DROP TABLE #access_roster_and_demographic
SELECT s.local_id
	   ,r.SchoolNameAbbreviated AS school_name

	   ,d.SPEDIndicator AS sped_indicator
	   ,d.[504Indicator] AS section_504_indicator
	   ,d.DyslexiaIndicator AS dyslexia_indicator
	   ,d.ESLIndicator AS esl_indicator
	   ,d.EconomicDisadvantagedIndicator AS economic_disadvantaged_indicator
	   ,d.race AS race

	   ,r.TeacherName AS teacher_name
	   ,r.UserName AS tableau_user_name
	   ,r.CourseSection AS course_section
	   ,r.CourseCreditType AS course_credit_type

 INTO #access_roster_and_demographic

 FROM #current_scholar_list AS s

 JOIN #temp_vroster AS r
   ON s.local_id = CAST(CAST(r.studentid AS BIGINT) AS VARCHAR(10))
	  AND @roster_date BETWEEN r.SchoolEntryDate AND r.SchoolExitDate
	  AND @roster_date BETWEEN r.StudentEnrollDate AND r.StudentExitDate 
	  AND @roster_date BETWEEN r.SectionStartDate AND r.SectionEndDate
	  AND r.SchoolNameAbbreviated NOT LIKE '%Summer%'

 JOIN ODS_CPS.dbo.fnDemographics(@roster_date) AS d
   ON s.local_id = CAST(CAST(d.StudentID AS BIGINT) AS VARCHAR(10))
		

 WHERE r.CourseCreditType NOT IN ('LC', 'NC')


/*
Join roster and demographics to scholar IDs for each year's snapshot date for current + historic teacher evaluation purposes
*/
IF OBJECT_ID('tempdb..#eval_roster_and_demographic') IS NOT NULL DROP TABLE #eval_roster_and_demographic
CREATE TABLE #eval_roster_and_demographic (
	local_id VARCHAR(10) NOT NULL
	,school_name VARCHAR(100)
	,year_id INT
	,sped_indicator INT NULL
	,section_504_indicator INT NULL
	,dyslexia_indicator INT NULL
	,esl_indicator INT NULL
	,economic_disadvantaged_indicator INT NULL
	,race VARCHAR(200)
	,teacher_name VARCHAR(200)
	,tableau_user_name VARCHAR(100)
	,course_section VARCHAR(100)
	,course_credit_type VARCHAR(10)
)

IF OBJECT_ID('tempdb..#scholars_by_year') IS NOT NULL DROP TABLE #scholars_by_year
SELECT DISTINCT
	   year_id
	   ,local_id

  INTO #scholars_by_year
	
  FROM #final_results


DECLARE eval_cursor CURSOR FOR 
	SELECT year_id
		   ,snapshot_date
	  
	  FROM @snapshot_dates

OPEN eval_cursor

FETCH NEXT FROM eval_cursor INTO @snapshot_year_id, @snapshot_date

WHILE @@FETCH_STATUS = 0
	BEGIN

		INSERT INTO #eval_roster_and_demographic
		SELECT s.local_id
			   ,r.SchoolNameAbbreviated AS school_name
			   ,s.year_id

			   ,d.SPEDIndicator AS sped_indicator
			   ,d.[504Indicator] AS section_504_indicator
			   ,d.DyslexiaIndicator AS dyslexia_indicator
			   ,d.ESLIndicator AS esl_indicator
			   ,d.EconomicDisadvantagedIndicator AS economic_disadvantaged_indicator
			   ,d.race AS race

			   ,r.TeacherName AS teacher_name
			   ,r.UserName AS tableau_user_name
			   ,r.CourseSection AS course_section
			   ,r.CourseCreditType AS course_credit_type

		  FROM #scholars_by_year AS s

		  JOIN #temp_vroster AS r
			ON s.local_id = CAST(CAST(r.StudentID AS BIGINT) AS VARCHAR(10))
				AND @snapshot_date BETWEEN r.SchoolEntryDate AND r.SchoolExitDate
				AND @snapshot_date BETWEEN r.StudentEnrollDate AND r.StudentExitDate
				AND @snapshot_date BETWEEN r.SectionStartDate AND r.SectionEndDate

		  JOIN ODS_CPS.dbo.fnDemographics(@snapshot_date) AS d
			ON s.local_id = CAST(CAST(d.StudentID AS BIGINT) AS VARCHAR(10))

		 WHERE s.year_id = @snapshot_year_id
		   AND r.CourseCreditType NOT IN ('LC', 'NC')

		FETCH NEXT FROM eval_cursor INTO @snapshot_year_id, @snapshot_date

	END

CLOSE eval_cursor
DEALLOCATE eval_cursor

/*
Join results to roster and demographics for current teacher access
*/
IF OBJECT_ID('tempdb..#access_results_roster_demographic') IS NOT NULL DROP TABLE #access_results_roster_demographic
SELECT r.year_id
	   ,r.local_id
	   ,r.scholar_name
	   ,rd.school_name
	   ,r.academic_term
	   ,r.test_date
	   ,r.test_type
	   ,r.result_type
	   ,r.grade_level
	   ,r.test_subject
	   ,r.scale_score
	   ,r.college_ready_score
	   ,r.college_ready_indicator
	   ,r.goal_score
	   ,r.goal_met_indicator
	   ,r.test_percentile
	   ,r.composite_score
	   ,r.composite_percentile
	   ,r.question_number
	   ,r.response
	   ,r.correct_response
	   ,r.correct_flag
	   ,rd.sped_indicator
	   ,rd.section_504_indicator
	   ,rd.dyslexia_indicator
	   ,rd.esl_indicator
	   ,rd.economic_disadvantaged_indicator
	   ,rd.race
	   ,rd.teacher_name
	   ,rd.tableau_user_name
	   ,rd.course_section
	   ,rd.course_credit_type
	   ,'1' AS roster_type_indicator --delineates records as belonging to the access roster for current teacher viewing

  INTO #access_results_roster_demographic

  FROM #join_goal_scores AS r

  JOIN #access_roster_and_demographic AS rd
	ON r.local_id = rd.local_id

/*
Join results to roster and demographics for evaluation purposes
*/
IF OBJECT_ID('tempdb..#eval_results_roster_demographic') IS NOT NULL DROP TABLE #eval_results_roster_demographic
SELECT r.year_id
	   ,r.local_id
	   ,r.scholar_name
	   ,rd.school_name
	   ,r.academic_term
	   ,r.test_date
	   ,r.test_type
	   ,r.result_type
	   ,r.grade_level
	   ,r.test_subject
	   ,r.scale_score
	   ,r.college_ready_score
	   ,r.college_ready_indicator
	   ,r.goal_score
	   ,r.goal_met_indicator
	   ,r.test_percentile
	   ,r.composite_score
	   ,r.composite_percentile
	   ,r.question_number
	   ,r.response
	   ,r.correct_response
	   ,r.correct_flag
	   ,rd.sped_indicator
	   ,rd.section_504_indicator
	   ,rd.dyslexia_indicator
	   ,rd.esl_indicator
	   ,rd.economic_disadvantaged_indicator
	   ,rd.race
	   ,rd.teacher_name
	   ,rd.tableau_user_name
	   ,rd.course_section
	   ,rd.course_credit_type
	   ,'0' AS roster_type_indicator --delineates records as belonging to the evaluation roster for teacher goals

  INTO #eval_results_roster_demographic

  FROM #join_goal_scores AS r

  JOIN #eval_roster_and_demographic AS rd
	ON r.local_id = rd.local_id
		AND r.year_id = rd.year_id


/*
Union roster types and insert into final table
*/
IF OBJECT_ID('ODS_CPS.DAT.EPAs_tableau_extract') IS NOT NULL DROP TABLE ODS_CPS.DAT.EPAs_tableau_extract
SELECT *
  INTO ODS_CPS.DAT.EPAs_tableau_extract
  FROM #access_results_roster_demographic
 UNION
SELECT *
  FROM #eval_results_roster_demographic

