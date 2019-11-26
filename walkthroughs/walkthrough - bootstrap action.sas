/* a step by step walkthrough of the bootstrap action in the resample actionset
  link to wiki:

Overview:
	if case is a column then sample these as units
	if strata is a column then sample units within each strata level separately

	1 - Add CaseID to intable
		If case in intable
			if strata in intable
				intable.caseID is 1.s where s is a decimal representation of the strata row numbers
					r has number of cases in intable
					rs has info per strata level
			if strata not in intable
				intable.caseID is 1,2,3,... for cases
					r has number of cases in intable
		If case not in intable
			if strata in intable
			 	intable.caseID is 1.s where s is a decimal representation of the strata row numbers
					r has number of rows/cases in intable
					rs has infor per strata level
			if strata not in intable
				intable.caseID is rownumber as rows are cases
					r has number of rows/cases in intable
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
proc sql;
	create table sample_strata as
		select count(*) as strata_n, type
		from sashelp.cars where type ne 'Sedan'
		group by type;
run;
data sample_strata; set sample_strata; if type ne 'Sedan' then strata_dist='Normal,200,50'; run;
proc casutil;
		load data=sashelp.cars casout="sample" replace; /* n=428 */
		load data=sample_strata casout="sample_strata" replace;
run;
proc cas;
		cases='YES';
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
		B=1000; /* desired number of resamples, used to reset value of bss to achieve at least B resamples */
		seed=12345; /* seed for call streaminit(seed) in the sampling */
		Bpct=.8; /* The percentage of the original samples rowsize to use as the resamples size 1=100% */
		case='unique_case'; /* if the value is a column in intable then uses unique values of that column as cases, otherwise will use rows of intable as cases */
		strata='Type'; /* if the value is a column in intable then uses unique values of that column as by levels, otherwise will bootstrap the full intable */
		strata_table='sample_strata';
run;

/* 1 - ADD caseID TO INTABLE */
		/* workflow: if case is a column in intable then do first route, otherwise do second route (else) */
		table.columninfo result=i / table=intable;

				/* if a column caseID is present then drop it - protected term, may be leftover from previous run */
				if i.columninfo.where(upcase(Column)='CASEID').nrows=1 then do;
						alterTable / name=intable columns={{name='caseID', drop=TRUE}};
				end;

				/* RECONCILE STRATA INFORMATION */
				/* STRATA */
				if i.columninfo.where(upcase(Column)=upcase(STRATA)).nrows=1 then do;
						/* CASE */
						if i.columninfo.where(upcase(column)=upcase(CASE)).nrows=1 then do;
								/* make a one column table of unique cases */
								fedsql.execDirect / query='create table '|| intable ||'_cases {options replace=TRUE} as select distinct '|| CASE ||', '|| STRATA ||' from '|| intable;
								fedsql.execDirect / query='create table internalstrata_info {options replace=TRUE} as select distinct '|| STRATA ||', count(*) as strata_n_data, '''' as strata_dist from '|| intable ||'_cases group by '|| STRATA;
						end;
						/* NO CASE */
						else do;
								fedsql.execDirect / query='create table internalstrata_info {options replace=TRUE} as select distinct '|| STRATA ||', count(*) as strata_n_data, '''' as strata_dist from '|| intable ||' group by '|| STRATA;
						end;
						resample.addRowID / intable='internalstrata_info';
								alterTable / name='internalstrata_info' columns={{name='rowID',rename='strataID'}};
						table.tableExists result=es / name=strata_table;
						if es.exists==1 then do;
								table.columninfo result=s / table=strata_table;
								if s.columninfo.where(upcase(column)=upcase('STRATA_DIST')).nrows=1 then do;
										fedsql.execDirect r=rs / query='create table internalstrata_info {options replace=TRUE} as
																									select a.'||strata||', a.strataID, a.strata_n_data, b.strata_n, b.strata_dist from
																											(select * from internalstrata_info) as a
																											left outer join
																											(select * from '|| strata_table ||') as b
																											using('||strata||')';
								end;
								else do;
									fedsql.execDirect r=rs / query='create table internalstrata_info {options replace=TRUE} as
																								select a.'||strata||', a.strataID, a.strata_n_data, b.strata_n, a.strata_dist from
																										(select * from internalstrata_info) as a
																										left outer join
																										(select * from '|| strata_table ||') as b
																										using('||strata||')';
								end;
						end;
						simple.numRows result=t / table='internalstrata_info';
						strata_div=10**((int64)(ceil(log10(t.numrows+1)))); /* count the number of digits and create a divisor so that all will be decimal valued when divided by the divisor: r.numrows=101 gives 10**3 which is 1000 */
				end;
				/* NO STRATA */
				else do;
						/* CASE */
						if i.columninfo.where(upcase(column)=upcase(CASE)).nrows=1 then do;
								/* make a one column table of unique cases */
								fedsql.execDirect / query='create table '|| intable ||'_cases {options replace=TRUE} as select distinct '|| CASE ||' from '|| intable;
								/* addRowID to the unique cases, then rename rowID to caseID */
								resample.addRowID / intable=intable||'_cases';
										alterTable / name=intable||'_cases' columns={{name='rowID',rename='caseID'}};
								/* store the row count from the cases for further calculations */
								simple.numRows result=r / table=intable||'_cases';
								/* store the size of the original sample data (cases) in r.numCases */
								numCases=r.numrows;
								/* set r.Bpctn to the fraction of the original sample tables case size to be resampled for for each bootstrap resample */
								Bpctn=CEIL(numCases*Bpct);
						end;
						/* NO CASE */
						else do;
								/* store the row count from the cases for further calculations */
								simple.numRows result=r / table=intable;
								numCases=r.numRows;
								Bpctn=CEIL(numCases*Bpct);
						end;
				end;


				/* first route: case= is a column in intable */
				if i.columninfo.where(upcase(column)=upcase(CASE)).nrows=1 then do;
						/* strata= is a column in intable so stratify sampling */
						if i.columninfo.where(upcase(column)=upcase(STRATA)).nrows=1 then do;
								/* make a one column table of unique cases & strata levels */
								fedsql.execDirect / query='create table '|| intable ||'_cases {options replace=TRUE} as select distinct '|| CASE ||', '|| STRATA ||' from '|| intable;
										/*merge intable_cases with internalstrata_table (adds a integer representation of strata levels)*/
										fedsql.execDirect / query='create table '|| intable ||'_cases {options replace=TRUE} as select * from
																									(select * from '|| intable ||'_cases) a
																									left outer join
																									(select '|| STRATA ||', strataID from internalstrata_info) b
																									using('|| STRATA ||')';
								/* number rows for each level of strata= starting with 1 for each */
								datastep.runcode result=t / code='data '|| intable ||'_cases; set '|| intable ||'_cases; by '|| strata ||'; retain caseID; if first.'|| strata ||' then caseID=1+strataID/'|| strata_div ||'; else caseID+1; run;';
								/* merge the caseID into the intable */
								fedsql.execDirect / query='create table '|| intable ||' {options replace=TRUE} as
																							select * From
																								(select '|| CASE ||', '|| STRATA ||', caseID from '|| intable ||'_cases) a
																								left outer join
																								(select * from '|| intable ||') b
																								using('|| CASE ||', '|| STRATA ||')';
								/* drop the table of unique cases: size is in r.numrows (rs.numrows), values are merged into intable */
								dropTable name=intable||'_cases';
						end;
						/* strata= is not a column in intable */
						else do;
								/* merge the caseID into the intable */
								fedsql.execDirect / query='create table '|| intable ||' {options replace=TRUE} as
																							select * From
																								(select * from '|| intable ||'_cases) a
																								left outer join
																								(select * from '|| intable ||') b
																								using('|| CASE ||')';
								/* drop the table of unique cases: size is in r.numrows, values are merged into intable */
								dropTable name=intable||'_cases';
						end;
				end;
				/* second route: case= is not a column in intable */
				else do;
						/* strata= is a column in intable so stratify sampling */
						if i.columninfo.where(upcase(column)=upcase(STRATA)).nrows=1 then do;
								/*merge intable with stratan (adds a integer representation of strata levels)*/
								fedsql.execDirect / query='create table '|| intable ||' {options replace=TRUE} as select * from
																							(select * from '|| intable ||') a
																							left outer join
																							(select '|| STRATA ||', strataID from internalstrata_info) b
																							using('|| STRATA ||')';
								datastep.runcode result=t / code='data '|| intable ||'; set '|| intable ||'; by '|| strata ||'; retain caseID; if first.'|| strata ||' then caseID=1+strataID/'|| strata_div ||'; else caseID+1; drop strataID; run;';
						end;
						/* strata= is not a column in intable */
						else do;
								/* addRowID to intable since rows are unique cases, then rename rowID to caseID */
								resample.addRowID / intable=intable;
										alterTable / name=intable columns={{name='rowID',rename='caseID'}};
						end;
				end;
run;

/* 2 - CREATE BOOTSTRAP STRUCTURE */
/* setup parameters for boostrap structure then create the structure */
		/* If user specifies desired number of resamples B then reset bss to achieve atleast B resamples */
		datastep.runcode result=t / code='data tempholdb; nthreads=_nthreads_; output; run;';
				fedsql.execDirect result=q / query='select max(nthreads) as M from tempholdb';
				dropTable name='tempholdb';
				bss=ceil(B/q[1,1].M);
				bssmax=bss*q[1,1].M;

		/* strata= is a column in intable so stratify sampling */
		if i.columninfo.where(upcase(column)=upcase(STRATA)).nrows=1 then do;
				/* create a structure for the bootstrap sampling.
							Will make resample sized by the internalstrata_info table constructed above
							these instructions are sent to each _threadid_ and replicated bss times */
						datastep.runcode result=t / code='data '||intable||'_bskey;
																									call streaminit('||seed||');
																									set internalstrata_info;
																									array p(*) $ p1-p100;
																									bag = 1;
																									do bsID = 1 to '||bssmax||';
																											if strata_dist ne '''' then do;
																													i = 1;
																													do while(scan(strata_dist,i,'','')ne'''');
																															p(i)=scan(strata_dist,i,'','');
																															i+1;
																													end;
																													if p3 then holder = rand(p1,1*p2,1*p3);
																													else if p2 then holder = rand(p1,1*p2);
																													else if p1 then holder =rand(p1);
																													if holder <= 0 then holder = 0;
																											end;
																											else if strata_n then holder = strata_n;
																											else holder = strata_n_data;
																											do bs_CaseIDn = 1 to holder;
																													caseID = int(1 + strata_n_data*rand(''Uniform''))+strataID/'|| strata_div ||';
																													bs_caseID = bs_CaseIDn + '||strata_div||';
																													output;
																											end;
																									end;
																									drop p: i strata_n strata_n_data strata_dist holder bs_CaseIDn;
																							run;' single='yes';
						partition / casout={name=intable||'_bskey', replace=TRUE} table={name=intable||'_bskey', groupby={{name='bsID'}}};
		end;
		/* strata= is not a column in intable */
		else do;
				/* create a structure for the bootstrap sampling.
							Will make resamples equal to the size of the original tables cases adjusted by Bpctn
							these instructions are sent to each _threadid_ and replicated bss times */
						datastep.runcode result=t / code='data '|| intable ||'_bskey;
													call streaminit('|| seed ||');
													do bs = 1 to '|| bss ||';
														bsID = (_threadid_-1)*'|| bss ||' + bs;
														do bs_caseID = 1 to '|| Bpctn ||';
															caseID = int(1+'|| numCases ||'*rand(''Uniform''));
															bag=1;
															output;
														end;
													end;
													drop bs;
												 run;';
		end;
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_bskey; set '||intable||'_bskey; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_bskey" where="bag=1"} row="bsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_bskey" where="bag=1"} row="bsid" col="threadid" aggregator="N";
run;

/* 3 - MERGE INTABLE WITH BOOTSTRAP STRUCTURE */
		/* use some fancy sql to merge the bootstrap structure with the sample data
					and include the rows not resampled with bag=0
					(see walkthrough of this SQL at the bottom of this file)*/
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
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_bs; set '||intable||'_bs; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_bs" where="bag=1"} row="bsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_bs" where="bag=1"} row="bsid" col="threadid" aggregator="N";
run;

		/* drop the table holding the bootstrap resampling structure */
		dropTable name=intable||'_bskey';
		dropTable name='internalstrata_info';
run;

		/* rebalance the table by partitioning by bsID, this will ensure all the same values of bsID are on the same host but not necessarily the same _threadid_ */
		partition / casout={name=intable||'_bs', replace=TRUE} table={name=intable||'_bs', groupby={{name='bsID'}}};
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_bs; set '||intable||'_bs; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_bs" where="bag=1"} row="bsid" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_bs" where="bag=1"} row="bsid" col="threadid" aggregator="N";
		alterTable / name=intable||"_bs" columns={{name='host', drop=TRUE},{name='threadid', drop=TRUE}};
run;

		/* allow the action to have a response value, in this case the value of bss stored in a variable named bss */
		resp.bss=bss;
		resp.bssmax=bssmax;
		send_response(resp);
run;

quit;


*cas mysess clear;

/* create full bootstrap sampled file with bag (sampled) and oob (unsampled) rows
logic for sample_bs:
	input tables:
		sample: source, caseID identifies unique rows
		sample_bskey: bsID, bs_caseID identifies unique rows
			has caseID to connect the bs_caseID to the sampled caseID in cars
	Merge Flow:
		1: cartisian join of distinct sample_bskey.bsID with sample - keep bsID, caseID
			rows 3-4
		2: join (1) with sample_bskey.(bsID, bs_caseID, caseID, bag), use case to assign bag=0 to unmatched rows
			rows (1) + 5-7
		3: left join (2) to sample data on caseID to populate source table columns
			rows 1-2 + (2) + 8-10
1	select * from
2		(select b.bsID, b.caseID, c.bs_caseID, CASE when c.bag is null then 0 else c.bag END as bag from
3			(select bsID, caseID from
4				(select distinct bsID from sample_bskey) as a, (select distint caseID from sample) as a2) as b
5			full join
6			(select bsID, bs_caseID, caseID, bag from sample_bskey) c
7			using (bsID, caseID)) d
8		left join
9		sample
10		using (caseID)
*/
