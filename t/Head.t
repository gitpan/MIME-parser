BEGIN { 
    push(@INC, "./blib/lib");
}
use MIME::Head;
print STDERR "\n";

sub okay_if { print( ($_[0] ? "ok\n" : "not ok\n")) }
sub note    { print STDERR "\ttest ", @_, "\n" }
my $head;


#------------------------------------------------------------
# BEGIN
#------------------------------------------------------------
print "1..11\n";


#------------------------------------------------------------
note "1: read a bogus file (this had better fail...)";
#------------------------------------------------------------
$head = MIME::Head->from_file('BLAHBLAH');
okay_if(!$head);

#------------------------------------------------------------
note "2: parse in the crlf.hdr file:";
#------------------------------------------------------------
($head = MIME::Head->from_file('./testin/crlf.hdr'))
    or die "couldn't parse input";  # stop now
okay_if('HERE');

#------------------------------------------------------------
note "3: did we get all the fields?";
#------------------------------------------------------------
my @actuals = qw(path
		 from
		 newsgroups
		 subject
		 date
		 organization
		 lines
		 mail-from
		 message-id
		 nntp-posting-host
		 mime-version
		 content-type
		 content-transfer-encoding
		 x-mailer
		 x-url
		 );
my $actual = join '|', sort @actuals;
my $parsed = join '|', sort($head->fields);
okay_if($parsed eq $actual);

#------------------------------------------------------------
note "4: could we get() the 'subject'?";
#------------------------------------------------------------
my $subject = $head->get('subject');
okay_if($subject eq 'EMPLOYMENT: CHICAGO, IL UNIX/CGI/WEB/DBASE');

#------------------------------------------------------------
note "5: could we set() the 'Subject', and get it as 'SUBJECT'?";
#------------------------------------------------------------
my $newsubject = 'Hellooooooo, nurse!';
$head->set('Subject', $newsubject);
$subject = $head->get('SUBJECT');
okay_if($subject eq $newsubject);

#------------------------------------------------------------
note "6: does the exists() method work?";
#------------------------------------------------------------
okay_if($head->exists('NNTP-Posting-Host') and
        $head->exists('nntp-POSTING-HOST') and
        !($head->exists('Doesnt-Exist')));

#------------------------------------------------------------
note "7-11: create a custom structured field, and extract parameters";
#------------------------------------------------------------
$head->set('X-Files', 'default ; name="X Files Test"; LENgth=60 ;setting="6"');
my $params = $head->params('X-Files');
okay_if($params);
okay_if($$params{_}         eq 'default');
okay_if($$params{'name'}    eq 'X Files Test');
okay_if($$params{'length'}  eq '60');
okay_if($$params{'setting'} eq '6');

# Done!
exit(0);
1;





