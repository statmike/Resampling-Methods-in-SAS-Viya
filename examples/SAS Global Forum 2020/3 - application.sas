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


/* model selection - casl syntax with more features: select effects with stepwise, consider 2-way interactions, include some poly */
proc cas;
   loadactionset / actionset='regression';
   logistic / table  = {name='sample'},
		 class = {'Sex','BP_Status','Smoking_Status'},
		 model = {
					clb=TRUE,
		 			target = 'Status'
		 			effects = {
								{vars={'Sex','BP_Status','Smoking_Status','AgeAtStart','MRW','Cholesterol'},
                                interaction='BAR',maxinteract=2
                                }
							}
		 		},
         selection = 'STEPWISE';
run;


proc cas;
    /* spec final model - spec out final selected model above with lower level effects included for inference */
    fullmodel = {
					clb=TRUE,
		 			target = 'Status'
		 			effects = {
								{vars={'Sex','Smoking_Status','AgeAtStart','BP_Status','Cholesterol','MRW'}},
								{vars={'AgeAtStart','Sex'}, interaction='CROSS'},
								{vars={'BP_Status','Smoking_Status'}, interaction='CROSS'},
								{vars={'Cholesterol','MRW'}, interaction='CROSS'}
							}                    
                };
    /* run final model - spec out final selected model above with lower level effects included for inference */
   logistic / table  = {name='sample'},
		 class = {'Sex','Smoking_Status','BP_Status'},
		 model = fullmodel,
		 display = {names={'ParameterEstimates','FitStatistics'}},
         outputTables = {names={'ParameterEstimates'="sample_PE"}, replace=TRUE},
         output = {casOut={name='sample_pred', replace=TRUE}, 
                    pred='Pred', resid='Resid',
                    copyVars={"Status"}};
    /* model resamples - analyze/train each bootstrap resample with the same model effects selected on the full sample data */
   logistic result=myresult / table  = {name='sample_bs', groupBy='bsID'},
		 class = {'Sex','Smoking_Status','BP_Status'},
		 model = fullmodel,
         partByVar = {name="bag",train="1",test="0"},
         outputTables = {names={'ParameterEstimates'="sample_BS_PE","FitStatistics"="sample_BS_FS"}, groupByVarsRaw=TRUE, replace=TRUE},
         output = {casOut={name='sample_bs_pred', replace=TRUE},
                    pred='Pred', resid='Resid',
                    copyVars={"bsID","bs_caseID","caseID","Status","bag"}};
run;


/* Use model M2LL from each bootstrap resample to detect influential rows of data - their presence or absence drive the fit (M2LL) of the data */

/* create a table of counts: 
    rows represent resamples (bsID),
    columns represent cases (rows) in the original sample, 
    values are the count of occurence (0,1,2,..) of the case in the resample
*/
proc cas;
    /* gets counts of case occurence within each resample */
    fedsql.execDirect / query="create table sample_bs_Influence {options replace=true} as
                    select bsID, caseID, count(*) as bagged
                      from sample_bs
                      where bag=1
                      group by bsID, caseID";
    /* transpose so rows are resamples, columns are cases */
    loadActionSet / actionSet='transpose';
    transpose / table={name='sample_bs_Influence', groupBy={{name='bsID'}}},
          id={'caseID'},
          casOut={name='sample_bs_Influence', replace=true},
          prefix='caseID_',
          validVarName='any',
          transpose={'bagged'};
    alterTable / name="sample_bs_Influence" columns={{name="_name_", drop=TRUE}};
    /* add column for the fit measure (M2LL) from fitting each resample */
    fedsql.execDirect / query="create table sample_bs_Influence {options replace=True} as
                    select * from
                      (select * from sample_bs_Influence) a
                      join
                      (select bsID, Training as M2LL from sample_bs_fs where rowID='M2LL') b
                      using (bsID)";
run;

/* Fit DT on the counts table to understand the influence of each case on predicting the Fit (M2LL): Influence could be the inclusion or exclusion of a Case */
proc cas;
		table.columninfo result=c / table={name='sample_bs_Influence'};
				c2=c.columninfo.where(substr(column,1,4)=='case')[,"column"];
		loadActionSet / actionSet='decisionTree';
		decisionTree.dtreeTrain / table={name='SAMPLE_BS_INFLUENCE'},
			target='M2LL', inputs=c2,
			nBins=20, maxLevel=16, maxBranch=2, leafSize=5, crit='VARIANCE',
    	missing='USEINSEARCH', minUseInSearch=1, binOrder=true, varImp=true, casOut={name='SAMPLE_BS_INFLUENCE_MODEL_M2LL',
      replace=true}, mergeBin=true, encodeName=true;
		*decisionTree.dtreeScore / table={name='SAMPLE_BS_INFLUENCE'}, modelTable={name='SAMPLE_BS_INFLUENCE_MODEL_M2LL'}, noPath=true, encodeName=true;
		*table.fetch / table={name='SAMPLE_BS_INFLUENCE_MODEL_RMSE'}, from=1, to=16384, sortBy={{name='_NodeID_', order='ASCENDING'}};
run;

*cas mysess clear;
