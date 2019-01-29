cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

proc cas;
  builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
run;

/* load a small table sample
sample1 - 1 row per case and no case identification columns
sample2 - 1 row per case and case identification in unique_case
sample3 - 3 rows per case and case identification in unique_case (rep takes down to row level 1,2,3)
*/
proc casutil;
	load data=sashelp.cars casout="sample1" replace;
quit;
data mylib.sample2; set mylib.sample1; run;
    proc cas;
      resample.addRowID / intable='sample2';
    quit;
    data mylib.sample2; set mylib.sample2; unique_case=10000+rowID; drop rowID; run;
data mylib.sample3; set mylib.sample2; do rep = 1 to 3; output; end; run;

data mylib.sample1B mylib.sample1D mylib.sample1J; set mylib.sample1; output; run;
data mylib.sample2B mylib.sample2D mylib.sample2J; set mylib.sample2; output; run;
data mylib.sample3B mylib.sample3D mylib.sample3J; set mylib.sample3; output; run;

proc cas;
  B=2;
  D=2;
  seed=12345;
  Bpct=1;
  Dpct=1;

  resample.bootstrap / intable='sample1B' B=B seed=seed Bpct=Bpct case='rows';
  resample.bootstrap / intable='sample2B' B=B seed=seed Bpct=Bpct case='unique_case';
  resample.bootstrap / intable='sample3B' B=B seed=seed Bpct=Bpct case='unique_case';

  resample.doubleBootstrap / intable='sample1D' B=B D=D seed=seed Bpct=Bpct Dpct=Dpct case='rows';
  resample.doubleBootstrap / intable='sample2D' B=B D=D seed=seed Bpct=Bpct Dpct=Dpct case='unique_case';
  resample.doubleBootstrap / intable='sample3D' B=B D=D seed=seed Bpct=Bpct Dpct=Dpct case='unique_case';

  resample.jackknife / intable='sample1J' case='rows';
  resample.jackknife / intable='sample2J' case='unique_case';
  resample.jackknife / intable='sample3J' case='unique_case';
run;




quit;

*cas mysess clear;
