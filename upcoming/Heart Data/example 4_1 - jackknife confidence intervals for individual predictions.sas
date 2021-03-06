/*
An example of using the predicted values from each jackknife resample, including the out-of-bag rows,
to create confidence intervals for the predicted value as percentiles from the fitted jackknife resamples.
Based on example 4
*/
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
  			         outputTables = {names={'ParameterEstimates'="sample_PE"}, replace=TRUE},
  			         output = {casOut={name='sample_pred', replace=TRUE},
  			         		   pred='Pred', resid='Resid', cooksd='CooksD', h='H',
  			         		   copyVars={"MSRP"}};
  			run;

/* create jackknife resamples */
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.jackknife / intable='sample' case='unique_case';
run;

/* analyze/train each jackknife resample with the same model effects selected on the full sample data */
proc cas;
   glm result=myresult / table  = {name='sample_jk', groupBy='jkID'},
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
         partByVar = {name="bag",train="1",test="0"}, /* only 1 row per sample without bag=1 but useful for getting prediction */
         outputTables = {names={'ParameterEstimates'="sample_JK_PE","FitStatistics"="sample_JK_FS"}, groupByVarsRaw=TRUE, replace=TRUE},
         output = {casOut={name='sample_jk_pred', replace=TRUE}, pred='Pred', resid='Resid', copyVars={"caseID","jkID","bag"}};
run;


/* use the output predictions from fitting all the jackknife resamples to construct percentile intervals for the predictions: */
proc cas;
	/* select distinct bsID and caseID - this will get all the original rows of the dataset scored by including bag which has the out-of-bag values with bag=0 */
  fedsql.execDirect / query='create table sample_jk_pred {options replace=TRUE} as select distinct caseID, jkID, bag, pred, resid from sample_jk_pred';
	/* calculate the percentile intervals for the predictions */
  percentile / table = {name='sample_jk_pred', groupBy="CASEID", vars={"Pred"}},
    casOut = {name='sample_jk_pred_perc', replace=TRUE},
    values = {2.5, 50, 97.5};
	/* transpose the rows for each caseID */
  fedsql.execDirect / query="create table sample_jk_pred_perc {options replace=true} as
                                select * from
                                    (select CASEID, _Value_ as jk_LowerCL from sample_jk_pred_perc where (_pctl_=2.5 and _column_='Pred')) a
                                    join
                                    (select CASEID, _Value_ as jk_Estimate from sample_jk_pred_perc where (_pctl_=50 and _column_='Pred')) b
                                    using (CASEID)
                                    join
                                    (select CASEID, _Value_ as jk_UpperCL from sample_jk_pred_perc where (_pctl_=97.5 and _column_='Pred')) c
                                    using (CASEID)";
	/* merge the orginal target variable back into the confidence intervals for the predictions */
  fedsql.execDirect / query='create table sample_jk_pred_perc {options replace=true} as
  								select * from
  									(select * from sample_jk_pred_perc) a
  									left outer join
  									(select CASEID, MSRP from sample) b
  									using(CASEID)';
	/* calculate confidence intervals for the residuals */
  datastep.runcode result=t / code='data sample_jk_pred_perc; set sample_jk_pred_perc;
                                          resid_jk_LowerCL=jk_LowerCL-MSRP;
                                          resid_jk=jk_Estimate-MSRP;
                                          resid_jk_UpperCL=jk_UpperCL-MSRP;
                                    run;';
run;



/* plot intervals for predictions
make residual plot with intervals */
data sample_jk_pred_perc;
	set mylib.sample_jk_pred_perc;
run;

title "Jackknife Confidence Intervals for Predictions";
proc sgplot data=sample_jk_pred_perc;
	scatter y=caseid x=jk_Estimate / xerrorlower=jk_LowerCL xerrorupper=jk_UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Prediction';
	scatter y=caseid x=resid_jk / xerrorlower=resid_jk_LowerCL xerrorupper=resid_jk_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Residual';
  scatter y=caseid x=MSRP / legendlabel='Actual Value';
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;

title "Residual Plot";
proc sgplot data=sample_jk_pred_perc;
  scatter x=caseid y=resid_jk / markerattrs=(symbol=circlefilled size=6 color=red) legendlabel='Residual';
  refline 0 / axis=y;
run;
title "Residual Plot with Jackknife Intervals";
proc sgplot data=sample_jk_pred_perc;
  scatter x=caseid y=resid_jk / yerrorlower=resid_jk_LowerCL yerrorupper=resid_jk_UpperCL markerattrs=(symbol=circlefilled size=6 color=red) legendlabel='Residual';
  refline 0 / axis=y;
run;
title "Residual Plot with Jackknife Intervals";
title2 "Intervals Not Covering Zero";
proc sgplot data=sample_jk_pred_perc;
	where resid_jk_LowerCL>0 or resid_jk_UpperCL<0;
  scatter x=caseid y=resid_jk / yerrorlower=resid_jk_LowerCL yerrorupper=resid_jk_UpperCL markerattrs=(symbol=circlefilled size=6 color=red) legendlabel='Residual';
  refline 0 / axis=y;
run;
title "Residual Plot with Jackknife Intervals";
title2 "Intervals Exceeding 10k";
proc sgplot data=sample_jk_pred_perc;
	where resid_jk_LowerCL<=-10000 or resid_jk_UpperCL>=10000;
  scatter x=caseid y=resid_jk / yerrorlower=resid_jk_LowerCL yerrorupper=resid_jk_UpperCL markerattrs=(symbol=circlefilled size=6 color=red) legendlabel='Residual';
  refline 0 / axis=y;
run;
title "Residual Plot with Jackknife Intervals";
title2 "Intervals Exceeding 15k";
proc sgplot data=sample_jk_pred_perc;
	where resid_jk_LowerCL<=-15000 or resid_jk_UpperCL>=15000;
  scatter x=caseid y=resid_jk / yerrorlower=resid_jk_LowerCL yerrorupper=resid_jk_UpperCL markerattrs=(symbol=circlefilled size=6 color=red) legendlabel='Residual';
  refline 0 / axis=y;
run;
title "Residual Plot with Jackknife Intervals";
title2 "Intervals Exceeding 20k";
proc sgplot data=sample_jk_pred_perc;
	where resid_jk_LowerCL<=-20000 or resid_jk_UpperCL>=20000;
  scatter x=caseid y=resid_jk / yerrorlower=resid_jk_LowerCL yerrorupper=resid_jk_UpperCL markerattrs=(symbol=circlefilled size=6 color=red) legendlabel='Residual';
  refline 0 / axis=y;
run;


*cas mysess clear;
