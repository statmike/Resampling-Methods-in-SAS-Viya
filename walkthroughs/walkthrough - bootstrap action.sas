/* a step by step walkthrough of the bootstrap action in the resample actionset
  link to wiki:
*/

/* setup a session - in SAS Studio use interactive mode for this walkthrough */
cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load example data to work with */
proc casutil;
	load data=sashelp.cars casout="sample" replace;
quit;

/* define a parameter to hold the table name and B (the desired number of resamples)
      If you are in SAS Studio use interactive mode so this will be remembered */
proc cas;
	  intable='sample';
		B=100; /* desired number of resamples, used to reset value of bss to achieve at least B resamples */
run;

		/* use the resample.addRowID action to add a naturally numbered rowID to the sample data */
		builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
		resample.addRowID / intable=intable;
run;

		/* If user specifies desired number of resamples B then reset bss to achieve atleast B resamples */
		datastep.runcode result=t / code='data tempholdb; nthreads=_nthreads_; output; run;';
				fedsql.execDirect result=q / query='select max(nthreads) as M from tempholdb';
				dropTable name='tempholdb';
				bss=ceil(B/q[1,1].M);
run;

		/* store the size of the original sample data in r.numRows */
	  simple.numRows result=r / table=intable;
run;

		/* create a structure for the bootstrap sampling.
      		Will make resamples equal to the size of the original table
      		these instructions are sent to each _threadid_ and replicated bss times */
    simple.numRows result=r / table=intable;
    datastep.runcode result=t / code='data '|| intable ||'_bskey;
                  call streaminit(12345);
                  do bs = 1 to '|| bss ||';
                    bsID = (_threadid_-1)*'|| bss ||' + bs;
                    do bs_rowID = 1 to '|| r.numrows ||';
                      rowID = int(1+'|| r.numrows ||'*rand(''Uniform''));
                      bag=1;
                      output;
                    end;
                  end;
                  drop bs;
                 run;';
run;

		/* use some fancy sql to merge the bootstrap structure with the sample data
      		and include the rows not resampled with bag=0 */
    fedSql.execDirect / query='create table '|| intable ||'_bs {options replace=true} as
                    select * from
                      (select b.bsID, b.rowID, c.bs_rowID, CASE when c.bag is null then 0 else c.bag END as bag from
                        (select bsID, rowID from
                          (select distinct bsID from '|| intable ||'_bskey) as a, '|| intable ||') as b
                        full join
                        (select bsID, bs_rowID, rowID, bag from '|| intable ||'_bskey) c
                        using (bsID, rowID)) d
                      left join
                      '|| intable ||'
                      using (rowID)';
run;

		/* drop the table holding the bootstrap resampling structure */
    dropTable name=intable||'_bskey';
quit;

/* review the output table sample_bs */
proc cas;
/*
how many bsID
	how many bsID per _threadid_
how many rows each (bag and OOB)
*/
run;


*cas mysess clear;
