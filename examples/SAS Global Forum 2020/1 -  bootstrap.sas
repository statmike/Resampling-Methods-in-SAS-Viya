/* create a cas session and libname to refer to data in it */
cas mysess sessopts=(caslib='casuser');
libname mycas cas sessref=mysess;

/* load original sample that will be resampled */
proc casutil;
	load data=sashelp.heart casout="sample" replace;
quit;

/* create bootstrap resamples */
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.bootstrap / intable='sample' B=1000 seed=12345 Bpct=1 case='none' strata='none' strata_table='none';
run;

*cas mysess clear;
