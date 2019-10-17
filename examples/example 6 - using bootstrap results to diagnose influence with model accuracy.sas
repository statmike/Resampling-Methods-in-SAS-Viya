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
					fullmodel = {
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
  			   glm / table  = {name='sample'},
  					 class = {'Origin','DriveTrain'},
  					 model = fullmodel,
  					 display = {names={'ParameterEstimates','Anova','FitStatistics'}},
  			         outputTables = {names={'ParameterEstimates'="sample_PE"}, replace=TRUE},
  			         output = {casOut={name='sample_pred', replace=TRUE},
  			         		   pred='Pred', resid='Resid', cooksd='CooksD', h='H',
  			         		   copyVars={"MSRP"}};
  			run;

/* create bootstrap resamples */
	builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
	resample.bootstrap / intable='sample' B=100 seed=12345 Bpct=1 case='unique_case' strata='none';
run;

/* analyze/train each bootstrap resample with the same model effects selected on the full sample data */
   glm result=myresult / table  = {name='sample_bs', groupBy='bsID'},
		 class = {'Origin','DriveTrain'},
		 model = fullmodel,
         partByVar = {name="bag",train="1",test="0"},
         outputTables = {names={'ParameterEstimates'="sample_BS_PE","FitStatistics"="sample_BS_FS"}, groupByVarsRaw=TRUE, replace=TRUE},
         output = {casOut={name='sample_bs_pred', replace=TRUE},
         		   pred='Pred', resid='Resid', cooksd='CooksD', h='H',
         		   copyVars={"bsID","bs_caseID","caseID","MSRP","bag"}};
run;







/* Use model accuracy from each bootstrap resample to detect influential rows of data */

/* create a table of counts for input sample rows occuring in the bootstrap resamples
    rows are bootstrap resamples and columns are those found in the input sample table.  */
proc cas;
    fedsql.execDirect / query="create table sample_bs_Influence {options replace=true} as
                    select bsID, caseID, count(*) as bagged
                      from sample_bs
                      where bag=1
                      group by bsID, caseID";
run;
proc cas;
    loadActionSet / actionSet='transpose';
    transpose / table={name='sample_bs_Influence', groupBy={{name='bsID'}}},
          id={'caseID'},
          casOut={name='sample_bs_Influence', replace=true},
          prefix='caseID_',
          validVarName='any',
          transpose={'bagged'};
    alterTable / name="sample_bs_Influence" columns={{name="_name_", drop=TRUE}};
run;


/* Use model of Difference in MAP from each bootstrap resample to detect influential rows of data */
proc cas;
assess / table={name='sample_BS_PRED', groupBy={{name='bsID'}, {name='BAG'}}},
         casOut={name='sample_BS_PRED_LIFT', replace=true},
         inputs={{name='Pred'}},
         response='MSRP',
         fitStatOut={name='sample_BS_PRED_FITSTAT', replace=true},
         includeZeroDepth=true;
/* merge the absolute difference in fitstat.map between bag=0/1 and use as response in tree */
transpose / table={name='sample_BS_PRED_FITSTAT', groupBy={{name='bsID'}}},
      id={'BAG'},
      casOut={name='TEMP_FITSTAT', replace=true},
      prefix='bag',
      validVarName='any',
      transpose={'_MAE_'};
/* Need to quote **** because it is a fedsql reserverd word */
fedsql.execDirect / query="create table sample_bs_Influence {options replace=True} as
                select * from
                  (select * from sample_bs_Influence) a
                  join
                  (select bsID, abs(bag1-bag0) as aMAE_1m0, (bag1-bag0) as MAE_1m0 from temp_FITSTAT) b
                  using (bsID)";
  dropTable name='temp_FITSTAT';
run;

proc cas;
		table.columninfo result=c / table={name='sample_bs_Influence'};
		loadActionSet / actionSet='decisionTree';
		decisionTree.dtreeTrain / table={name='SAMPLE_BS_INFLUENCE'},
			target='aMAE_1m0', inputs=c.columninfo.where(substr(column,1,4)=='case')[,"column"],
			nBins=20, maxLevel=16, maxBranch=2, leafSize=5, crit='VARIANCE',
    	missing='USEINSEARCH', minUseInSearch=1, binOrder=true, varImp=true, casOut={name='SAMPLE_BS_INFLUENCE_ACCURACY_aMAE_1m0', replace=true},
			mergeBin=true, encodeName=true;
		decisionTree.dtreeTrain / table={name='SAMPLE_BS_INFLUENCE'},
			target='MAE_1m0', inputs=c.columninfo.where(substr(column,1,4)=='case')[,"column"],
			nBins=20, maxLevel=16, maxBranch=2, leafSize=5, crit='VARIANCE',
    	missing='USEINSEARCH', minUseInSearch=1, binOrder=true, varImp=true, casOut={name='SAMPLE_BS_INFLUENCE_ACCURACY_MAE_1m0', replace=true},
			mergeBin=true, encodeName=true;
run;







*cas mysess clear;
