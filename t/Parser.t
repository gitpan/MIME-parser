BEGIN { 
    push(@INC, "./blib/lib");
}
use MIME::Parser;
print STDERR "\n";

sub okay_if { print( ($_[0] ? "ok\n" : "not ok\n")) }
sub note    { print STDERR "\ttest ", @_, "\n" }

# simple_output_path -- sample hook function, for testing
sub simple_output_path {
    my ($parser, $head) = @_;

    # Get the recommended filename:
    my $filename = $head->recommended_filename;
    if (defined($filename) && MIME::Parser::evil_name($filename)) {
	warn "I'm ignoring an evil recommended filename ($filename)";
	$filename = undef;      # forget it: it was evil
    }
    if (!defined($filename)) {  # either no name or an evil name
	++$Counter;
	$filename = "message-$Counter.dat";
    }

    # Get the output filename:
    my $outdir = $parser->output_dir;
    "$outdir/$filename";
}

# Set the counter:
$Counter = 0;

# Check and clear the output directory:
$DIR = "./testout";
((-d $DIR) && (-w $DIR)) or die "no output directory $DIR";
unlink <$DIR/[a-z]*>;


#------------------------------------------------------------
# BEGIN
#------------------------------------------------------------
print "1..7\n";

#------------------------------------------------------------
note "1: read a nested multipart MIME message";
#------------------------------------------------------------
my $parser = new MIME::Parser;
$parser->output_dir($DIR);
$parser->output_path_hook(\&simple_output_path);
open IN, "./testin/multi-nested.msg" or die "open: $!";
my $entity = $parser->read(\*IN);
$entity or die "parse failed";
okay_if('here');

#------------------------------------------------------------
note "2-7: check the various output files";
#------------------------------------------------------------
okay_if(-s "$DIR/3d-vise.gif" == 419);
okay_if(-s "$DIR/3d-eye.gif" == 357);
okay_if(-s "$DIR/message-1.dat");
okay_if(-s "$DIR/message-2.dat");
okay_if(-s "$DIR/message-3.dat");
okay_if(-s "$DIR/message-4.dat");

# Done!
exit(0);
1;




