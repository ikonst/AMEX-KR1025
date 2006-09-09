package FlatTextSchema;

=head1 FlatTextSchema

The purpose of this module is to handle data files that are
generated by Cobol programs.  These are often records 
with fixed length fields.  The only real challenge about them
is that they often have varying parameters. e.g. if the
character in column 57 is "Y" then characters in 58-65 have
one meaning, otherwise they should be interpreted as a totally
different set of fields.

This module helps you read such a data file in and store it
in a database.  It also has code to help you set up the
configuration.

=head2 Terminology

The "data" file is the thing that the Cobol program generates.
A "configuration" file tells this module what to expect where
in the data file.

=cut

sub new {
  my $class = shift;
  my $self = {
	      "line_number" => 1,
	      "database_type" => "pg"
	     };  # what line of a config file we've read
  bless $self,$class;
  if ($#_ > -1) {
    $self->initialize_from_file($_[0]);
  }
  return $self;
}



######################################################################
# Configuration file stuff...

=head2 Configuration File format

The following represents just one line, which defines one data element. 
A data element will correspond to one column from an insert
statement that gets generated.  Each part of the definition of
a data element is separated by a tab.

=over 4

=item table name

What table to put this data into element.

=item field name

What column name this data goes into.

=item field type

ASCII or INTEGER or FLOAT or DATE or KEY.  

=item column start

The character position in the data file where this data starts.
If the field type is KEY,  this column is ignored;  the data is always
'timestamp,datafile_linenumber' (e.g.  '2002-08-13/14:33:24.333,12')

=item bytelength

How many characters wide it is in the data file.

=item decimal place shift

Only relevant for floating point fields (where field type is FLOAT).
It states what column in the data file to look for a decimal point
shift.  The decimal point shift number it finds there (only a single
digit, sorry), says how many characters from the right the decimal
place goes.

=item sign position

What column in the data file to look for a signum (e.g. a +,- or nothing).
Only used for data elements where the field type is FLOAT or INTEGER.

=item populated

Should I expect to find some real data for this field,  or is just
a place holder for something that will be added later?

=item condition 1 character position

This is a partner with the next item.  Go and look at this
character position in the data file...

=item condition 1 character requirement

... and check to see if the character there in the data 
file matches this character defined in the config file.

=item condition 2 character position

Same idea as for condition 1.  Incidentally, the conditions
are optional.

=item condition 2 character requirement

=item ...

As many more conditions as you want.  Actually,  the code
probably doesn't work with more than three.

=back

#'#



=cut


sub initialize_from_line ($$) {
  my $self = shift;
  my $line = shift;
  my $line_number = $self->{"line_number"};

  chomp $line;
  return if $line =~ /^#/;
  return if $line =~ /^\s*$/;

  my @fields = split(/\t/,$line);
  my $name = $fields[0] . "." . $fields[1] . "," . $line_number;

  return if $name =~ /^\s*$/;  # don't know if this is possible, or problematic

  $config_file_data = exists $self->{"config_file_data"} ?
    $self->{"config_file_data"} : {};

  $config_file_data->{$name} = {};
  $config_file_data->{$name}->{"line_number"} = $line_number++;
  $self->{"line_number"} = $line_number;
  my @ls = qw{table_name field_name field_type column_start bytelength
	      decimal_place_shift sign_pos populated};
  my $l;
  foreach $l (@ls) { $config_file_data->{$name}->{$l} = shift @fields; }
  die "Unknown value ($config_file_data->{$name}->{populated}) for $name populated field" if ($config_file_data->{$name}->{"populated"} !~ /Y|N/i);
  my $i = 1;
  while ($#fields > -1) {
    $config_file_data->{$name}->{"condition_${i}_character_pos"} = shift @fields;
    $config_file_data->{$name}->{"condition_${i}_character_req"} = shift @fields;
    $i++;
  }
  $self->{"config_file_data"} = $config_file_data;
  return;
}

sub initialize_from_file ($$) {
  my $self = shift;
  my $filename = shift;
  my $line;
  open(CONFIG_FILE,$filename);
  while ($line = <CONFIG_FILE>) {  $self->initialize_from_line($line); }
  close(CONFIG_FILE);

}

sub set_database_type ($$) {
  my $self = shift;
  my $dbtype = shift;
  $dbtype = lc $dbtype;
  my %types = ("oracle" => "oracle",
	       "postgresql" => "pg",
	       "pg" => "pg",
	       "psql" => "pg",
	       "pgsql" => "pg");
  if (exists ($types{$dbtype})) { $self->{"database_type"} = $dbtype; }
  else { die "unknown database $dbtype"; }
}

sub field_type_to_sql_type ($$$) {
  my $self = shift;
  my $field_type = shift;
  my $size = shift;
  my $dbtype = $self->{"database_type"};
  if ($dbtype eq "oracle") {
    if ($field_type eq "ASCII") { return "varchar2($size)"; }
    if ($field_type eq "INTEGER") { return "numeric($size)"; }
    if ($field_type eq "FLOAT") { return "numeric($size,2)"; }  # hmm???
    if ($field_type eq "KEY") { return "varchar2(32)"; }
    if ($field_type eq "DATE") { return "date"; }
    die "unknown type $field_type";
  }
  if ($dbtype eq "pg") {
    if ($field_type eq "ASCII") { return "varchar"; }
    if ($field_type eq "INTEGER") { return "int"; }
    if ($field_type eq "FLOAT") { return "float"; }
    if ($field_type eq "KEY") { return "varchar"; }
    if ($field_type eq "DATE") { return "date"; }
    die "unknown type $field_type";
  }
  die "unknown dbtype $dbtype";
}

sub schema_creation ($) {
  my $self = shift;
  my $name;
  my $tablename;
  $config_file_data = exists $self->{"config_file_data"} ?
    $self->{"config_file_data"} : {};
  print "-- Schema generated at ".localtime()."\n";
  my %tables = ();
  my $list;
  my $sqlname;
  my $columntype;
  my $seen_sqlnames = {};
  foreach $name (keys %$config_file_data) {
    next unless $config_file_data->{$name}->{"populated"} =~ /Y/i;
    $tablename = $config_file_data->{$name}->{"table_name"};
    $sqlname = $config_file_data->{$name}->{"field_name"};
    next if (exists $seen_sqlnames{"$tablename.$sqlname"});
    $seen_sqlnames{"$tablename.$sqlname"} = 1;
    $columntype = 
      $self->field_type_to_sql_type
	(
	 $config_file_data->{$name}->{"field_type"},
	 $config_file_data->{$name}->{"bytelength"}
	);
    unless (exists $tables{$tablename}) { $tables{$tablename} = []; }
    $list = $tables{$tablename};
    if ($config_file_data->{$name}->{"field_type"} eq "KEY") {
      @$list = ("$sqlname $columntype PRIMARY KEY",@$list);
    } else {
      @$list = (@$list,"$sqlname $columntype");
    }
  }

  my $sql;
  my @results = ();
  foreach $tablename (keys %tables) {
    $list = $tables{$tablename};
    # Now, sort the fields alphabetically, but keep the keys first
    @$list = ((sort grep($_ =~ /PRIMARY KEY/,@$list)), 
	      (sort grep($_ !~ /PRIMARY KEY/,@$list)));
    $sql = "create table \U$tablename\E (\n     ".
      join(",\n     ",@$list). "\n);";
    @results = (@results,"drop table \U$tablename\E;",$sql);
  }
  return @results;

}

######################################################################
# OK, that's enough stuff about configuration files,  now
# we're into things that manipulate data files...

sub check_conditions ($$$) {
  my $self = shift;
  my $name = shift;
  my $line = shift;
  my $condition_pos;
  my $condition_req;
  my $condition_char;
  my $i;
  my $config_file_data = $self->{"config_file_data"};
  my $element = $config_file_data->{$name};

  for ($i=1;  exists $element->{"condition_${i}_character_pos"};$i++) {
    $condition_pos = $element->{"condition_${i}_character_pos"};
    $condition_req = $element->{"condition_${i}_character_req"};
    if ($condition_pos =~ /^\d+$/) {
      $condition_char = substr($line,$condition_pos-1,1);
     if ($condition_char ne $condition_req) { return 0; }
    }
  }
  return 1;
}


1;

package FlatTextSchema::Record;

my @package_load_timestamp = localtime();
my $package_load_timestamp = 
		      sprintf ("%4d-%.2d-%.2d/%.2d:%.2d:%.2d",
			       $package_load_timestamp[5]+1900,
			       $package_load_timestamp[4]+1,
			       $package_load_timestamp[3],
			       $package_load_timestamp[2],
			       $package_load_timestamp[1],
			       $package_load_timestamp[0]);

sub timestamp { return $package_load_timestamp; }
		
sub new {
  my $class = shift;
  my $schema = shift;
  my $line = shift;
  my $datafile_linenumber = shift;
  my $self = { "schema" => $schema , "line" => $line };
  bless $self,$class;
  $self->parse($datafile_linenumber);
  return $self;
}

my %month_names = ('01' => 'Jan',  '1' => 'Jan',
		   '02' => 'Feb',  '2' => 'Feb',
		   '03' => 'Mar',  '3' => 'Mar',
		   '04' => 'Apr',  '4' => 'Apr',
		   '05' => 'May',  '5' => 'May',
		   '06' => 'Jun',  '6' => 'Jun',
		   '07' => 'Jul',  '7' => 'Jul',
		   '08' => 'Aug',  '8' => 'Aug',
		   '09' => 'Sep',  '9' => 'Sep',
		   '10' => 'Oct',  '11' => 'Nov', '12' => 'Dec');

my %month_lengths = ('Jan' => 31, 'Feb' => 29, 'Mar' => 31, 'Apr' => 30,
		     'May' => 31, 'Jun' => 30, 'Jul' => 31, 'Aug' => 31,
		     'Sep' => 30, 'Oct' => 31, 'Nov' => 30, 'Dec' => 31);

sub cobol_date_string_to_sql_date_string {
  my $cobol_date_string = shift;
  $cobol_date_string =~ s/ *$//;
  $cobol_date_string =~ s/^ *//;
  my ($day,$month_number,$year);
  # YYYY-MM-DD or YYYYMMDD or YYYYY/MM/DD or YYMMDD or YY-MM-DD or YY/MM/DD
  if ($cobol_date_string =~ /^\s*$/) {
    return "NULL";
  }
  if ($cobol_date_string =~ m!^(\d{2,4})[-:/]?(\d{2})[-:/]?(\d{2})$!) {
    $day = $3;
    $month_number = $2;
    $year = $1;
    if (length($year) == 2) { $year = "20" . $year; } # y21c problem.
    if (exists $month_names{$month_number} and
	$day <= $month_lengths{$month_names{$month_number}}
	and  ($year <= $package_load_timestamp[5]+1900)
       ) {
      return $day."/".$month_names{$month_number}."/".$year;
    }
  }

  # DD-MM-YYYY or DDMMYYYY or DD/MM/YYYY or DD-MM-YY or DDMMYY or DD/MM/YY
  if ($cobol_date_string =~ m!^(\d{2})[-:/]?(\d{2})[-:/]?(\d{2,4})$!) {
    $day = $1;
    $month_number = $2;
    $year = $3;
    if (length($year) == 2) { $year = "20" . $year; } # y21c problem.
    if (exists $month_names{$month_number} and
	$day <= $month_lengths{$month_names{$month_number}}
	and  ($year <= $package_load_timestamp[5]+1900)
       ) {
      return $day."/".$month_names{$month_number}."/".$year;
    }
  }

  # Last variations...  MMDDYY (USA)?
  if ($cobol_date_string =~ m!^(\d{2})[-:/]?(\d{2})[-:/]?(\d{2,4})$!) {
    $day = $2;
    $month_number = $1;
    $year = $3;
    if (length($year) == 2) { $year = "20" . $year; } # y21c problem.
    if (exists $month_names{$month_number} and
	$day <= $month_lengths{$month_names{$month_number}}
	and  ($year <= $package_load_timestamp[5]+1900)
       ) {
      return $day."/".$month_names{$month_number}."/".$year;
    }
  }
  # Finally MMYYDD (France) ?
  if ($cobol_date_string =~ m!^(\d{2})[-:/]?(\d{2,4})[-:/]?(\d{2})$!) {
    $day = $3;
    $month_number = $1;
    $year = $2;
    if (length($year) == 2) { $year = "20" . $year; } # y21c problem.
    if (exists $month_names{$month_number} and
	$day <= $month_lengths{$month_names{$month_number}}
	and  ($year <= $package_load_timestamp[5]+1900)
       ) {
      return $day."/".$month_names{$month_number}."/".$year;
    }
  }
  return "NULL";
#  die "Don't know how to convert $cobol_date_string to a date";
}


sub parse {
  my $self = shift;
  my $datafile_linenumber = shift;
  my $schema = $self->{'schema'};
  my $config_file_data = $schema->{"config_file_data"};
  my $line = $self->{'line'};
#  my @fieldnames = sort 
#    {
#      $config_file_data->{$a}->{"line_number"}
#	<=>  $config_file_data->{$b}->{"line_number"};
#    } (keys %$config_file_data);
  my @fieldnames = keys %$config_file_data;
  my $inserts = {};  # what we are going to emit as an insert statement
  $self->{"inserts"} = $inserts;
  my $name;
  foreach $name (@fieldnames) {
    next if $config_file_data->{$name}->{"populated"} !~ /Y/i;
    next unless $schema->check_conditions($name,$line);
    my $element = $config_file_data->{$name};
    # OK, this data element is good.  Let's fetch it.
    my $text;
    my $column_name;
    my $table_name;
    if ($element->{"field_type"} eq "KEY") {
      $text = "$package_load_timestamp,$datafile_linenumber";
    } else {
      $text = substr($line,$element->{"column_start"}-1,$element->{"bytelength"});
      # now, adjustments to it,  multiplications, signum, etc.
      $text *= 0.1 ** substr($line,$element->{"decimal_place_shift"}-1,1)
	if ($element->{"decimal_place_shift"} =~ /^\d+$/);
      $text *= (substr($line,$element->{"sign_pos"}-1,1)."1")
	if ($element->{"sign_pos"} =~ /^\d+$/);
    }
    $table_name = $element->{"table_name"};
    $column_name = $element->{"field_name"};
    if (!exists $inserts->{$table_name}) { $inserts->{$table_name} = {} };

    if ($element->{"field_type"} =~ /ASCII|KEY/) {
      $text =~ s/'/''/g;  # this isn't quite correct quoting, really
      $text =~ s/ *$//g;  # get rid of tailing spaces
      $inserts->{$table_name}->{$column_name} = "'".$text."'";
    } elsif ($element->{"field_type"} =~ /DATE/) {
      #print STDERR "date = '$text'  (line $datafile_linenumber,  $table_name.$column_name)\n";
      $text = &cobol_date_string_to_sql_date_string($text);
      if ($text eq 'NULL') {
	$inserts->{$table_name}->{$column_name} = "NULL";
      } else {
	$inserts->{$table_name}->{$column_name} = "'$text'";
      }
    } else {
      $inserts->{$table_name}->{$column_name} = $text;
    }
  }
}


sub emit_as_sql {
  my $self = shift;
  my $inserts = $self->{'inserts'};
  my $tname;
  my @sql = ();
  my $schema = $self->{'schema'};
  my $database_type = $schema->{"database_type"};
  my $separator = ",";
  if ($database_type eq 'oracle') {  $separator = ",\n"; }
  
  foreach $tname (keys %$inserts) {
    my $table = $inserts->{$tname};
    my @columns = keys %$table;
    my @values = values %$table;
    my $sql = "insert into $tname (".join(',',@columns).") values (".
      join($separator,@values).")";
    @sql = (@sql,$sql);
  }
  return @sql;
}

sub emit_as_oracle_loader {
  die "Unimplemented";
}

1;

package FlatTextSchema;

=head2 read_data_file($filename)

This function returns a list of FlatTextSchema::Records

=cut

sub read_data_file {
  my $self = shift;
  my $filename = shift;
  my @results = ();
  open(DATAFILE,$filename) || die "Can't open $filename";
  my $line;
  while ($line = <DATAFILE>) {
print STDERR "\r$.  ";
    @results = (@results,new FlatTextSchema::Record ($self,$line,$.));
  }
  close(DATAFILE);
  return @results;
}


1;