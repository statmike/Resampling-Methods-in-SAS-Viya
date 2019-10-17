cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

proc casutil;
	load data=sashelp.cars casout="sample" replace; /* n=428 */
run;
proc cas;
	simple.numRows result=r / table='sample';
	simple.freq result=r / inputs='Origin' table='sample';
	describe r;
	print r.frequency[,{"FmtVar","Frequency"}];
	print r.frequency[1:3,5];
	r.frequency=r.frequency.compute({"NewSize","New Size"},CEIL(Frequency*.5));
	print r.frequency;
	do row over r.frequency;
		print row.FMtVar;
	end;
run;

proc cas;
	datastep.runcode result=t / code='data sample; set sample; host=_hostname_; threadid=_threadid_; run;';
	simple.crossTab / table={name="sample"} row="make" col="host" aggregator="N";
	simple.crossTab / table={name="sample"} row="make" col="threadid" aggregator="N";
run;

data mylib.sample;
	set mylib.sample;
	by make;
	retain rowID;
	if first.make then rowID=1;
		else rowID+1;
run;

proc cas;
	datastep.runcode result=t / code='data sample; set sample; host=_hostname_; threadid=_threadid_; run;';
	simple.crossTab / table={name="sample"} row="make" col="host" aggregator="N";
	simple.crossTab / table={name="sample"} row="make" col="threadid" aggregator="N";
run;

cas mysess clear;
