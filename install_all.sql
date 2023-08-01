create table cmu_error_log 
(
  cel_id               number(30) primary key,
  cel_package          varchar2(200),
  cel_time             timestamp(6),
  cel_message_type     varchar2(10),
  cel_ora_session_info varchar2(4000) 
);

create table cmu_error_log_detail 
(
  ced_id                  number(30) primary key,
  ced_name                varchar2(200),
  ced_time                timestamp(6),
  ced_message_type        varchar2(10),
  ced_cel_id              number(30),
  ced_message             varchar2(4000),
  ced_e_sqlerrm           varchar2(200),
  ced_e_sqlcode           number(30),
  ced_e_error_stack       varchar2(1000),
  ced_e_error_backtrace   varchar2(1000),
  ced_e_error_call_stack  varchar2(1000),
  
  constraint fk_ced_cps foreign key (ced_cel_id)
    references cmu_error_log(cel_id)
);

create table cmu_parameters 
(
  cps_id             number(30) primary key,
  cps_parameter_name varchar2(200),
  cps_module_name    varchar2(200),
  cps_value_date     date,
  cps_value_text     varchar2(500),
  cps_value_number   number(20,2),
  cps_valid_from     date not null,
  cps_valid_to       date
);

create table cmu_messages 
(
  cms_id         number(30) primary key,
  cms_message    varchar2(400),
  cms_code       number(10),
  cms_valid_from date not null,
  cms_valid_to   date
);

create sequence cmu_error_log_seq start with 1 increment by 1;
create sequence cmu_error_log_detail_seq start with 1 increment by 1;
create sequence cmu_parameters_seq start with 1 increment by 1;
create sequence cmu_messages_seq start with 1 increment by 1;

CREATE OR REPLACE package cmu_error_log_pkg as
  pragma serially_reusable;

  /**
   * naziv     : cmu_error_log_pkg
   * opis      : Error handling and loging package 
   * autor     : Igor Sliskovic 
   */
  subtype message_nn is cmu_error_log_detail.ced_message%type not null;
  
 /**
  * name       : p_add_log
  * desc       : Main procedure for loging
  * author     : Igor Sliskovic 
  *
  * requires   : Message that user wants to log
  *
  * guarantees : Will add the message to the log detail table and connect it to master log
  *
  * parameter  : i_message - Message text
  */
  procedure p_add_log (i_message in message_nn);


 /**
  * name       : p_handle_exception
  * desc       : Procedura za obradu gresaka
  * author     : Igor Sliskovic 
  *
  * requires   : Message text, sqlcode and sqlerrm
  *
  * guarantees : Will log message regardless if the paramater for log is on or not
  *
  * parameter  : i_message - Message text
  * parameter  : i_sqlerrm - SQLERRM oracle function
  * parameter  : i_sqlcode - SQLCODE oracle function
  *
  * aditional  : the package initializes master log row and marks it as Error, aditional
  *              messages are added to the detail table
  */
  procedure p_handle_exception (i_message   in message_nn
                               ,i_sqlerrm   in varchar2
                               ,i_sqlcode   in number);
end cmu_error_log_pkg;
/

create or replace package body cmu_error_log_pkg as
  pragma serially_reusable;
  g_user        varchar2 (100);
  g_package     varchar2 (100);
  g_line_code   number;
  g_object_type varchar2 (100);
  g_do_i_log    pls_integer;
  g_cel_id      pls_integer;

 /**
  * name       : f_check_loging_enabled
  * desc       : Funkcija to check if log paramater is set
  * author     : Igor Sliskovic 
  *
  * requires   : Parameter name and module that is calling the procedure
  *
  * guarantees : Returns value for number parameter in parameters table for given module
  *
  * parameter  : i_parameter_name - Parameter name
  * parameter  : i_module_name    - Module name
  */
  function f_check_loging_enabled(i_parameter_name in cmu_parameters.cps_parameter_name%type default 'LOG'
                                  ,i_module_name in cmu_parameters.cps_module_name%type)
    return number is
    l_return cmu_parameters.cps_value_number%type;
  begin
    select cps.cps_value_number
      into l_return
      from cmu_parameters cps
     where cps.cps_parameter_name = i_parameter_name
       and cps.cps_module_name = i_module_name
       and sysdate between cps.cps_valid_from and nvl (cps.cps_valid_to, sysdate);

    return l_return;
  exception
    when others then
      return null;
  end;
 /**
  * naziv     : p_check_log
  * opis      : Check if loging is enabled and store that information into global varible
  * autor     : Igor Sliskovic 
  *
  * zahtjeva  :
  *
  * garantira : Set log flag into global variable
  *
  * aditional : If the package.procedure is not in the parameter list the log will not work.
  *             reason for this is to not query the parameter table constantly.
  */
  procedure p_check_log is
  begin
    g_do_i_log := f_check_loging_enabled (i_parameter_name => 'LOG', i_module_name => g_package);

    if (g_do_i_log is null) then
      g_do_i_log := 0;
    end if;
  exception
    when others then
      g_do_i_log := 0;
  end p_check_log;

 /**
  * name       : p_add_master_record
  * desc       : Procedure to add one master log record per a call
  * author     : Igor Sliskovic 
  *
  * requires   : Message type, default is log
  *
  * guarantees : Will create one record in master log table for one call
  *
  * parameter  : i_message_type - Message type
  */
  procedure p_add_master_record (i_message_type in varchar2 default 'Log') is
    pragma autonomous_transaction;
  begin
    insert /*+ APPEND */
          into  cmu_error_log (cel_id
                              ,cel_package
                              ,cel_time
                              ,cel_message_type
                              ,cel_ora_session_info)
           values (
                    cmu_error_log_seq.nextval
                   ,g_package
                   ,systimestamp
                   ,i_message_type
                   ,   'userenv -> session_user: '
                    || sys_context ('userenv', 'session_user')
                    || ', host: '
                    || sys_context ('userenv', 'host')
                    || ', ip_address: '
                    || sys_context ('userenv', 'ip_address')
                    || ', os_user: '
                    || sys_context ('userenv', 'os_user')
                    || ', session_userid: '
                    || sys_context ('userenv', 'session_userid')
                    || ', terminal: '
                    || sys_context ('userenv', 'terminal'))
      returning cel_id
           into g_cel_id;

    commit;
  end p_add_master_record;

 /**
  * name       : p_add_log
  * desc       : Main procedure for loging
  * author     : Igor Sliskovic 
  *
  * requires   : Message that user wants to log
  *
  * guarantees : Will add the message to the log detail table and connect it to master log
  *
  * parameter  : i_message - Message text
  */
  procedure p_add_log (i_message in message_nn) is
    pragma autonomous_transaction;
    l_log number;
  begin
    if (g_do_i_log = 1) then
      owa_util.who_called_me (owner      => g_user
                             ,name       => g_package
                             ,lineno     => g_line_code
                             ,caller_t   => g_object_type);
      dbms_application_info.set_module (g_package, 'p_add_log');

      insert /*+ APPEND */
            into  cmu_error_log_detail (ced_id
                                       ,ced_message
                                       ,ced_time
                                       ,ced_name
                                       ,ced_cel_id
                                       ,ced_message_type)
           values (cmu_error_log_detail_seq.nextval
                  ,i_message
                  ,systimestamp
                  ,g_package
                  ,g_cel_id
                  ,'L');

      commit;
    end if;
  end p_add_log;

 /**
  * name       : p_handle_exception
  * desc       : Procedura za obradu gresaka
  * author     : Igor Sliskovic 
  *
  * requires   : Message text, sqlcode and sqlerrm
  *
  * guarantees : Will log message regardless if the paramater for log is on or not
  *
  * parameter  : i_message - Message text
  * parameter  : i_sqlerrm - SQLERRM oracle function
  * parameter  : i_sqlcode - SQLCODE oracle function
  *
  * aditional  : the package initializes master log row and marks it as Error, aditional
  *              messages are added to the detail table
  */
  procedure p_handle_exception (i_message   in message_nn
                               ,i_sqlerrm   in varchar2
                               ,i_sqlcode   in number) is
  begin
    if (g_cel_id is null) then
      p_add_master_record (i_message_type => 'Error');
    else
      update cmu_error_log
         set cel_message_type = 'Error'
       where cel_id = g_cel_id;
    end if;

    owa_util.who_called_me (owner      => g_user
                           ,name       => g_package
                           ,lineno     => g_line_code
                           ,caller_t   => g_object_type);

    insert /*+ APPEND */
          into  cmu_error_log_detail (ced_id
                                     ,ced_message
                                     ,ced_time
                                     ,ced_name
                                     ,ced_cel_id
                                     ,ced_e_sqlerrm
                                     ,ced_e_sqlcode
                                     ,ced_message_type
                                     ,ced_e_error_stack
                                     ,ced_e_error_backtrace
                                     ,ced_e_error_call_stack)
         values (cmu_error_log_detail_seq.nextval
                ,i_message
                ,systimestamp
                ,g_package
                ,g_cel_id
                ,i_sqlerrm
                ,i_sqlcode
                ,'E'
                ,dbms_utility.format_error_stack
                ,dbms_utility.format_error_backtrace
                ,dbms_utility.format_call_stack);

    commit;
  end p_handle_exception;
begin
  owa_util.who_called_me (owner      => g_user
                         ,name       => g_package
                         ,lineno     => g_line_code
                         ,caller_t   => g_object_type);
  p_check_log;

  if (g_do_i_log = 1) then
    p_add_master_record;
  end if;
end cmu_error_log_pkg;
/

/*
drop table cmu_messages;
drop table cmu_parameters;
drop table cmu_error_log_detail;
drop table cmu_error_log;
drop sequence cmu_error_log_seq;
drop sequence cmu_error_log_detail_seq;
drop sequence cmu_parameters_seq;
drop sequence cmu_messages_seq;
drop package cmu_error_log_pkg;
*/