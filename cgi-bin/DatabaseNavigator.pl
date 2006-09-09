#!/usr/bin/perl -w

use strict;
use DBI;
use CGI;

# What variables do I expect?
#   - database instance
#   - username,  password (perhaps -- maybe I use Basic HTTP Authentication)
#   - table


my $dbh = DBI->connect("dbi:Pg:dbname=AMEX","","", 
		       {RaiseError => 1, FetchHashKeyName => "NAME_uc" }
		      );
END { $dbh->disconnect(); }
my $query = new CGI;

my $database_instance = "AMEX";

my ($table,$id);
my $url = $query->url();

my @tables = $dbh->tables;
@tables = map (uc,@tables);


print $query->header;
$table = $query->param("table") || "";
$id = $query->param("id") || "";

&list_tables()                     if ($id eq "") && ($table eq "");
&show_tables_with_id($id)          if ($id ne "");
&show_table($table)                if grep (/$table/i,@tables);



sub show_table ($) {
  my $table = shift;
  print $query->start_html("$table");
  print $query->h1($table);
  &show_constrained_table($table,"1=1");
  print $query->end_html();
  exit(0);
}

sub list_tables {
  print $query->start_html("Tables");
  print $query->h1("Tables");
  print $query->start_table({-border=>2});
  my @links = map (qq{<A HREF="$url?table=$_"> $_ </A>},@tables);
  print $query->Tr(\@links);
  print $query->end_table();
  print $query->end_html();
  exit(0);
}

sub show_tables_with_id {
  my $id = shift;
  my $constraint = "id = ". $dbh->quote($id);
  my $table;
  print $query->start_html("ID = $id");
  print $query->h1("ID = $id");
  foreach $table (@tables) { &show_constrained_table($table,$constraint); }
  print $query->end_html();
  exit(0);
}

sub show_constrained_table ($$) {
  my $table = shift;
  my $constraint = shift;
  my $sth = $dbh->prepare("select * from $table WHERE $constraint");
  $sth->execute() || return;
  my $result;
  my $k;
  my @columns;
  my $first_time = 1;
  my $how_many_rows = $sth->rows;
  my $current_row_number = 0;
  my $start = $query->param('start') || 1;
  my $count = $query->param('count') || 40;
  my @data_rows;
  my @neaten_names;
  my $i;
  print $query->i("Showing results $start to ".($start+$count-1)." of $how_many_rows of $table");
  while ($result = $sth->fetchrow_hashref) {
    $current_row_number++;
    next if ($current_row_number < $start);
    last if ($current_row_number >= $start + $count);
    if ($first_time) {
      @columns = keys %$result;
      # if we have a field called ID,  put it first
      @columns = ("ID",grep($_ !~ /^ID$/,@columns)) if grep (/^ID$/,@columns);
      print $query->start_table({-border=>2});
      @neaten_names = @columns;    map(s/_/ /g,@neaten_names);
      print $query->Tr($query->th(\@neaten_names));
      $first_time = 0;
    }
    my @data_rows = map ($result->{$_}, @columns);
    $data_rows[0] = "<a href=\"$url?id=".$query->escapeHTML($data_rows[0]).
      "\"> $data_rows[0] </a>";
    print $query->Tr($query->td(\@data_rows));
  }
  print $query->end_table();
  $sth->finish();
}




