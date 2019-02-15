/*
unfinished and depricated
REASON:
	create percentilePE action
		user can... model full, resample, model resamples, run percentilePE

FUTURE: would be great if for any model building action you could save the output model action spec to rerun/refit on a new intable
*/


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

/* build model - select effects with forwardswap, consider 2-way interactions, include poly(2) terms for enginesize, horsepower, weight */
   loadactionset / actionset='regression';
   glm / table  = {name='sample'},
		 class = {'Cylinders','Make','Type','Origin','DriveTrain'},
		 model = {
					clb=TRUE,
		 			target = 'MSRP'
		 			effects = {
								{vars={'Make','Type','Origin','DriveTrain','EngineSize','EngineSize','Cylinders','Horsepower','Horsepower','MPG_City','MPG_Highway','Weight','Weight','Wheelbase'},interaction='BAR',maxinteract=2}
							}
		 			},
         selection = 'FORWARDSWAP',
		 display = {names={'ParameterEstimates','Anova','FitStatistics'}},
         outputTables = {names={'ParameterEstimates'="sample_PE",'SelectedEffects'="sample_SE"}, replace=TRUE},
         output = {casOut={name='sample_pred', replace=TRUE},
         		   pred='Pred', resid='Resid', cooksd='CooksD', h='H',
         		   copyVars={"MSRP"}};
run;

/* define parameters to hold the action inputs */
	  intable='sample';
    method='bootstrap';
		  case='unique_case'; /* if the value is a column in intable then uses unique values of that column as cases, otherwise will use rows of intable as cases */
      B = 100;
      Bpct = 1;
      seed = 12345;
      D = 10;
      Dpct = 1;
    class = {'Origin','DriveTrain'};
    model = {
         clb=TRUE,
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
run;

/* run model on the sample data */
    loadactionset / actionset='regression';
    regression.glm result=temp /
      table = intable,
      class = class,
      model = model,
      outputTables = {names={'ParameterEstimates'=intable||"_PE"}, replace=TRUE};
run;

/* based on bootstrap method, resample, fit same model to all the resamples, calculate percentiles of all the model parameter estimates, combine full and bs parameter estimates */
    if method=='bootstrap' then do;
      resample.bootstrap / intable=intable B=B seed=seed Bpct=Bpct case=case;
      regression.glm result=temp /
        table = {name=intable||'_BS', groupBy='bsID'},
        class = class,
        model = model,
        partByVar = {name="bag",train="1",test="0"},
        outputTables = {names={'ParameterEstimates'=intable||"_BS_PE"}, groupByVarsRaw=TRUE, replace=TRUE};
      percentile / table = {name=intable||"_BS_PE", groupBy='Parameter', vars={"Estimate"}},
        casOut = {name=intable||"_BS_PE_perc", replace=TRUE},
        values = {2.5, 50, 97.5};
      fedSql.execDirect / query='create table sample_BS_PE_PLOT {options replace=true} as
                                  select * from
                                  	(select "Parameter", Estimate, LowerCL, UpperCL from sample_PE) a
                                  	join
                                  	(select "Parameter", _Value_ as BS_LowerCL from sample_BS_PE_perc where _pctl_=2.5) b
                                  	using ("Parameter")
                                  	join
                                  	(select "Parameter", _Value_ as BS_Estimate from sample_BS_PE_perc where _pctl_=50) c
                                  	using ("Parameter")
                                  	join
                                  	(select "Parameter", _Value_ as BS_UpperCL from sample_BS_PE_perc where _pctl_=97.5) d
                                  	using ("Parameter")
                                  ';
    end;
    else if method=='doubleBootstrap' then do;
      resample.doubleBootstrap / intable=intable B=B seed=seed Bpct=Bpct case=case D=D Dpct=Dpct;
      regression.glm result=temp /
        table = {name=intable||'_BS', groupBy='bsID'},
        class = class,
        model = model,
        partByVar = {name="bag",train="1",test="0"},
        outputTables = {names={'ParameterEstimates'=intable||"_BS_PE"}, groupByVarsRaw=TRUE, replace=TRUE};
      percentile / table = {name=intable||"_BS_PE", groupBy='Parameter', vars={"Estimate"}},
        casOut = {name=intable||"_BS_PE_perc", replace=TRUE},
        values = {2.5, 50, 97.5};
      regression.glm result=temp /
        table = {name=intable||'_dbs', groupBy={'bsID','dbsID'}},
        class = class,
        model = model,
        partByVar = {name="bag",train="1",test="0"},
        outputTables = {names={'ParameterEstimates'=intable||"_DBS_PE"}, groupByVarsRaw=TRUE, replace=TRUE};
      percentile / table = {name=intable||"_DBS_PE", groupBy='Parameter', vars={"Estimate"}},
        casOut = {name=intable||"_DBS_PE_perc", replace=TRUE},
        values = {2.5, 50, 97.5};
      fedSql.execDirect / query='create table sample_DBS_PE_PLOT {options replace=true} as
                      select * from
                        (select "Parameter", Estimate, LowerCL, UpperCL from sample_PE) a
                        join
                        (select "Parameter", _Value_ as BS_LowerCL from sample_BS_PE_perc where _pctl_=2.5) b
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as BS_Estimate from sample_BS_PE_perc where _pctl_=50) c
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as BS_UpperCL from sample_BS_PE_perc where _pctl_=97.5) d
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as DBS_LowerCL from sample_DBS_PE_perc where _pctl_=2.5) b
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as DBS_Estimate from sample_DBS_PE_perc where _pctl_=50) c
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as DBS_UpperCL from sample_DBS_PE_perc where _pctl_=97.5) d
                        using ("Parameter")
                    ';
    end;
    else if method=='jackknife' then do;
      resample.jackknife / intable=intable case=case;
      regression.glm result=temp /
        table = {name=intable||'_JK', groupBy='jkID'},
        class = class,
        model = model,
        partByVar = {name="bag",train="1",test="0"},
        outputTables = {names={'ParameterEstimates'=intable||"_JK_PE"}, groupByVarsRaw=TRUE, replace=TRUE};
      percentile / table = {name=intable||"_JK_PE", groupBy='Parameter', vars={"Estimate"}},
        casOut = {name=intable||"_JK_PE_perc", replace=TRUE},
        values = {2.5, 50, 97.5};
      fedSql.execDirect / query='create table sample_JK_PE_PLOT {options replace=true} as
                      select * from
                        (select "Parameter", Estimate, LowerCL, UpperCL from sample_PE) a
                        join
                        (select "Parameter", _Value_ as JK_LowerCL from sample_JK_PE_perc where _pctl_=2.5) b
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as JK_Estimate from sample_JK_PE_perc where _pctl_=50) c
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as JK_UpperCL from sample_JK_PE_perc where _pctl_=97.5) d
                        using ("Parameter")
                    ';
    end;
run;




*cas mysess clear;












/*
idea here
1 - run full model - output PE
2 - run selected resample method - output PE by sample
3 - run percentiles on resampled PE
4 - combine PE

notes
  case on method eval
  percentile - prevent _f columns = dont worry if next step works...
  possible to transpose?

*/
