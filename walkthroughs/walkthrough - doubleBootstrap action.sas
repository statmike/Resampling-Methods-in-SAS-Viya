/* a step by step walkthrough of the doubleBootstrap action in the resample actionset
  link to wiki:
*/

/* setup a session - in SAS Studio use interactive mode for this walkthrough */
cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load example data to work with */
proc casutil;
	load data=sashelp.cars casout="sample" replace;
quit;

/* define a parameter to hold the table name and B (the desired number of resamples for the bootstrap) and D (the desired number of resamples for the double-bootstrap)
      If you are in SAS Studio use interactive mode so this will be remembered */
proc cas;
	 intable='sample';
	 B=50;
	 D=50;
	 seed=12345; /* seed for call streaminit(seed) in the sampling */
	 Bpct=1; /* The percentage of the original samples rowsize to use as the resamples (Bootstrap) size 1=100% */
	 Dpct=1; /* The percentage of the original samples rowsize to use as the resamples (DoubleBootstrap) size 1=100% */
run;

		/* check to see if resample.bootstrap has already been run
      		if not then run it first to get bootstrap resamples for double-bootstrap resampling */
		builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
		table.tableExists result=c / name=intable||'_bs';
			if c.exists then do;
					/* calculate bss */
					datastep.runcode result=t / code='data tempholdbss; set '|| intable || '_bs; threadid=_threadid_; nthreads=_nthreads_; run;';
							fedsql.execDirect result=q / query='select max(bscount) as bss from (select count(*) as bscount from (select distinct bsID, threadid from tempholdbss) a group by threadid) b';
							dropTable name='tempholdbss';
							bss=q[1,1].bss;
			end;
			else; do;
				bootstrap result=r / intable=intable B=B seed=seed Bpct=Bpct;
				*describe(r);
				*print r.bss;
						/* calculate bss, can this be retrieved as response from the bootstrap action (not working) */
						datastep.runcode result=t / code='data tempholdbss; set '|| intable || '_bs; threadid=_threadid_; nthreads=_nthreads_; run;';
								fedsql.execDirect result=q / query='select max(bscount) as bss from (select count(*) as bscount from (select distinct bsID, threadid from tempholdbss) a group by threadid) b';
								dropTable name='tempholdbss';
								bss=q[1,1].bss;
			end;
run;

		/* create a structure for the double-bootstrap sampling.
		      Will make resamples equal to the size of the original table
		      these instructions are sent to each _threadid_ which will have bss bootstrap resamples
		          it then creates bss*nthreads resamples - double-bootstrap
		          example: if you environment has 48 threads (maybe 3 workers with 16 threads each)
		                    bss=10 will create 480 bootstrap resamples
		                    each bootstrap resample will yield D double-bootstrap resamples
		                    if D=480 also then 480*480 = 230,400 double-bootstrap resamples */
    simple.numRows result=r / table=intable;
				r.Bpctn=CEIL(r.numrows*Bpct); /* set r.Bpctn to the fraction of the original sample tables size requested for each bootstrap resample */
				r.Dpctn=CEIL(r.Bpctn*Dpct); /* set r.Dpctn to the fraction of the bootstrap resample tables size requested for each double-bootstrap resample */
    datastep.runcode result=t / code='data '|| intable ||'_dbskey;
                        call streaminit(12345);
                      do bs = 1 to '|| bss ||';
                        bsID = (_threadid_-1)*'|| bss ||' + bs;
                          do dbsID = 1 to '|| D ||';
                            do dbs_rowID = 1 to '|| r.Dpctn ||';
                              bs_rowID = int(1+'|| r.Bpctn ||'*rand(''Uniform''));
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
      		to link dbs_rowID to bs_rowID and get the actual original rowID */
    fedSql.execDirect / query='create table '|| intable ||'_dbskey {options replace=true} as
                    select * from
                      (select * from '|| intable ||'_dbskey) a
                      join
                      (select bsID, bs_rowID, rowID from '|| intable ||'_bs where bag=1) b
                      using (bsID,bs_rowID)';
run;

		/* use some fancy sql to merge the bootstrap structure with the sample data
      		and include the unsampled rows with bag=0
        			note unsampled (bag=0) includes unsampled in bootstrap and double-bootstrap */
    fedSql.execDirect / query='create table '|| intable ||'_dbs {options replace=true} as
                    select * from
                      (select b.bsID, b.dbsID, b.rowID, c.bs_rowID, c.dbs_rowID, CASE when c.bag is null then 0 else c.bag END as bag from
                        (select bsID, dbsID, rowID from
                          (select distinct bsID, dbsID from '|| intable ||'_dbskey) as a, '|| intable ||') as b
                        full join
                        (select bsID, dbsID, dbs_rowID, bs_rowID, rowID, bag from '|| intable ||'_dbskey) c
                        using (bsID, dbsID, rowID)) d
                      left join
                      '|| intable ||'
                      using (rowID)';
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_dbs; set '||intable||'_dbs; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_dbs" where="bag=1 and bsid=1"} row="dbsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_dbs" where="bag=1 and bsid=1"} row="dbsid" col="threadid" aggregator="N";
run;

		/* rebalance the table by partitioning by bsID and dbsID, this will ensure all the same values of bsID are on the same host but not necessarily the same _threadid_ */
		partition / casout={name=intable||'_dbs', replace=TRUE} table={name=intable||'_dbs', groupby={{name='bsID'},{name='dbsID'}}};
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_dbs; set '||intable||'_dbs; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_dbs" where="bag=1 and bsid=1"} row="dbsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_dbs" where="bag=1 and bsid=1"} row="dbsid" col="threadid" aggregator="N";
		alterTable / name=intable||"_dbs" columns={{name='host', drop=TRUE},{name='threadid', drop=TRUE}};
run;

		/* drop the table holding the bootstrap resampling structure */
		dropTable name=intable||'_dbskey';
quit;

*cas mysess clear;
