package MIME::Parser;


=head1 NAME

MIME::Parser - split MIME mail into decoded components

I<B<WARNING: This code is in an evaluation phase until 1 August 1996.>
Depending on any comments/complaints received before this cutoff date, 
the interface B<may> change in a non-backwards-compatible manner.>


=head1 DESCRIPTION

Where it all begins.  This is how you'll parse MIME streams to
obtain MIME::Entity objects.


=head1 SYNOPSIS

    use MIME::Parser;
    
    # Create a new parser object:
    my $parser = new MIME::Parser;
    
    # Optional: set up parameters that will affect how it extracts 
    #   documents from the input stream:
    $parser->output_dir("$ENV{HOME}/mimemail");
    
    # Parse an input stream:
    $entity = $parser->read(\*STDIN) or die "couldn't parse MIME stream";
    
    # Congratulations: you now have a (possibly multipart) MIME entity!
    $entity->dump_skeleton;          # for debugging 


=head1 WARNINGS

The organization of the C<output_path()> code changed in version 1.11
of this module.  If you are upgrading from a previous version, and
you use inheritance to override the C<output_path()> method, please
take a moment to familiarize yourself with the new code.  Everything I<should>
still work, but ya never know...

New, untested binmode() calls were added in module version 1.11... 
if binmode() is I<not> a NOOP on your system, please pay careful attention 
to your output, and report I<any> anomalies.  
I<It is possible that "make test" will fail on such systems,> 
since some of the tests involve checking the sizes of the output files.
That doesn't necessarily indicate a problem.


=head1 PUBLIC INTERFACE

=over 4

=cut

#------------------------------------------------------------

require 5.001;         # sorry, but I need the new FileHandle:: methods!

use MIME::Head;
use MIME::Entity;
use MIME::Decoder;
BEGIN {
   require POSIX if ($] < 5.002);  # I dunno; supposedly, 5.001m needs this...
}
use FileHandle ();
				


#------------------------------
#
# Globals
#
#------------------------------

# The package version, both in 1.23 style *and* usable by MakeMaker:
$VERSION = undef;
( $VERSION ) = '$Revision: 1.14 $ ' =~ /\$Revision:\s+([^\s]+)/;

# How to catenate:
$CAT = '/bin/cat';

# Debug?
$DEBUG = 0;

# The CRLF sequence:
$CRLF = "\015\012";


#------------------------------------------------------------
#
# UTILITIES
#
#------------------------------------------------------------

#------------------------------------------------------------
# error -- private utility: register unhappiness
#------------------------------------------------------------
sub error { 
    warn "(line $.) @_";
    (wantarray ? () : undef);
}

#------------------------------------------------------------
# textlike -- private utility: does HEAD indicate a textlike document?
#------------------------------------------------------------
sub textlike {
    my $head = shift;
    my ($type, $subtype) = split('/', $head->mime_type);
    return (($type eq 'text') || ($type eq 'message'));
}


#------------------------------------------------------------
#
# PUBLIC INTERFACE
#
#------------------------------------------------------------

#------------------------------------------------------------
# new
#------------------------------------------------------------

=item new

Create a new parser object.  You can then set up various parameters
before doing the actual parsing:

    my $parser = new MIME::Parser;
    $parser->output_dir("/tmp");
    $parser->output_prefix("msg1");
    my $entity = $parser->read(\*STDIN);

=cut

sub new {
    my $class = shift;
    my $self = {};
    $self->{Dir} = '.';
    $self->{Prefix} = 'msg';
    $self->{FH} = undef;
    bless $self, $class;
}

#------------------------------------------------------------
# output_dir
#------------------------------------------------------------

=item output_dir [DIRECTORY]

Get/set the output directory for the parsing operation.
This is the directory where the extracted and decoded body parts will go.
The default is C<".">.

If C<DIRECTORY> I<is not> given, the current output directory is returned.
If C<DIRECTORY> I<is> given, the output directory is set to the new value,
and the previous value is returned.

=cut

sub output_dir {
    my ($self, $dir) = @_;

    if (@_ > 1) {     # arg given...
	$dir = '.' if (!defined($dir) || ($dir eq ''));   # coerce empty to "."
	$dir = '/.' if ($dir eq '/');   # coerce "/" so "$dir/$filename" works
	$dir =~ s|/$||;                 # be nice: get rid of any trailing "/"
	$self->{Dir} = $dir;
    }
    $self->{Dir};
}

#------------------------------------------------------------
# evil_name -- private: is recommended filename evil?
#------------------------------------------------------------
sub evil_name {
    my $name = shift;
    return 1 if (!defined($name) || ($name eq ''));
    return 1 if ($name =~ m|/|);                      # currently, '/' is evil
    return 1 if (($name eq '.') || ($name eq '..'));  # '.' and '..' are evil
    return 1 if ($name =~ /\x00-\x1f\x80-\xff/);      # non-ASCIIs are evil
    0;     # it's good!
}

#------------------------------------------------------------
# output_path_or_hook HEAD
#------------------------------------------------------------
# PRIVATE.  If an output_path_hook() function is installed by the user, 
# then that function is called.  Otherwise, the output_path()
# method (which does all the real work) is called.

sub output_path_or_hook {
    my $self = shift;

    # If there's an output path hook, just call it:
    if ($self->{OutputPathHook}) {
	return &{$self->{OutputPathHook}}($self, @_);
    }
    else {
	$self->output_path(@_);
    }
}

#------------------------------------------------------------
# output_path
#------------------------------------------------------------

=item output_path HEAD

I<Utility method.>
Given a MIME head for a file to be extracted, come up with a good
output pathname for the extracted file.

=over

=item *

You'll probably never need to invoke this method directly.
As of version 1.11, this method is provided so that your 
C<output_path_hook()> function (or your MIME::Parser subclass)
can have clean access to the original algorithm.  
B<This method no longer attempts to run the user hook function.>

=back

Normally, the "directory" portion of the returned path will be the 
C<output_dir()>, and the "filename" portion will be the recommended 
filename extracted from the MIME header (or some simple temporary file 
name, starting with the output_prefix(), if the header does not specify 
a filename).

If there I<is> a recommended filename, but it is judged to be evil 
(if it is empty, or if it contains "/"s or ".."s or non-ASCII
characters), then a warning is issued and the temporary file name
is used in its place.  I<This may be overly restrictive, so...>

B<NOTE: If you don't like the behavior of this function,> you 
can override it with your own routine.  See C<output_path_hook()>
for details.   If you want to be OOish about it, you could instead
define your own subclass of MIME::Parser and override it there:

     package MIME::MyParser;
     
     require 5.002;                # for SUPER
     use strict;
     use package MIME::Parser;
     
     @MIME::MyParser::ISA = ('MIME::Parser');
     
     sub output_path {
         my ($self, $head) = @_;
         
         # Your code here; FOR EXAMPLE...
         if (i_have_a_preference) {
	     return my_custom_path;
         }
	 else {                      # return the default path:
             return $self->SUPER::output_path($head);
         }
     }
     1;

I<Thanks to Laurent Amon for pointing out problems with the original
implementation, and for making some good suggestions.  Thanks also to
Achim Bohnet for pointing out that there should be a hookless, OO way of 
overriding the output_path.>

=cut

sub output_path {
    my ($self, $head) = @_;

    # Get the output filename:
    my $outname = $head->recommended_filename;
    if (defined($outname) && evil_name($outname)) {
	warn "Desired filename '$outname' is evil... I'm ignoring it\n";
	$outname = undef;
    }
    if (!defined($outname)) {      # evil or missing; make our OWN filename:
	++$G_output_path;
	$outname = ($self->output_prefix . "-$$-$G_output_path.doc");
    }
    
    # Compose the full path from the output directory and filename:
    my $outdir = $self->output_dir;
    $outdir = '.' if (!defined($outdir) || ($outdir eq ''));  # just to be safe
    return "$outdir/$outname";  
}

#------------------------------------------------------------
# output_path_hook
#------------------------------------------------------------

=item output_path_hook SUBREF

Install a different function to generate the output filename
for extracted message data.  Declare it like this:

    sub my_output_path_hook {
        my $parser = shift;   # this MIME::Parser
	my $head = shift;     # the MIME::Head for the current message

        # Your code here: it must return a path that can be 
        # open()ed for writing.  Remember that you can ask the
        # $parser about the output_dir, and you can ask the
        # $head about the recommended_filename!
    }

And install it immediately before parsing the input stream, like this:

    # Create a new parser object, and install my own output_path hook:
    my $parser = new MIME::Parser;
    $parser->output_path_hook(\&my_output_path_hook);
    
    # NOW we can parse an input stream:
    $entity = $parser->read(\*STDIN);

This method is intended for people who are squeamish about creating 
subclasses.  See the C<output_path()> documentation for a cleaner, 
OOish way to do this.

=cut

sub output_path_hook {
    my ($self, $subr) = @_;
    $self->{OutputPathHook} = $subr if (@_ > 1);
    $self->{OutputPathHook};
}

#------------------------------------------------------------
# output_prefix 
#------------------------------------------------------------

=item output_prefix [PREFIX]

Get/set the output prefix for the parsing operation.
This is a short string that all filenames for extracted and decoded 
body parts will begin with.  The default is F<"msg">.

If C<PREFIX> I<is not> given, the current output prefix is returned.
If C<PREFIX> I<is> given, the output directory is set to the new value,
and the previous value is returned.

=cut

sub output_prefix {
    my ($self, $prefix) = @_;
    $self->{Prefix} = $prefix if (@_ > 1);
    $self->{Prefix};
}

#------------------------------------------------------------
# parse_preamble -- dispose of a multipart message's preamble
#------------------------------------------------------------
# NOTES
#    The boundary is mandatory!
#
#    We watch out for illegal zero-part messages.
#
# RETURNS
#    What we ended on (DELIM), or undef for error.
#
sub parse_preamble {
    my ($self, $in, $inner_bound) = @_;

    # Get possible delimiters:
    my ($delim, $close) = ("--$inner_bound", "--$inner_bound--");

    # Parse preamble:
    $DEBUG and print STDERR "skip until\n\tdelim <$delim>\n\tclose <$close>\n";
    while (<$in>) {
	s/\r?\n$//o;        # chomps both \r and \r\n
	
	$DEBUG and print STDERR "preamble: <$_>\n";
	($_ eq $delim) and return 'DELIM';
	($_ eq $close) and return error "multipart message has no parts";
    }
    error "unexpected eof in preamble" if eof($in);
}

#------------------------------------------------------------
# parse_epilogue -- dispose of a multipart message's epilogue
#------------------------------------------------------------
# NOTES
#    The boundary in this case is optional; it is only defined if
#    the multipart message we are parsing is itself part of 
#    an outer multipart message.
#
# RETURNS
#    What we ended on (DELIM, CLOSE, EOF), or undef for error.
#
sub parse_epilogue {
    my ($self, $in, $outer_bound) = @_;

    # If there's a boundary, get possible delimiters (for efficiency):
    my ($delim, $close) = ("--$outer_bound", "--$outer_bound--") 
	if defined($outer_bound);

    # Parse epilogue:
    $DEBUG and print STDERR "skip until\n\tdelim <$delim>\n\tclose <$close>\n";
    while (<$in>) {
	s/\r?\n$//o;        # chomps both \r and \r\n

	$DEBUG and print STDERR "epilogue: <$_>\n";
	if (defined($outer_bound)) {    # if there's a boundary, look for it:
	    ($_ eq $delim) and return 'DELIM';
	    ($_ eq $close) and return 'CLOSE';
	}
    }
    return 'EOF';       # the only way to get here!
}

#------------------------------------------------------------
# parse_to_bound -- parse up to (and including) the boundary, and dump output
#------------------------------------------------------------
# NOTES
#    Follows the RFC-1521 specification, that the CRLF
#    immediately preceding the boundary is part of the boundary,
#    NOT part of the input!
#
# RETURNS
#    'DELIM' or 'CLOSE' on success (to indicate the type of boundary
#    encountered, and undef on failure.
#
sub parse_to_bound {
    my ($self, $bound, $in, $out) = @_;    
    my $eol;                 # EOL sequence of current line
    my $held_eol = '';       # EOL sequence of previous line

    # Set up strings for faster checking:
    my $delim = "--$bound";
    my $close = "--$bound--";

    # Read:
    while (<$in>) {

	# Complicated chomp, to REMOVE AND REMEMBER end-of-line sequence:
	($eol) = ($_ =~ m/($CRLF|\n)$/o);
	if ($eol eq $CRLF) { chop; chop } else { chop };
	
	# Now, look at what we've got:
	($_ eq $delim) and return 'DELIM';   # done!
	($_ eq $close) and return 'CLOSE';   # done!
	print $out $held_eol, $_;            # print EOL from *last* line
	$held_eol = $eol;                    # hold EOL from *this* line
    }

    # Yow!
    return error "unexpected EOF while waiting for $bound !";
}


#------------------------------------------------------------
# parse_part -- the real back-end engine
#------------------------------------------------------------
# DESCRIPTION
#    See the documentation up top for the overview of the algorithm.
#
# RETURNS
#    The array ($entity, $state), or the empty array to indicate failure.
#    The following states are legal:
#
#        "EOF"   -- stopped on end of file
#        "DELIM" -- stopped on "--boundary"
#        "CLOSE" -- stopped on "--boundary--"
#         undef  -- stopped on error
#
sub parse_part {
    my ($self, $in, $outer_bound) = @_;
    my $state = 'OK';

    # Create a new entity:
    my $entity = MIME::Entity->new;

    # Parse and save the (possibly empty) header, up to and including the
    #    blank line that terminates it:
    my $head = MIME::Head->read($in);
    $head or return error "couldn't parse head!";
    $entity->head($head);

    # Handle, according to the MIME type:
    my ($type, $subtype) = split('/', $head->mime_type);
    if ($type eq 'multipart') {   # a multi-part MIME stream...
	
	# Get the boundaries for the parts:
	my $inner_bound = $head->multipart_boundary;
	defined($inner_bound) or return error "no multipart boundary!";
	
	# Parse preamble:
	$DEBUG and print STDERR "preamble...\n";
	($state = $self->parse_preamble($in, $inner_bound))
	    or return ();
		    
	# Parse parts:	
	my $partno = 0;
	my $part;
	while (1) {
	    ++$partno;
	    $DEBUG and print STDERR "parsing part $partno...\n";

	    # Parse the next part:
	    ($part, $state) = $self->parse_part($in, $inner_bound)
		or return ();
	    ($state eq 'EOF') and return error "unexpected EOF before close";

	    # Add it to the entity:
	    $entity->add_part($part);
	    last if ($state eq 'CLOSE');        # done!
	}
	
	# Parse epilogue:
	$DEBUG and print STDERR "epilogue...\n";
	($state = $self->parse_epilogue($in, $outer_bound)) 
	    or return ();
    }
    else {                        # a single part MIME stream...
	$DEBUG and print STDERR "decoding single part...\n";

	# Get a content-decoder to decode this part's encoding:
	my $encoding = $head->mime_encoding || 'binary';
	my $decoder = new MIME::Decoder $encoding;
	if (!$decoder) {
	    warn "unrecognized encoding '$encoding': using 'binary'";
	    $decoder = new MIME::Decoder 'binary';
	}

	# Generate a good name for the body file:
	my $bodyfile = $self->output_path_or_hook($head);

	# Obtain a filehandle for reading the encoded information:
	#    We have two different approaches, based on whether or not we 
	#    have to content with boundaries.
	my $encoded;            # filehandle for encoded data
	if (defined($outer_bound)) {     # BOUNDARIES...

	    # Open a temp file to dump the encoded info to, and do so:
	    $encoded = FileHandle->new_tmpfile;
	    binmode($encoded);                # extract the part AS IS
	    $state = $self->parse_to_bound($outer_bound, $in, $encoded)
		or return ();
	    
	    # Flush and rewind it, so we can read it:
	    $encoded->flush;
	    $encoded->seek(0, 0);
	}
	else {                           # NO BOUNDARIES!
	    
	    # The rest of the MIME stream becomes our temp file!
	    $encoded = $in;
	    #                       # do NOT binmode()... might be a user FH!
	    $state = 'EOF';         # it will be, if we return okay
	}

	# Open the final-destination output file:
	open OUT, ">$bodyfile" or return error "$bodyfile not opened: $!";
	binmode OUT unless textlike($head);    # no binmode if text output!

	# Decode and save the body (using the decoder):
	my $decoded_ok = $decoder->decode($encoded, \*OUT);
	close OUT;
	$decoded_ok or return error "decoding failed";

	# Success!  Remember where we put stuff:
	$entity->body($bodyfile);
    }
    
    # Done (we hope!):
    return ($entity, $state);
}

#------------------------------------------------------------
# parse_two
#------------------------------------------------------------

=item parse_two HEADFILE BODYFILE

Convenience front-end onto C<read()>, intended for programs 
running under mail-handlers like B<deliver>, which splits the incoming
mail message into a header file and a body file.

Simply give this method the paths to the respective files.  
I<These must be pathnames:> Perl "open-able" expressions won't
work, since the pathnames are shell-quoted for safety.

B<WARNING:> it is assumed that, once the files are cat'ed together,
there will be a blank line separating the head part and the body part.

=cut

sub parse_two {
    my ($self, $headfile, $bodyfile) = @_;
    my @result;

    # Shell-quote the filenames:
    my $safe_headfile = shell_quote($headfile);
    my $safe_bodyfile = shell_quote($bodyfile);

    # Catenate the files, and open a stream on them:
    open(CAT, qq{$CAT $safe_headfile $safe_bodyfile |}) or
	return error("couldn't open $CAT pipe: $!");
    @result = $self->read(\*CAT);
    close (CAT);
    @result;
}

#------------------------------------------------------------
# read 
#------------------------------------------------------------

=item read FILEHANDLE

Takes a MIME-stream and splits it into its component entities,
each of which is decoded and placed in a separate file in the splitter's
output_dir().  

The stream should be given as a glob ref to a readable FILEHANDLE; 
e.g., C<\*STDIN>.

Returns a MIME::Entity, which may be a single entity, or an 
arbitrarily-nested multipart entity.  Returns undef on failure.

=cut

sub read {
    my ($self, $in) = @_;

    my ($entity) = $self->parse_part($in);
    $entity;
}

#------------------------------------------------------------
# shell_quote -- private utility: make string safe for shell
#------------------------------------------------------------
sub shell_quote {
    my $str = shift;
    $str =~ s/\$/\\\$/g;
    $str =~ s/\`/\\`/g;
    $str =~ s/\"/\\"/g;
    return "\"$str\"";        # wrap in double-quotes
}


#------------------------------------------------------------

=back


=head1 UNDER THE HOOD

RFC-1521 gives us the following BNF grammar for the body of a
multipart MIME message:

      multipart-body  := preamble 1*encapsulation close-delimiter epilogue

      encapsulation   := delimiter body-part CRLF

      delimiter       := "--" boundary CRLF 
                                   ; taken from Content-Type field.
                                   ; There must be no space between "--" 
                                   ; and boundary.

      close-delimiter := "--" boundary "--" CRLF 
                                   ; Again, no space by "--"

      preamble        := discard-text   
                                   ; to be ignored upon receipt.

      epilogue        := discard-text   
                                   ; to be ignored upon receipt.

      discard-text    := *(*text CRLF)

      body-part       := <"message" as defined in RFC 822, with all 
                          header fields optional, and with the specified 
                          delimiter not occurring anywhere in the message 
                          body, either on a line by itself or as a substring 
                          anywhere.  Note that the semantics of a part 
                          differ from the semantics of a message, as 
                          described in the text.>

From this we glean the following algorithm for parsing a MIME stream:

    PROCEDURE parse
    INPUT
        A FILEHANDLE for the stream.
        An optional end-of-stream OUTER_BOUND (for a nested multipart message).
    
    RETURNS
        The (possibly-multipart) ENTITY that was parsed.
        A STATE indicating how we left things: "END" or "ERROR".
    
    BEGIN   
        LET OUTER_DELIM = "--OUTER_BOUND".
        LET OUTER_CLOSE = "--OUTER_BOUND--".
    
        LET ENTITY = a new MIME entity object.
        LET STATE  = "OK".
    
        Parse the (possibly empty) header, up to and including the
        blank line that terminates it.   Store it in the ENTITY.
    
        IF the MIME type is "multipart":
            LET INNER_BOUND = get multipart "boundary" from header.
            LET INNER_DELIM = "--INNER_BOUND".
            LET INNER_CLOSE = "--INNER_BOUND--".
    
            Parse preamble:
                REPEAT:
                    Read (and discard) next line
                UNTIL (line is INNER_DELIM) OR we hit EOF (error).
    
            Parse parts:
                REPEAT:
                    LET (PART, STATE) = parse(FILEHANDLE, INNER_BOUND).
                    Add PART to ENTITY.
                UNTIL (STATE != "DELIM").
    
            Parse epilogue:
                REPEAT (to parse epilogue): 
                    Read (and discard) next line
                UNTIL (line is OUTER_DELIM or OUTER_CLOSE) OR we hit EOF
                LET STATE = "EOF", "DELIM", or "CLOSE" accordingly.
     
        ELSE (if the MIME type is not "multipart"):
            Open output destination (e.g., a file)
    
            DO:
                Read, decode, and output data from FILEHANDLE
            UNTIL (line is OUTER_DELIM or OUTER_CLOSE) OR we hit EOF.
            LET STATE = "EOF", "DELIM", or "CLOSE" accordingly.
    
        ENDIF
    
        RETURN (ENTITY, STATE).
    END

For reasons discussed in MIME::Entity, we can't just discard the 
"discard text": some mailers actually put data in the preamble.


=head1 QUESTIONABLE PRACTICES

=over 4

=item Multipart messages are always read line-by-line 

Multipart document parts are read line-by-line, so that the
encapsulation boundaries may easily be detected.  However, bad MIME
composition agents (for example, naive CGI scripts) might return
multipart documents where the parts are, say, unencoded bitmap
files... and, consequently, where such "lines" might be 
veeeeeeeeery long indeed.

A better solution for this case would be to set up some form of 
state machine for input processing.  This will be left for future versions.

=item Multipart parts read into temp files before decoding

In my original implementation, the MIME::Decoder classes had to be aware
of encapsulation boundaries in multipart MIME documents.
While this decode-while-parsing approach obviated the need for 
temporary files, it resulted in inflexible and complex decoder
implementations.

The revised implementation uses temporary files (a la C<tmpfile()>)
to hold the encoded portions of MIME documents.  Such files are deleted
automatically after decoding is done, and no more
than one such file is opened at a time, so you should never need to 
worry about them.

=item Fuzzing of CRLF and newline on input

RFC-1521 dictates that MIME streams have lines terminated by CRLF
(C<"\r\n">).  However, it is extremely likely that folks will want to 
parse MIME streams where each line ends in the local newline 
character C<"\n"> instead. 

An attempt has been made to allow the parser to handle both CRLF 
and newline-terminated input.

=item Fuzzing of CRLF and newline on output

The C<"7bit"> and C<"8bit"> decoders will decode both
a C<"\n"> and a C<"\r\n"> end-of-line sequence into a C<"\n">.

The C<"binary"> decoder (default if no encoding specified) 
still outputs stuff verbatim... so a MIME message with CRLFs 
and no explicit encoding will be output as a text file 
that, on many systems, will have an annoying ^M at the end of
each line... I<but this is as it should be>.

=back

=head1 CALL FOR TESTERS

If anyone wants to test out this package's handling of both binary
and textual email on a system where binmode() is not a NOOP, I would be 
most grateful.  If stuff breaks, send me the pieces (including the 
original email that broke it, and at the very least a description
of how the output was screwed up).

=head1 SEE ALSO

MIME::Decoder,
MIME::Entity,
MIME::Head, 
MIME::Parser.

=head1 AUTHOR

Copyright (c) 1996 by Eryq / eryq@rhine.gsfc.nasa.gov

All rights reserved.  This program is free software; you can redistribute 
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

$Revision: 1.14 $ $Date: 1996/07/06 05:28:29 $

=cut



#------------------------------------------------------------
# Execute simple test if run as a script...
#------------------------------------------------------------
{ 
  package main; no strict;
  $INC{'MIME/Head.pm'} = 1;
  eval join('',<main::DATA>) || die "$@ $main::DATA" unless caller();
}
1;           # end the module
__END__

BEGIN { unshift @INC, "./etc" }

use MIME::Parser;
use MIME::Entity;

$Counter = 0;

# simple_output_path -- sample hook function, for testing
sub simple_output_path {
    my ($parser, $head) = @_;

    # Get the output filename:
    ++$Counter;
    my $outname = "message-$Counter.dat";
    my $outdir = $parser->output_dir;
    "$outdir/$outname";  
}

$DIR = "./testout";
((-d $DIR) && (-w $DIR)) or die "no output directory $DIR";

my $parser = new MIME::Parser;
$parser->output_dir($DIR);

# Uncomment me to see path hooks in action...
# $parser->output_path_hook(\&simple_output_path);

print "* Waiting for a MIME message from STDIN...\n";
my $entity = $parser->read(\*STDIN);
$entity or die "parse failed";

print "=" x 60, "\n";
$entity->dump_skeleton;
print "=" x 60, "\n\n";


#------------------------------------------------------------
1;

