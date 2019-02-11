cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;


proc cas;
builtins.defineActionSet /
	name = "example"
	actions = {
			{
				name = "optional"
				parms = {
							{name="req_string" type="string" required=TRUE},
							{name="opt_parm" type="INT" default=0 required=FALSE}
						}
				definition = "if exists('opt_parm') then do;
								print req_string opt_parm;
							  end;"
			}
		}
;
run;

proc cas;
	example.optional / req_string='This is a required parameter (string)' opt_parm=1;
	example.optional / req_string='This is a required parameter (string)';* opt_parm=1;
	example.optional;
	example.optional / req_string='This is a required parameter (string)' something_unexpected=1;
run;

*cas mysess clear;

/*
1
This is a required parameter (string)1
2
** NOTHING - the default value is not seen! ****
3
ERROR: Parameter 'req_string' is required but was not specified.
ERROR: The action stopped due to errors.
4
ERROR: Parameter 'something_unexpected' is not recognized.
ERROR: Expecting one of the following: req_string, opt_parm.
ERROR: The action stopped due to errors.
*/
