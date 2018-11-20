# Resampling Methods in the SAS Viya CAS Engine
This repository contains code, walkthroughs, examples, and applications of bootstrap methods.  It utilizes the computing infrastructure of SAS Viya's CAS engine.  This allows distributed computation of bootstrap iterations in parallel with very minimal code!

## Motivation
When our sample is limited (when isn't it?) and we want to understand parameter estimates, it is desirable to resample the population.  With bootstrapping, we can resample the sample many times to further learn from our sample and assess uncertainty.  The benefit of this project is making the "many times" easy and fast for the user.

For an acknowledgement of the importance of the bootstrap, a great place to start is the writeup for it's inventor being awarded the [International Prize in Statistics](http://statprize.org).  Thank you Professor Efron for putting a computer on the desk (now, the cloud) of every statistician.

## Notes about code
All code is written in SAS CASL which can be executed from a SAS interface with PROC CAS or from the various (Python, R, REST,...) API's.  As of SAS Viya version 3.4 there is not a packaged bootstrap action.  This repository has a user defined action set and instructions for loading it in your environment.  This also makes a great example of how to easily extend the capabilities of SAS Viya and share with all users in your environment.

## Contents of the repository
* [resample - defineActionSet.sas](./resample%20-%20defineActionSet.sas)
* Folder: [examples](./examples) contains examples of using the actions
  * [example 1 - loading and using bootstrap action from resample.sas](./examples/example%201%20-%20loading%20and%20using%20bootstrap%20action%20from%20resample.sas)
  * [example 2 - regression bootstrap parameter estimates.sas](./examples/example%202%20-%20regression%20bootstrap%20parameter%20estimates.sas)
  * [example 3 - regression double bootstrap parameter estimates.sas](./examples/example%203%20-%20regression%20double%20bootstrap%20parameter%20estimates.sas)
* Folder: [walkthroughs](./walkthroughs) contains step-by-step commented versions of the code within the actions to help understand how they work.  This is great for learning!
  * [walkthrough - addRowID action.sas](./walkthroughs/walkthrough%20-%20addRowID%20action.sas)
  * [walkthrough - bootstrap action.sas](./walkthroughs/walkthrough%20-%20bootstrap%20action.sas)
  * [walkthrough - doubleBootstrap action.sas](./walkthroughs/walkthrough%20-%20doubleBootstrap%20action.sas)
  * [walkthrough - working with distributed data.sas](./walkthroughs/walkthrough%20-%20working%20with%20distributed%20data.sas)

## Setting up the actions in your environment
Run the code in [resample - defineActionSet.sas](./resample%20-%20defineActionSet.sas).  Some lines that may need changing:
* line 1: connects to a CAS session
* To Save the actions for future sessions and use by other users:
  * line 130: create an in-memory table of the action set
  * line 131: persist the in-memory table in .sashdat file.  Here it is pointed as caslib="Public".
* If you need to remove the action set then uncomment and use:
  * line 133: removes the persisted in-memory table

## Actions Instructions
To use the actions you will need to load the user define actions with:
```SAS
builtins.actionSetFromTable / table={caslib="Public" name="resampleActionSet.sashdat"} name="resample";
```
---
### resample.addRowID action
Updates the provided table <intable> with a new column named RowID that has a naturally numbered (1,2,...,n) across the distributed in-memory table.
```
CASL Syntax

    resample.addRowID /
      intable="string"

Parameter Descriptions

    intable="string"  
      required  
      Specifies the name of the table in cas
```

---
### resample.bootstrap action
Creates a table of identically sized bootstrap samples from table <intable> and stores them in a table named <intable>_bs.  Runs the addRowID action on the <intable>.  Columns that describe the link between the bootstrap samples and the original samples are:
* bsID - is the naturally numbered (1, 2, ..., b) identifier of a resample
* bs_rowID - is the natually numbered (1, 2, ..., n) row identifier within the value of bsID
* rowID - is the natrually numbered (1, 2, ..., n) row identifier for the sampled row in <intable>
* bag - is 1 for sampled rows, 0 for rowID values not sampled within the bsID (will have missing for bs_rowID)

```
CASL Syntax

    resample.bootstrap /
      intable="string"
      bss=integer

Parameter Descriptions

    intable="string"  
      required  
      specifies the name of the table to sample from in cas
    bss=integer
      not required
      default=10
      Specifies the number of resamples to take per threadid in the cas environment
```

---
### resample.doubleBootstrap action
Creates a table of identically sized bootstrap and double-bootstrap samples from table <intable> and stores them in a tables <intable>_bs and <intable>_dbs.  Runs the addRowID action on the <intable>.  Columns that describe the link between the double-bootstrap samples and the bootstrap samples are:
* bsID - is the naturally numbered (1, 2, ..., b) identifier of a resample
* dbsID - is the naturally numbered (1, 2, ..., b) identifier of a resample from bsID
* dbs_rowID - is the naturally numbered (1, 2, ..., n) row identifier within the value of dbsID
* bs_rowID - is the naturally numbered (1, 2, ..., n) row identifier for the sampled in bsID
* rowID - is the naturally numbered (1, 2, ..., n) row identifier for the sampled row in <intable>
* bag - is 1 for sampled rows, 0 for rowID values not sampled within the bsID (will have missing for bs_rowID)
  * 0 could be a non-sampled row in either the bsID or the dbsID (samples from bsID)

```
CASL Syntax

    resample.doubleBootstrap /
      intable="string"
      bss=integer

Parameter Descriptions

    intable="string"  
      required  
      specifies the name of the table to sampel from in cas
    bss=integer
      not required
      default=10
      Specifies the number of bootstrap resamples to take per threadid in the cas environment.
      The number of double-bootstrap resamples per bootstrap resample will be:
          bss multiplied by the number of threads in the cas environment  
      If you run resample.bootstrap first then ensure you used the same value of bss.
          If you don't run resample.bootstrap first then resample.doubleBootstrap will do it correctly.

```
---
## Contribute
Have something to add?  Just fork it, change it, and create a pull request!

Have comments, questions, suggestions? Just use the issues feature






## Notes - Move to Project in Github

dependency flow:
resample - defineActionSet.sashdat
  example 1
  walkthroughs - make sure changes to defineAction are reflected here
    wiki (these will reference row numbers)

readme:
  what this repo is
  overview of files
  links to wiki for deeper details, methodology, references, etc

wiki
  almost like a class teaching and illustrating methods
  code walkthroughs for documentation

  todo:
  how is double bootstrap spelled (hyphen?)
  is cas upper or lower case?
  test studio interactive with saving value between proc cas submission with and without quit statements.
  edit walkthrough distributed data
  add diagnostics at end of walkthroughs
  explain bss as function of nthreads - show code to get _nthreads_
    consider adding option to specify number of resamples and have code figure out bss
  create wiki pages with walkthrough code explained in detail
    first a a walkthrough page explaining why mpp for this - and point to walkthrough of dist data
  wiki page describing bootstrap in pictures using notation of book
  main wiki page point to efron award
    point out everything is in actions so portable to api's - link to documentation
