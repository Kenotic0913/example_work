/*
Script: Create Official Pre/ACT results tables
Author: THarpin
Date: 4/25/19

***ASSUMPTIONS: 

			 1. Only one test form for PreACT per administration
					-- Currently, this procedure determines the correct answer to each test question by finding a random student who got the question correct, and inserting their answer into a "correct answer" column.
					   If there were to be multiple test forms, this procedure will throw an error.

			 2. ACT's College Readiness Standard Strands have not changed since previous administration
					-- The ACT part of the procedure loops over a unioned base table for each ACT subject, and has the names of the CRS strands hard coded into case statements depending on the loop count.
					   If the names of the CRS strands were to change, the results would be inaccurate.
*/

BEGIN TRY
	BEGIN TRAN epas_proc


/*==========================================================================================
OFFICIAL PREACT DATA TRANSFORM
==========================================================================================*/


/*
Step 1: Create the "result" table that will hold raw results
*/
IF OBJECT_ID('tempdb..#preact_raw') IS NOT NULL DROP TABLE #preact_raw
CREATE TABLE #preact_raw (
	row_id INT IDENTITY(1,1)
	,test_date DATE
	,local_id VARCHAR(10)
	,reading_scale_score INT
	,math_scale_score INT
	,english_scale_score INT
	,science_scale_score INT
	,composite_scale_score INT
	,reading_percentile INT
	,math_percentile INT
	,english_percentile INT
	,science_percentile INT
	,composite_percentile INT
	,reading_item_responses VARCHAR(100)
	,reading_response_vectors VARCHAR(100)
	,math_item_responses VARCHAR(100)
	,math_response_vectors VARCHAR(100)
	,english_item_responses VARCHAR(100)
	,english_response_vectors VARCHAR(100)
	,science_item_responses VARCHAR(100)
	,science_response_vectors VARCHAR(100)
	,table_of_origin VARCHAR(100)
)

INSERT INTO #preact_raw
SELECT expandedtestdate
	   ,studentid
	   ,scalescore_r
	   ,scalescore_m
	   ,scalescore_e
	   ,scalescore_s
	   ,scalescore_c
	   ,NULL
	   ,NULL
	   ,NULL
	   ,NULL
	   ,NULL
	   ,itemresponse_r
	   ,correctresponse_r
	   ,itemresponse_m
	   ,correctresponse_m
	   ,itemresponse_e
	   ,correctresponse_e
	   ,itemresponse_s
	   ,correctresponse_s
	   ,'ODS_CPS.FF.PreACT'

  FROM ODS_CPS.FF.PREACT
 UNION
SELECT LEFT(test_date, 4) + '-' + SUBSTRING(test_date, 5, 2) + '-' + RIGHT(test_date, 2) AS test_date
	   ,Student_ID_Number
	   ,test_scale_scores_reading
	   ,Test_Scale_Scores_Math
	   ,Test_Scale_Scores_English
	   ,Test_Scale_Scores_Science
	   ,Test_Scale_Scores_Composite
	   ,NULL
	   ,NULL
	   ,NULL
	   ,NULL
	   ,NULL
	   ,reading_item_responses
	   ,reading_response_vectors
	   ,math_item_responses
	   ,math_response_vectors
	   ,english_item_responses
	   ,english_response_vectors
	   ,science_item_responses
	   ,science_response_vectors
	   ,'ODS_CPS.FF.PreACT_Spring27'

  FROM ODS_CPS.FF.PreACT_Spring27
 UNION
SELECT test_date
	   ,student_id_number
	   ,test_scale_scores_reading
	   ,test_scale_scores_math
	   ,test_scale_scores_english
	   ,test_scale_scores_science
	   ,test_scale_scores_composite
	   ,natl_ntile_reading
	   ,natl_ntile_math
	   ,natl_ntile_english
	   ,natl_ntile_science
	   ,natl_ntile_composite
	   ,test_item_responses_reading
	   ,correct_response_vectors_reading
	   ,test_item_responses_math
	   ,correct_response_vectors_math
	   ,test_item_responses_english
	   ,correct_response_vectors_english
	   ,test_item_responses_science
	   ,correct_response_vectors_science
	   ,'ODS_CPS.FF.preact_28'

  FROM ODS_CPS.FF.preact_28


/*
Step 2: Transform test date/any other demographic info into data team variables (i.e. year id and term columns)
*/
IF OBJECT_ID('tempdb..#clean_demographics') IS NOT NULL DROP TABLE #clean_demographics

SELECT CASE
			WHEN MONTH(test_date) BETWEEN 8 AND 12 THEN YEAR(test_date) - 1990
			ELSE YEAR(test_date) - 1991
		END AS year_id

	   ,test_date

	   ,CASE
			WHEN MONTH(test_date) BETWEEN 8 AND 12 THEN 'Fall'
			WHEN MONTH(test_date) BETWEEN 1 AND 3 THEN 'Winter'
			WHEN MONTH(test_date) BETWEEN 4 AND 7 THEN 'Spring'
		END AS academic_term

	   ,local_id
	   ,reading_scale_score
	   ,math_scale_score
	   ,english_scale_score
	   ,science_scale_score
	   ,composite_scale_score
	   ,reading_percentile
	   ,math_percentile
	   ,english_percentile
	   ,science_percentile
	   ,composite_percentile
	   ,reading_item_responses
	   ,reading_response_vectors
	   ,math_item_responses
	   ,math_response_vectors
	   ,english_item_responses
	   ,english_response_vectors
	   ,science_item_responses
	   ,science_response_vectors


  INTO #clean_demographics

  FROM #preact_raw


/*
Step 3: Pivot Subject results by scholar
*/
--variables used to set up double loop, one for the test subject, the other for the individual questions on that subject test
DECLARE @question_counter INT
	    ,@subject_counter INT

SET @question_counter = 1
SET @subject_counter = 1

IF OBJECT_ID('tempdb..#preact_pivoted_results') IS NOT NULL DROP TABLE #preact_pivoted_results
CREATE TABLE #preact_pivoted_results (
	year_id INT
	,test_date DATE
	,academic_term VARCHAR(15)
	,local_id VARCHAR(10)
	,test_subject VARCHAR(25)
	,scale_score INT
	,natl_percentile INT
	,composite_scale_score INT
	,composite_percentile INT
	,question_number INT
	,response VARCHAR(1)
	,correct_flag INT
)
--5 subjects for 4 act sub tests and composite score
WHILE @subject_counter <= 5
	BEGIN
	--set to 100 to account for any number of questions on each subject test up to 100 (unlikely)
	WHILE @question_counter <= 100
		BEGIN

			INSERT INTO #preact_pivoted_results
			SELECT year_id
				   ,test_date
				   ,academic_term
				   ,local_id
				   --The outer loop will pull results for an individual subject test depending on its value, and put them next to this column that shows which subject its referring to
				   ,CASE
						WHEN @subject_counter = 1 THEN 'Reading'
						WHEN @subject_counter = 2 THEN 'Math'
						WHEN @subject_counter = 3 THEN 'English'
						WHEN @subject_counter = 4 THEN 'Science' 
						WHEN @subject_counter = 5 THEN 'Composite'
					END AS test_subject

				   ,CASE
						WHEN @subject_counter = 1 THEN reading_scale_score
						WHEN @subject_counter = 2 THEN math_scale_score
						WHEN @subject_counter = 3 THEN english_scale_score
						WHEN @subject_counter = 4 THEN science_scale_score
						WHEN @subject_counter = 5 THEN composite_scale_score
					END AS scale_score

				   ,CASE
						WHEN @subject_counter = 1 THEN reading_percentile
						WHEN @subject_counter = 2 THEN math_percentile
						WHEN @subject_counter = 3 THEN english_percentile
						WHEN @subject_counter = 4 THEN science_percentile
						WHEN @subject_counter = 5 THEN composite_percentile
					END AS natl_percentile

				   ,composite_scale_score
				   ,composite_percentile

				   ,CASE 
						WHEN @subject_counter BETWEEN 1 AND 4 THEN @question_counter
						WHEN @subject_counter = 5 THEN NULL
				    END AS question_num
					--Each inner loop deals with subject + question specific information. The SUBSTRING functions break out the item response columns by the index of each value
					--ex. The answer to question #1 for reading is in the first position of the item responses string, so we pull that out on loop 1
				   ,CASE 
						WHEN @subject_counter = 1 THEN CASE
															WHEN SUBSTRING(reading_item_responses, @question_counter, 1) = '' THEN NULL
															ELSE SUBSTRING(reading_item_responses, @question_counter, 1) 
													   END

						WHEN @subject_counter = 2 THEN CASE
															WHEN SUBSTRING(math_item_responses, @question_counter, 1) = '' THEN NULL
															ELSE SUBSTRING(math_item_responses, @question_counter, 1)
													   END

						WHEN @subject_counter = 3 THEN CASE
															WHEN SUBSTRING(english_item_responses, @question_counter, 1) = '' THEN NULL
															ELSE SUBSTRING(english_item_responses, @question_counter, 1)
													   END

						WHEN @subject_counter = 4 THEN CASE
															WHEN SUBSTRING(science_item_responses, @question_counter, 1) = '' THEN NULL
															ELSE SUBSTRING(science_item_responses, @question_counter, 1)
													   END

						WHEN @subject_counter = 5 THEN NULL
					END AS response
															
				   ,CASE
						WHEN @subject_counter = 1 THEN SUBSTRING(reading_response_vectors, @question_counter, 1) 
						WHEN @subject_counter = 2 THEN SUBSTRING(math_response_vectors, @question_counter, 1)
						WHEN @subject_counter = 3 THEN SUBSTRING(english_response_vectors, @question_counter, 1)
						WHEN @subject_counter = 4 THEN SUBSTRING(science_response_vectors, @question_counter, 1)
						WHEN @subject_counter = 5 THEN NULL
					END AS correct_flag
		
			  FROM #clean_demographics
			--This where clause ensures that the procedure doesnt look for answers to questions that dont exist on each subject test. When the question counter is larger than the length of the
			--possible answers column, the loop ends. 
			 WHERE CASE
						WHEN @subject_counter = 1 THEN LEN(reading_response_vectors)
						WHEN @subject_counter = 2 THEN LEN(math_response_vectors)
						WHEN @subject_counter = 3 THEN LEN(english_response_vectors)
						WHEN @subject_counter = 4 THEN LEN(science_response_vectors)
						WHEN @subject_counter = 5 THEN 1
					END >= @question_counter

			  SET @question_counter = @question_counter + 1

		 END

		 SET @question_counter = 1
		 SET @subject_counter = @subject_counter + 1
	END

SET @question_counter = 1
SET @subject_counter = 1


/*
Step 4: Enter correct answers for each test/question number into temp table for lookups.
		This process will break if we ever have >1 test booklet for PreACT. 
*/
IF OBJECT_ID('tempdb..#correct_responses') IS NOT NULL DROP TABLE #correct_responses
SELECT DISTINCT
	   year_id
	   ,test_date
	   ,test_subject
	   ,question_number
	   ,response AS correct_response

  INTO #correct_responses

  FROM #preact_pivoted_results

 WHERE correct_flag = 1


/*
Step 5: Join pivoted results to correct responses
*/
IF OBJECT_ID('tempdb..#correct_results') IS NOT NULL DROP TABLE #correct_results
SELECT p.year_id
	   ,p.test_date
	   ,p.academic_term
	   ,p.local_id
	   ,p.test_subject
	   ,p.scale_score
	   ,p.natl_percentile
	   ,p.composite_scale_score
	   ,p.composite_percentile
	   ,p.question_number
	   ,p.response
	   ,c.correct_response
	   ,p.correct_flag

  INTO #correct_results

  FROM #preact_pivoted_results AS p

LEFT JOIN #correct_responses AS c
	ON p.year_id = c.year_id
		AND p.test_date = c.test_date
		AND p.test_subject = c.test_subject
		AND p.question_number = c.question_number


/*
Step 6: Insert rows into official table
*/
IF OBJECT_ID('ODS_CPS.DAT.official_preact_results') IS NOT NULL DROP TABLE ODS_CPS.DAT.official_preact_results

SELECT * 
  INTO ODS_CPS.DAT.official_preact_results
  FROM #correct_results 


/*=========================================================================================
OFFICIAL ACT DATA TRANSFORM
=========================================================================================*/

/*
Step 1: Create raw result table for ACTs by year
*/

IF OBJECT_ID('tempdb..#act_raw') IS NOT NULL DROP TABLE #act_raw

CREATE TABLE #act_raw (
	test_date DATE
	,local_id VARCHAR(10)
	,reading_score INT
	,reading_rank INT
	,math_score INT
	,math_rank INT
	,english_score INT
	,english_rank INT
	,science_score INT
	,science_rank INT
	,composite_score INT
	,composite_rank	 INT
	,r_strand_1_score VARCHAR(3)
	,r_strand_1_cut   VARCHAR(3)
	,r_strand_2_score VARCHAR(3)
	,r_strand_2_cut   VARCHAR(3)
	,r_strand_3_score VARCHAR(3)
	,r_strand_3_cut   VARCHAR(3)
	,m_strand_1_score VARCHAR(3)
	,m_strand_1_cut   VARCHAR(3)
	,m_strand_2_score VARCHAR(3)
	,m_strand_2_cut   VARCHAR(3)
	,m_strand_3_score VARCHAR(3)
	,m_strand_3_cut   VARCHAR(3)
	,m_strand_4_score VARCHAR(3)
	,m_strand_4_cut   VARCHAR(3)
	,m_strand_5_score VARCHAR(3)
	,m_strand_5_cut   VARCHAR(3)
	,e_strand_1_score VARCHAR(3)
	,e_strand_1_cut   VARCHAR(3)
	,e_strand_2_score VARCHAR(3)
	,e_strand_2_cut   VARCHAR(3)
	,e_strand_3_score VARCHAR(3)
	,e_strand_3_cut   VARCHAR(3)
	,s_strand_1_score VARCHAR(3)
	,s_strand_1_cut   VARCHAR(3)
	,s_strand_2_score VARCHAR(3)
	,s_strand_2_cut   VARCHAR(3)
	,s_strand_3_score VARCHAR(3)
	,s_strand_3_cut   VARCHAR(3)
	,table_of_origin VARCHAR(100)
)

INSERT INTO #act_raw
SELECT expanded_test_date
	   ,local_id_number
	   ,reading_scale_scores
	   ,us_ranks_reading
	   ,mathematics_scale_scores
	   ,us_ranks_mathematics
	   ,english_scale_scores
	   ,us_ranks_english
	   ,science_scale_scores
	   ,us_ranks_science
	   ,composite_scale_scores
	   ,us_ranks_composite
	   ,reading_key_ideas_details_correct
	   ,reading_key_ideas_details_readiness_range_lower_bound
	   ,reading_craft_structure_correct
	   ,reading_craft_structure_readiness_range_lower_bound
	   ,reading_integration_of_knowledge_ideas_correct
	   ,reading_integration_of_knowledge_ideas_readiness_range_lower_bound
	   ,mathematics_number_quantity_correct
	   ,mathematics_number_quantity_readiness_range_lower_bound
	   ,mathematics_algebra_correct
	   ,mathematics_algebra_readiness_range_lower_bound
	   ,mathematics_functions_correct
	   ,mathematics_functions_readiness_range_lower_bound
	   ,mathematics_geometry_geometry_correct
	   ,mathematics_geometry_geometry_readiness_range_lower_bound
	   ,mathematics_statistics_probability_correct
	   ,mathematics_statistics_probability_readiness_range_lower_bound
	   ,english_production_of_writing_correct
	   ,english_production_of_writing_readiness_range_lower_bound
	   ,english_knowledge_of_language_correct
	   ,english_knowledge_of_language_readiness_range_lower_bound
	   ,english_conventions_of_standard_english_correct
	   ,english_conventions_of_standard_english_readiness_range_lower_bound
	   ,science_interpretation_of_data_correct
	   ,science_interpretation_of_data_readiness_range_lower_bound
	   ,science_scientific_investigation_correct
	   ,science_scientific_investigation_readiness_range_lower_bound
	   ,science_evaluation_of_models_inferences_experimental_results_correct
	   ,science_evaluation_of_models_inferences_experimental_results_readiness_range
	   ,'ODS_CPS.FF.ACT_26'

   FROM ODS_CPS.FF.ACT_26
  UNION
 SELECT expanded_test_date
	    ,local_id_number
	    ,reading_scale_scores
	    ,us_ranks_reading
	    ,mathematics_scale_scores
	    ,us_ranks_mathematics
	    ,english_scale_scores
	    ,us_ranks_english
	    ,science_scale_scores
	    ,us_ranks_science
	    ,composite_scale_scores
	    ,us_ranks_composite
	    ,reading_key_ideas_details_correct
	    ,reading_key_ideas_details_readiness_range_lower_bound
	    ,reading_craft_structure_correct
	    ,reading_craft_structure_readiness_range_lower_bound
	    ,reading_integration_of_knowledge_ideas_correct
	    ,reading_integration_of_knowledge_ideas_readiness_range_lower_bound
	    ,mathematics_number_quantity_correct
	    ,mathematics_number_quantity_readiness_range_lower_bound
	    ,mathematics_algebra_correct
	    ,mathematics_algebra_readiness_range_lower_bound
	    ,mathematics_functions_correct
	    ,mathematics_functions_readiness_range_lower_bound
	    ,mathematics_geometry_geometry_correct
	    ,mathematics_geometry_geometry_readiness_range_lower_bound
	    ,mathematics_statistics_probability_correct
	    ,mathematics_statistics_probability_readiness_range_lower_bound
	    ,english_production_of_writing_correct
	    ,english_production_of_writing_readiness_range_lower_bound
	    ,english_knowledge_of_language_correct
	    ,english_knowledge_of_language_readiness_range_lower_bound
	    ,english_conventions_of_standard_english_correct
	    ,english_conventions_of_standard_english_readiness_range_lower_bound
	    ,science_interpretation_of_data_correct
	    ,science_interpretation_of_data_readiness_range_lower_bound
	    ,science_scientific_investigation_correct
	    ,science_scientific_investigation_readiness_range_lower_bound
	    ,science_evaluation_of_models_inferences_experimental_results_correct
	    ,science_evaluation_of_models_inferences_experimental_results_readiness_range
		,'ODS_CPS.FF.ACT_27'

   FROM ODS_CPS.FF.ACT_27
  UNION
 SELECT expanded_test_date
	   ,local_id
	   ,reading_score
	   ,us_rank_scale_score_reading
	   ,math_score
	   ,us_rank_scale_score_mathematics
	   ,english_score
	   ,us_rank_scale_score_english
	   ,science_score
	   ,us_rank_scale_score_science
	   ,composite_score
	   ,us_rank_scale_score_composite
	   ,percentage_correct_reading_key_ideas_and_details
	   ,readiness_range_reading_key_ideas_and_details
	   ,percentage_correct_reading_craft_and_structure
	   ,readiness_range_reading_craft_and_structure
	   ,percentage_correct_reading_integration_of_knowledge_and_ideas
	   ,readiness_range_reading_integration_of_knowledge_and_ideas
	   ,percentage_correct_math_number_and_quantity
	   ,readiness_range_math_number_and_quantity
	   ,percentage_correct_math_algebra
	   ,readiness_range_math_algebra
	   ,percentage_correct_math_functions
	   ,readiness_range_math_functions
	   ,percentage_correct_math_geometry
	   ,readiness_range_math_geometry
	   ,percentage_correct_math_statistics_and_probablility
	   ,readiness_range_math_statistics_and_probablility
	   ,percentage_correct_english_production_of_writing
	   ,readiness_range_english_production_of_writing
	   ,percentage_correct_english_knowledge_of_language
	   ,readiness_range_english_knowledge_of_language
	   ,percentage_correct_english_convention_of_standard_english
	   ,readiness_range_english_convention_of_standard_english
	   ,percentage_correct_science_integration_of_data
	   ,readiness_range_science_integration_of_data
	   ,percentage_correct_science_scientific_investigation
	   ,readiness_range_science_scientific_investigation
	   ,percentage_correct_science_evaluation_of_models_inferences_and_experimental_results
	   ,readiness_range_science_evaluation_of_models_inferences_and_experimental_results
	   ,'ODS_CPS.FF.ACT_28'

  FROM ODS_CPS.FF.ACT_28

/*
Step 2: Transform test date into year id and academic term
*/
IF OBJECT_ID('tempdb..#act_dates') IS NOT NULL DROP TABLE #act_dates

SELECT CASE
			WHEN MONTH(test_date) BETWEEN 8 AND 12 THEN YEAR(test_date) - 1990
			ELSE YEAR(test_date) - 1991
		END AS year_id

	   ,test_date

	   ,CASE
			WHEN MONTH(test_date) BETWEEN 8 AND 12 THEN 'Fall'
			WHEN MONTH(test_date) BETWEEN 1 AND 3 THEN 'Winter'
			WHEN MONTH(test_date) BETWEEN 4 AND 7 THEN 'Spring'
		END AS academic_term

	   ,local_id
	   ,reading_score
	   ,reading_rank
	   ,math_score
	   ,math_rank
	   ,english_score
	   ,english_rank
	   ,science_score
	   ,science_rank
	   ,composite_score
	   ,composite_rank
	   ,r_strand_1_score
	   ,r_strand_1_cut
	   ,r_strand_2_score
	   ,r_strand_2_cut
	   ,r_strand_3_score
	   ,r_strand_3_cut
	   ,m_strand_1_score
	   ,m_strand_1_cut
	   ,m_strand_2_score
	   ,m_strand_2_cut
	   ,m_strand_3_score
	   ,m_strand_3_cut
	   ,m_strand_4_score
	   ,m_strand_4_cut
	   ,m_strand_5_score
	   ,m_strand_5_cut
	   ,e_strand_1_score
	   ,e_strand_1_cut
	   ,e_strand_2_score
	   ,e_strand_2_cut
	   ,e_strand_3_score
	   ,e_strand_3_cut
	   ,s_strand_1_score
	   ,s_strand_1_cut
	   ,s_strand_2_score
	   ,s_strand_2_cut
	   ,s_strand_3_score
	   ,s_strand_3_cut
	   ,table_of_origin

  INTO #act_dates

  FROM #act_raw

/*
Step 3: Pivot results by test subject
		This section works the same way as the PreACT nested loop, but is organized by subject and CRS Strand rather than subject and question number, because the ACT org
		doesn't release question-level data to us for the official ACT
*/
DECLARE @loop_counter INT
SET @loop_counter = 1

IF OBJECT_ID('tempdb..#pivoted_act_results') IS NOT NULL DROP TABLE #pivoted_act_results

CREATE TABLE #pivoted_act_results (
	year_id INT
	,test_date DATE
	,academic_term VARCHAR(15)
	,local_id VARCHAR(10)
	,test_subject VARCHAR(25)
	,scale_score INT
	,subject_percentile INT
	,composite_score INT
	,composite_percentile INT
	,CRS_strand VARCHAR(100)
	,CRS_strand_score INT
	,CRS_strand_readiness_cut INT
)
WHILE @subject_counter <= 5
	BEGIN
	WHILE @loop_counter <= 5
		BEGIN
			INSERT INTO #pivoted_act_results
			SELECT year_id
				   ,test_date
				   ,academic_term
				   ,local_id

				   ,CASE
						WHEN @subject_counter = 1 THEN 'Reading'
						WHEN @subject_counter = 2 THEN 'Math'
						WHEN @subject_counter = 3 THEN 'English'
						WHEN @subject_counter = 4 THEN 'Science'
						WHEN @subject_counter = 5 THEN 'Composite'
					END AS test_subject

				   ,CASE
						WHEN @subject_counter = 1 THEN reading_score
						WHEN @subject_counter = 2 THEN math_score
						WHEN @subject_counter = 3 THEN english_score
						WHEN @subject_counter = 4 THEN science_score
						WHEN @subject_counter = 5 THEN composite_score
					END AS scale_score

				   ,CASE
						WHEN @subject_counter = 1 THEN reading_rank
						WHEN @subject_counter = 2 THEN math_rank
						WHEN @subject_counter = 3 THEN english_rank
						WHEN @subject_counter = 4 THEN science_rank
						WHEN @subject_counter = 5 THEN composite_rank
					END AS subject_percentile

				   ,composite_score
				   ,composite_rank


				   ,CASE
						WHEN @subject_counter = 1 THEN CASE
															WHEN @loop_counter = 1 THEN 'Key Ideas and Details'
															WHEN @loop_counter = 2 THEN 'Craft and Structure'
															WHEN @loop_counter = 3 THEN 'Integration of Knowledge and Ideas'
														END
						WHEN @subject_counter = 2 THEN CASE
															WHEN @loop_counter = 1 THEN 'Number and Quantity'
															WHEN @loop_counter = 2 THEN 'Algebra'
															WHEN @loop_counter = 3 THEN 'Functions'
															WHEN @loop_counter = 4 THEN 'Geometry'
															WHEN @loop_counter = 5 THEN 'Statistics and Probability'
														END
						WHEN @subject_counter = 3 THEN CASE
															WHEN @loop_counter = 1 THEN 'Production of Writing'
															WHEN @loop_counter = 2 THEN 'Knowledge of Language'
															WHEN @loop_counter = 3 THEN 'Conventions of Standard English...'
														END
						WHEN @subject_counter = 4 THEN CASE
															WHEN @loop_counter = 1 THEN 'Interpretation of Data'
															WHEN @loop_counter = 2 THEN 'Scientific Investigation'
															WHEN @loop_counter = 3 THEN 'Evaluation of Models...'
														END
						WHEN @subject_counter = 5 THEN NULL
					END AS CRS_strand


				   ,CASE
						WHEN @subject_counter = 1 THEN CASE 
															WHEN @loop_counter = 1 THEN r_strand_1_score
															WHEN @loop_counter = 2 THEN r_strand_2_score
															WHEN @loop_counter = 3 THEN r_strand_3_score
														END
						WHEN @subject_counter = 2 THEN CASE
															WHEN @loop_counter = 1 THEN m_strand_1_score
															WHEN @loop_counter = 2 THEN m_strand_2_score
															WHEN @loop_counter = 3 THEN m_strand_3_score
															WHEN @loop_counter = 4 THEN m_strand_4_score
															WHEN @loop_counter = 5 THEN m_strand_5_score
														END
						WHEN @subject_counter = 3 THEN CASE
															WHEN @loop_counter = 1 THEN e_strand_1_score
															WHEN @loop_counter = 2 THEN e_strand_2_score
															WHEN @loop_counter = 3 THEN e_strand_3_score
														END
						WHEN @subject_counter = 4 THEN CASE
															WHEN @loop_counter = 1 THEN s_strand_1_score
															WHEN @loop_counter = 2 THEN s_strand_2_score
															WHEN @loop_counter = 3 THEN s_strand_3_score
														END
						WHEN @subject_counter = 5 THEN NULL
					END AS CRS_strand_score

				   ,CASE 
						WHEN @subject_counter = 1 THEN CASE 
															WHEN @loop_counter = 1 THEN r_strand_1_cut
															WHEN @loop_counter = 2 THEN r_strand_2_cut
															WHEN @loop_counter = 3 THEN r_strand_3_cut
														END
						WHEN @subject_counter = 2 THEN CASE
															WHEN @loop_counter = 1 THEN m_strand_1_cut
															WHEN @loop_counter = 2 THEN m_strand_2_cut
															WHEN @loop_counter = 3 THEN m_strand_3_cut
															WHEN @loop_counter = 4 THEN m_strand_4_cut
															WHEN @loop_counter = 5 THEN m_strand_5_cut
														END
						WHEN @subject_counter = 3 THEN CASe
															WHEN @loop_counter = 1 THEN e_strand_1_cut
															WHEN @loop_counter = 2 THEN e_strand_2_cut
															WHEN @loop_counter = 3 THEN e_strand_3_cut
														END
						WHEN @subject_counter = 4 THEN CASE
															WHEN @loop_counter = 1 THEN s_strand_1_cut
															WHEN @loop_counter = 2 THEN s_strand_2_cut
															WHEN @loop_counter = 3 THEN s_strand_3_cut
														END
						WHEN @subject_counter = 5 THEN NULL
					END AS CRS_strand_readiness_cut

		
			  FROM #act_dates

			 WHERE CASE
						WHEN @subject_counter = 1 AND reading_score IS NOT NULL THEN 3
						WHEN @subject_counter = 2 AND math_score IS NOT NULL THEN 5
						WHEN @subject_counter = 3 AND english_score IS NOT NULL THEN 3
						WHEN @subject_counter = 4 AND science_score IS NOT NULL THEN 3
						WHEN @subject_counter = 5 THEN 1
						ELSE NULL
					END >= @loop_counter

			  SET @loop_counter = @loop_counter + 1
		END

		SET @loop_counter = 1
		SET @subject_counter = @subject_counter + 1
	END

/*
Step 4: Insert results into official table
*/

IF OBJECT_ID('ODS_CPS.DAT.official_act_results') IS NOT NULL DROP TABLE ODS_CPS.DAT.official_act_results

SELECT *
  INTO ODS_CPS.DAT.official_act_results
  FROM #pivoted_act_results



/*=====================================================================
Error Handling
=====================================================================*/

/*
The following statements check to make sure that there is only one correct answer per test/question on PreACT results. If it finds more than one distinct correct answer, it throws an error, and rolls back the procedure.
*/

DECLARE @throw_state INT
SET @throw_state = 1

IF OBJECT_ID('tempdb..#preact_errors') IS NOT NULL DROP TABLE #preact_errors
SELECT COUNT(correct_response) AS correct_response_count
	   ,year_id
	   ,test_date
	   ,test_subject
	   ,question_number

  INTO #preact_errors

  FROM #correct_responses

GROUP BY year_id, test_date, test_subject, question_number


IF @throw_state != (SELECT MAX(correct_response_count)

					 FROM #preact_errors)
				    THROW 500001, '', 1

ELSE
COMMIT TRAN epas_proc
END TRY

BEGIN CATCH
	ROLLBACK TRAN epas_proc
	;THROW 500001, 'PreACT results contain more than one correct answer for a single question. This indicates assumption #1 of this procedure has been broken. 
If more than one test form for the most recent PreACT administration exists, this will also break the eduphoria.dat.epas_crs_tagging table, because it joins on academic term rather than test date.', 1
END CATCH



END