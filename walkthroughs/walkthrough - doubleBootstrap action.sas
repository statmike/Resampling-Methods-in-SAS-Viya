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

/* define a parameter to hold the table name and B (the desired number of resamples, both bootstrap, and double-bootstrap)
      If you are in SAS Studio use interactive mode so this will be remembered */
proc cas;
	 intable='sample';
	 B=50;
run;

		/* check to see if resample.bootstrap has already been run
      		if not then run it first to get bootstrap resamples for double-bootstrap resampling */
		builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
    table.tableExists result=c / name=intable||'_bs';
      if c.exists then do;

      end;
      else; do;
        resample.bootstrap / intable=intable B=B;
      end;
run;

		/* use the datastep automatic variable nthreads to store the environment size (number of threads) in q[1,1].M
				use this to calculate the value of bss - number of resamples per _threadid_ to achieve atleast B resamples */
		datastep.runcode result=t / code='data tempholdb; nthreads=_nthreads_; output; run;';
				fedsql.execDirect result=q / query='select max(nthreads) as M from tempholdb';
				dropTable name='tempholdb';
				bss=ceil(B/q[1,1].M);
run;

		/* create a structure for the double-bootstrap sampling.
		      Will make resamples equal to the size of the original table
		      these instructions are sent to each _threadid_ which will have bss bootstrap resamples
		          it then creates bss*nthreads resamples - double-bootstrap
		          example: if you environment has 48 threads (maybe 3 workers with 16 threads each)
		                    bss=10 will create 480 bootstrap resamples
		                    each bootstrap resample will yield 480 double-bootstrap resamples
		                    480*480 = 230,400 double-bootstrap resamples */
    simple.numRows result=r / table=intable;
    datastep.runcode result=t / code='data '|| intable ||'_dbskey;
                        call streaminit(12345);
                      do bs = 1 to '|| bss ||';
                        bsID = (_threadid_-1)*'|| bss ||' + bs;
                          do dbsID = 1 to '|| bss ||'*'|| q[1,1].M ||';
                            do dbs_rowID = 1 to '|| r.numrows ||';
                              bs_rowID = int(1+'|| r.numrows ||'*rand(''Uniform''));
                              bag=1;
                              output;
                            end;
                          end;
                      end;
                      drop bs;
                      run;';
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

		/* drop the table holding the bootstrap resampling structure */
		dropTable name=intable||'_dbskey';
quit;

*cas mysess clear;
