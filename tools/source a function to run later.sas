cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

proc cas;
	source sf1;
		function f1(innum);
			outnum=innum*2;
			print outnum;
			return(outnum);
		end func;
		print "this is the result of the function: " f1(x);
	endsource;

	loadactionset / actionset="sccasl";
	sccasl.runCasl result=temp / code=sf1 vars={x=4};
run;

*cas mysess clear;
