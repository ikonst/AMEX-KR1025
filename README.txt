KR1025 Reporting System
========================

First of all, the name is a misnomer.  The programs I have written do 
two things:
 - load new data files into Oracle
 - let a user modify a couple of specific custom tables.

The point is that if you want your American Express KR1025 monthly
reports automatically loaded into your general ledger, and you think that
AMEX take too long to update department_ids and business_units, you can
maintain this information yourself relatively easily.

Most of the reporting would be done through a tool like Crystal Reports,  
which should mostly work off one specific view (usually called 
MY_DETAIL_BILLING_DATA). This view is a cross join of the two specific tables 
(BLANK_FILLINS and SIC_TO_GENERAL_LEDGER) and one of the upload-generated 
tables (DETAIL_BILLING_DATA).  



[Files, Programs, Libraries]


The programs involved are mostly a CGI Perl script that talks to an
Oracle or Postgresql database as a back-end.  It makes almost no
assumptions about the browser; the only requirements are tables and
redirections (HTML 3.2 and onwards, I think).  No Javascript, no Java,
no cookies.  No graphics even.  Hardly any colour; works fine in black
and white.

Usually this would be installed in /usr/local/KR1025loader.
The web server (usually) Apache is configured with the following:

ScriptAlias /KR1025loader "/usr/local/KR1025loader/cgi-bin"

So visit the URL http://your-server/KR1025loader/amex-reporting.pl to
start using the software.

There is one program that gets used in production (amex-reporting.pl)
which performs all functions -- it uploads new data, provides screens
to display blank fields and lets the user update locations,
distribution points, etc.

amex-reporting.pl makes use of:
  /usr/local/KR1025loader/lib/DatabaseInteraction.pm
  /usr/local/KR1025loader/lib/FlatTextSchema.pm
  /usr/local/KR1025loader/conf/KR1025.conf

FlatTextSchema.pm understands the KR1025.conf file.  It can manipulate
individual lines from an Amex data feed and turn them into SQL statements.

DatabaseInteraction.pm is the site-specific customisations.  Have
a look at the [Customisation] section below for the kinds of things
in it.

The KR1025.conf is documented in the [KR1025.conf] section of this
document.

There are three other programs of note:

 - make_schema.pl  (in  /usr/local/KR1025loader/bin);  this creates the
 tables in the Oracle database that are needed -- see the [Database
 Setup section]

 - read_amex_data_file.pl (also in /usr/local/KR1025loader/bin);  this
 is a command-line way of loading Amex data files into the Oracle database.
 It doesn't actually load anything,  it just creates SQL statements to
 do the inserts.

 - DatabaseNavigator.pl (in /usr/local/KR1025loader/cgi-bin);  I just
 used this to poke around in the database when I was developing things.
 I doubt it even works still.



[Web security]

The apache configuration conftains:
<Directory "/usr/local/KR1025loader/cgi-bin">
   AllowOverride AuthConfig
   ... 
</Directory>

The AllowOverride lets the .htaccess file in /usr/local/KR1025loader/cgi-bin
get used - here is its configuration:

AuthUserFile /usr/local/KR1025loader/etc/passwd
AuthName "AMEX Reporting System"
AuthType Basic
require valid-user

This forces a password to be given whenever anyone tries to run a 
program on the server.  There is only one account listed in 
/usr/local/KR1025loader/etc/passwd;  but if there were more,  it would
happily accept anyone to do anything.  The username is "amex", the same
as the password.

Of course, you can change this to use any other kind of authentication
you like (e.g. LDAP).


[Customisation,  Appearance]

There are only two files that need modification.  The DatabaseInteraction.pm
file in /usr/local/KR1025loader/lib is where you would change:
 - what database instance to connect to  (modify the "dbconnect" function)
 - what username and password to use   (modify the "dbconnect" function)
 - what name the view has (modify "view_name")
 - what sort of database it is (modify "dbtype" -- Oracle and Postgresql
 definitely work,  others can probably be made to work without too much
 trouble)
 - what you want to see on screen (modify "big_data_array").  For example,
 if you want to display more columns from the view (e.g. more information
 about the cardholder,  or more information about a transaction code),  
 you would add extra elements in the list of "display" fields. Currently,
 the display fields for 'blank_fillins' is cardmem_acnt_num and 
 cardmem_acnt_name.  'sic_to_general_ledger' has many more -- the
 trans_descr_line_1, gst_amount, mis_industry_code for starters.
 - how column headings are display (modify "pretty_up_column_heading")

The comments in  DatabaseInteraction.pm tell you what to do.

We wavered over how many lines to display for each page.  Originally it
was 10,  and then I up-ed it to 40.  This wasn't going to be a configurable
option,  so changing it is a little ugly. Line 266 of amex-reporting.pl says
  my $count = $query->param('count') || 40;
Replace the 40 by whatever number you want.

Alternatively,  you can add "&count=200" to the end of the URL field in
your browser at any time (and then press return  / go).  This overrides
the default.


[KR1025.conf]

The KR1025 format is documented internally to the file.  It is just a
plain text file, tab-separated.  Each line in it describes a column to
be inserted into a table of the database.

Here's a sample line,  broken up for readability:
DETAIL_BILLING_DATA	BUSINESS_PROCESS_DATE	DATE	398	8
  Y	1	1

This is saying that starting at character 398 in the Amex data file,
there are 8 characters which should be turned into a DATE field, and
stored in the BUSINESS_PROCESS_DATE column of the DETAIL_BILLING_DATA
table.  The field is populated ("Y"),  but this rule should only be
used if character 1 is equal to "1".

A more complicated example is:

DETAIL_BILLING_DATA	GST_AMOUNT	FLOAT	1384	15	
  1399	1383	Y	1	1


Which is saying... start at character 1384 in the Amex data file,  
and take the next 15 characters.  Put a decimal point at the
position specified by column 1399.  Check character 1383,  and see 
if it is a minus sign,  if it is, then negate the whole amount.  Again,
it is populated "Y",  but should only be used if character 1 is "1".

And finally, a simple one:

TELEPHONE_CALL	TELE_TIME_OF_CALL	ASCII	689	5
  Y	1	1	1332	2	1333	0

Take the 5 characters after char 689; this was goes into the
TELE_TIME_OF_CALL column of the TELEPHONE_CALL table,  but only if
character 1 is "1",  character 1332 is "2" and character 1333 is "0".






[Extensions -- what to do if Amex change formats]

a) A lot of the fields are not populated at the moment.  If Amex were
to populate some of these, there would be no impact at all --
amex-reporting.pl would just ignore it as it did the upload, since the
KR1025.conf file will have the populated field as "N".

b) Now suppose you really did want to get the data from one of these
fields that Amex has decided to populate.  Let's work through what we
would do if FILE_HEADER suddenly did get some COMMENTS in it.  The
KR1025.conf file has this to say: 
   FILE_HEADER COMMENTS ASCII 51 31    N 1 0
(Note the "N").

Firstly,  we would need to log in to Oracle,  and alter the FILE_HEADER
table,  since it will not have a comments column.  No problems here....
  svrmgrl>  alter table file_header add column comments varchar2(31); 
  svrmgrl>  commit;
Now we set the "N" to "Y" in that line in KR1025.conf .  

c) Amex decides to change the data file format completely.  There's no
easy way for amex-reporting.pl to know this has happened. You might
notice the "AMEX change control date" on the front screen changed;
although what you would probably notice is that either
amex-reporting.pl would never finish uploading the data, or that it
would, but there was garbage in lots of columns.  Either way, convince
a DBA to delete all the bad lines,  i.e:
  SVRMGRL> delete from detail_billing_data where upload_id = 'todaysdate' 

You would then need to work through the KR1025.conf file and check each 
line to see whether Amex's new file format still had each field in the
same location.  Then add any new ones and remove any old ones.  You could
then go through the database initialisation procedures documented here
(losing all old data),  or convince a DBA to manually run lots of 
"alter table" commands to add the extra columns,  remove the dud ones
and resize any columns that had changed in size.  (You might want to 
test this somewhere other than in production.)  

The KR1025.conf file gets re-read every time amex-reporting.pl gets
run.





[Database Initialisation]

The database is now set up and running,  and hopefully being backed
up,  but here is how it was created.  It is quite configurable,  too.

1.  Create the generic schema. 
 /usr/local/KR1025loader/bin/make_schema.pl

make_schema.pl reads the KR1025.conf file,  and prints out a sequence
of SQL statements that will create most of the tables in the database.
Save the statements off to a file somewhere,  and run them in Oracle
as the user you would like to have 

2.  Load /usr/local/KR1025loader/sql/sic-codes.sql check that the 
version for your database is uncommented.  It is mostly the same
between Postgresql and Oracle;  where there is a difference,  the
Oracle version is in place,  and the Postgresql version is commented
out.

3.  Take some sample data and turn it into SQL.  The program for
doing this is /usr/local/KR1025loader/bin/read_amex_data_file.pl.  
You will probably run it like this:

read_amex_data_file.pl amex_20020809.txt > /tmp/load-data.sql

It can be given arguments for alternative configuration files,  and
alternative database types.   Load this data up.  This step isn't
completely necessary,  but it will make the next steps nicer;  
for example,  the blank_fillins.sql file has a whole bunch of
insert statements that reference some real data.  

4.  Assuming you didn't skip step 3,  load the SQL file
/usr/local/KR1025loader/sql/blank_fillins.sql.

You might want to edit the file first;  there is a wad of 
(possibly obsolete) insert statements in it.  Also,  again
there are subtle differences between the Postgresql and Oracle
versions;  check that the version for your 
 database is uncommented. 

5.  Load custom_view.sql

You can make changes to this.   If you wanted a view that
cross-joined other new tables (that you wanted to fill in),
you can. By default it just creates a view covering detail_billing_data,
blank_fillins and sic_to_general_ledger.

6.  Load progress.sql

This can be done at any stage.  It's a tiny little file.

7. Make some indexes.  A few of these have been done,  but given the
small quantities of data involved,  it's hardly important. Here are
some ideas of worthwhile indexes:
   hash on DETAIL_BILLING_DATA.bill_date
   hash on DETAIL_BILLING_DATA.cardmem_acnt_num
   hash on DETAIL_BILLING_DATA.sic


