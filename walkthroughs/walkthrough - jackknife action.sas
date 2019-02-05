/* a step by step walkthrough of the jackknife action in the resample actionset
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
		case='unique_case'; /* if the value is a column in intable then uses unique values of that column as cases, otherwise will use rows of intable as cases */
run;

		/* workflow: if case is a column in intable the do first route, otherwise do second route (else) */
		table.columninfo result=i / table=intable;
				/* if a column caseID is present then drop it - protected term, may be leftover from previous run */
				if i.columninfo.where(upcase(Column)='CASEID').nrows=1 then do;
					alterTable / name=intable columns={{name='caseID', drop=TRUE}};
				end;
				/* first route: case is a column in intable */
				if i.columninfo.where(upcase(column)=upcase(CASE)).nrows=1 then do;
						/* make a one column table of unique cases */
						fedsql.execDirect / query='create table '|| intable ||'_cases {options replace=TRUE} as select distinct '|| CASE ||' from '|| intable;
						/* addRowID to the unique cases, then rename rowID to caseID */
						resample.addRowID / intable=intable||'_cases';
							alterTable / name=intable||'_cases' columns={{name='rowID',rename='caseID'}};
						/* store the row count from the cases for further calculations */
						simple.numRows result=r / table=intable||'_cases';
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
				/* second route: case is not a column in intable */
				else do;
						/* addRowID to intable since rows are unique cases, then rename rowID to caseID */
						resample.addRowID / intable=intable;
							alterTable / name=intable columns={{name='rowID',rename='caseID'}};
						/* store the row count from the cases for further calculations */
						simple.numRows result=r / table=intable;
				end;
run;

		/* store the size of the original sample data (cases) in r.numCases */
		r.numCases=r.numrows;
run;

		/* create a structure for the jackknife sampling.
      		Will make resamples equal to the size of the original table -1 row
      		single='YES' create this structure on a single node/thread of the CAS environment */
		datastep.runcode result=t / code='data '|| intable ||'_jkkey;
									do jkID = 1 to '|| r.numCases ||';
										do caseID = 1 to '|| r.numCases ||';
											bag=1;
											if jkID ne caseID then output;
										end;
									end;
								run;' single='YES';
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_jkkey; set '||intable||'_jkkey; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_jkkey" where="bag=1"} row="jkID" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_jkkey" where="bag=1"} row="jkID" col="threadid" aggregator="N";
run;

		/* merge the structure with the input table */
		fedSql.execDirect / query='create table '|| intable ||'_jk {options replace=TRUE} as
										select * From
											(select jkID, caseID, bag from '|| intable ||'_jkkey) a
											join
											(select * from '|| intable ||') b
											using(caseID)';
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_jk; set '||intable||'_jk; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_jk" where="bag=1"} row="jkID" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_jk" where="bag=1"} row="jkID" col="threadid" aggregator="N";
run;

		dropTable name=intable||'_jkkey';
run;

		partition / casout={name=intable||'_jk', replace=TRUE} table={name=intable||'_jk', groupby={{name='jkID'}}};
run;

		/*  take a look at how the table is distributed in the CAS environment */
		datastep.runcode result=t / code='data '||intable||'_jk; set '||intable||'_jk; host=_hostname_; threadid=_threadid_; run;';
		simple.crossTab / table={name=intable||"_jk" where="bag=1"} row="jkID" col="host" aggregator="N";
		simple.crossTab / table={name=intable||"_jk" where="bag=1"} row="jkID" col="threadid" aggregator="N";
		alterTable / name=intable||"_jk" columns={{name='host', drop=TRUE},{name='threadid', drop=TRUE}};
run;

quit;


*cas mysess clear;
