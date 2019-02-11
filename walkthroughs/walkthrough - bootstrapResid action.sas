/* a step by step walkthrough of the regressionPE action in the resample actionset
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

/* build model add residuals to intable */
    class = {'Origin','DriveTrain'};
    model = {
         target = 'MSRP'
         effects = {
               {vars={'Weight','EngineSize','Origin','Horsepower','DriveTrain','Wheelbase','MPG_Highway'}},
               {vars={'EngineSize','Origin'}, interaction='CROSS'},
               {vars={'Horsepower','Origin'}, interaction='CROSS'},
               {vars={'Horsepower','DriveTrain'}, interaction='CROSS'},
               {vars={'EngineSize','Horsepower'}, interaction='CROSS'},
               {vars={'EngineSize','Wheelbase'}, interaction='CROSS'},
               {vars={'Horsepower','Horsepower'}, interaction='CROSS'},
               {vars={'Horsepower','MPG_Highway'}, interaction='CROSS'},
               {vars={'Horsepower','Wheelbase'}, interaction='CROSS'}
             }
         };
   loadactionset / actionset='regression';
   glm / table  = {name='sample'},
      class = class,
      model = model,
      output = {casOut={name='sample_pred', replace=TRUE}, pred='Pred', resid='Residual', student='stuResidual', rstudent='rstuResidual' copyVars={"ALL"}};
run;

/*
feed sample_pred to bootstrap (all original data + residuals), maybe=unique_cases
  columns in bs_key = bsID, caseID, residualID, residual + all (target=target+residual)


*/







/* define parameters to hold the action inputs */
	  intable='sample_pred';
	  case='unique_case'; /* if the value is a column in intable then uses unique values of that column as cases, otherwise will use rows of intable as cases */
    B = 100;
    Bpct = 1;
    seed = 12345;
    D = 10;
    Dpct = 1;
run;


    loadactionset / actionset='regression';
    regression.glm /
      table = intable,
      class = class,
      model = model,
      outputTables = {names={'ParameterEstimates'=intable||"_PE"}, replace=TRUE};
run;
