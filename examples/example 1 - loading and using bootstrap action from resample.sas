cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load a small table sample from */
proc casutil;
	load data=sashelp.cars casout="sample" replace;
quit;

/* load the bootstrap action set and run it on the sample dataset
  B=100 indicates it will create atleast 100 resamples (creates resamples in multiples of the value of _nthreads_)
*/
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.bootstrap / intable='sample' B=100;
	*resample.doubleBootstrap / intable='sample' B=100;
run;
/*
test bs first
test dbs after bs
test dbs without bs first
*/


*cas mysess clear;
