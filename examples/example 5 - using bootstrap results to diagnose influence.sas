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
	resample.bootstrap / intable='sample' B=100 seed=12345 Bpct=1;
run;

/* analyze/train each bootstrap resample with the same model effects selected on the full sample data */
   glm result=myresult / table  = {name='sample_bs', groupBy='bsID'},
		 class = {'Origin','DriveTrain'},
		 model = fullmodel,
         partByVar = {name="bag",train="1",test="0"},
         outputTables = {names={'ParameterEstimates'="sample_BS_PE","FitStatistics"="sample_BS_FS"}, groupByVarsRaw=TRUE, replace=TRUE},
         output = {casOut={name='sample_bs_pred', replace=TRUE},
         		   pred='Pred', resid='Resid', cooksd='CooksD', h='H',
         		   copyVars={"bsID","bs_rowID","rowID","MSRP","bag"}};
run;

/* Use model RMSE from each bootstrap resample to detect influential rows of data */

/* create a table of counts for input sample rows occuring in the bootstrap resamples
    rows are bootstrap resamples and columns are those found in the input sample table.  */
proc cas;
    fedsql.execDirect / query="create table sample_bs_Influence {options replace=true} as
                    select bsID, rowID, count(*) as bagged
                      from sample_bs
                      where bag=1
                      group by bsID, rowID";
run;
proc cas;
    loadActionSet / actionSet='transpose';
    transpose / table={name='sample_bs_Influence', groupBy={{name='bsID'}}},
          id={'rowID'},
          casOut={name='sample_bs_Influence', replace=true},
          prefix='rowID_',
          validVarName='any',
          transpose={'bagged'};
    alterTable / name="sample_bs_Influence" columns={{name="_name_", drop=TRUE}};
run;
proc cas;
    /* Need to quote Value because it is a fedsql reserved word */
    fedsql.execDirect / query="create table sample_bs_Influence {options replace=True} as
                    select * from
                      (select * from sample_bs_Influence) a
                      join
                      (select bsID, "||quote('Value')||" as RMSE from sample_bs_fs where rowID='RMSE') b
                      using (bsID)";
run;

/* use a decision tree to model RMSE with the counts of column occurence in the modeled resamples */
ods graphics on;
  proc treesplit data=mylib.sample_bs_Influence outmodel=mylib.sample_bs_Influence_Model_RMSE maxdepth=15 plots=zoomedtree(depth=3);
    model RMSE = rowID_:;
    prune none;
  run;
ods graphics off;

proc cas;
		loadActionSet / actionSet='decisionTree';
		decisionTree.dtreeTrain / table={name='SAMPLE_BS_INFLUENCE'}, target='RMSE', inputs={{name='/rowID_/'},}, nBins=20, maxLevel=16, maxBranch=2, leafSize=5, crit='VARIANCE',
      missing='USEINSEARCH', minUseInSearch=1, binOrder=true, varImp=true, casOut={name='SAMPLE_BS_INFLUENCE_MODEL_RMSE',
      replace=true}, mergeBin=true, encodeName=true;
run;
		decisionTree.dtreeTrain / table={name='SAMPLE_BS_INFLUENCE'}, target='RMSE', inputs={{name='rowID_1'},
      {name='rowID_2'}, {name='rowID_3'}, {name='rowID_4'}, {name='rowID_5'}, {name='rowID_6'}, {name='rowID_7'}, {name='rowID_8'},
      {name='rowID_9'}, {name='rowID_10'}, {name='rowID_11'}, {name='rowID_12'}, {name='rowID_13'}, {name='rowID_14'},
      {name='rowID_15'}, {name='rowID_16'}, {name='rowID_17'}, {name='rowID_18'}, {name='rowID_19'}, {name='rowID_20'},
      {name='rowID_21'}, {name='rowID_22'}, {name='rowID_23'}, {name='rowID_24'}, {name='rowID_25'}, {name='rowID_26'},
      {name='rowID_27'}, {name='rowID_28'}, {name='rowID_29'}, {name='rowID_30'}, {name='rowID_31'}, {name='rowID_32'},
      {name='rowID_33'}, {name='rowID_34'}, {name='rowID_35'}, {name='rowID_36'}, {name='rowID_37'}, {name='rowID_38'},
      {name='rowID_39'}, {name='rowID_40'}, {name='rowID_41'}, {name='rowID_42'}, {name='rowID_43'}, {name='rowID_44'},
      {name='rowID_45'}, {name='rowID_46'}, {name='rowID_47'}, {name='rowID_48'}, {name='rowID_49'}, {name='rowID_50'},
      {name='rowID_51'}, {name='rowID_52'}, {name='rowID_53'}, {name='rowID_54'}, {name='rowID_55'}, {name='rowID_56'},
      {name='rowID_57'}, {name='rowID_58'}, {name='rowID_59'}, {name='rowID_60'}, {name='rowID_61'}, {name='rowID_62'},
      {name='rowID_63'}, {name='rowID_64'}, {name='rowID_65'}, {name='rowID_66'}, {name='rowID_67'}, {name='rowID_68'},
      {name='rowID_69'}, {name='rowID_70'}, {name='rowID_71'}, {name='rowID_72'}, {name='rowID_73'}, {name='rowID_74'},
      {name='rowID_75'}, {name='rowID_76'}, {name='rowID_77'}, {name='rowID_78'}, {name='rowID_79'}, {name='rowID_80'},
      {name='rowID_81'}, {name='rowID_82'}, {name='rowID_83'}, {name='rowID_84'}, {name='rowID_85'}, {name='rowID_86'},
      {name='rowID_87'}, {name='rowID_88'}, {name='rowID_89'}, {name='rowID_90'}, {name='rowID_91'}, {name='rowID_92'},
      {name='rowID_93'}, {name='rowID_94'}, {name='rowID_95'}, {name='rowID_96'}, {name='rowID_97'}, {name='rowID_98'},
      {name='rowID_99'}, {name='rowID_100'}}, nBins=20, maxLevel=16, maxBranch=2, leafSize=5, crit='VARIANCE',
      missing='USEINSEARCH', minUseInSearch=1, binOrder=true, varImp=true, casOut={name='SAMPLE_BS_INFLUENCE_MODEL_RMSE',
      replace=true}, mergeBin=true, encodeName=true;
			decisionTree.dtreeScore / table={name='SAMPLE_BS_INFLUENCE'}, modelTable={name='SAMPLE_BS_INFLUENCE_MODEL_RMSE'},
      noPath=true, encodeName=true;
			table.fetch / table={name='SAMPLE_BS_INFLUENCE_MODEL_RMSE'}, from=1, to=16384, sortBy={{name='_NodeID_',
      order='ASCENDING'}};
			sessionProp.getSessOpt / name='caslib';
			table.tableInfo / name='SAMPLE_BS_INFLUENCE_MODEL_RMSE', caslib='CASUSER(mihend)', quiet=true;
			table.columnInfo / table={name='SAMPLE_BS_INFLUENCE_MODEL_RMSE', caslib='CASUSER(mihend)'}, extended=true,
      sastypes=false;
run;

*cas mysess clear;
/* to do
decisionTree action - figure out wildcard for column names
comment code
make project plan for action that digs into tree results looking for interesting rows and clusters
*/
