#!/usr/bin/perl -w

use strict;
use CGI;
use DBI;
BEGIN { @INC = ('../lib',@INC); }
use FlatTextSchema;
use DatabaseInteraction;

my $query = new CGI;

print $query->header;

# Let's work out what parameters were given to us.  This
# will let us decide what to do next.

my $fh = $query->upload('RawAmexDataFile');
&handle_file_upload ($fh) if defined $fh;

my $upload_id = $query->param('upload_id');
my $tablename = $query->param('table');
my $full_display = $query->param('full_display') || 'no';
my $action = $query->param('action');

&update_supporting_table($upload_id,$tablename,$full_display)
  if defined $action and defined $tablename and defined $upload_id;
&display_dud_fields($upload_id,$tablename,$full_display) 
  if defined $tablename and defined $upload_id;
&show_upload_status($upload_id) if defined $upload_id;

# I give up.
&default_page();

######################################################################
die "Somehow fell through all the other functions";
######################################################################


sub default_page () {
  print 
    ( $query->start_html('AMEX Reporting System'),
      $query->h1(uc 'AMEX Reporting System'),
      $query->p("Past uploads: ")
      );
  my $dbh = &DatabaseInteraction::dbconnect();
  my $sql = qq{
	       select 
	         UPLOADS_AND_PROGRESS.ID AS upload_time,
	         ROWS_LOADED_SO_FAR,
	         (FILE_HEADER.report_prefix
	             || FILE_HEADER.report_number
	             || '-' || FILE_HEADER.product_version) as report_name,
  	         FILE_HEADER.change_control as change_ctl_field,
		 FILE_HEADER.cutoff_date as cutoff_date_field
               from UPLOADS_AND_PROGRESS, FILE_HEADER
               where FILE_HEADER.id like (UPLOADS_AND_PROGRESS.ID || '%')
	       and UPLOADS_AND_PROGRESS.COMPLETED=1
	       order by cutoff_date_field desc
	       };
  my $sth = $dbh->prepare($sql);
  $sth->execute();
  my $result;
  my @supporting_tables = &DatabaseInteraction::supporting_tables();
  my $table;

  print $query->start_table({-border => 2 });
  print $query->Tr($query->th("Cutoff Date"),
		   $query->th("Upload Time"),
		   $query->th("Rows in data file"),
		   $query->th("Report Name"),
		   $query->th("AMEX change control date"),
		   map($query->th($_),@supporting_tables)
		   );
  my ($upload_time,$link,@dud_lines,@final_columns);
  while ($result = $sth->fetchrow_hashref()) {
    $upload_time = $result->{"UPLOAD_TIME"};

    @final_columns = ();
    foreach $table (@supporting_tables) {
      my $count = &dud_lines($dbh,$upload_time,$table,
			     'NOT-FULL',"COUNT-DISTINCT");
      my $link = 
	$query->a({-href =>$query->url."?table=$table&upload_id=$upload_time"},
		  "Fix this &gt;&gt;");
      @final_columns = (@final_columns,$count. " ".$link);
    }
    print
      $query->Tr(
		 $query->td($result->{"CUTOFF_DATE_FIELD"}),
		 $query->td($query->a({-href=>$query->url."?upload_id=$upload_time"},
				      $upload_time)),
		 $query->td($result->{"ROWS_LOADED_SO_FAR"}),
		 $query->td($result->{"REPORT_NAME"}),
		 $query->td($result->{"CHANGE_CTL_FIELD"}),
		 map($query->td($_),@final_columns)
		);
  }
  $sth->finish();
  print $query->end_table;
  print $query->hr;
  print $query->p("Fresh upload: ");
  print $query->start_multipart_form(-method=>'post', -action=>$query->url());
  print $query->filefield(-name => 'RawAmexDataFile');
  print $query->submit(-value => 'Upload');
  print $query->end_multipart_form();
  print $query->end_html;
  $dbh->disconnect();
  exit(0);
};

sub handle_file_upload ($) {
  my $fh = shift;
  my @file_data = <$fh>;
  my $timestamp = &FlatTextSchema::Record::timestamp();
  $|=1;  # make sure things get flushed...
  my $pid = fork();
  if ($pid == 0) {
    # I am the child,  I do the work.
    &load_data_into_database($timestamp,\@file_data);
    exit(0);
  }
  my $url = $query->url() . "?upload_id=$timestamp";

  print $query->start_html(-title => "Data upload $timestamp",
			   -head => $query->meta({-http_equiv=>"refresh",
						  -content=>"2;URL=$url"})
			   );
  print $query->p("Data has not loaded yet,  please wait...");
  print $query->end_html;
  exit(0);
};
			
sub load_data_into_database ($$) {
  close(STDOUT);  # I think...
  my $dbh = &DatabaseInteraction::dbconnect();
  my $timestamp = shift;
  my $file_data = shift;
  my $total_rows = $#$file_data + 1;
  my $i;
  my $record;
  my $schema = new FlatTextSchema '../conf/KR1025.conf';
  $schema->set_database_type(&DatabaseInteraction::dbtype());
  my $sql;
  my @sql;
  $sql = qq{
	    INSERT INTO UPLOADS_AND_PROGRESS (ID,ROWS_LOADED_SO_FAR,
					      TOTAL_ROWS_TO_LOAD,COMPLETED)
	    VALUES ('$timestamp',0,$total_rows,0)
	   };
  $dbh->do($sql);
	   
  for ($i=0;$i<$total_rows;$i++) {
    $record = new FlatTextSchema::Record ($schema,$file_data->[$i],$i);
    @sql = $record->emit_as_sql();
    foreach $sql (@sql) {
      $dbh->do($sql);
    }
    $sql = qq{
	      update UPLOADS_AND_PROGRESS
	      SET ROWS_LOADED_SO_FAR = ROWS_LOADED_SO_FAR + 1 WHERE ID = '$timestamp'
	     };
    $dbh->do($sql);
    $dbh->commit unless $dbh->{AutoCommit};
  }
  $dbh->do(&DatabaseInteraction::post_upload_statements());
  $dbh->do(qq{ 
	      UPDATE UPLOADS_AND_PROGRESS
	      SET COMPLETED = 1 WHERE ID = '$timestamp'
	     });
  $dbh->disconnect();
};

sub get_upload_information ($$) {
  my $dbh = shift;
  my $timestamp = shift;
  my $sth = $dbh->prepare(qq{select ROWS_LOADED_SO_FAR,TOTAL_ROWS_TO_LOAD,COMPLETED
			      from UPLOADS_AND_PROGRESS
			     WHERE ID = '$timestamp'});
  $sth->execute();
  my $result;
  $result = $sth->fetchrow_hashref();
  unless (defined $result) { $sth->finish(); return (); }
  my $rows_loaded = $result->{"ROWS_LOADED_SO_FAR"};
  my $total_rows_to_load = $result->{"TOTAL_ROWS_TO_LOAD"};
  my $completed = $result->{"COMPLETED"};
  return ($rows_loaded,$total_rows_to_load,$completed);
}

sub show_upload_status ($) {
  my $dbh = &DatabaseInteraction::dbconnect();
  my $timestamp = shift;
  my $url = $query->self_url;
  my @upload_information = &get_upload_information($dbh,$timestamp);


  # No information at all???
  if ($#upload_information == -1) {
    print $query->start_html(-title => "Data upload $timestamp",
			     -head => $query->meta({-http_equiv=>"refresh",
						    -content=>"2;URL=$url"})
			    );
    print $query->p("Data has not loaded yet,  please wait...");
    print $query->end_html;
    $dbh->disconnect();
    exit(0);
  }

  my ($rows_loaded,$total_rows_to_load,$completed) = @upload_information;

  # Incomplete???
  if (!$completed) {
    $dbh->disconnect();
    print $query->start_html(-title => "Data upload $timestamp",
			     -head => $query->meta({-http_equiv=>"refresh",
						    -content=>"2;URL=$url"})
			    );
    print $query->p("Still loading -- $rows_loaded rows (out of $total_rows_to_load) done so far...");
    print $query->end_html;
    $dbh->disconnect();
    exit(0);
  }

  # Complete!!!
  my @supporting_tables = &DatabaseInteraction::supporting_tables();
  print $query->start_html("Data upload $timestamp"),
	 $query->h1(uc "Data upload $timestamp");
  my $table;
  my $full_url = $query->url."?upload_id=$timestamp&full_display=FULL&table=";
  my $brief_url = $query->url."?upload_id=$timestamp&full_display=NO&table=";
  foreach $table (@supporting_tables) {
    print $query->h3($table);
    my $dud_lines = &dud_lines($dbh,$timestamp,$table,'NOT-FULL',"COUNT");
    my $distinct_duds = &dud_lines($dbh,$timestamp,$table,'NOT-FULL',"COUNT-DISTINCT");
    print $query->p($query->b($dud_lines)," incomplete lines out of ",
		    $query->b($rows_loaded)," (",
		    $query->b($distinct_duds)," from distinct keys). ");
    print $query->ul
      (
       $query->li($query->a({-href => $full_url . $table},
			    "full view of all references used in $timestamp")),
       $query->li($query->a({-href => $brief_url . $table},
			    "just look at the $distinct_duds distinct blanks from this table"))
      );
  }
#  map (&display_dud_fields($dbh,$timestamp,$_,$rows_loaded),
#			  @supporting_tables);
  print $query->p({-align => 'right'},
		   $query->a({-href=> $query->url},
			     "Back to the list of data uploads &gt;&gt;"));

  print  $query->end_html;
  $dbh->disconnect();
  exit(0);

}

sub display_dud_fields ($$$) {
  my $dbh = &DatabaseInteraction::dbconnect();
  my $timestamp = shift;
  my $table = shift;
  my $full_display = shift;
  my ($rows_loaded,$total_rows_to_load,$completed)
    = &get_upload_information($dbh,$timestamp);
  my $sth;
  my $result;
  my $start_point = $query->param('start') || 0;
  my $count = $query->param('count') || 40;
  my $search_term = $query->param('search_term') || '';
  die unless $start_point =~ /^\d+$/ and $count =~ /^\d+$/;
  
  # The word "dud" here means "database update data";  things
  # that are worthy of being updated,  either because they have
  # some blank / missing data,  or because the user has explicitly
  # requested it.
  my @dud_lines;  # what lines to display
  my $dud_lines;  # how many there are
  my $distinct_duds;  # how many different ones there are

  if ($search_term ne '') {
    $full_display = "FULL";
    @dud_lines = &lines_matching_search_condition ($dbh,$timestamp,$table,$search_term);
    $dud_lines = $#dud_lines + 1;
    $distinct_duds = $dud_lines;
  } else {
    @dud_lines = &dud_lines($dbh,$timestamp,$table,$full_display,0,$start_point,$count);
    $dud_lines = &dud_lines($dbh,$timestamp,$table,$full_display,"COUNT");
    $distinct_duds = &dud_lines($dbh,$timestamp,$table,$full_display,"COUNT-DISTINCT");
  }
  print $query->start_html($table);
  print $query->h1(uc $table);
  my $url = $query->url. "?upload_id=$timestamp&table=$table&full_display=$full_display&start=";
  my $previous_link = $url.($start_point > $count ? $start_point - $count : 0);
  my $previous = $start_point > 0 ?
    $query->a({-href=>$previous_link}," &lt;&lt; Previous ") :
      $query->span({-style=>'Color: grey;'}," &lt;&lt; Previous "); 
  my $next_link = $url. ($start_point + $count);
  my $next = $start_point + $count > $distinct_duds ? 
    $query->span({-style=>'Color: grey;'}," Next &gt&gt; ") :
      $query->a({-href=>$next_link}," Next &gt;&gt; ");
  my $count_information;
  if ($search_term ne "") {
    $count_information =
      $query->p("Displaying lines that mention: ",
		$query->b($search_term));
  } elsif ($full_display !~ /^FULL$/i) {
    $count_information = 
      $query->p($query->b($dud_lines)," incomplete lines out of ",
		$query->b($rows_loaded)," (",
		$query->b($distinct_duds), 
		" from distinct keys). ")
	.
	  $query->p("Displaying distinct entries ",
		    $query->b($start_point+1), " to ",
		    $query->b($start_point+$count > $distinct_duds ? 
			      $distinct_duds : $start_point + $count),
		    ".",
		    $previous,
		    " -- ",
		    $next
		    );
  } else {
    $count_information = 
      $query->p("Displaying rows ",
		$query->b($start_point+1), " to ",
		$query->b($start_point+$count > $distinct_duds ? 
			  $distinct_duds : $start_point + $count),
		" of ",
		$query->b($distinct_duds),
		" from upload $timestamp .",
		$previous,
		" -- ",
		$next);
  }
  my @search_form_parts = 
    ($query->start_form,
     $query->hidden(-name=>'upload_id', -value=>$timestamp),
     $query->hidden(-name=>'table', -value=>$table),
     $query->hidden(-name=>'full_display', -value=>$full_display),
     $query->i("Search: "),
     $query->textfield(-name=>'search_term'),
     $query->submit(-name=>'Go',-value=>"Go"),
     $query->end_form
     );
	
  my $dud;
  my @extension_fields = &DatabaseInteraction::fields_to_fill_in($table);
  my @view_support_fields = &DatabaseInteraction::helpful_fields_to_show($table);
  my @keyed_fields = &DatabaseInteraction::keyed_fields($table);


  my @keying_information = 
    (  $query->p("Table is keyed from: "),
       $query->ul(map ($query->li(&DatabaseInteraction::pretty_up_column_heading($_)),@keyed_fields))
    );

  print $query->start_table({-border => 1, -width => '100%'});
  print $query->Tr(
		   $query->td($query->small($count_information)),
		   $query->td($query->small(@keying_information)),
		   $query->td({-align=>'right'},$query->small(@search_form_parts))
		  );
  print $query->end_table();


  my $columns = join(",",@extension_fields,@view_support_fields);
  my $viewname = &DatabaseInteraction::view_name();
  print $query->start_table({-border => 2});
  print $query->Tr(map($query->th($query->small(&DatabaseInteraction::pretty_up_column_heading($_))),
		       @view_support_fields,@extension_fields));
  my (@keying_data,@valling_data);
  foreach $dud (@dud_lines) {
    my $sql = "select distinct $columns from $viewname where $dud";
    $sth = $dbh->prepare($sql);
    $sth->execute();
    $result = $sth->fetchrow_hashref();
    @valling_data = 
      map(defined $result->{uc $_} 
	  ? $query->td($query->input({-name => (uc $_), -size => 14,
				      -value => ($result->{uc $_})}))
	  : $query->td($query->input({-name => (uc $_), -size => 14})),
	  @extension_fields
		       );
    @keying_data = 
      map($query->td($query->input({-type => 'hidden',
				    -name => (uc $_),
				    -value => ($result->{uc $_})}),
		     $result->{uc $_}),@view_support_fields);
    print $query->start_form({-action => $query->url,
			      -method => 'POST'});
    print $query->input({-type => 'hidden',
			 -name => 'table',
			 -value => $table});
    print $query->input({-type => 'hidden',
			 -name => 'upload_id',
			 -value => $timestamp});
    print $query->input({-type => 'hidden',
			 -name => 'full_display',
			 -value => $full_display});
    print $query->input({-type => 'hidden',
			 -name => 'action',
			 -value => 'update-table'});
    print $query->Tr(@keying_data,@valling_data,
		    $query->td($query->input({-type => 'submit',
					      -value => 'update'})));
    print $query->end_form();

    $sth->finish();
  }
  print $query->end_table();
  print $query->p({-align => 'right'},
		   $query->a({-href=> $query->url."?upload_id=$timestamp"},
			     "Back to the data upload summary ".
			     "and list of tables &gt;&gt;"));

  if ($full_display =~ /^FULL$/) {
    my $new_url =
      $query->url."?upload_id=$timestamp&full_display=NO&table=$table";
    print $query->p({-align =>'right'},$query->a({-href=> $new_url},
						 "Just show blanks &gt;&gt;"));
  } else {
    my $new_url =
      $query->url."?upload_id=$timestamp&full_display=FULL&table=$table";
    print $query->p({-align =>'right'},$query->a({-href=> $new_url},
						 "Full view &gt;&gt;"));
  }
		  
  print $query->end_html();
  $dbh->disconnect();
  exit(0);
}


# I am hoping that there is one unique bill_date for an upload_id.
# Also I am hoping that you can't have two upload_ids for one bill_date.
# I could probably do something about this if I got really desperate. 
# (Actually, I am already;  performance problems have been killing me,
# which is why I am writing this function.)
my %cache = ();
sub get_bill_date_of_upload_id {
  my $dbh = shift;
  my $upload_id = shift;
  if (exists $cache{$upload_id}) { return $cache{$upload_id}; }
  my $viewname = &DatabaseInteraction::view_name();
  my $database_type = &DatabaseInteraction::dbtype();
  my $sql;
  if ($database_type eq 'oracle') {
    # totally nonstandard
    $sql = qq{
	      select bill_date 
	       from $viewname 
	      where substr(id,1,19) = '$upload_id'
	      and rownum = 1};
  } else {
    $sql = qq{select bill_date 
	       from $viewname 
	      where substr(id,1,19)='$upload_id'
	      limit 1};
  }
  my $sth = $dbh->prepare($sql);
  $sth->execute();
  my $result = $sth->fetchrow_hashref();
  my $bill_date = $result->{"BILL_DATE"};
  $cache{$upload_id} = $bill_date;
  return $bill_date;
}

sub lines_matching_search_condition {
  my $dbh = shift;
  my $upload_timestamp = shift;  # although I don't think I will use it.
  my $table = shift;
  my $search_term = shift;
  $search_term = $dbh->quote('%'.uc $search_term.'%');
  my $sql;

  my @fields_to_search =
    (&DatabaseInteraction::fields_to_fill_in($table),
     &DatabaseInteraction::helpful_fields_to_show($table),
     &DatabaseInteraction::keyed_fields($table));
  my $where_clause = 
    join("\n or ",map("(upper($_) like $search_term)",@fields_to_search));
  my @keyed_fields = &DatabaseInteraction::keyed_fields($table);
  my $keyed_fields = join(", ",@keyed_fields);
  my $table2 = &DatabaseInteraction::view_name();
  $sql = qq{
	    select distinct $keyed_fields
 	      from $table2
             where $where_clause };
  my $sth = $dbh->prepare($sql);
  my $result;
  my @results = ();
  $sth->execute();
  while ($result = $sth->fetchrow_hashref()) {
      @results = (@results,
		  join (" AND ",
			map("($_ = '".$result->{uc $_}."')",@keyed_fields)
		       )
		  );
    }
  $sth->finish();
  return @results;
}
  
sub dud_lines {
  # IDs of all the transactions that have nulls in them.
  # Actually,  it's not so much an ID as a clause one could put
  # in a query that would return a appropriate row that has a null in it.

  my $dbh = shift;
  my $upload_timestamp = shift;
  my $bill_date = &get_bill_date_of_upload_id($dbh,$upload_timestamp);
  my $table = shift;
  my $full_story = shift;
  my $just_count = shift;
  my $selection;
  my $offset = "";
  my $limits = "";
  my $ordering = "";
  my $database_type = &DatabaseInteraction::dbtype();
  my @keyed_fields = 
    &DatabaseInteraction::keyed_fields($table);
  if ($just_count =~ /COUNT-DISTINCT/i) {
    $selection = "COUNT(distinct ". join(",",@keyed_fields) . ") as duds";
  } elsif ($just_count =~ /COUNT/i) {
    $selection = "COUNT(". join(",",@keyed_fields) . ") as duds";
  } else {
    #$selection = "cast(substr(id,21) as int4) as duds";
    $selection = "distinct ".join(",",@keyed_fields);
    $offset = shift;
    $limits = shift;
    $offset = " OFFSET $offset " unless $database_type eq 'oracle';
    $limits = " LIMIT $limits " unless $database_type eq 'oracle';
    #$ordering = " ORDER BY duds ";
    $ordering = "";
  }

  my ($dud_lines_query,$dud_lines,$dud_lines_result,$dud_lines_sql);
  my $viewname = &DatabaseInteraction::view_name();
  my $nullity_clause = $full_story =~ /^FULL$/i ? "(1=1)" :
    &DatabaseInteraction::nullity_clause($table);
  if ($database_type ne 'oracle') {
    $dud_lines_sql =
      qq{
	 select $selection 
         from $viewname
	 where bill_date  = '$bill_date'
	 and ($nullity_clause)  $ordering $limits $offset
	};
  } else {
    $dud_lines_sql = "";
    if ($offset !~ /^\d+$/ and $limits !~ /^\d+$/) {
      # then there is no offset and no limit
      $dud_lines_sql = qq{select $selection from  $viewname
                            where ($nullity_clause)
                              and bill_date = '$bill_date'};
    } else {
      if ($offset =~ /^\d+$/ and $limits =~ /^\d+$/) {
	$offset = $offset + 1 ;
	$limits = $limits + $offset - 1;
      } elsif ($offset =~ /^\d+$/) {
	# can't happen, can it?
	$offset = $offset + 1;
	$limits = $offset + 10;
      } elsif ($limits =~ /^d+$/) {
	$offset = 1;
      } else {
	# this can not occur.
	die;
      }
      $dud_lines_sql =
	qq{
	   select $selection from
	   (  select $selection, rownum n from
	      ( select $selection from $viewname 
                      where ($nullity_clause) and bill_date = '$bill_date' )
	   )
	   where n between $offset and $limits
	  };
    }
  }

  $dud_lines_query = $dbh->prepare($dud_lines_sql);
  $dud_lines_query->execute();
  if ($just_count =~ /COUNT-DISTINCT|COUNT/i) {
    $dud_lines_result = $dud_lines_query->fetchrow_hashref();
    die unless defined $dud_lines_result;
    $dud_lines = $dud_lines_result->{"DUDS"};
    return $dud_lines;
  } else {
    my @results = ();
    while ($dud_lines_result = $dud_lines_query->fetchrow_hashref()) {
      @results = 
	(@results,
	 join (" AND ",
	       map("($_ = '".$dud_lines_result->{uc $_}."')",@keyed_fields)
	       )
	 );
      #@results = (@results,$dud_lines_result);
      #$upload_timestamp.",".$dud_lines_result->{"DUDS"});
    }
    $dud_lines_query->finish();
    return @results;
  }
}
    


sub update_supporting_table {
 my $dbh = &DatabaseInteraction::dbconnect();
 my $upload_id = shift;
 my $table = shift;
 my $full_display = shift;
 my @keyed_fields = &DatabaseInteraction::keyed_fields($table);
 my @extension_fields = &DatabaseInteraction::fields_to_fill_in($table);
 my $viewname = &DatabaseInteraction::view_name();

 # make sure that everything is there, and build the SQL statements
 # along the way
 my @where_clause = ();
 my @insert_names_clause = ();
 my @insert_values_clause = ();
 my @update_values_clause = ();
 
 my $argument;
 my $value;
 foreach $argument (@keyed_fields) {
   $value = $query->param($argument) || $query->param(uc $argument) 
     || $query->param(lc $argument)  || '';
   $value = $dbh->quote($value);
   @where_clause = (@where_clause,"( $argument = $value )");
   @insert_names_clause = (@insert_names_clause,$argument);
   @insert_values_clause = (@insert_values_clause,$value);
 }
 foreach $argument (@extension_fields) {
   $value = $query->param($argument) || $query->param(uc $argument) 
     || $query->param(lc $argument)  || '';
   $value = $dbh->quote($value);
   @insert_names_clause = (@insert_names_clause,$argument);
   @insert_values_clause = (@insert_values_clause,$value);
   @update_values_clause = (@update_values_clause,"$argument=$value");
 }

 # first we find out whether or not it exists already.  This
 # uses the where_clause,  which doesn't involve any extension_fields
 my $check_for_existance = "select count(*) as NUMERO from $table WHERE" .
   join(" AND ",@where_clause);
 my $sth = $dbh->prepare($check_for_existance);
 $sth->execute();
 my $result = $sth->fetchrow_hashref();
 my $count = $result->{"NUMERO"};
 $sth->finish();

 # where will we go next?
 my $url =  $query->url. "?upload_id=$upload_id&table=$table&full_display=$full_display";

 if ($count == 0) {
   # then we need to do an insert
   my $insert_statement = 
     "insert into $table (".join(",",@insert_names_clause).") values (".
       join(",",@insert_values_clause). ")";
   my $rows = $dbh->do($insert_statement);
   die $dbh->errstr unless $rows == 1;
   print $query->start_html(-title => "Inserted data",
			    -head => $query->meta({-http_equiv=>"refresh",
						  -content=>"0;URL=$url"})
			   );
   print $query->p("Data has been inserted...");
   print $query->end_html;
   $dbh->disconnect();
   exit(0);
 } elsif ($count == 1) {
   # we need to do an update
   my $update_statement = 
     "update $table set ".join(",",@update_values_clause)." where (".
       join(",",@where_clause). ")";
   my $rows = $dbh->do($update_statement);
   die $dbh->errstr unless $rows == 1;
   print $query->start_html(-title => "Updated data",
			    -head => $query->meta({-http_equiv=>"refresh",
						  -content=>"0;URL=$url"})
			   );
   print $query->p("Data has been updated...");
   print $query->end_html;
   $dbh->disconnect();
   exit(0);

 } else {
   # Oh dear.  What does this mean?
    print $query->start_html("Problem updating table $tablename");
    print $query->h1(uc "Problem updating table $tablename");
    print $query->p("I have encountered a condition that makes ",
		    "no sense to me.  You will want to get a ",
		    "database administrator solve it for me.",
		   " Please print this page out and give it to someone.");
    print $query->p("When I ran: ");
    print $query->pre($check_for_existance);
    print $query->p("I got back a result of `",
		    $query->b($count),
		    "'.  I was expecting either 0 or 1.");
    print $query->end_html();
    exit(0);
  }
 print $query->p("No wuzzas, mate.");
 print $query->end_html();

 
 print $query->start_html("Updating table $tablename");
 print $query->h1(uc "Updating table $tablename");
 print $query->p("No wuzzas, mate.");
 print $query->end_html();
 exit(0);
}
