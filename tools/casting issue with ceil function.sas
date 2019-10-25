cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

proc cas;
    numrows=73;
    strata_div=10**ceil(log10(numrows+1));
run;
/*
ERROR: Binary operation is not supported
ERROR: An expression failed to evaluate
ERROR: strata_div = 10 ** ceil ( log10 ( numrows + 1 ) ) ;
ERROR: ^
ERROR: Execution halted
*/
    a=numrows+1; describe a; print a;
run;
/*
int64_t;
74
*/
    b=log10(a); describe b; print b;
run;
/*
double;
1.8692317197
*/
    c=ceil(b); describe c; print c;
run;
/*
double;
2
*/
    d=10**c; describe d; print d;
run;
/*
ERROR: Binary operation is not supported
ERROR: An expression failed to evaluate
ERROR: d = 10 ** c ;
ERROR: ^
ERROR: Execution halted
*/
	  d=10**(int64)(c); describe d; print d;
run;
/*
int64_t;
100
*/
    strata_div=10**((int64)(ceil(log10(numrows+1))));
    describe strata_div; print strata_div;
run;
/*
int64_t;
100
*/


proc cas;
	sccasl.runcasl result=r / code="numrows=73; strata_div=10**((int64)(ceil(log10(numrows+1))));";
run;
/*
ERROR: strata_div = 10 * * ( ( int64 ) ( ceil ( log10 ( numrows + 1
ERROR:                   ^
ERROR: A binary operator was not expected
ERROR: The code stream was not executed due to errors.
ERROR: The action stopped due to errors.
*/
	sccasl.runcasl result=r / code="strata_div=10**3;";
run;
/*
ERROR: strata_div = 10 * * 3 ;
ERROR:                   ^
ERROR: A binary operator was not expected
ERROR: The code stream was not executed due to errors.
ERROR: The action stopped due to errors.
*/

*cas mysess clear;
