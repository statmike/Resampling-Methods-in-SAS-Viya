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
							fedSql.execDirect / query='create table '|| intable ||' {options replace=true} as
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
					{name="Bpct", type="DOUBLE", required=TRUE}
				}
				definition = "
							resample.addRowID / intable=intable;
							datastep.runcode result=t / code='data tempholdb; nthreads=_nthreads_; output; run;';
									fedsql.execDirect result=q / query='select max(nthreads) as M from tempholdb';
									dropTable name='tempholdb';
									bss=ceil(B/q[1,1].M);
							simple.numRows result=r / table=intable;
									r.Bpctn=CEIL(r.numrows*Bpct);
							datastep.runcode result=t / code='data '|| intable ||'_bskey;
														call streaminit('|| seed ||');
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
							partition / casout={name=intable||'_bs', replace=TRUE} table={name=intable||'_bs', groupby={{name='bsID'}}};
							dropTable name=intable||'_bskey';
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
					{name="Dpct", type="DOUBLE", required=TRUE}
				}
				definition = "
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
											/* calculate bss, can this be retrieved as response from the bootsrap action (not working) */
											datastep.runcode result=t / code='data tempholdbss; set '|| intable || '_bs; threadid=_threadid_; nthreads=_nthreads_; run;';
													fedsql.execDirect result=q / query='select max(bscount) as bss from (select count(*) as bscount from (select distinct bsID, threadid from tempholdbss) a group by threadid) b';
													dropTable name='tempholdbss';
													bss=q[1,1].bss;
								end;
							simple.numRows result=r / table=intable;
									r.Bpctn=CEIL(r.numrows*Bpct);
									r.Dpctn=CEIL(r.Bpctn*Dpct);
							datastep.runcode result=t / code='data '|| intable ||'_dbskey;
															  	call streaminit('|| seed ||');
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
							fedSql.execDirect / query='create table '|| intable ||'_dbskey {options replace=true} as
															select * from
																(select * from '|| intable ||'_dbskey) a
																join
																(select bsID, bs_rowID, rowID from '|| intable ||'_bs where bag=1) b
																using (bsID,bs_rowID)';
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
							partition / casout={name=intable||'_dbs', replace=TRUE} table={name=intable||'_dbs', groupby={{name='bsID'},{name='dbsID'}}};
							dropTable name=intable||'_dbskey';
				"
			}
			{
				name = "jackknife"
				desc = "Create a table with jackknife resamples of input table"
				parms = {
					{name="intable", type="STRING", required=TRUE}
				}
				definition = "
							resample.addRowID / intable=intable;
							simple.numRows result=r / table=intable;
							datastep.runcode result=t / code='data '|| intable ||'_jkkey;
														do jkID = 1 to '|| r.numrows ||';
												 			do rowID = 1 to '|| r.numrows ||';
																bag=1;
																if jkID ne rowID then output;
															end;
														end;
													run;' single='YES';
							fedSql.execDirect / query='create table '|| intable ||'_jk {options replace=true} as
															select * From
																(select jkID, rowID, bag from '|| intable ||'_jkkey) a
																join
																(select * from '|| intable ||') b
																using(rowID)';
							partition / casout={name=intable||'_jk', replace=TRUE} table={name=intable||'_jk', groupby={{name='jkID'}}};
							dropTable name=intable||'_jkkey';
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
