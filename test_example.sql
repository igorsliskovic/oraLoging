create or replace package example_pkg is
  procedure p_main (i_input1 varchar2, i_raise_error number);
end example_pkg;
/

create or replace package body example_pkg is
  procedure p_main (i_input1 varchar2, i_raise_error number) is
  l_procedure_name varchar2(200) := 'p_main';
  l_loop pls_integer;
  begin
    cmu_error_log_pkg.p_add_log(i_message => i_input1);
    for i in 1..100 
    loop
      cmu_error_log_pkg.p_add_log(i_message=> i);
      l_loop := i;
      if i = 50 and i_raise_error = 1 then
        raise_application_error(-20001, 'custom error message goes here.');
      end if;
    end loop;
    cmu_error_log_pkg.p_add_log(i_message=> 'commit test');
  exception
    when others then
      cmu_error_log_pkg.p_handle_exception(i_message => 'input: ' || i_input1 || 
                                                        ' loop iteration: ' || l_loop
                                          ,i_sqlerrm => sqlerrm
                                          ,i_sqlcode => sqlcode);
      rollback;
      raise;
  end;
end example_pkg;
/

--start the procedure without log parameter setup 
--result: 0 rows inserted as there is no param for loging
begin 
  example_pkg.p_main(i_input1=>'test', i_raise_error=> 0);
end;
/
--start the procedure without log parameter setup with exception
--result: 1 master log inserted as error handling doesnt need parameters
begin 
  example_pkg.p_main(i_input1=>'test', i_raise_error=> 1);
end;
/

insert into cmu_parameters (cps_id
                           ,cps_parameter_name
                           ,cps_module_name
                           ,cps_value_number
                           ,cps_valid_from)
     values (1
            ,'LOG'
            ,'EXAMPLE_PKG.P_MAIN'
            ,1
            ,sysdate-1);
            
--start the procedure without log parameter setup
--result: 1 row inserted as we inserted the loging parameter
begin 
  example_pkg.p_main(i_input1=>'test', i_raise_error=> 0);
end;
/

--start the procedure without log parameter setup with exception
--result: 1 master log inserted as error handling doesnt need parameters
begin 
  example_pkg.p_main(i_input1=>'test', i_raise_error=> 1);
end; 
/

/* drop script:
drop package example_pkg;
delete from cmu_parameters where cps_module_name = 'EXAMPLE_PKG.P_MAIN'; commit;
select * from cmu_error_log;
select * from cmu_error_log_detail where ced_cel_id = 1;
*/
