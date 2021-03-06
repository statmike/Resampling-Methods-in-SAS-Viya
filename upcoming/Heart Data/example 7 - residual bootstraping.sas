/**
	bootstrapping residuals
		regression with full data yields residuals
		each bootstrap sample is the original data with the target variable adjusted by a random (with replacement) residual from the full data model fit
	built on top of example 2 - regression bootstrap parameter estimate.sas
		The additions to example 2 will be inclosed in comment blocks with *************************************************
**/

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
  			         		   copyVars="ALL_MODEL"};
  			run;

/***************************************************************************************************************************/
/* added to example 2 */

proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.addRowID / intable="sample_pred";
		fedsql.execDirect / query='create table sample_pred_resid {options replace=TRUE} as select rowID as residID, Resid from sample_pred';
		alterTable / name='sample_pred' columns={{name='Resid',drop=TRUE},{name='rowID',rename='caseID'}};
run;

/***************************************************************************************************************************/
/* edit to example 2 */

/* create bootstrap resamples */
proc cas;
	*builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.bootstrap / intable='sample_pred_resid' B=100 seed=12345 Bpct=1 case='unique_case';
run;

/***************************************************************************************************************************/
/* added to example 2 */

proc cas;
	fedsql.execDirect / query='create table sample_bs {options replace=TRUE} as
								select * from
									(select bsID, CASE when bs_caseID is null then caseID else bs_caseID END as bs_caseID, bag, residID, resid from sample_pred_resid_bs) a
									left outer join
									(select * from sample_pred) b
									on a.bs_caseID=b.caseID
								';
	datastep.runcode result=t / code='data sample_bs; set sample_bs; MSRP=MSRP+resid; run;';
run;

/***************************************************************************************************************************/

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
         outputTables = {names={'ParameterEstimates'="sample_BS_PE"}, groupByVarsRaw=TRUE, replace=TRUE};
run;

/* create percentile intervals for the bootstrap samples and merge with full model CI
		this action expects table intable_BS_PE and intable_PE */
proc cas;
	resample.percentilePE / intable='sample' alpha=0.05;
run;


/* plot the parameter effects and CI from the full sample data with BS percentile intervals on top */
data sample_BS_PE_PLOT;
	set mylib.sample_pe_pctCI;
run;

title "Evaluate Parameter Estimates with 95% CI";
title2 "ALL";
proc sgplot data=sample_BS_PE_PLOT;
	where lowerCL is not null;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Over 10000";
proc sgplot data=sample_BS_PE_PLOT;
	where max(abs(LowerCL),abs(UpperCL))>=10000;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Under 10000";
proc sgplot data=sample_BS_PE_PLOT;
	where max(abs(LowerCL),abs(UpperCL))<10000 and max(abs(LowerCL),abs(UpperCL))>=1000;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Under 1000";
proc sgplot data=sample_BS_PE_PLOT;
	where max(abs(LowerCL),abs(UpperCL))<1000 and max(abs(LowerCL),abs(UpperCL))>=100;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Under 100";
proc sgplot data=sample_BS_PE_PLOT;
	where lowerCL is not null and max(abs(LowerCL),abs(UpperCL))<100;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;

*cas mysess clear;
