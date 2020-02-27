/* create a cas session and libname to refer to data in it */
cas mysess sessopts=(caslib='casuser');
libname mycas cas sessref=mysess;

/* load original sample that will be resampled */
proc casutil;
	load data=sashelp.heart casout="sample" replace;
quit;

/* create bootstrap resamples */
proc cas;
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.bootstrap / intable='sample' B=1000 seed=12345 Bpct=1 case='none' strata='none' strata_table='none';
run;

/* model selection - traditional SAS Proc Syntax but with a new CAS enable Proc */
proc logselect data=mycas.sample;
	class sex  bp_status smoking_status;
	model status = sex bp_status smoking_status
	 			   AgeAtStart MRW Cholesterol	/ CLB;
	selection method=stepwise;
run;


/* model selection - casl syntax with more features: select effects with stepwise, consider 2-way interactions, include some poly */
proc cas;
   loadactionset / actionset='regression';
   logistic / table  = {name='sample'},
		 class = {'Sex','BP_Status','Smoking_Status'},
		 model = {
					clb=TRUE,
		 			target = 'Status'
		 			effects = {
								{vars={'Sex','BP_Status','Smoking_Status',
										'AgeAtStart','MRW','Cholesterol'
									   },interaction='BAR',maxinteract=2}
							}
		 			},
         selection = 'STEPWISE';
run;


/* final model - spec out final selected model above with lower level effects included for inference */
proc cas;
   logistic / table  = {name='sample'},
		 class = {'Sex','Smoking_Status','BP_Status'},
		 model = {
					clb=TRUE,
		 			target = 'Status'
		 			effects = {
								{vars={'Sex','Smoking_Status','AgeAtStart','BP_Status','Cholesterol','MRW'}},
								{vars={'AgeAtStart','Sex'}, interaction='CROSS'},
								{vars={'BP_Status','Smoking_Status'}, interaction='CROSS'},
								{vars={'Cholesterol','MRW'}, interaction='CROSS'}
							}
		 			},
		 display = {names={'ParameterEstimates','FitStatistics'}},
         outputTables = {names={'ParameterEstimates'="sample_PE"}, replace=TRUE},
         output = {casOut={name='sample_pred', replace=TRUE}, pred='Pred', resid='Resid', copyVars={"Status"}};
run;


/* model resamples - analyze/train each bootstrap resample with the same model effects selected on the full sample data */
proc cas;
   logistic result=myresult / table  = {name='sample_bs', groupBy='bsID'},
		 class = {'Sex','Smoking_Status','BP_Status'},
		 model = {
					clb=TRUE,
					target = 'Status'
		 			effects = {
								{vars={'Sex','Smoking_Status','AgeAtStart','BP_Status','Cholesterol','MRW'}},
								{vars={'AgeAtStart','Sex'}, interaction='CROSS'},
								{vars={'BP_Status','Smoking_Status'}, interaction='CROSS'},
								{vars={'Cholesterol','MRW'}, interaction='CROSS'}
							}
		 			},
         partByVar = {name="bag",train="1",test="0"},
         outputTables = {names={'ParameterEstimates'="sample_BS_PE"}, groupByVarsRaw=TRUE, replace=TRUE},
         output = {casOut={name='sample_bs_pred', replace=TRUE}, pred='Pred', resid='Resid', copyVars={"caseID","bsID","bag"}};
run;


/* create percentile intervals for the bootstrap samples and merge with full model CI
		this action expects table intable_BS_PE and intable_PE */
proc cas;
	resample.percentilePE / intable='sample' alpha=0.05;
run;

/* plot the parameter effects and CI from the full sample data with BS percentile intervals on top */
data sample_BS_PE_PLOT;
	set mycas.sample_pe_pctCI;
run;

title "Evaluate Parameter Estimates with 95% CI (percentile)";
proc sgplot data=sample_BS_PE_PLOT;
	where lowerCL is not null;
	scatter y=Parameter x=Estimate / xerrorlower=LowerCL xerrorupper=UpperCL markerattrs=(symbol=circle size=9 color=red) legendlabel='Full Data';
	scatter y=Parameter x=BS_Estimate / xerrorlower=BS_LowerCL xerrorupper=BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=green) legendlabel='Bootstrap';
	*xaxis grid;
	yaxis display=(nolabel);
	refline 0 / axis=x;
run;





/* use the output predictions from fitting all the bootstrap resamples to construct percentile intervals for the predictions: */
proc cas;
	/* select distinct bsID and caseID - this will get all the original rows of the dataset scored by including bag which has the out-of-bag values with bag=0 */
  fedsql.execDirect / query='create table sample_bs_pred {options replace=TRUE} as select distinct caseID, bsID, bag, pred, resid from sample_bs_pred';
	/* calculate the percentile intervals for the predictions */
  percentile / table = {name='sample_bs_pred', groupBy="CASEID", vars={"Pred"}},
    casOut = {name='sample_bs_pred_perc', replace=TRUE},
    values = {2.5, 50, 97.5};
	/* transpose the rows for each caseID */
  fedsql.execDirect / query="create table sample_bs_pred_perc {options replace=true} as
                                select * from
                                    (select CASEID, _Value_ as BS_LowerCL from sample_bs_pred_perc where (_pctl_=2.5 and _column_='Pred')) a
                                    join
                                    (select CASEID, _Value_ as BS_Estimate from sample_bs_pred_perc where (_pctl_=50 and _column_='Pred')) b
                                    using (CASEID)
                                    join
                                    (select CASEID, _Value_ as BS_UpperCL from sample_bs_pred_perc where (_pctl_=97.5 and _column_='Pred')) c
                                    using (CASEID)";
	/* merge the orginal target variable back into the confidence intervals for the predictions */
  fedsql.execDirect / query='create table sample_bs_pred_perc {options replace=true} as
  								select * from
  									(select * from sample_bs_pred_perc) a
  									left outer join
  									(select CASEID, Status from sample) b
  									using(CASEID)';
	/* calculate confidence intervals for the residuals */
  datastep.runcode result=t / code='data sample_bs_pred_perc; set sample_bs_pred_perc;
																				if status="Dead" then do;
																					status2=0;
                                          resid_BS_LowerCL=1-BS_UpperCL;
                                          resid_BS=1-BS_Estimate;
                                          resid_BS_UpperCL=1-BS_LowerCL;
																				end;
																				else do;
																					status2=1;
                                          resid_BS_LowerCL=BS_LowerCL;
                                          resid_BS=BS_Estimate;
                                          resid_BS_UpperCL=BS_UpperCL;
																				end;
                                    run;';
run;


/* plot intervals for predictions
make residual plot with intervals */
data sample_bs_pred_perc;
	set mycas.sample_bs_pred_perc;
run;

ods graphics / imagemap;

title "Bootstrap Confidence Intervals for Individual Predictions";
title2 "Cases where prediction is consistently highly inaccurate (residual >0.94)";
proc sgpanel data=sample_bs_pred_perc;
	where resid_BS_LowerCL>0.94;
	panelby status;
	scatter y=caseid x=resid_BS / xerrorlower=resid_BS_LowerCL xerrorupper=resid_BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=red) legendlabel='Residual';
	refline 0.5 / axis=x;
run;

title "Residual Plot with 95% Bootstrap Intervals (percentile)";
title2 "Cases where prediction is consistently highly inaccurate (residual >0.94)";
proc sgpanel data=sample_bs_pred_perc;
	where resid_BS_LowerCL>0.94;
	panelby status;
	scatter x=caseid y=resid_BS / yerrorlower=resid_BS_LowerCL yerrorupper=resid_BS_UpperCL markerattrs=(symbol=circlefilled size=6 color=red) legendlabel='Residual';
	refline 0.5 / axis=y;
run;

*cas mysess clear;