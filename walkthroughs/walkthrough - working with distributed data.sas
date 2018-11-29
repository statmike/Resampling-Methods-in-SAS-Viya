understanding distributed data in sas
	look at proc that brings data back
		look at it with a where statement - only some rows



cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;



/* load to CAS and examine distribution using action */
libname myloc '/home/mihend/sasuser.viya/Bootstrap';
data myloc.cars; set sashelp.cars; do i=1 to 1001; output; end; drop i; run;
proc cas;
	upload path="/home/mihend/sasuser.viya/Bootstrap/cars.sas7bdat" casout={name="cars" replace=TRUE} importoptions={filetype="BASESAS"};
run;
data mylib.cars;
	set mylib.cars;
	n=_n_;
	nthread=_nthreads_;
	thread=_threadid_;
	host=_hostname_;
run;
		proc cas;
			table.tabledetails / level="node" table="cars";
			simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
				table={name="cars", groupBy={"nthread", "host", "thread"}}
				casout={name="cars_dist", replace=TRUE};
		run;





/* load to CAS and examine distribution */
data mylib.cars;
	set sashelp.cars;
	n=_n_;
	nthread=_nthreads_;
	thread=_threadid_;
	host=_hostname_;
run;
		proc cas;
			table.tabledetails / level="node" table="cars";
			simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
				table={name="cars", groupBy={"nthread", "host", "thread"}}
				casout={name="cars_dist", replace=TRUE};
		run;








/* redo auto variables examine distribution CAS to CAS */
data mylib.cars;
	set mylib.cars;
	n=_n_;
	nthread=_nthreads_;
	thread=_threadid_;
	host=_hostname_;
run;
		proc cas;
			table.tabledetails / level="node" table="cars";
			simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
				table={name="cars", groupBy={"nthread", "host", "thread"}}
				casout={name="cars_dist", replace=TRUE};
		run;








/* shuffle rows and examine distribution */
proc cas;
	shuffle / casout={name="cars", replace=TRUE} table="cars";
run;
		data mylib.cars;
			set mylib.cars;
			n=_n_;
			nthread=_nthreads_;
			thread=_threadid_;
			host=_hostname_;
		run;
		proc cas;
			table.tabledetails / level="node" table="cars";
			simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
				table={name="cars", groupBy={"nthread", "host", "thread"}}
				casout={name="cars_dist", replace=TRUE};
		run;








/* partition rows and examine distribution */
proc cas;
	partition / casout={name="cars", replace=TRUE} table={name="cars", groupby={{name="Make"}}};
run;
		data mylib.cars;
			set mylib.cars;
			n=_n_;
			nthread=_nthreads_;
			thread=_threadid_;
			host=_hostname_;
		run;
		proc cas;
			table.tabledetails / level="node" table="cars";
			simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
				table={name="cars", groupBy={"nthread", "host", "thread"}}
				casout={name="cars_dist", replace=TRUE};
		run;
		proc cas;
			simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
				table={name="cars", groupBy={"nthread", "host", "thread","Make"}}
				casout={name="cars_dist", replace=TRUE};
		run;








/* use CASUTIL to load to CAS and examine distribution */
proc casutil;
	load data=sashelp.cars casout="cars" replace;
quit;
		data mylib.cars;
			set mylib.cars;
			n=_n_;
			nthread=_nthreads_;
			thread=_threadid_;
			host=_hostname_;
		run;
		proc cas;
			table.tabledetails / level="node" table="cars";
			simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
				table={name="cars", groupBy={"nthread", "host", "thread"}}
				casout={name="cars_dist", replace=TRUE};
		run;








/* make data bigger then load to CAS and examine distribution */
data cars; set sashelp.cars;
	do i = 1 to 1000;
		output;
	end;
	drop i;
run;
proc casutil;
	load data=work.cars casout="cars" replace;
quit;
		data mylib.cars;
			set mylib.cars;
			n=_n_;
			nthread=_nthreads_;
			thread=_threadid_;
			host=_hostname_;
		run;
		proc cas;
			table.tabledetails / level="node" table="cars";
			simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
				table={name="cars", groupBy={"nthread", "host", "thread"}}
				casout={name="cars_dist", replace=TRUE};
		run;








/* create data in CAS and examine distribution */
data mylib.temp / sessref=mysess;
	do i = 1 to 2;
		n=_n_;
		nthread=_nthreads_;
		thread=_threadid_;
		host=_hostname_;
		output;
	end;
run;
		proc cas;
			table.tabledetails / level="node" table="temp";
			simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
				table={name="temp", groupBy={"nthread", "host", "thread"}}
				casout={name="temp_dist", replace=TRUE};
		run;

		/* redo auto variables and examine distribution */
		data mylib.temp;
			set mylib.temp;
			n=_n_;
			nthread=_nthreads_;
			thread=_threadid_;
			host=_hostname_;
		run;
				proc cas;
					table.tabledetails / level="node" table="temp";
					simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
						table={name="temp", groupBy={"nthread", "host", "thread"}}
						casout={name="temp_dist", replace=TRUE};
				run;








/* load and examine distribution - refresher */
proc casutil;
	load data=sashelp.cars casout="cars" replace;
quit;
		data mylib.cars;
			set mylib.cars;
			n=_n_;
			nthread=_nthreads_;
			thread=_threadid_;
			host=_hostname_;
		run;
		proc cas;
			table.tabledetails / level="node" table="cars";
			simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
				table={name="cars", groupBy={"nthread", "host", "thread"}}
				casout={name="cars_dist", replace=TRUE};
		run;



/* create the bootstrap resamples - look at the sample file after running */
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.bootstrap / intable='cars' B=10;
run;
		data mylib.cars;
			set mylib.cars;
			n=_n_;
			nthread=_nthreads_;
			thread=_threadid_;
			host=_hostname_;
		run;
		proc cas;
					table.tabledetails / level="node" table="cars";
					simple.summary result=r / inputs={"N","rowID"} subSet={"MAX", "MIN", "N"}
						table={name="cars", groupBy={"nthread", "host", "thread"}}
						casout={name="cars_dist", replace=TRUE};
		run;









/* go create a rowID action and run it here, then review */
proc cas;
	mikeH.addRowID / intable='cars';
run;
		data mylib.cars;
			set mylib.cars;
			n=_n_;
			nthread=_nthreads_;
			thread=_threadid_;
			host=_hostname_;
		run;
		proc cas;
					table.tabledetails / level="node" table="cars";
					simple.summary result=r / inputs={"N","rowID"} subSet={"MAX", "MIN", "N"}
						table={name="cars", groupBy={"nthread", "host", "thread"}}
						casout={name="cars_dist", replace=TRUE};
		run;

*cas mysess clear;
