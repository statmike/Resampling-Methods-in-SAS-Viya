cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load original sample that will be resampled from */
proc casutil;
	load data=sashelp.heart casout="sample" replace;
quit;

/* model - select effects with forwardswap, consider 2-way interactions, include poly(2)  */
proc cas;
   loadactionset / actionset='regression';
   logistic / table  = {name='sample'},
		 class = {'Sex','Chol_Status','BP_Status','Weight_Status','Smoking_Status'},
		 model = {
					clb=TRUE,
		 			target = 'Status'
		 			effects = {
								{vars={'Sex','Chol_Status','BP_Status','Weight_Status','Smoking_Status','AgeAtStart','Height','Weight','Diastolic','Systolic','MRW','Smoking','Cholesterol','AgeAtStart','Height','Weight','Diastolic','Systolic','MRW','Smoking','Cholesterol'},interaction='BAR',maxinteract=2}
							}
		 			},
         selection = 'STEPWISE',
		 display = {names={'ParameterEstimates','FitStatistics'}},
         outputTables = {names={'ParameterEstimates'="sample_PE",'SelectedEffects'="sample_SE"}, replace=TRUE},
         output = {casOut={name='sample_pred', replace=TRUE},
         		   pred='Pred', resid='Resid', copyVars={"Status"}};
run;

  			/* spec out final selected model above with lower level effects included for inference */
  			proc cas;
  			   logistic / table  = {name='sample'},
  					 class = {'Sex','Smoking_Status'},
  					 model = {
  								clb=TRUE,
  					 			target = 'Status'
  					 			effects = {
  											{vars={'Sex','Smoking_Status','AgeAtStart','Systolic','Cholesterol'}},
  											{vars={'AgeAtStart','Sex'}, interaction='CROSS'},
  											{vars={'Systolic','Sex'}, interaction='CROSS'},
  											{vars={'AgeAtStart','AgeAtStart'}, interaction='CROSS'},
  											{vars={'Cholesterol','Smoking_Status'}, interaction='CROSS'}
  										}
  					 			},
  					 display = {names={'ParameterEstimates','FitStatistics'}},
  			         outputTables = {names={'ParameterEstimates'="sample_PE"}, replace=TRUE},
  			         output = {casOut={name='sample_pred', replace=TRUE},
  			         		   pred='Pred', resid='Resid', copyVars={"Status"}};
  			run;
