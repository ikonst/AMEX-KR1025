#!/usr/bin/perl -w

use strict;
use DBI;
use Getopt::Long;
BEGIN { @INC = ('../lib',@INC); }
use FlatTextSchema;

# File format... the following represents just one line...
# table name <TAB> field name <TAB> field type <TAB> column start 
#  <TAB> bytelength <TAB> decimal place shift <TAB> sign pos 
#  <TAB> populated <TAB> condition 1 character pos
#  <TAB> condition 1 character <TAB> condition 2 character pos <TAB>
# condition 2 character <TAB> condition 3 character pos <TAB>
# condition 3 character
#  - field type is either ASCII or INTEGER or FLOAT
#  - decimal place shift only gets used for float fields, and is the
#    char position of the data.
#  - sign pos is the char position giving the sign of this entry
#  - conditions are optional


sub usage {
  print STDERR "$0 [--config configfile] [--dbtype oracle|pg]\n";
  print STDERR "   amexdatafile ...\n";
  exit(1);
}
my $config_file = "../conf/KR1025.conf";
my $dbtype = "oracle";
GetOptions('config|c=s' => \$config_file,
	   'dbtype|d=s' => \$dbtype)
  || &usage();
if ($config_file eq "") { &usage(); }


my $schema = new FlatTextSchema $config_file;
$schema->set_database_type($dbtype);
my @records = $schema->read_data_file($ARGV[0]);

print "BEGIN TRANSACTION;\n" unless $dbtype eq 'oracle';
  # it's too big a transaction for oracle (!!!)
my $record;
my @sql_statements;
my $sql;
foreach $record (@records) {
  @sql_statements = $record->emit_as_sql();
  foreach $sql (@sql_statements) {
    print "   $sql;\n";
  }
}
print "END TRANSACTION;\n" unless $dbtype eq 'oracle';



