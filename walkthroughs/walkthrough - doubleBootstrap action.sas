/* a step by step walkthrough of the doubleBootstrap action in the resample actionset
  link to wiki:
*/

/* setup a session - in SAS Studio use interactive mode for this walkthrough */
cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load actionSet */
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
quit;

/* load example data to work with - three possible scenarios
		if rows are cases and no column identifies cases then: cases=NO and multipleRows=NO
		if rows are cases and unique_case is a column holding identifier then: cases=YES and multipleRows=NO
		if multiple rows per cases then need a column, unique_case, to hold identifier: cases=YES and multipleRows=YES
*/
proc casutil;
		load data=sashelp.cars casout="sample" replace; /* n=428 */
run;
proc cas;
		cases='NO';
		multipleRows='NO';
		if cases='YES' then do;
			resample.addRowID / intable='sample';
			datastep.runcode / code='data sample; set sample; unique_case=10000+rowID; drop rowID; run;'; /* n=428 */
			if multipleRows='YES' then do;
				datastep.runcode / code='data sample; set sample; do rep = 1 to 3; output; end; run;'; /* n=1284 */
			end;
		end;
		simple.numRows result=r / table='sample';
			print(r.numRows);
		table.fetch / table='sample' index=false to=12;
run;

/* define parameters to hold the action inputs */
proc cas;
	  intable='sample';
		B=50; /* desired number of resamples, used to reset value of bss to achieve at least B resamples */
		D=50; /* the number of doubleBootstrap resample per bootstrap resample - D*B */
		seed=12345; /* seed for call streaminit(seed) in the sampling */
		Bpct=1; /* The percentage of the original samples rowsize to use as the resamples size 1=100% */
		Dpct=1; /* The percentage of the original samples rowsize to use as the resamples (DoubleBootstrap) size 1=100% */
		case='unique_case'; /* if the value is a column in intable then uses unique values of that column as cases, otherwise will use rows of intable as cases */
		strata='Make'; /* if the value is a column in intable then uses unique values of that column as by levels, otherwise will bootstrap the full intable */
run;

		/* check to see if resample.bootstrap has already been run
					if not then run it first to get bootstrap resamples for double-bootstrap resampling */
		table.tableExists result=c / name=intable||'_bs';
				/* if intable_bs does not exists then run the resample.bootstrap action to create it */
				if c.exists==0 then do;
					resample.bootstrap result=r / intable=intable B=B seed=seed Bpct=Bpct Case=Case Strata=Strata;
				end;
run;

		/* calculate bss, can this be retrieved as response from the bootsrap action (not working) */
		datastep.runcode result=t / code='data tempholdbss; set '|| intable || '_bs; threadid=_threadid_; nthreads=_nthreads_; run;';
				*fedsql.execDirect result=q / query='select max(bscount) as bss from (select count(*) as bscount from (select distinct bsID, threadid from tempholdbss) a group by threadid) b';
				fedsql.execDirect result=q1 / query='select count(*) as cbsid from (select distinct bsID from tempholdbss) a';
				fedsql.execDirect result=q2 / query='select max(nthreads) as nthreads from tempholdbss';
				dropTable name='tempholdbss';
				bss=q1[1,1].cbsid/q2[1,1].nthreads;
				print bss;
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_bs; set '||intable||'_bs; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_bs" where="bag=1"} row="bsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_bs" where="bag=1"} row="bsid" col="threadid" aggregator="N";
		alterTable / name=intable||"_bs" columns={{name='host', drop=TRUE},{name='threadid', drop=TRUE}};
run;

		/* workflow: if case is a column in intable then do first route, otherwise do second route (else) */
		table.columninfo result=i / table=intable;
				/* first route: case is a column in intable */
				if i.columninfo.where(upcase(column)=upcase(CASE)).nrows=1 then do;
						/* make a one column table of unique cases */
						fedsql.execDirect / query='create table '|| intable ||'_cases {options replace=TRUE} as select distinct caseID from '|| intable;
						/* store the row count from the cases for further calculations */
						simple.numRows result=r / table=intable||'_cases';
						/* drop the table of unique cases: size is in r.numrows, values are in intable_bs and intable */
						dropTable name=intable||'_cases';
				end;
				/* second route: case is not a column in intable */
				else do;
						/* store the row count from the cases for further calculations */
						simple.numRows result=r / table=intable;
				end;
run;

		/* store the size of the original sample data (cases) in r.numCases */
		r.numCases=r.numrows;
		/* set r.Bpctn to the fraction of the original sample tables cases size to be resample for each bootstrap */
		r.Bpctn=CEIL(r.numCases*Bpct);
		/* set the r.Dpctn to the fraction of the bootstrap resample tables cases size to be resampled for each doubleBootstrap */
		r.Dpctn=CEIL(r.Bpctn*Dpct);
run;

		/* create a structure for the double-bootstrap sampling.
					Will make resamples equal to the size of the original table
					these instructions are sent to each _threadid_ which will have bss bootstrap resamples
							it then creates bss*nthreads resamples - double-bootstrap
							example: if your environment has 48 threads (maybe 3 workers with 16 threads each)
												bss=10 will create 480 bootstrap resamples
												each bootstrap resample will yield D double-bootstrap resamples
												if D=480 also then 480*480 = 230,400 double-bootstrap resamples */
		datastep.runcode result=t / code='data '|| intable ||'_dbskey;
												call streaminit('|| seed ||');
											do bs = 1 to '|| bss ||';
												bsID = (_threadid_-1)*'|| bss ||' + bs;
													do dbsID = 1 to '|| D ||';
														do dbs_caseID = 1 to '|| r.Dpctn ||';
															bs_caseID = int(1+'|| r.Bpctn ||'*rand(''Uniform''));
															bag=1;
															output;
														end;
													end;
											end;
											drop bs;
											run;';
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_dbskey; set '||intable||'_dbskey; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_dbskey" where="bag=1"} row="bsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_dbskey" where="bag=1"} row="bsid" col="threadid" aggregator="N";
run;

		/* merge the double-bootstrap structure with the bootstrap structure data
					to link dbs_caseID to bs_caseID and get the actual original caseID */
		fedSql.execDirect / query='create table '|| intable ||'_dbskey {options replace=TRUE} as
										select * from
											(select * from '|| intable ||'_dbskey) a
											join
											(select distinct bsID, bs_caseID, caseID from '|| intable ||'_bs where bag=1) b
											using (bsID,bs_caseID)';
run;

		/* use some fancy sql to merge the bootstrap structure with the sample data
					and include the unsampled rows with bag=0
							note unsampled (bag=0) includes unsampled cases in bootstrap and double-bootstrap
				a review of this sql can be found in the bootstrap action walkthrough */
		fedSql.execDirect / query='create table '|| intable ||'_dbs {options replace=TRUE} as
										select * from
											(select b.bsID, b.dbsID, b.caseID, c.bs_caseID, c.dbs_caseID, CASE when c.bag is null then 0 else c.bag END as bag from
												(select bsID, dbsID, caseID from
													(select distinct bsID, dbsID from '|| intable ||'_dbskey) as a, (select distinct caseID from '|| intable ||') as a2) as b
												full join
												(select bsID, dbsID, dbs_caseID, bs_caseID, caseID, bag from '|| intable ||'_dbskey) c
												using (bsID, dbsID, caseID)) d
											left join
											'|| intable ||'
											using (caseID)';
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_dbs; set '||intable||'_dbs; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_dbs" where="bag=1 and bsid=1"} row="dbsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_dbs" where="bag=1 and bsid=1"} row="dbsid" col="threadid" aggregator="N";
run;

		/* drop the table holding the doubleBoostrap resampling structure */
		dropTable name=intable||'_dbskey';
run;

		/* rebalance the table by partitioning by bsID and dbsID, this will ensure all the same values of bsID are on the same host but not necessarily the same _threadid_ */
		partition / casout={name=intable||'_dbs', replace=TRUE} table={name=intable||'_dbs', groupby={{name='bsID'}}};
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_dbs; set '||intable||'_dbs; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_dbs" where="bag=1 and bsid=1"} row="dbsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_dbs" where="bag=1 and bsid=1"} row="dbsid" col="threadid" aggregator="N";
		alterTable / name=intable||"_dbs" columns={{name='host', drop=TRUE},{name='threadid', drop=TRUE}};
run;

quit;


*cas mysess clear;
