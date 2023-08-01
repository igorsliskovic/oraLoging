A simple package for loging information during program execution. Has a paramater table to turn full loging on or off, while exception loging will always work 
regardless of the parameters. Requires that each procedure at the beggining has a call p_add_log, and each has a exception handle with p_handle_exception call 
as shown in the example. This will allow full stack loging as the program goes deeper into decision nesting and different procedure. In case of an error you will 
be able to check all the data required to find out what happend.
