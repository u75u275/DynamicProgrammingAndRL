create or replace package DP_Bellman_InvestPlan is
/*v.6 09.09.2025 15:05*/

   procedure initialize;
 
   procedure PriorStep;
   
   procedure ConditionalOptimizationStep;

   procedure FullOptimizationStep;
 
   function StopCondition(x_current_controlid in DP_U_CONTROL_DICTIONARY.ID%TYPE,current_stageid DP_STAGE_PROJECT.id%TYPE) RETURN number; 

   function CalcCondOptimalValue( Z_id in DP_Z_STAGE_OBJECTIVE_FUNCTION_DICTIONARY.id%TYPE, 
                                  B_id in DP_Z_STAGE_OBJECTIVE_FUNCTION_DICTIONARY.id%TYPE ) return NUMBER;

   function State_transition_function(x_prev_stage_id in DP_U_CONTROL_DICTIONARY.ID%TYPE,
                                     u_control_id    in DP_U_CONTROL_DICTIONARY.ID%TYPE) RETURN DP_U_CONTROL_DICTIONARY.ID%TYPE;
                                  
end DP_Bellman_InvestPlan;
/
create or replace package body DP_Bellman_InvestPlan is

  g_LastStage             DP_STAGE_PROJECT.id%TYPE;
  g_FulFillment_Controlid DP_u_control_dictionary.u_Value%TYPE;

  cFINISHSTATE CONSTANT number(10) := 9999999999;
  cINITIALSTATE CONSTANT number(10) :=  -9999999999;

  procedure initialize is
  begin
    delete from dp_bellmanprocesscalculation;
    delete from dp_b_value_function;
    
    select max(id) into g_LastStage from DP_STAGE_PROJECT  where DESCRIPTION <> 'FINISH STATE';

    select id
      into g_FulFillment_Controlid
      from DP_u_control_dictionary
     where u_value = (select max(u_value) from DP_u_control_dictionary);
    
    
    insert into dp_bellmanprocesscalculation
      (ID,
       STAGEID,
       x_current_controlid,
       U_CONTROLID,
       Z_STAGE_OBJECTIVE_FUNCTIONID,
       B_VALUE_FUNCTIONID,
       description)
    values
      (0, 0, 0, 0, 0, cINITIALSTATE, 'INITIAL VALUE');

    insert into dp_bellmanprocesscalculation
      (id,
       stageid,
       x_current_controlid,
       x_prev_controlid,
       u_controlid,
       z_stage_objective_functionid,
       b_value_functionid,
       description)
    values
      (-1, DP_Bellman_InvestPlan.g_LastStage+1, cINITIALSTATE,cINITIALSTATE, 0, 0, cFINISHSTATE, 'FINISH STATE');
     

      insert into dp_b_value_function (STAGEID, X_STATEID, ID, DESCRIPTION, B_STAGE_OBJECTIVE_FUNCTIONID, U_CONTROLID, THREDNO)
      values (0, 0, cINITIALSTATE, 'INITIAL VALUE', cINITIALSTATE, null, null);

      insert into dp_b_value_function (STAGEID, X_STATEID, ID, DESCRIPTION, B_STAGE_OBJECTIVE_FUNCTIONID, U_CONTROLID, THREDNO)
      values (DP_Bellman_InvestPlan.g_LastStage+1, 0, cFINISHSTATE, 'FINISH STATE', cFINISHSTATE, null, null);
      
      commit;
      
  end;

  procedure PriorStep is
  begin
  for rec in (select ID stageid from DP_STAGE_PROJECT where ID >0 order by id) loop
     insert into dp_bellmanprocesscalculation(
                                            stageid,
                                            x_current_controlid,
                                            x_prev_controlid,
                                            u_controlid,
                                            z_stage_objective_functionid,
                                            b_value_functionid)
    SELECT stageid, 
           x_current, 
           x_prev,
           u, 
           z, 
           B
      FROM (
           select rec.stageid,
                   bellman.x_current_controlid x_prev,
                   rul.u_controlid u,
                   State_transition_function(x_prev_stage_id => bellman.x_current_controlid,
                                             u_control_id    => rul.u_controlid) x_current,
                   rul.z_stage_objective_functionid z,
                   cINITIALSTATE B
              from dp_dynamicrule rul, ( select distinct x_current_controlid 
                                           from dp_bellmanprocesscalculation 
                                          where stageid = (rec.stageid - 1) )bellman
             where rul.stageid = rec.stageid
          order by x_prev, u           
               )
     WHERE x_current IS NOT NULL
      and  DP_Bellman_InvestPlan.StopCondition(x_current_controlid => x_current, current_stageid => stageid) = 1
     ORDER BY x_prev, u;
     commit;
  end loop; 
 end;  
    
 procedure ConditionalOptimizationStep is
 begin
    for rec in (select id stageid from dp_stage_project where id <=g_LastStage and id <>0  order by id desc)   loop
    Merge into dp_bellmanprocesscalculation dest
         using (
    select bcur.id bcurid,
           bcur.stageid,
           bcur.x_prev_controlid,
           bcur.u_controlid,
           bcur.x_current_controlid,
           bcur.z_stage_objective_functionid curr_Z,
           bnext.b_value_functionid next_B, 
           DP_Bellman_InvestPlan.CalcCondOptimalValue( bcur.z_stage_objective_functionid, bnext.b_value_functionid) B_id
      from ( select * from dp_bellmanprocesscalculation where stageid = rec.stageid) bcur,
           ( 
           select zd1.id b_value_functionid, a.x_prev_controlid
           from
           (
            select  MAX(zd.z_income_value) b_value,
                    decode(n.x_prev_controlid,-9999999999,g_FulFillment_Controlid,n.x_prev_controlid) x_prev_controlid
              from dp_bellmanprocesscalculation n, 
                   DP_Z_STAGE_OBJECTIVE_FUNCTION_DICTIONARY zd 
              where stageid  = rec.stageid+1 and n.b_value_functionid=zd.id
              group by decode(n.x_prev_controlid,-9999999999,g_FulFillment_Controlid,n.x_prev_controlid)  
                      ) a,
              DP_Z_STAGE_OBJECTIVE_FUNCTION_DICTIONARY zd1
             where zd1.z_income_value=a.b_value  and  zd1.id not in (-9999999999,9999999999)
              ) bnext
      where bcur.x_current_controlid= bnext.x_prev_controlid    
       ) src
    on (dest.id=src.bcurid)   
    when matched then 
         update set dest.b_value_functionid=B_id,
                    dest.description ='row has been processed';
    end loop; 
    commit;
 end;
 
  procedure FullOptimizationStep is
  begin
     FOR rec IN  (select id stageid from dp_stage_project where id <=g_LastStage and id <>0  order by id ) LOOP
       
        insert into dp_b_value_function(stageid,b_stage_objective_functionid,u_controlid,x_stateid,thredno,description)
        select A.stageid,
               A.b_value_functionid,
               A.u_controlid,
               A.x_current_controlid,
               case when rec.stageid =1 then rownum 
                    else bres.thredno
                end  thredno,     
               'calculated' description
          from
            (
              SELECT
                stageid,
                x_prev_controlid,
                u_controlid,      
                x_current_controlid,
                b_value_functionid
              FROM (SELECT
                      b.stageid,
                      b.b_value_functionid,
                      b.u_controlid,
                      b.x_current_controlid,        
                      b.x_prev_controlid,
                      z.z_income_value,
                      MAX(z.z_income_value) OVER (PARTITION BY b.stageid,b.x_prev_controlid) AS max_z
                    FROM dp_bellmanprocesscalculation b
                    JOIN dp_z_stage_objective_function_dictionary z
                      ON z.id = b.b_value_functionid) 
              WHERE z_income_value = max_z  and stageid=rec.stageid
              order by stageid,x_prev_controlid,u_controlid
            ) A,
            (select * from dp_b_value_function bres where bres.stageid=rec.stageid-1) bres
        WHERE bres.x_stateid=A.x_prev_controlid;
        
     END LOOP;
     commit;
  end; 
  
  function StopCondition(x_current_controlid in DP_U_CONTROL_DICTIONARY.ID%TYPE,
                         current_stageid DP_STAGE_PROJECT.id%TYPE)
    RETURN number is
  begin
  
    case
      when current_stageid = G_LastStage then
        if x_current_controlid = g_FulFillment_Controlid then
          return 1;
        else
          return 0;
        end if;
      else
        return 1;
    end case;
  end;
  
  function CalcCondOptimalValue( Z_id in DP_Z_STAGE_OBJECTIVE_FUNCTION_DICTIONARY.id%TYPE, 
                                 B_id in DP_Z_STAGE_OBJECTIVE_FUNCTION_DICTIONARY.id%TYPE ) return NUMBER is
      l_hlp DP_Z_STAGE_OBJECTIVE_FUNCTION_DICTIONARY.id%TYPE;
  begin

     select a.id
     INTO   l_hlp
     FROM DP_Z_STAGE_OBJECTIVE_FUNCTION_DICTIONARY a,
          ( select dict1.z_income_value+dict2.z_income_value  z_income_value 
              from DP_Z_STAGE_OBJECTIVE_FUNCTION_DICTIONARY dict1, 
                   DP_Z_STAGE_OBJECTIVE_FUNCTION_DICTIONARY dict2 
             where dict1.id=Z_id and dict2.id=B_id) b
     WHERE a.z_income_value = b.z_income_value
       and a.id not in (cFINISHSTATE,cINITIALSTATE) ;             
     return l_hlp;     
  end;        
  
  function State_transition_function(x_prev_stage_id in DP_U_CONTROL_DICTIONARY.ID%TYPE,
                                     u_control_id    in DP_U_CONTROL_DICTIONARY.ID%TYPE)
    RETURN DP_U_CONTROL_DICTIONARY.ID%TYPE is
    l_x_new_state_id DP_U_CONTROL_DICTIONARY.ID%TYPE;
  begin
    select dic.id 
      into l_x_new_state_id
     from  dp_u_control_dictionary dic,
           (select u_value x  from  dp_u_control_dictionary where id = x_prev_stage_id) prev,
           (select u_value u from  dp_u_control_dictionary where id = u_control_id) ctrl
      where dic.u_value=prev.X+ctrl.U;
   return l_x_new_state_id;
end;
                             

end DP_Bellman_InvestPlan;
/
