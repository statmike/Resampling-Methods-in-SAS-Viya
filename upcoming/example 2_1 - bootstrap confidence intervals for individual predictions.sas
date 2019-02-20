cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load original sample that will be resampled from */
proc casutil;
	load data=sashelp.cars casout="sample" replace;
quit;

/* model - select effects with forwardswap, consider 2-way interactions, include poly(2) terms for enginesize, horsepower, weight */
proc cas;
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


  			/* spec out final selected model above with lower level effects included for inference */
  			proc cas;
  			   glm / table  = {name='sample'},
  					 class = {'Origin','DriveTrain'},
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
  					 			},
  					 display = {names={'ParameterEstimates','Anova','FitStatistics'}},
  			         outputTables = {names={'ParameterEstimates'="sample_PE"}, replace=TRUE};
  			run;

/* create bootstrap resamples */
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.bootstrap / intable='sample' B=100 seed=12345 Bpct=1 case='unique_case';
run;

/* analyze/train each bootstrap resample with the same model effects selected on the full sample data */
proc cas;
   glm result=myresult / table  = {name='sample_bs', groupBy='bsID'},
		 class = {'Origin','DriveTrain'},
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
		 			},
         partByVar = {name="bag",train="1",test="0"},
         outputTables = {names={'ParameterEstimates'="sample_BS_PE"}, groupByVarsRaw=TRUE, replace=TRUE},
         output = {casOut={name='sample_bs_pred', replace=TRUE}, pred='Pred', resid='Resid', copyVars={"caseID","bsID","bag"}};
run;


proc cas;
/*
select distinct bsID and rows
calculate percentiels for predictions - walkthrough percentilePE for code
 transpose to rows for each caseID
 merge in original target by caseID
 calculate residual CI
*/
  fedsql.execDirect / query='create table sample_bs_pred {options replace=TRUE} as select distinct caseID, bsID, bag, pred, resid from sample_bs_pred';
  percentile / table = {name='sample_bs_pred', groupBy="CASEID", vars={"Pred"}},
    casOut = {name='sample_bs_pred_perc', replace=TRUE},
    values = {2.5, 50, 97.5};
  fedsql.execDirect / query="create table sample_bs_pred_perc {options replace=true} as
                                select * from
                                    (select CASEID, _Value_ as BS_LowerCL from sample_bs_pred_perc where (_pctl_=2.5 and _column_='Pred')) a
                                    join
                                    (select CASEID, _Value_ as BS_Estimate from sample_bs_pred_perc where (_pctl_=50 and _column_='Pred')) b
                                    using (CASEID)
                                    join
                                    (select CASEID, _Value_ as BS_UpperCL from sample_bs_pred_perc where (_pctl_=97.5 and _column_='Pred')) c
                                    using (CASEID)";
  fedsql.execDirect / query='create table sample_bs_pred_perc {options replace=true} as
  								select * from
  									(select * from sample_bs_pred_perc) a
  									left outer join
  									(select CASEID, MSRP from sample) b
  									using(CASEID)';
  datastep.runcode result=t / code='data sample_bs_pred_perc; set sample_bs_pred_perc;
                                          resid_BS_LowerCL=BS_LowerCL-MSRP;
                                          resid_BS=BS_Estimate-MSRP;
                                          resid_BS_UpperCL=BS_UpperCL-MSRP;
                                    run;';
run;



/* plot intervals for predictions
make residual plot with intervals */
data sample_bs_pred_perc;
	set mylib.sample_bs_pred_perc;
run;

title "Confidence Intervals for Predictions";
proc sgplot data=sample_bs_pred_perc;
	scatter y=caseid x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Prediction';
	scatter y=caseid x=resid_BS / xerrorlower=resid_BS_LowerCL xerrorupper=resid_BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Residual';
  scatter y=caseid x=MSRP / legendlabel='Actual Value';
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;

title "Residual Plot with BS Intervals";
proc sgplot data=sample_bs_pred_perc;
  scatter x=caseid y=resid_BS / yerrorlower=resid_BS_LowerCL yerrorupper=resid_BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=red) legendlabel='Residual';
  refline 0 / axis=y;
run;



*cas mysess clear;
