/* a step by step walkthrough of the doubleBootstrap action in the resample actionset
  link to wiki:
*/

/* set a local path */
		%let locpath=/home/mihend/sasuser.viya/Bootstrap;

/* setup a session */
		cas mysess sessopts=(caslib='casuser');
		libname mycas cas sessref=mysess;

/* data for examples */
		libname mylocal "&locpath.";
		data myloc.cars; set sashelp.cars; run;
		data myloc.carsbig; set sashelp.cars; do i=1 to 10; output; end; drop i; run;
		data myloc.carsbigger; set sashelp.cars; do i=1 to 100; output; end; drop i; run;
		data myloc.carsbiggest; set sashelp.cars; do i=1 to 1000; output; end; drop i; run;

/* 2 functions for adding automatic variables to dataset and looking at distribution of tables
		%include later: https://documentation.sas.com/?cdcId=pgmsascdc&cdcVersion=9.4_3.4&docsetId=lestmtsglobal&docsetTarget=p1s3uhhqtscz2sn1otiatbovfn1t.htm&locale=en
		*/
		proc cas;
		   function addautos(intable);
			 		datastep.runcode result=t / code='data intable; set intable; n=_n_; nthread=_nthreads_; thread=_threadid_; host=_hostname_; run;';
					return(t);
		   end func;
			 function summtab(intable);
				 table.tabledetails / level="node" table=intable;
				 simple.summary result=r / inputs={"N"} subSet={"MAX", "MIN", "N"}
					 table={name=intable, groupBy={"nthread", "host", "thread"}}
					 casout={name=intable||"_dist", replace=TRUE};
			 	 return(r);
			 end func;
		run;

/* Load Cars
			From: local
			To: CAS
			With: CAS upload action
			and examine distribution
*/
		proc cas;
			upload path="&locpath./cars.sas7bdat" casout={name="cars" replace=TRUE} importoptions={filetype="BASESAS"};
			%include 23-33;
			t=addautos(cars);
			r=summtab(cars);
		run;
		data mycas.cars;
			set mycas.cars;
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

/* Load Cars
			From: local
			To: CAS
			With: Data Step
			and examine distribution
*/
		data mycas.cars;
			set mylocal.cars;
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
				/* redo auto variables examine distribution From: CAS To: CAS */
						data mycas.cars;
							set mycas.cars;
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

/* Load Cars
			From: local
			To: CAS
			With: Proc CASUTIL
			and examine distribution
*/
		proc casutil;
			load data=mylocal.cars casout="cars" replace;
		quit;
				data mycas.cars;
					set mycas.cars;
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
				data mycas.cars;
					set mycas.cars;
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
				data mycas.cars;
					set mycas.cars;
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

/* make data bigger then load to CAS and examine distribution: CAS, DATA STEP, CASUTIL */








/* Create data
			From: CAS
			To: CAS
			With: Data Step
			and examine distribution
*/
		data mycas.temp / sessref=mysess;
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
						data mycas.temp;
							set mycas.temp;
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
/* Create data
			From: CAS
			To: CAS
			With: Data Step action
			and examine distribution
*/


/* create the bootstrap resamples - look at the cars_bs file after running */
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.bootstrap / intable='cars' B=10;
run;
		data mycas.cars;
			set mycas.cars;
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
	resample.addRowID / intable='cars';
run;
		data mycas.cars;
			set mycas.cars;
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
