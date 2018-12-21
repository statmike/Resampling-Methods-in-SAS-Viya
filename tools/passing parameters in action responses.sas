/* verbose version */
cas mysess sessopts=(caslib='casuser');

proc cas;
	builtins.defineActionSet /
		name = "examples"
		actions = {
			{
				name = "actionA"
				parms = {
					{name="inparmA", type="INT", required=TRUE}
				}
				definition = "
					print 'In Action A';
					print 'Calling Action B';
							examples.actionB result=B / inparmB=inparmA;
					print 'Back in Action A';
					print B.ourparmB ' is outparmB';
							resp.outparmA=B.outparmB;
							resp.outparmA2=4;
							send_response(resp);
					print 'Leaving Action A';
				"
			}
			{
				name = "actionB"
				parms = {
					{name="inparmB", type="INT", required=TRUE}
				}
				definition = "
					print 'In Action B';
							resp.outparmB=2*inparmB;
					print inparmB 'is inparmB';
					print resp.outparmB ' is outparmB';
							send_response(resp);
					print 'Leaving Action B';
				"
			}
		}
	;
quit;

proc cas;
	examples.actionB result=B / inparmB=1;
	print B.outparmB ' is outparmB';
quit;

proc cas;
	examples.actionA result=A / inparmA=1;
	print A.outparmA ' is outparmA';
	print A.outparmA2 ' is outparmA2';
quit;


cas mysess clear;








/* short version */
cas mysess sessopts=(caslib='casuser');

proc cas;
	builtins.defineActionSet /
		name = "examples"
		actions = {
			{
				name = "actionA"
				parms = {
					{name="inparmA", type="INT", required=TRUE}
				}
				definition = "
							examples.actionB result=B / inparmB=inparmA;
							resp.ourparmA=B.outparmB;
							send_response(resp);
				"
			}
			{
				name = "actionB"
				parms = {
					{name="inparmB", type="INT", required=TRUE}
				}
				definition = "
							resp.outparmB=2*inparmB;
							send_response(resp);
				"
			}
		}
	;
quit;

/* directly call actionB and print result */
proc cas;
	examples.actionB result=B / inparmB=1;
	print B.outparmB ' is outparmB';
quit;

/* call actionA which will call actionB and then print result */
proc cas;
	examples.actionA result=A / inparmA=1;
	print A.outparmA ' is outparmA';
quit;


cas mysess clear;
