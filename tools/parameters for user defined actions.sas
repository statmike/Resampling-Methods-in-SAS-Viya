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
				definition = "print req_string opt_parm;"
			}
		}
;
run;

proc cas;
	example.optional / req_string='This is a required parameter (string)' opt_parm=1;
	example.optional / req_string='This is a required parameter (string)';* opt_parm=1;
run;

*cas mysess clear; 
