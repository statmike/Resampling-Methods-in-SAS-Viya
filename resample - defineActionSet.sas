cas mysess sessopts=(caslib='casuser');
*libname mylib cas sessref=mysess;

proc cas;
	builtins.defineActionSet /
		name = "resample"
		actions = {
			{
				name = "addRowID"
				desc = "Add a naturally numbered (1,... n) column to a CAS Table"
				parms = {
					{name="intable", type="STRING", required=TRUE}
				}
				definition = "
							table.columninfo result=i / table=intable;
								if i.columninfo.where(Column='ROWID').nrows=1 then do;
									alterTable / name=intable columns={{name='ROWID', drop=TRUE}};
								end;
								else; do; end;
							datastep.runcode result=t / code='data '|| intable ||'; set '|| intable ||'; threadid=_threadid_; n=_n_; run;';
							fedSql.execDirect / query='create table '|| intable ||' {options replace=TRUE} as
															select * from
																'|| intable ||'
																join
																(select c.threadid, c.n, c.n+ifnull(d.basecount,0) as rowID from
																	(select threadid, n from '|| intable ||') c
																	left outer join
																	(select a.threadid, sum(b.threadcount) as basecount from
																			((select distinct threadid from '|| intable ||') a
																			left outer join
																			(select threadid, count(*) as threadcount from '|| intable ||' group by threadid) b
																			on b.threadid < a.threadid)
																			group by a.threadid) d
																	on c.threadid=d.threadid) e
																using(threadid,n)';
							alterTable / name=intable columns={{name='n', drop=TRUE},{name='threadid', drop=TRUE}};
				"
			}
			{
				name = "bootstrap"
				desc = "Create a table with bootstrap resamples of input table"
				parms = {
					{name="intable", type="STRING", required=TRUE},
					{name="B", type="INT", required=TRUE},
					{name="seed", type="INT", required=TRUE},
					{name="Bpct", type="DOUBLE", required=TRUE},
					{name="Case", type="STRING", required=TRUE}
				}
				definition = "
							table.columninfo result=i / table=intable;
									if i.columninfo.where(upcase(Column)='CASEID').nrows=1 then do;
										alterTable / name=intable columns={{name='caseID', drop=TRUE}};
									end;
									if i.columninfo.where(upcase(column)=upcase(CASE)).nrows=1 then do;
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
											resample.addRowID / intable=intable;
												alterTable / name=intable columns={{name='rowID',rename='caseID'}};
											simple.numRows result=r / table=intable;
									end;
							r.numCases=r.numrows;
							r.Bpctn=CEIL(r.numCases*Bpct);
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
				"
			}
			{
				name = "doubleBootstrap"
				desc = "Create a table with double-bootstrap resamples of input table sample_bs created by the bootstrap action"
				parms = {
					{name="intable", type="STRING", required=TRUE},
					{name="B", type="INT", required=TRUE},
					{name="D", type="INT", required=TRUE},
					{name="seed", type="INT", required=TRUE},
					{name="Bpct", type="DOUBLE", required=TRUE},
					{name="Dpct", type="DOUBLE", required=TRUE},
					{name="Case", type="STRING", required=TRUE}
				}
				definition = "
							table.tableExists result=c / name=intable||'_bs';
								if c.exists==0 then do;
									bootstrap result=r / intable=intable B=B seed=seed Bpct=Bpct Case=Case;
								end;
							datastep.runcode result=t / code='data tempholdbss; set '|| intable || '_bs; threadid=_threadid_; nthreads=_nthreads_; run;';
									fedsql.execDirect result=q1 / query='select count(*) as cbsid from (select distinct bsID from tempholdbss) a';
									fedsql.execDirect result=q2 / query='select max(nthreads) as nthreads from tempholdbss';
									dropTable name='tempholdbss';
									bss=q1[1,1].cbsid/q2[1,1].nthreads;
									*print bss;
							table.columninfo result=i / table=intable;
									if i.columninfo.where(upcase(column)=upcase(CASE)).nrows=1 then do;
											fedsql.execDirect / query='create table '|| intable ||'_cases {options replace=TRUE} as select distinct caseID from '|| intable;
											simple.numRows result=r / table=intable||'_cases';
											dropTable name=intable||'_cases';
									end;
									else do;
											simple.numRows result=r / table=intable;
									end;
							r.numCases=r.numrows;
							r.Bpctn=CEIL(r.numCases*Bpct);
							r.Dpctn=CEIL(r.Bpctn*Dpct);
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
							fedSql.execDirect / query='create table '|| intable ||'_dbskey {options replace=TRUE} as
															select * from
																(select * from '|| intable ||'_dbskey) a
																join
																(select distinct bsID, bs_caseID, caseID from '|| intable ||'_bs where bag=1) b
																using (bsID,bs_caseID)';
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
							dropTable name=intable||'_dbskey';
							partition / casout={name=intable||'_dbs', replace=TRUE} table={name=intable||'_dbs', groupby={{name='bsID'}}};
				"
			}
			{
				name = "jackknife"
				desc = "Create a table with jackknife resamples of input table"
				parms = {
					{name="intable", type="STRING", required=TRUE},
					{name="Case", type="STRING", required=TRUE}
				}
				definition = "
							table.columninfo result=i / table=intable;
									if i.columninfo.where(upcase(Column)='CASEID').nrows=1 then do;
										alterTable / name=intable columns={{name='caseID', drop=TRUE}};
									end;
									if i.columninfo.where(upcase(column)=upcase(CASE)).nrows=1 then do;
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
											resample.addRowID / intable=intable;
												alterTable / name=intable columns={{name='rowID',rename='caseID'}};
											simple.numRows result=r / table=intable;
									end;
							r.numCases=r.numrows;
							datastep.runcode result=t / code='data '|| intable ||'_jkkey;
														do jkID = 1 to '|| r.numCases ||';
												 			do caseID = 1 to '|| r.numCases ||';
																bag=1;
																if jkID ne caseID then output;
															end;
														end;
													run;' single='YES';
							fedSql.execDirect / query='create table '|| intable ||'_jk {options replace=TRUE} as
															select * From
																(select jkID, caseID, bag from '|| intable ||'_jkkey) a
																join
																(select * from '|| intable ||') b
																using(caseID)';
							dropTable name=intable||'_jkkey';
							partition / casout={name=intable||'_jk', replace=TRUE} table={name=intable||'_jk', groupby={{name='jkID'}}};
				"
			}
			{
				name = "percentilePE"
				desc = "Create a table with percentile based CI's for each resample method that has been run"
				parms = {
					{name="intable", type="STRING", required=TRUE},
					{name="alpha", type="DOUBLE", required=TRUE}
				}
				definition = "
							percs={100*alpha/2,50,100-100*alpha/2};
							table.tableExists result=bs / name=intable||'_BS_PE';
							table.tableExists result=dbs / name=intable||'_DBS_PE';
							table.tableExists result=jk / name=intable||'_JK_PE';
							if bs.exists+dbs.exists+jk.exists>0 then do;
								PEquery='create table sample_PE_percentiles {options replace=true} as
													select * from
														(select ""Parameter"", Estimate, LowerCL, UpperCL from '|| intable ||'_PE) a';
							end;
					    if bs.exists then do;
					      percentile / table = {name=intable||'_BS_PE', groupBy='Parameter', vars={'Estimate'}},
					        casOut = {name=intable||'_BS_PE_perc', replace=TRUE},
					        values = percs;*{2.5, 50, 97.5};
					      PEquery=PEquery||' join
					                        (select ""Parameter"", _Value_ as BS_LowerCL from '||intable||'_BS_PE_perc where _pctl_='||(string)(percs[1])||') bb
					                        using (""Parameter"")
					                        join
					                        (select ""Parameter"", _Value_ as BS_Estimate from '||intable||'_BS_PE_perc where _pctl_=50) cb
					                        using (""Parameter"")
					                        join
					                        (select ""Parameter"", _Value_ as BS_UpperCL from '||intable||'_BS_PE_perc where _pctl_='||(string)(percs[3])||') db
					                        using (""Parameter"")';
					    end;
					    if dbs.exists then do;
					      percentile / table = {name=intable||'_DBS_PE', groupBy='Parameter', vars={'Estimate'}},
					        casOut = {name=intable||'_DBS_PE_perc', replace=TRUE},
					        values = percs;*{2.5, 50, 97.5};
					      PEquery=PEquery||' join
					                        (select ""Parameter"", _Value_ as DBS_LowerCL from '||intable||'_DBS_PE_perc where _pctl_='||(string)(percs[1])||') bd
					                        using (""Parameter"")
					                        join
					                        (select ""Parameter"", _Value_ as DBS_Estimate from '||intable||'_DBS_PE_perc where _pctl_=50) cd
					                        using (""Parameter"")
					                        join
					                        (select ""Parameter"", _Value_ as DBS_UpperCL from '||intable||'_DBS_PE_perc where _pctl_='||(string)(percs[3])||') dd
					                        using (""Parameter"")';
					    end;
					    if jk.exists then do;
					      percentile / table = {name=intable||'_JK_PE', groupBy='Parameter', vars={'Estimate'}},
					        casOut = {name=intable||'_JK_PE_perc', replace=TRUE},
					        values = percs;*{2.5, 50, 97.5};
					      PEquery=PEquery||' join
					                        (select ""Parameter"", _Value_ as JK_LowerCL from '||intable||'_JK_PE_perc where _pctl_='||(string)(percs[1])||') bj
					                        using (""Parameter"")
					                        join
					                        (select ""Parameter"", _Value_ as JK_Estimate from '||intable||'_JK_PE_perc where _pctl_=50) cj
					                        using (""Parameter"")
					                        join
					                        (select ""Parameter"", _Value_ as JK_UpperCL from '||intable||'_JK_PE_perc where _pctl_='||(string)(percs[3])||') dj
					                        using (""Parameter"")';
					    end;
							if bs.exists+dbs.exists+jk.exists>0 then do;
								*print PEquery;
					    	fedsql.execDirect / query=PEquery;
							end;
				"
			}
		}
	;
	builtins.actionSetToTable / actionset="resample" casOut={caslib="casuser" name="resample" replace=True};
	table.save / table="resample" caslib="Public" name="resampleActionSet.sashdat" replace=True;
		/* to remove this table at any point use the following */
		*table.deleteSource / Source="resampleActionSet.sashdat" caslib="Public";
run;

quit;
cas mysess clear;
