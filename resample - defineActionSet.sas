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
					{name="intable" type="string" required=TRUE}
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
					{name="intable" type="string" required=TRUE}
					{name="B" type="int" required=TRUE default=100}
				}
				definition = "
							resample.addRowID / intable=intable;
							datastep.runcode result=t / code='data tempholdb; nthreads=_nthreads_; output; run;';
									fedsql.execDirect result=q / query='select max(nthreads) as M from tempholdb';
									dropTable name='tempholdb';
									bss=ceil(B/q[1,1].M);
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
							dropTable name=intable||'_bskey';
				"
			}
			{
				name = "doubleBootstrap"
				desc = "Create a table with double bootstrap resamples of input table sample_bs created by the bootstrap action"
				parms = {
					{name="intable" type="string" required=TRUE}
					{name="B" type="int" required=TRUE default=10}
				}
				definition = "
							table.tableExists result=c / name=intable||'_bs';
								if c.exists then do;

								end;
								else; do;
									resample.bootstrap / intable=intable B=B;
								end;
							datastep.runcode result=t / code='data tempholdb; nthreads=_nthreads_; output; run;';
									fedsql.execDirect result=q / query='select max(nthreads) as M from tempholdb';
									dropTable name='tempholdb';
									bss=ceil(B/q[1,1].M);
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
							dropTable name=intable||'_dbskey';
				"
			}
		}
	;
	builtins.actionSetToTable / actionset="resample" casOut={caslib="casuser" name="resample" replace=True};
	table.save / table="resample" caslib="Public" name="resampleActionSet.sashdat" replace=True;
		/* to remove this table at any point use the following */
		*table.deleteSource / Source="resampleActionSet.sashdat" caslib="Public";
run;


*cas mysess clear;
