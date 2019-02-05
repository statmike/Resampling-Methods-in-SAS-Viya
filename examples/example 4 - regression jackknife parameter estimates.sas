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
         partByVar = {name="bag",train="1",test="0"}, /* only 1 row per sample without bag=1 and it may be missing... */
         outputTables = {names={'ParameterEstimates'="sample_JK_PE","FitStatistics"="sample_JK_FS"}, groupByVarsRaw=TRUE, replace=TRUE},
         output = {casOut={name='sample_jk_pred', replace=TRUE},
         		   pred='Pred', resid='Resid', cooksd='CooksD', h='H',
         		   copyVars={"jkID","rowID","MSRP","bag"}};
run;


/* plot the parameter effects and CI from the full sample data with JK percentile intervals on top */
proc cas;
	/* get percentiles for 95% JK CI for each parameter */
	percentile / table = {name="sample_JK_PE", groupBy='Parameter', vars={"Estimate"}},
				 casOut = {name="sample_JK_PE_perc", replace=TRUE},
				 values = {2.5, 50, 97.5};
	/* merge full sample parameter estimates with 95% JK CI estimates. */
		/* NOTE: need to quote "parameter" because it is a reserved word in fedsql */
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
run;


data sample_JK_PE_PLOT;
	set mylib.sample_jk_pe_plot;
run;

title "Evaluate Parameter Estimates with 95% CI";
title2 "ALL";
proc sgplot data=sample_JK_PE_PLOT;
	where lowerCL is not null;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=JK_Estimate / xerrorlower=JK_LowerCL xerrorupper=JK_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Jackknife';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Over 10000";
proc sgplot data=sample_JK_PE_PLOT;
	where max(abs(LowerCL),abs(UpperCL))>=10000;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=JK_Estimate / xerrorlower=JK_LowerCL xerrorupper=JK_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Jackknife';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Under 10000";
proc sgplot data=sample_JK_PE_PLOT;
	where max(abs(LowerCL),abs(UpperCL))<10000 and max(abs(LowerCL),abs(UpperCL))>=1000;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=JK_Estimate / xerrorlower=JK_LowerCL xerrorupper=JK_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Jackknife';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Under 1000";
proc sgplot data=sample_JK_PE_PLOT;
	where max(abs(LowerCL),abs(UpperCL))<1000 and max(abs(LowerCL),abs(UpperCL))>=100;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=JK_Estimate / xerrorlower=JK_LowerCL xerrorupper=JK_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Jackknife';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Under 100";
proc sgplot data=sample_JK_PE_PLOT;
	where lowerCL is not null and max(abs(LowerCL),abs(UpperCL))<100;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=JK_Estimate / xerrorlower=JK_LowerCL xerrorupper=JK_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Jackknife';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;

*cas mysess clear;
