/* a step by step walkthrough of the percentilePE action in the resample actionset
  link to wiki:
*/

/* setup a session - in SAS Studio use interactive mode for this walkthrough */
cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load actionSet */
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
quit;

/* SETUP: load example data to work with - three possible scenarios
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

/* SETUP: build model - select effects with forwardswap, consider 2-way interactions, include poly(2) terms for enginesize, horsepower, weight */
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

/* SETUP: define inputs for the final model fit */
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
		intable='sample';
    /* fit model to the sample data */
    regression.glm result=temp /
      table = intable,
      class = class,
      model = model,
      outputTables = {names={'ParameterEstimates'=intable||"_PE"}, replace=TRUE};
    /* create bootstrap resamples and fit model to each resample (BS)*/
    resample.bootstrap / intable=intable B=100 seed=12345 Bpct=1 case='unique_case';
      regression.glm result=temp /
        table = {name=intable||'_BS', groupBy='bsID'},
        class = class,
        model = model,
        partByVar = {name="bag",train="1",test="0"},
        outputTables = {names={'ParameterEstimates'=intable||"_BS_PE"}, groupByVarsRaw=TRUE, replace=TRUE};
    /* create double-bootstrap resamples and fit model to each resample (BS and DBS) */
    resample.doubleBootstrap / intable=intable B=100 seed=12345 Bpct=1 case='unique_case' D=10 Dpct=1;
      regression.glm result=temp /
        table = {name=intable||'_BS', groupBy='bsID'},
        class = class,
        model = model,
        partByVar = {name="bag",train="1",test="0"},
        outputTables = {names={'ParameterEstimates'=intable||"_BS_PE"}, groupByVarsRaw=TRUE, replace=TRUE};
      regression.glm result=temp /
        table = {name=intable||'_dbs', groupBy={'bsID','dbsID'}},
        class = class,
        model = model,
        partByVar = {name="bag",train="1",test="0"},
        outputTables = {names={'ParameterEstimates'=intable||"_DBS_PE"}, groupByVarsRaw=TRUE, replace=TRUE};
    /* create jackknife resamples and fit model to each resample (JK) */
    resample.jackknife / intable=intable case='unique_case';
      regression.glm result=temp /
        table = {name=intable||'_JK', groupBy='jkID'},
        class = class,
        model = model,
        partByVar = {name="bag",train="1",test="0"},
        outputTables = {names={'ParameterEstimates'=intable||"_JK_PE"}, groupByVarsRaw=TRUE, replace=TRUE};
run;

/* START WALKTHROUGH of the percentilePE action */

/* define parameters to hold the action inputs */
		intable='sample';
    alpha=0.05;
run;

/* detect intable_method_PE tables and create percentiles for each then merge all the percentile together into intable_PE_percentiles */
		/* create the percentiles list using the input=alpha */
		percs={100*alpha/2,50,100-100*alpha/2};
		/* check for existance of PE tables from each of the resample methods (BS, DBS, JK) */
		table.tableExists result=bs / name=intable||'_BS_PE';
		table.tableExists result=dbs / name=intable||'_DBS_PE';
		table.tableExists result=jk / name=intable||'_JK_PE';
		/* if atleast one PE table exists then setup the ouput query */
		if bs.exists+dbs.exists+jk.exists>0 then do;
			PEquery='create table sample_PE_pctCI {options replace=true} as
								select * from
									(select "Parameter", Estimate, LowerCL, UpperCL from '|| intable ||'_PE) a';
		end;
		/* if intable_BS_PE exists then do percentiles and add the parameters to the output query */
    if bs.exists then do;
      percentile / table = {name=intable||"_BS_PE", groupBy='Parameter', vars={"Estimate"}},
        casOut = {name=intable||"_BS_PE_perc", replace=TRUE},
        values = percs;
      PEquery=PEquery||' join
                        (select "Parameter", _Value_ as BS_LowerCL from '||intable||'_BS_PE_perc where _pctl_='||(string)(percs[1])||') bb
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as BS_Estimate from '||intable||'_BS_PE_perc where _pctl_=50) cb
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as BS_UpperCL from '||intable||'_BS_PE_perc where _pctl_='||(string)(percs[3])||') db
                        using ("Parameter")';
    end;
		/* if intable_DBS_PE exists then do percentiles and add the parameters to the output query */
    if dbs.exists then do;
      percentile / table = {name=intable||"_DBS_PE", groupBy='Parameter', vars={"Estimate"}},
        casOut = {name=intable||"_DBS_PE_perc", replace=TRUE},
        values = percs;
      PEquery=PEquery||' join
                        (select "Parameter", _Value_ as DBS_LowerCL from '||intable||'_DBS_PE_perc where _pctl_='||(string)(percs[1])||') bd
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as DBS_Estimate from '||intable||'_DBS_PE_perc where _pctl_=50) cd
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as DBS_UpperCL from '||intable||'_DBS_PE_perc where _pctl_='||(string)(percs[3])||') dd
                        using ("Parameter")';
    end;
		/* if intable_JK_PE exists then do percentiles and add the parameters to the output query */
    if jk.exists then do;
      percentile / table = {name=intable||"_JK_PE", groupBy='Parameter', vars={"Estimate"}},
        casOut = {name=intable||"_JK_PE_perc", replace=TRUE},
        values = percs;
      PEquery=PEquery||' join
                        (select "Parameter", _Value_ as JK_LowerCL from '||intable||'_JK_PE_perc where _pctl_='||(string)(percs[1])||') bj
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as JK_Estimate from '||intable||'_JK_PE_perc where _pctl_=50) cj
                        using ("Parameter")
                        join
                        (select "Parameter", _Value_ as JK_UpperCL from '||intable||'_JK_PE_perc where _pctl_='||(string)(percs[3])||') dj
                        using ("Parameter")';
    end;
		/* execute the output query to create intable_PE_pctCI */
		if bs.exists+dbs.exists+jk.exists>0 then do;
			*print PEquery;
    	fedsql.execDirect / query=PEquery;
		end;
run;




*cas mysess clear;
