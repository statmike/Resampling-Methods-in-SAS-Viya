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
run;;

		/* look at a few rows of the intable to see the values of rowID */
		table.fetch / table=intable index=false to=10;
run;

quit;

*cas mysess clear;


/*
logic for unique rowID:
	input table: by processing as cas table into itself and keeping these automatic datastep variables:
		_nthreads_ is number of threads in the environment
		_threadid_ is the partition of rows assigned to a thread - these are naturally numbered in the environment
		_n_ is the natural number row count for row assigned to a _threadid_
	merge flow:
		1: rows 8-11  - keep threadid and a count of rows for smaller values of threadid
			left=distinct threadid, right=threadid, threadcount
			on right(b).threadid<left(a).threadid (will help get a cumulative count of rows)
		2: rows 7-12(includes step 1) - keep threadid and the sum of rows on all smaller threadid values
		3: rows 4-13(includes step 2) - keep threadid and n along with natural number rowID built from n and sum of rows on lower values of threadid
		4: rows 1-14(includes step 2) - merge original data with the above to get unique rowID using threadid, n
1	select * from
2		sample
3		join
4		(select c.threadid, c.n, c.n+ifnull(d.basecount,0) as rowID from
5			(select threadid, n from sample) c
6			left outer join
7			(select a.threadid, sum(b.threadcount) as basecount from
8					((select distinct threadid from sample) a
9					left outer join
10					(select threadid, count(*) as threadcount from sample group by threadid) b
11					on b.threadid < a.threadid)
12					group by a.threadid) d
13			on c.threadid=d.threadid) e
14		using(threadid,n)'
*/
