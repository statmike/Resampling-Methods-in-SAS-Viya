cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

proc cas;
	x1='"x1"';
		print x1;
	x2="""x2""";
		print x2;
	x3="'x3'";
		print x3;
	x4='''x4''';
		print x4;
	x5="Here is a 'quote with a nested (""quote"")'";
		print x5;
run;

/* log
"x1"
"x2"
'x3'
'x4'
Here is a 'quote with a nested ("quote")'
*/






proc casutil;
	load data=sashelp.cars casout="sample" replace;
run;

proc cas;
   loadactionset / actionset='regression';
   glm result=r / table  = {name='sample'},
		 class = {'Cylinders','Make','Type','Origin','DriveTrain'},
		 model = {
					clb=TRUE,
		 			target = 'MSRP'
		 			effects = {
								{vars={'Make','Type','Origin','DriveTrain','EngineSize','EngineSize','Cylinders','Horsepower','Horsepower','MPG_City','MPG_Highway','Weight','Weight','Wheelbase'},interaction='BAR',maxinteract=2}
							}
		 			},
         selection = 'FORWARDSWAP',
         outputTables = {names={'ParameterEstimates'="sample_PE"}, replace=TRUE};
run;

proc cas;
	fedSql.execDirect / query='create table temp {options replace=true} as select distinct "Parameter", Estimate from sample_PE';
run;

proc cas;
builtins.defineActionSet /
	name = "example"
	actions = {
			{
				name = "quoteJail"
				definition = "fedSql.execDirect /
								query='create table temp {options replace=true} as
										select distinct ""Parameter"", Estimate from sample_PE';"
			}
		}
;
run;

proc cas;
	example.quoteJail;
run;



*cas mysess clear;
