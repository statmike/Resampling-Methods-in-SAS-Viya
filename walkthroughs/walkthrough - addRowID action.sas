/* a step by step walkthrough of the addRowID action in the resample actionset
  link to wiki:
*/

/* setup a session - in SAS Studio use interactive mode for this walkthrough */
cas mysess sessopts=(caslib='casuser');
libname mylib cas sessref=mysess;

/* load example data to work with */
proc casutil;
	load data=sashelp.cars casout="sample" replace;
quit;

/* define a parameter to hold the table name.
      If you are in SAS Studio use interactive mode so this will be remembered */
proc cas;
		intable='sample';
run;

		/* If the table already has a column named rowID, remove it */
    table.columninfo result=i / table=intable;
      if i.columninfo.where(Column='ROWID').nrows=1 then do;
        alterTable / name=intable columns={{name='ROWID', drop=TRUE}};
      end;
      else; do; end;
run;

		/* get the row information from datastep automatic variables _threadid_ and _n_ */
    datastep.runcode result=t / code='data '|| intable ||'; set '|| intable ||'; threadid=_threadid_; n=_n_; run;';
run;

		/* use some fancy SQL to create a naturally numbered rowID from the _threadid_ and _n_ values */
    fedSql.execDirect / query='create table '|| intable ||' {options replace=true} as
                    select * from
                      '|| intable ||'
                      join
                      (select c.threadid, c.n, c.n+ifnull(d.basecount,0) as rowID from
                        (select threadid, n from '|| intable ||') c
                        left outer join
                        (select a.threadid, sum(b.threadcount) as basecount from
                            ((select distinct threadid from '|| intable ||') a
                            left outer join
                            (select threadid, count(*) as threadcount from '|| intable ||' group by threadid) b
                            on b.threadid < a.threadid)
                            group by a.threadid) d
                        on c.threadid=d.threadid) e
                      using(threadid,n)';
run;

		/* drop the columns that are nolonger needed: n, threadid */
    alterTable / name=intable columns={{name='n', drop=TRUE},{name='threadid', drop=TRUE}};
quit;

*cas mysess clear;
