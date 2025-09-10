-- steps_quontity   - кількість кроків ( проектів)
-- Total_investment - сума інвестицій, яку треба інвестувати

SELECT COMBINATION_NO,combination, sum(Z_stage_objective_functionid) RESULT_objectivefunction
FROM
  (
  SELECT
        cc.combination_no, cc.combination, cc.position_in_combination, cc.controlid, dyn.Z_stage_objective_functionid,u_max_total ,total_number_of_combination      
  FROM 
  (
  SELECT COMBINATION_NO,
         combination,
         ((count(*) over())/&steps_quontity) total_number_of_combination,
         LEVEL AS position_in_combination,
         TO_NUMBER(REGEXP_SUBSTR(c.combination, '[^,]+', 1, LEVEL)) AS CONTROLID,
         u_max_total
    FROM (
          select rownum COMBINATION_NO, innr1.*
           from
              (
              SELECT 
                       Bellman_steps_quontity, 
                       combination, 
                       u u_max_total
                  FROM (WITH recursive_cartesian(Bellman_steps_quontity, 
                                                 combination           ,
                                                 u) AS 
                                                  ( SELECT 1 AS Bellman_steps_quontity,
                                                            TO_CHAR(p.id) AS combination,
                                                            p.u_value u
                                                       FROM DP_U_CONTROL_dictionary p 
                                                       where id <> -9999999999
                                                     UNION ALL
                                                     SELECT Bellman_steps_quontity + 1,
                                                            combination || ',' || TO_CHAR(p.id),
                                                            u+u_value 
                                                       FROM recursive_cartesian, DP_U_CONTROL_dictionary p
                                                      WHERE Bellman_steps_quontity <= &steps_quontity-1
                                                        and id <> -9999999999 )
                         SELECT Bellman_steps_quontity, combination,u
                           FROM recursive_cartesian
                          WHERE Bellman_steps_quontity > &steps_quontity-1)
                       ORDER BY Combination  
                       )innr1
            WHERE u_max_total = &Total_investment      
          ) c
  CONNECT BY LEVEL <= REGEXP_COUNT(c.combination, ',') + 1
         AND PRIOR c.COMBINATION_NO = c.COMBINATION_NO
         AND PRIOR SYS_GUID() IS NOT NULL
         ) cc,
         dp_dynamicRule dyn
  WHERE  cc.controlid=dyn.u_controlid
    and  cc.position_in_combination=dyn.Stageid
    
    )
GROUP BY COMBINATION_NO,combination
ORDER BY RESULT_objectivefunction DESC



