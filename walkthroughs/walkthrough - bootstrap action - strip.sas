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
		strata='Make'; /* if the value is a column in intable then uses unique values of that column as by levels, otherwise will bootstrap the full intable */
run;



table.columninfo result=i / table=intable;
		if i.columninfo.where(upcase(Column)='CASEID').nrows=1 then do;
				alterTable / name=intable columns={{name='caseID', drop=TRUE}};
		end;
		if i.columninfo.where(upcase(column)=upcase(CASE)).nrows=1 then do;
				if i.columninfo.where(upcase(column)=upcase(STRATA)).nrows=1 then do;
						fedsql.execDirect / query='create table '|| intable ||'_cases {options replace=TRUE} as select distinct '|| CASE ||', '|| STRATA ||' from '|| intable;
								fedsql.execDirect / query='create table stratan as select distinct '|| STRATA ||' from '|| intable ||'_cases';
								datastep.runcode result=t / code='data stratan; set stratan; by '|| STRATA ||'; retain stratan 0; stratan+1; run;' single='yes';
								fedsql.execDirect / query='create table '|| intable ||'_cases {options replace=TRUE} as select * From
																							(select * from '|| intable ||'_cases) a
																							left outer join
																							(select * from stratan) b
																							using('|| STRATA ||')';
								simple.numRows result=r / table='stratan';
								strata_div=10**((int64)(ceil(log10(r.numrows+1))));
								dropTable name='stratan';
						datastep.runcode result=t / code='data '|| intable ||'_cases; set '|| intable ||'_cases; by '|| strata ||'; retain caseID; if first.'|| strata ||' then caseID=1+stratan/'|| strata_div ||'; else caseID+1; run;';
						simple.numRows result=r / table=intable||'_cases';
						simple.freq result=rs / inputs='stratan' table=intable||'_cases';
						fedsql.execDirect / query='create table '|| intable ||' {options replace=TRUE} as
																					select * From
																						(select '|| CASE ||', '|| STRATA ||', caseID from '|| intable ||'_cases) a
																						left outer join
																						(select * from '|| intable ||') b
																						using('|| CASE ||', '|| STRATA ||')';
						dropTable name=intable||'_cases';
				end;
				else do;
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
		end;
		else do;
				if i.columninfo.where(upcase(column)=upcase(STRATA)).nrows=1 then do;
								fedsql.execDirect / query='create table stratan as select distinct '|| STRATA ||' from '|| intable;
								datastep.runcode result=t / code='data stratan; set stratan; by '|| STRATA ||'; retain stratan 0; stratan+1; run;' single='yes';
								fedsql.execDirect / query='create table '|| intable ||' {options replace=TRUE} as select * From
																							(select * from '|| intable ||') a
																							left outer join
																							(select * from stratan) b
																							using('|| STRATA ||')';
								simple.numRows result=r / table='stratan';
								strata_div=10**((int64)(ceil(log10(r.numrows+1))));
								dropTable name='stratan';
						datastep.runcode result=t / code='data '|| intable ||'; set '|| intable ||'; by '|| strata ||'; retain caseID; if first.'|| strata ||' then caseID=1+stratan/'|| strata_div ||'; else caseID+1; run;';
						simple.numRows result=r / table=intable;
						simple.freq result=rs / inputs='stratan' table=intable;
						datastep.runcode result=t / code='data '|| intable ||'; set '|| intable ||'; drop stratan; run;';
				end;
				else do;
						resample.addRowID / intable=intable;
							alterTable / name=intable columns={{name='rowID',rename='caseID'}};
						simple.numRows result=r / table=intable;
				end;
		end;
datastep.runcode result=t / code='data tempholdb; nthreads=_nthreads_; output; run;';
		fedsql.execDirect result=q / query='select max(nthreads) as M from tempholdb';
		dropTable name='tempholdb';
		bss=ceil(B/q[1,1].M);
if i.columninfo.where(upcase(column)=upcase(STRATA)).nrows=1 then do;
		rs.frequency=rs.frequency.compute({'Bpctn','Bpctn'},CEIL(Frequency*Bpct));
				dscode='data '|| intable || '_bskey; call streaminit('|| seed ||'); do bs = 1 to '|| bss || '; bsID = (_threadid_-1)*'|| bss ||' + bs;';
					do row over rs.frequency;
						dscode=dscode||'stratan='|| strip(row.FmtVar) ||'/'|| strata_div ||'; do bs_caseIDn = 1 to '|| row.Bpctn ||'; caseID=int(1+'|| row.Frequency ||'*rand(''Uniform'')); bs_caseID=bs_caseIDn+stratan; caseID=caseID+stratan; bag=1; output; end;';
					end;
					dscode=dscode||'end; drop bs bs_caseIDn stratan; run;';
				datastep.runcode result=t / code=dscode;
end;
else do;
		r.numCases=r.numrows;
		r.Bpctn=CEIL(r.numCases*Bpct);
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
end;
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
run;

cas mysess clear;
