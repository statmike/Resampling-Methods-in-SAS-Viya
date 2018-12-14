/* a step by step walkthrough of the jackknife action in the resample actionset
  link to wiki:
*/

/* setup a session - in SAS Studio use interactive mode for this walkthrough */
cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load example data to work with */
proc casutil;
	load data=sashelp.cars casout="sample" replace;
quit;

/* define a parameter to hold the table name
      If you are in SAS Studio use interactive mode so this will be remembered */
proc cas;
	  intable='sample';
run;

		/* use the resample.addRowID action to add a naturally numbered rowID to the sample data */
		builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
		resample.addRowID / intable=intable;
run;

		/* store the size of the original sample data in r.numRows */
	  simple.numRows result=r / table=intable;
run;

		/* create a structure for the jackknife sampling.
      		Will make resamples equal to the size of the original table -1 row
      		single='YES' create this structure on a single node/thread of the CAS environment */
		datastep.runcode result=t / code='data '|| intable ||'_jkkey;
									do jkID = 1 to '|| r.numrows ||';
										do rowID = 1 to '|| r.numrows ||';
											bag=1;
											if jkID ne rowID then output;
										end;
									end;
								run;' single='YES';
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_jkkey; set '||intable||'_jkkey; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_jkkey" where="bag=1"} row="jkID" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_jkkey" where="bag=1"} row="jkID" col="threadid" aggregator="N";
run;

		/* merge the structure with the input table */
		fedSql.execDirect / query='create table '|| intable ||'_jk {options replace=true} as
										select * From
											(select jkID, rowID, bag from '|| intable ||'_jkkey) a
											join
											(select * from '|| intable ||') b
											using(rowID)';
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_jk; set '||intable||'_jk; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_jk" where="bag=1"} row="jkID" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_jk" where="bag=1"} row="jkID" col="threadid" aggregator="N";
run;

		/* rebalance the table by partitioning by jkID, this will ensure all the same values of jkID are on the same host but not necessarily the same _threadid_ */
		partition / casout={name=intable||'_jk', replace=TRUE} table={name=intable||'_jk', groupby={{name="jkID"}}};
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_jk; set '||intable||'_jk; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_jk" where="bag=1"} row="jkID" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_jk" where="bag=1"} row="jkID" col="threadid" aggregator="N";
		alterTable / name=intable||"_jk" columns={{name='host', drop=TRUE},{name='threadid', drop=TRUE}};
run;

		/* drop the table holding the jackknife resampling structure */
    dropTable name=intable||'_jkkey';
run;

quit;

*cas mysess clear;
