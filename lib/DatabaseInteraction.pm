package DatabaseInteraction;

# Obviously,  you change this file.

use DBI;

# If you are using a view

sub view_name {
  return "MY_DETAIL_BILLING_DATA";
}


## jayanya is Greg Baker's laptop, in case you're wondering, and I use
## postgresql

sub dbconnect {
  my $dbconn_str;
  my $username;
  my $password;
  if (`hostname` =~ /jayanya/) {
    return DBI->connect("dbi:Pg:dbname=AMEX","","", 
			{ RaiseError => 1, FetchHashKeyName => 'NAME_uc'});
  } else {
    $ENV{ORACLE_HOME}='/opt/oracle/product/8.1.7';
    return DBI->connect("dbi:Oracle:AMEX","amex","password-goes-here",
			{ RaiseError => 1, FetchHashKeyName => 'NAME_uc'});
  }

}


sub dbtype {
  if (`hostname` =~ /jayanya/) {
    return "postgresql";
  } else {
    return "oracle";
  }

}

# Extra SQL you want produced at the end of each upload.
sub post_upload_statements {
  return "update detail_billing_data set sic = 'XXX' where sic is null"
}


# The format for this thing is:
#
# - The keys are tables that suport the view in &view_name.  (i.e.
#   if you fill in one of these,  the view will magically fill stuff 
#   in for you.
# - The values point to a hash ref.  Here's the format for the hash-ref
#       - There should be three keys: display, fill-in and keyed-from
#       - The values should be list references, listing columns from
#         the &view_name table (they will also be names in the keyname
#         table).

my %big_data_array = 
  (
   'blank_fillins' 
   => { 'display' => ['cardmem_acnt_num','cardmem_acnt_name'],
	'fill-in' => ['surname','firstname','business_unit',
		      'department_id','distribution_point','location'],
	'keyed-from' => ['cardmem_acnt_num']
      },

   'sic_to_general_ledger'
   => { 'display' => ['sic','sic_description','trans_descr_line_1',
		      'trans_descr_line_2',
		      'billed_amt','mis_industry_code'],
	'fill-in' => ['gl_code','gl_description'],
	'keyed-from' => ['sic']
       }
   );


sub pretty_up_column_heading {
  my $column_heading = shift;
  $column_heading =~ s/_/ /g;
  $column_heading = uc $column_heading;
  return $column_heading;
}

######################################################################
######################################################################
######################################################################
######################################################################
######################################################################
######################################################################
######################################################################
######################################################################
#
# OK,  everything after this you don't change.
#
#
#
######################################################################
######################################################################

sub supporting_tables { return keys %big_data_array; }

# This function returns a where clause that will pick out
# incomplete rows from the &view_name table -- i.e. ones
# that have some NULLs which would be fixed by inserting stuff
# into a supporting_table.  You give it an argument of the supporting_table 
# you are working on.

sub nullity_clause {
  my $table = shift;
  my $or = " or ";
  my $and = " and ";
  my $dbtype = &dbtype();
  if ($dbtype eq 'oracle') { $or = "\n or "; $and = "\n and "; }
  my @dangerous_nulls = &fields_to_fill_in($table);
  my @ignores = &keyed_fields($table);
  if ($#dangerous_nulls == -1) { return "1=0"; } # because nothing is a problem
  my $positives;
  if ($dbtype eq 'oracle') {
    # oh dear,  oracle is *really, really* silly.  It thinks
    # that an empty string is a NULL.
    $positives = join($or,map("(trim($_) is null)",@dangerous_nulls));
  } else {
    $positives = join($or,map("(($_ is null) or (trim($_) = '')) ",
			      @dangerous_nulls));
  }
  if ($#ignores == -1) { return $positives; }
  my $negatives;
  if ($dbtype eq 'oracle') {
    $negatives = join($and,map("(trim($_) is not null)",@ignores));
  } else {
    $negatives = join($and,map("(trim($_)!='')",@ignores));
  }
  return "(($positives)\n and ($negatives))";
}

sub to_list { my $x = $big_data_array{$_[0]}->{$_[1]}; my @x = @$x; return @x;}
sub fields_to_fill_in { return &to_list($_[0],'fill-in'); }
sub helpful_fields_to_show { return &to_list($_[0],'display'); }
sub keyed_fields { return &to_list($_[0],'keyed-from'); }



1;
