cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load original sample that will be sample from */
proc casutil;
	load data=sashelp.cars casout="sample" replace;
quit;

/* model - select effect with forwardswap, consider 2-way interactions, include poly(2) terms for enginesize, horsepower, weight */
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

					/* spec out final selected model above with lower level effects included */
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

/* create double bootstraped samples */
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.doubleBootstrap / intable='sample' bss=2;
run;

/* analyze/train each bootstrap sample with the same model effects selected on the full sample data */
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
         output = {casOut={name='sample_bs_pred', replace=TRUE},
         		   pred='Pred', resid='Resid', cooksd='CooksD', h='H',
         		   copyVars={"bsID","bs_rowID","rowID","MSRP","bag"}};
run;
/* analyze/train each double bootstrap sample with the same model effects selected on the full sample data */
proc cas;
   glm result=myresult / table  = {name='sample_dbs', groupBy={'bsID','dbsID'}},
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
         outputTables = {names={'ParameterEstimates'="sample_DBS_PE"}, groupByVarsRaw=TRUE, replace=TRUE},
         output = {casOut={name='sample_dbs_pred', replace=TRUE},
         		   pred='Pred', resid='Resid', cooksd='CooksD', h='H',
         		   copyVars={"bsID","dbsID","dbs_rowID","bs_rowID","rowID","MSRP","bag"}};
run;

/* plot the parameter effects and CI from the full sample data with BS intervals on top */
proc cas;
	/* bootstrap - get percentiles for 95% BS CI for each parameter */
	percentile / table = {name="sample_BS_PE", groupBy='Parameter', vars={"Estimate"}},
				 casOut = {name="sample_BS_PE_perc", replace=TRUE},
				 values = {2.5, 50, 97.5};
	/* double bootstrap - get percentiles for 95% BS CI for each parameter */
	percentile / table = {name="sample_DBS_PE", groupBy={{name='Parameter'},{name='bsID'}}, vars={"Estimate"}},
				 casOut = {name="sample_DBS_PE_perc", replace=TRUE, where="_Column_='Estimate'"},
				 values = {50};
			percentile / table = {name="sample_DBS_PE_perc", groupBy='Parameter', vars={"_Value_"}},
						 casOut = {name="sample_DBS_PE_perc", replace=TRUE},
						 values = {2.5, 50, 97.5};
	/* merge full sample parameter estimates with 95% BS & DBS CI estimates. */
		/* NOTE: need to quote "parameter" because it is a reserved word in fedsql */
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
run;

data sample_BS_PE_PLOT;
	set mylib.sample_bs_pe_plot;
run;

title "Evaluate Parameter Estimates with 95% CI";
title2 "ALL";
proc sgplot data=sample_BS_PE_PLOT;
	where lowerCL is not null;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	scatter y=Parameter x=DBS_Estimate / xerrorlower=DBS_LowerCL xerrorupper=DBS_UpperCL markerattrs=(symbol=circlefilled size=6 color=blue) legendlabel='Double Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Over 10000";
proc sgplot data=sample_BS_PE_PLOT;
	where max(abs(LowerCL),abs(UpperCL))>=10000;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	scatter y=Parameter x=DBS_Estimate / xerrorlower=DBS_LowerCL xerrorupper=DBS_UpperCL markerattrs=(symbol=circlefilled size=6 color=blue) legendlabel='Double Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Under 10000";
proc sgplot data=sample_BS_PE_PLOT;
	where max(abs(LowerCL),abs(UpperCL))<10000 and max(abs(LowerCL),abs(UpperCL))>=1000;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	scatter y=Parameter x=DBS_Estimate / xerrorlower=DBS_LowerCL xerrorupper=DBS_UpperCL markerattrs=(symbol=circlefilled size=6 color=blue) legendlabel='Double Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Under 1000";
proc sgplot data=sample_BS_PE_PLOT;
	where max(abs(LowerCL),abs(UpperCL))<1000 and max(abs(LowerCL),abs(UpperCL))>=100;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	scatter y=Parameter x=DBS_Estimate / xerrorlower=DBS_LowerCL xerrorupper=DBS_UpperCL markerattrs=(symbol=circlefilled size=6 color=blue) legendlabel='Double Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;
title2 "Zoom to Under 100";
proc sgplot data=sample_BS_PE_PLOT;
	where lowerCL is not null and max(abs(LowerCL),abs(UpperCL))<100;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Estimate';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	scatter y=Parameter x=DBS_Estimate / xerrorlower=DBS_LowerCL xerrorupper=DBS_UpperCL markerattrs=(symbol=circlefilled size=6 color=blue) legendlabel='Double Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;

*cas mysess clear;
