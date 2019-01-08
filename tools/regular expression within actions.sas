cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load original sample that will be resampled from */
proc casutil;
	load data=sashelp.cars casout="sample" replace;
quit;

proc cas;
   loadactionset / actionset='regression';
   glm / table  = {name='sample'},
		 model = {
					clb=TRUE,
		 			target = 'MSRP'
		 			effects = {
								{vars={'/^MPG/'}}
							}
		 			},
		 display = {names={'ParameterEstimates','Anova','FitStatistics'}};
run;

proc cas;
	loadActionSet / actionSet='decisionTree';
	dtreeTrain / table={name='sample'},
				 target='MSRP',
				 inputs={{name='/^MPG/'}},
				 nBins=20, maxLevel=16, maxBranch=2, leafSize=5, crit='VARIANCE',
      			 missing='USEINSEARCH', minUseInSearch=1, binOrder=true, varImp=true, mergeBin=true, encodeName=true;
run;

proc cas;
	loadActionSet / actionSet='decisionTree';
	dtreeTrain / table={name='sample'},
				 target='MSRP',
				 inputs={'MPG_City','MPG_Highway'},
				 nBins=20, maxLevel=16, maxBranch=2, leafSize=5, crit='VARIANCE',
      			 missing='USEINSEARCH', minUseInSearch=1, binOrder=true, varImp=true, mergeBin=true, encodeName=true;
run;

proc treesplit data=mylib.sample maxdepth=15;
  model MSRP = MPG:;
  prune none;
run;

*cas mysess clear;
