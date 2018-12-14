cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* case 1 */
proc cas;
datastep.runcode result=t / code='data threads1; host=_hostname_; threadid=_threadid_; output; run;';
simple.freq / inputs={"host"}, table={name="threads1"};
run;

/* case 2 */
proc cas;
builtins.defineActionSet /
name = "threads"
actions = {
{
name = "threads"
parms = {{name="intable" type="string" required=TRUE}}
definition = "datastep.runcode result=t / code='data '||intable||'; host=_hostname_; threadid=_threadid_; output; run;';"
}
}
;
threads.threads / intable='threads2';
simple.freq / inputs={"host"}, table={name="threads2"};
run;

*cas mysess clear; 
