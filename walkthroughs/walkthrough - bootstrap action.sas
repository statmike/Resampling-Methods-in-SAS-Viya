table.columninfo result=i / table=intable;
		if i.columninfo.where(upcase(column)=upcase(CASE)).nrows=1 then do;
				if i.columninfo.where(upcase(Column)='CASEID').nrows=1 then do;
					alterTable / name=intable columns={{name='caseID', drop=TRUE}};
				end;
				fedsql.execDirect / query='create table '|| intable ||'_cases {options replace=TRUE} as select distinct '|| CASE ||' from '|| intable;
				resample.addRowID / intable=intable||'_cases';
					alterTable / name=intable||'_cases' columns={{name='rowID',rename='caseID'}};
				simple.numRows result=r / table=intable||'_cases';
				fedsql.execDirect / query='create table '|| intable ||' {options replace=TRUE} as
																			select * From
																				(select * from '|| intable ||'_cases) a
																				left outer join
																				(select * from '|| intable ||') b
																				using('|| CASE ||')';
				dropTable name=intable||'_cases';
		end;
		else do;
				if i.columninfo.where(upcase(Column)='CASEID').nrows=1 then do;
					alterTable / name=intable columns={{name='caseID', drop=TRUE}};
				end;
				resample.addRowID / intable=intable;
					alterTable / name=intable columns={{name='rowID',rename='caseID'}};
				simple.numRows result=r / table=intable;
		end;
r.numCases=r.numrows;
r.Bpctn=CEIL(r.numrows*Bpct);
datastep.runcode result=t / code='data tempholdb; nthreads=_nthreads_; output; run;';
		fedsql.execDirect result=q / query='select max(nthreads) as M from tempholdb';
		dropTable name='tempholdb';
		bss=ceil(B/q[1,1].M);
datastep.runcode result=t / code='data '|| intable ||'_bskey;
							call streaminit('|| seed ||');
							do bs = 1 to '|| bss ||';
								bsID = (_threadid_-1)*'|| bss ||' + bs;
								do bs_caseID = 1 to '|| r.Bpctn ||';
									caseID = int(1+'|| r.numCases ||'*rand(''Uniform''));
									bag=1;
									output;
								end;
							end;
							drop bs;
						 run;';
fedSql.execDirect / query='create table '|| intable ||'_bs {options replace=TRUE} as
								select * from
									(select b.bsID, b.caseID, c.bs_caseID, CASE when c.bag is null then 0 else c.bag END as bag from
										(select bsID, caseID from
											(select distinct bsID from '|| intable ||'_bskey) as a, (select distinct caseID from '|| intable ||') as a2) as b
										full join
										(select bsID, bs_caseID, caseID, bag from '|| intable ||'_bskey) c
										using (bsID, caseID)) d
									left join
									'|| intable ||'
									using (caseID)';
dropTable name=intable||'_bskey';
partition / casout={name=intable||'_bs', replace=TRUE} table={name=intable||'_bs', groupby={{name='bsID'}}};
resp.bss=bss;
send_response(resp);




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
		seed=12345; /* seed for call streaminit(seed) in the sampling */
		Bpct=1; /* The percentage of the original samples rowsize to use as the resamples size 1=100% */
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
				r.Bpctn=CEIL(r.numrows*Bpct); /* set r.Bpctn to the fraction of the original sample tables size requested for each bootstrap resample */
run;

		/* create a structure for the bootstrap sampling.
      		Will make resamples equal to the size of the original table
      		these instructions are sent to each _threadid_ and replicated bss times */
    datastep.runcode result=t / code='data '|| intable ||'_bskey;
                  call streaminit(12345);
                  do bs = 1 to '|| bss ||';
                    bsID = (_threadid_-1)*'|| bss ||' + bs;
                    do bs_rowID = 1 to '|| r.Bpctn ||';
                      rowID = int(1+'|| r.numrows ||'*rand(''Uniform''));
                      bag=1;
                      output;
                    end;
                  end;
                  drop bs;
                 run;';
run;

	/*  take a look at how the table is distributed in the CAS environment */
	datastep.runcode result=t / code='data '||intable||'_bskey; set '||intable||'_bskey; host=_hostname_; threadid=_threadid_; run;';
	simple.crossTab / table={name=intable||"_bskey" where="bag=1"} row="bsid" col="host" aggregator="N";
	simple.crossTab / table={name=intable||"_bskey" where="bag=1"} row="bsid" col="threadid" aggregator="N";
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

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_bs; set '||intable||'_bs; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_bs" where="bag=1"} row="bsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_bs" where="bag=1"} row="bsid" col="threadid" aggregator="N";
run;

		/* rebalance the table by partitioning by bsID, this will ensure all the same values of bsID are on the same host but not necessarily the same _threadid_ */
		partition / casout={name=intable||'_bs', replace=TRUE} table={name=intable||'_bs', groupby={{name="bsID"}}};
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_bs; set '||intable||'_bs; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_bs" where="bag=1"} row="bsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_bs" where="bag=1"} row="bsid" col="threadid" aggregator="N";
		alterTable / name=intable||"_bs" columns={{name='host', drop=TRUE},{name='threadid', drop=TRUE}};
run;

		/* drop the table holding the bootstrap resampling structure */
    dropTable name=intable||'_bskey';
run;

		/* allow the action to have a response value, in this case the value of bss stored in a variable named bss */
		*resp.bss=bss;
		*send_response(resp);
run;

quit;

*cas mysess clear;

/* create full bootstrap sampled file with bag (sampled) and oob (unsampled) rows
logic for sample_bs:
	input tables:
		sample: source, rowID identifies unique rows
		sample_bskey: bsID, bs_rowID identifies unique rows
			has rowID to connect the bs_rowID to the sampled rowID in cars
	Merge Flow:
		1: cartisian join of distinct sample_bskey.bsID with sample - keep bsID, rowID
			rows 3-4
		2: join (1) with sample_bskey.(bsID, bs_rowID, rowID, bag), use case to assign bag=0 to unmatched rows
			rows (1) + 5-7
		3: left join (2) to sample data on rowID to populate source table columns
			rows 1-2 + (2) + 8-10
1	select * from
2		(select b.bsID, b.rowID, c.bs_rowID, CASE when c.bag is null then 0 else c.bag END as bag from
3			(select bsID, rowID from
4				(select distinct bsID from sample_bskey) as a, sample) as b
5			full join
6			(select bsID, bs_rowID, rowID, bag from sample_bskey) c
7			using (bsID, rowID)) d
8		left join
9		sample
10		using (rowID)
*/
