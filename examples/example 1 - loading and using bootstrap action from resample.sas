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
run;

/* bootstrap */
proc cas;
	resample.bootstrap / intable='sample' B=100 seed=12345 Bpct=1 case='unique_case' strata='none';
			/*  take a look at how the table is distributed in the CAS environment */
			datastep.runcode result=t / code='data sample_bs; set sample_bs; host=_hostname_; threadid=_threadid_; run;';
			simple.crossTab / table={name="sample_bs" where="bag=1"} row="bsid" col="host" aggregator="N";
			simple.crossTab / table={name="sample_bs" where="bag=1"} row="bsid" col="threadid" aggregator="N";
run;

/* double-bootstrap after bootstrap */
proc cas;
	resample.doubleBootstrap / intable='sample' B=100 D=10 seed=12345 Bpct=1 Dpct=1 case='unique_case';
			/*  take a look at how the table is distributed in the CAS environment */
			datastep.runcode result=t / code='data sample_dbs; set sample_dbs; host=_hostname_; threadid=_threadid_; run;';
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=1"} row="dbsid" col="host" aggregator="N";
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=1"} row="dbsid" col="threadid" aggregator="N";
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=128"} row="dbsid" col="host" aggregator="N";
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=128"} row="dbsid" col="threadid" aggregator="N";
run;

/* double-bootstrap after bootstrap - give wrong B? (it gets ignorned because it detects B from prior bootstrap) */
proc cas;
	resample.doubleBootstrap / intable='sample' B=10 D=10 seed=12345 Bpct=1 Dpct=1 case='unique_case';
			/*  take a look at how the table is distributed in the CAS environment */
			datastep.runcode result=t / code='data sample_dbs; set sample_dbs; host=_hostname_; threadid=_threadid_; run;';
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=1"} row="dbsid" col="host" aggregator="N";
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=1"} row="dbsid" col="threadid" aggregator="N";
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=128"} row="dbsid" col="host" aggregator="N";
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=128"} row="dbsid" col="threadid" aggregator="N";
run;

/* double-bootstrap without first running bootstrap */
proc cas;
	dropTable name="sample_bs";
	dropTable name="sample_dbs";
	resample.doubleBootstrap / intable='sample' B=100 D=10 seed=12345 Bpct=1 Dpct=1 case='unique_case';
			/*  take a look at how the table is distributed in the CAS environment */
			datastep.runcode result=t / code='data sample_bs; set sample_bs; host=_hostname_; threadid=_threadid_; run;';
			simple.crossTab / table={name="sample_bs" where="bag=1"} row="bsid" col="host" aggregator="N";
			simple.crossTab / table={name="sample_bs" where="bag=1"} row="bsid" col="threadid" aggregator="N";
			datastep.runcode result=t / code='data sample_dbs; set sample_dbs; host=_hostname_; threadid=_threadid_; run;';
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=1"} row="dbsid" col="host" aggregator="N";
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=1"} row="dbsid" col="threadid" aggregator="N";
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=128"} row="dbsid" col="host" aggregator="N";
			simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=128"} row="dbsid" col="threadid" aggregator="N";
run;

/* different size double-bootstrap */
proc cas;
		dropTable name="sample_bs";
		dropTable name="sample_dbs";
		resample.doubleBootstrap / intable='sample' B=100 D=100 seed=12345 Bpct=1 Dpct=1 case='unique_case';
				/*  take a look at how the table is distributed in the CAS environment */
				datastep.runcode result=t / code='data sample_bs; set sample_bs; host=_hostname_; threadid=_threadid_; run;';
				simple.crossTab / table={name="sample_bs" where="bag=1"} row="bsid" col="host" aggregator="N";
				simple.crossTab / table={name="sample_bs" where="bag=1"} row="bsid" col="threadid" aggregator="N";
				datastep.runcode result=t / code='data sample_dbs; set sample_dbs; host=_hostname_; threadid=_threadid_; run;';
				simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=1"} row="dbsid" col="host" aggregator="N";
				simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=1"} row="dbsid" col="threadid" aggregator="N";
				simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=128"} row="dbsid" col="host" aggregator="N";
				simple.crossTab / table={name="sample_dbs" where="bag=1 and bsid=128"} row="dbsid" col="threadid" aggregator="N";
run;

quit;
*cas mysess clear;
