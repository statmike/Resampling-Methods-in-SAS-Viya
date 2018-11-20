cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load a small table sample from */
proc casutil;
	load data=sashelp.cars casout="sample" replace;
quit;

/* load the bootstrap action set and run it on the sample dataset
  bss=2 indicates it will create two full samples for each thread in the environment
*/
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.bootstrap / intable='sample' bss=2;
	*resample.doubleBootstrap / intable='sample' bss=2;
run;

*cas mysess clear;
