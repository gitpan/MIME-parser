package MIME::Head;


=head1 NAME

MIME::Head - MIME message header

I<B<WARNING: This code is in an evaluation phase until 1 August 1996.>
Depending on any comments/complaints received before this cutoff date, 
the interface B<may> change in a non-backwards-compatible manner.>


=head1 DESCRIPTION

A class for parsing in and manipulating RFC-822 message headers, with some 
methods geared towards standard (and not so standard) MIME fields as 
specified in RFC-1521, I<Multipurpose Internet Mail Extensions>.


=head1 SYNOPSIS

Start off by requiring or using this package:

    require MIME::Head;

You can create a MIME::Head object in a number of ways:

    # Create a new, empty header, and populate it manually:    
    $head = MIME::Head->new;
    $head->set('content-type', 'text/plain; charset=US-ASCII');
    $head->set('content-length', $len);
    
    # Create a new header by parsing in the STDIN stream:
    $head = MIME::Head->read(\*STDIN);
    
    # Create a new header by parsing in a file:
    $head = MIME::Head->from_file("/tmp/test.hdr");
    
    # Create a new header by running a program:
    $head = MIME::Head->from_file("cat a.hdr b.hdr |");

To get rid of all internal newlines in all fields:

    # Get rid of all internal newlines:
    $head->unfold();

To test whether a given field exists:

    # Was a "Subject:" given?
    if ($head->exists('subject')) {
        # yes, it does!
    }

To get the contents of that field as a string:

    # Is this a reply?
    $reply = 1 if ($head->get('Subject') =~ /^Re: /);

To set the contents of a field to a given string:

    # Is this a reply?
    $head->set('Content-type', 'text/html');

To extract parameters from certain structured fields, as a hash reference:

    # What's the MIME type?
    $params = $head->params('content-type');
    $mime_type = $$params{_};
    $char_set  = $$params{'charset'};
    $file_name = $$params{'name'};

To get certain commonly-used MIME information:

    # The content type (e.g., "text/html"):
    $mime_type     = $head->mime_type;
    
    # The content transfer encoding (e.g., "quoted-printable"):
    $mime_encoding = $head->mime_encoding;
    
    # The recommended filename (e.g., "choosy-moms-choose.gif"):
    $file_name     = $head->recommended_filename;
    
    # The boundary text, for multipart messages:
    $boundary      = $head->multipart_boundary;

=head1 PUBLIC INTERFACE

=cut

#------------------------------------------------------------



#------------------------------
#
# Globals...
#
#------------------------------

# The package version, both in 1.23 style *and* usable by MakeMaker:
$VERSION = undef;
( $VERSION ) = '$Revision: 1.16 $ ' =~ /\$Revision:\s+([^\s]+)/;


# Lifted from Mail::Internet...
# Pattern to match an RFC-822 field name:
#
#     field       =  field-name ":" [ field-body ] CRLF
#     field-name  =  1*<any CHAR, excluding CTLs, SPACE, and ":">
#     CHAR        =  <any ASCII character>        ; (  0-177,  0.-127.)
#     CTL         =  <any ASCII control           ; (  0- 37,  0.- 31.)
#
$FIELDNAME = '[^\x00-\x1f\x80-\xff :]+';

# Pattern to match parameter names (like fieldnames, but = not allowed):
$PARAMNAME = '[^\x00-\x1f\x80-\xff :=]+';

# Pattern to match an RFC-1521 token:
#
#      token      =  1*<any  (ASCII) CHAR except SPACE, CTLs, or tspecials>
#
$TSPECIAL = '()<>@,;:\</[]?="';
$TOKEN    = '[^ \x00-\x1f\x80-\xff' . "\Q$TSPECIAL\E" . ']+';

# How to handle a "From " line?  One of IGNORE, ERROR, or COERCE (default):
$FROM_PARSING = 'COERCE';

# Debug?
$DEBUG = 0;


#------------------------------------------------------------
# error -- private: register unhappiness
#------------------------------------------------------------
sub error { 
    warn @_; return (wantarray ? () : undef);
}



#------------------------------

=head2 Creation, input, and output

=over 4

=cut

#------------------------------

#------------------------------------------------------------
# new
#------------------------------------------------------------

=item new

I<Class method>. 
Creates a new header object, with no fields.

=cut

sub new {
    my $class = shift;
    my $new = {};
    $new->{Fields} = {};
    $new->{Orig} = '';        # original text
    bless $new, $class;
}

#------------------------------------------------------------
# copy
#------------------------------------------------------------
sub copy {
    my $self = shift;
    my %copyhash = %$self;
    my $copy = \%copyhash;
    bless $copy, ref($self);
}

#------------------------------------------------------------
# from_file
#------------------------------------------------------------

=item from_file EXPR

I<Class or instance method>.
For convenience, you can use this to parse a header object in from EXPR, 
which may actually be any expression that can be sent to open() so as to 
return a readable filehandle.  The "file" will be opened, read, and then 
closed:

    # Create a new header by parsing in a file:
    my $head = MIME::Head->from_file("/tmp/test.hdr");

Since this method can function as either a class constructor I<or> 
an instance initializer, the above is exactly equivalent to:

    # Create a new header by parsing in a file:
    my $head = MIME::Head->new->from_file("/tmp/test.hdr");

On success, the object will be returned; on failure, the undefined value.

This is really just a convenience front-end onto C<read()>.

=cut

sub from_file {
    my ($self, $file) = @_;      # at this point, $self is instance or class!

    # Parse:
    open(HDR, $file) or return error("open $file: $!");
    $self = $self->read(\*HDR);      # after this, $self is instance!
    close(HDR);
    $self;           
}

#------------------------------------------------------------
# print
#------------------------------------------------------------

=item print FILEHANDLE

Output to the given FILEHANDLE, or to the currently-selected 
filehandle if none was given:

    # Output to STDOUT:
    $head->print(\*STDOUT);

B<WARNING:> this method does not output the blank line that terminates
the header in a legal message (since you may not always want it).

=cut

sub print {
    my ($self, $fh) = @_;
    $fh or $fh = select;         # make sure we've got one

    # Output:
    my $field;
    foreach $field (sort keys %{$self->{Fields}}) {
	my $value;
	foreach $value (@{$self->{Fields}{$field}}) {
	    print $fh "\u$field: $value\n";
	}
    }
    1;
}

#------------------------------------------------------------
# read
#------------------------------------------------------------

=item read FILEHANDLE

I<Class or instance method>.
This constructs a header object by reading it in from a FILEHANDLE,
until either a blank line or an end-of-stream is encountered.  
A syntax error will also halt processing.

Supply this routine with a reference to a filehandle glob;
e.g., C<\*STDIN>:

    # Create a new header by parsing in STDIN:
    my $head = MIME::Head->read(\*STDIN);

Since this method can function as either a class constructor I<or> 
an instance initializer, the above is exactly equivalent to:

    # Create a new header by parsing in STDIN:
    my $head = MIME::Head->new->read(\*STDIN);

Except that you should probably use the first form.
On success, the object will be returned; on failure, the undefined value.

=cut

sub read {
    my ($self, $fh) = @_;      # at this point, $self is instance or class!
    my ($lastparam, $value);

    # If invoked as a class method, create a new object and adjust $self so
    #  that we behave like an instance method sent to a brand new instance:
    ref($self) or $self = $self->new;
    
    # Parse:
    while (<$fh>) {
	$self->{Orig} .= $_;           # save original text
	s/\r?\n$//;                    # more robust than chomp
	$DEBUG and print STDERR "hdr: <$_>\n";
	last if ($_ eq '');     # done if line is empty

	if (/^From /) {                      # special "From " line:
	    if ($FROM_PARSING eq 'COERCE') {
		$self->add(($lastparam = 'mail-from'), $_);
	    }
	    elsif ($FROM_PARSING eq 'IGNORE') {
		next;
	    }
	    else {
		return error "unadorned 'From ' refused: <$_>";
	    }
	}
	elsif (/^($FIELDNAME): /o) {         # first line of a field
	    $self->add(($lastparam = lc($1)), $');
	}
	elsif (/^\s/) {                      # continuation line of a field
	    $self->add_text($lastparam, "\n$&$'");
	}
	else {                               # garbage: stop:
	    return error "bad email header line: <$_>";
	}
    }
    $self;     # done!
}



#------------------------------

=back

=head2 Getting/setting fields

B<NOTE:> this interface is not as extensive as that of MIME::Internet;
however, I have provided a set of methods that I can guarantee are 
supportable across any changes to the internal implementation of this
class.

=over 4

=cut

#------------------------------


#------------------------------------------------------------
# add
#------------------------------------------------------------

=item add FIELD,TEXT,[WHERE]

Add a new occurence of the FIELD, given by TEXT:

    # Add the trace information:    
    $head->add('Received', 'from eryq.pr.mcs.net by gonzo.net with smtp');

The FIELD is automatically coerced to lowercase.
Returns the TEXT.

Normally, the new occurence will be I<appended> to the existing 
occurences.  However, if the optional WHERE argument is the 
string C<"BEFORE">, then the new occurence will be I<prepended>.
B<NOTE:> if you want to be I<explicit> about appending, use the
string C<"AFTER"> for this argument.

B<WARNING>: this method always adds new occurences; it doesn't overwrite
any existing occurences... so if you just want to I<change> the value
of a field (creating it if necessary), then you probably B<don't> want to use 
this method: consider using C<set()> instead.

=cut

sub add {
    my ($self, $field, $text, $where) = @_;
    $field = lc($field);       # coerce to lowercase
    defined($text)  or ($text = '');
    defined($where) or ($where = 'AFTER');

    # Assert existence of field:
    $self->{Fields}{$field} or $self->{Fields}{$field} = [];

    # Add the new occurence:
    if ($where eq 'BEFORE') {     # prepend:
	unshift @{$self->{Fields}{$field}}, $text;
    }
    else {                        # append:
	push    @{$self->{Fields}{$field}}, $text;
    }
    $text;                 # return the text
}

#------------------------------------------------------------
# add_text
#------------------------------------------------------------

=item add_text FIELD,TEXT

Add some more text to the [last occurence of the] field:

    # Force an explicit character set:
    if ($head->get('Content-type') !~ /\bcharset=/) {
        $head->add_text('Content-type', '; charset="us-ascii"');
    }

The FIELD is automatically coerced to lowercase.

B<WARNING: be careful if adding text that contains a newline!>
A newline in a field value I<must> be followed by a single space 
or tab to be a valid continuation line!  

I had considered building this routine so that it "fixed" bare
newlines for you, but then I decided against it, since the behind-the-scenes
trickery would probably create more problems through confusion.  
So, instead, you've just been warned... proceed with caution.

=cut

sub add_text {
    my ($self, $field, $text) = @_;
    $field = lc($field);       # coerce to lowercase
    
    # Assert existence of field, with at least one occurence:
    $self->{Fields}{$field} or $self->{Fields}{$field} = [''];

    # Add the text to the last occurence:
    $self->{Fields}{$field}[-1] .= $text;
}

#------------------------------------------------------------
# delete
#------------------------------------------------------------

=item delete FIELD

Delete all occurences of the given field.

    # Remove all the MIME information:
    $head->delete('MIME-Version');
    $head->delete('Content-type');
    $head->delete('Content-transfer-encoding');
    $head->delete('Content-disposition');

Currently returns 1 always.

=cut

sub delete {
    my ($self, $field) = @_;

    delete $self->{Fields}{lc($field)};
    1;
}

#------------------------------------------------------------
# exists
#------------------------------------------------------------

=item exists FIELD

Returns whether a given field exists:

    # Was a "Subject:" given?
    if ($head->exists('subject')) {
        # yes, it does!
    }

The FIELD is automatically coerced to lowercase.
This method returns the undefined value if the field doesn't exist,
and some true value if it does.

=cut

sub exists {
    my ($self, $field) = @_;

    $self->{Fields}{lc($field)};
}

#------------------------------------------------------------
# fields
#------------------------------------------------------------

=item fields

Return a list of all fields (in no particular order):

    foreach $field (sort $head->fields) {
        print "$field: ", $head->get($field), "\n";
    }

=cut

sub fields {
    my $self = shift;

    keys %{$self->{Fields}};
}

#------------------------------------------------------------
# get
#------------------------------------------------------------

=item get FIELD,[OCCUR]

Returns the text of the [first occurence of the] field, or the 
empty string if the field is not present (nice for avoiding those 
"undefined value" warnings):

    # Is this a reply?
    $is_reply = 1 if ($head->get('Subject') =~ /^Re: /);

B<NOTE:> this returns the I<first> occurence of the field, so as to be
consistent with Mail::Internet::get().  However, if the optional OCCUR 
argument is defined, it specifies the index of the occurence you want: 
B<zero> for the first, and B<-1> for the last.

    # Print the first 'Received:' entry:
    print "Most recent: ", $head->get('received'), "\n";
    
    # Print the first 'Received:' entry, explicitly:
    print "Most recent: ", $head->get('received', 0), "\n";
    
    # Print the last 'Received:' entry:
    print "Least recent: ", $head->get('received', -1), "\n"; 

=cut

sub get {
    my ($self, $field, $occur) = @_;
    $field = lc($field);
    defined($occur) or $occur = 0;

    $self->exists($field) or return '';          # empty if doesn't exist
    my $text = $self->{Fields}{$field}[$occur];  # get contents
    defined($text) ? $text : '';
}

#------------------------------------------------------------
# get_all
#------------------------------------------------------------

=item get_all FIELD

Returns the list of I<all> occurences of the field, or the 
empty list if the field is not present:

    # How did it get here?
    @history = $head->get_all('Received');

B<NOTE:> I had originally experimented with having C<get()> return all 
occurences when invoked in an array context... but that causes a lot of 
accidents when you get careless and do stuff like this:

    print "\u$field: ", $head->get($field), "\n";

It also made the intuitive behaviour unclear if the OCCUR argument 
was given in an array context.  So I opted for an explicit approach
to asking for all occurences.

=cut

sub get_all {
    my ($self, $field) = @_;

    $self->exists($field) or return ();          # empty if doesn't exist
    @{$self->{Fields}{$field}};
}

#------------------------------------------------------------
# original_text
#------------------------------------------------------------

=item original_text

Recover the original text that was read() in to create this object:

    print "PARSED FROM:\n", $head->original_text;    

=cut
    
sub original_text {
    $_[0]->{Orig};
}

#------------------------------------------------------------
# set
#------------------------------------------------------------

=item set FIELD,TEXT

Set the field to [the single occurence given by] the TEXT:

    # Set the MIME type:
    $head->set('content-type', 'text/html');
    
The FIELD is automatically coerced to lowercase.
This method returns the text.

=cut

sub set {
    my ($self, $field, $text) = @_;
    $field = lc($field);       # coerce to lowercase
    
    # Create new, single-occurence field:
    $self->{Fields}{$field} = [$text];
    $text;                     # return the text of the occurence
}

#------------------------------------------------------------
# unfold
#------------------------------------------------------------

=item unfold [FIELD]

Unfold the text of all occurences of the given FIELD.  
If the FIELD is omitted, I<all> fields are unfolded.

"Unfolding" is the act of removing all newlines.

    $head->unfold;

Currently, returns 1 always.

=cut

sub unfold {
    my ($self, $field) = @_;
    
    # One or all?
    if (defined($field)) {    # one field...
	$field = lc($field);	
	$self->{Fields}{$field} or return 1;   # nothing to do!	
	my $i;
	for ($i = 0; $i < int(@{$self->{Fields}{$field}}); $i++) {
	    $self->{Fields}{$field}[$i] =~ s/\r?\n//g;
	}       	
    }
    else {                    # all fields!
	foreach $field (keys %{$self->{Fields}}) {
	    defined($field) or next;     # just to be safe
	    $self->unfold($field);       # cheap and sleazy
	}	   	    
    }
    1;
}

#------------------------------------------------------------

=back

=head2 MIME-specific methods

All of the following methods extract information from the following 
structured fields:

    Content-type
    Content-transfer-encoding
    Content-disposition

Be aware that they do not just return the raw contents of those fields,
and in some cases they will fill in sensible (I hope) default values.
Use C<get()> if you need to grab and process the raw field text.

=over 4

=cut

#------------------------------------------------------------


#------------------------------------------------------------
# params
#------------------------------------------------------------

=item params FIELD

Extract parameter info from a structured field, and return
it as a hash reference.  For example, here is a field with parameters:

    Content-Type: Message/Partial;
        number=2; total=3;
        id="oc=jpbe0M2Yt4s@thumper.bellcore.com"

Here is how you'd extract them:

    $params = $head->params('content-type');
    if ($$params{_} eq 'message/partial') {
        $number = $$params{'number'};
        $total  = $$params{'total'};
        $id     = $$params{'id'};
    }

Like field names, parameter names are coerced to lowercase.
The special '_' parameter means the default parameter for the
field.

B<WARNING:> the syntax is a little different for each field
(content-type, content-disposition, etc.). I've attempted to come 
up with a nice, simple catch-all solution: it simply stops when
it can't match anything else.

=cut

sub params {
    my ($self, $field) = @_;

    my %params = ();
    my $param;

    # Get raw field, and unfold it:
    my $raw = $self->get($field);
    $raw =~ s/\n//g;

    # Extract special first parameter:
    $raw =~ m/\A\s*([^\s\;\x00-\x1f\x80-\xff]+)\s*/g or return {};    # nada!
    $params{_} = $1;

    # Extract subsequent parameters.
    # No, we can't just "split" on semicolons: they're legal in quoted strings!
    while (1) {                     # keep chopping away until done...
	$raw =~ m/\s*\;\s*/g or last;                  # skip leading separator
	$raw =~ m/($PARAMNAME)\s*=\s*/og or last;      # give up if not a param
	$param = lc($1);
	$DEBUG and print STDERR "  param name: $param\n";
	$raw =~ m/(\"([^\"]+)\")|($TOKEN)/g or last;   # give up if no value
	$params{$param} = defined($1) ? $2 : $3;
    }

    # Done:
    \%params;
}

#------------------------------------------------------------
# mime_encoding
#------------------------------------------------------------

=item mime_encoding

Try real hard to determine the content transfer encoding, 
which is returned as a non-empty string in all-lowercase.

If no encoding could be found, the empty string is returned.

=cut

sub mime_encoding {
    my $self = shift;

    my $params = $self->params('content-transfer-encoding');
    lc($$params{_} || '');
}

#------------------------------------------------------------
# mime_type 
#------------------------------------------------------------

=item mime_type

Try real hard to determine the content type, which is returned 
as C<"$type/$subtype"> in all-lowercase.

    ($type, $subtype) = split('/', $head->mime_type);

If I<both> the type I<and> the subtype are missing, the content-type defaults 
to C<"text/plain">, as per RFC-1521:

    Default RFC-822 messages are typed by this protocol as plain text in
    the US-ASCII character set, which can be explicitly specified as
    "Content-type: text/plain; charset=us-ascii".  If no Content-Type is
    specified, this default is assumed.  

If I<just> the subtype is missing (really a syntax error, but we'll 
tolerate it, since some mailers actually do this), then the subtype
defaults to C<"x-subtype-unknown">.
This may change in the future, since I don't know if this was a really 
horrible idea: unfortunately, there is no standard default subtype,
and even when a good default can be decided upon, I felt queasy about 
returning the erroneous C<"text"> as either the legal C<"text/plain">
or the still-illegal C<"text/">.

If the content type is present but can't be parsed at all (yow!), 
the empty string is returned.

=cut

sub mime_type {
    my $self = shift;
    my ($type, $subtype);

    # Get the raw value:
    my $params = $self->params('content-type');
    my $value = $$params{_} || 'text/plain';
    
    # Extract info:
    ($value =~ m|([A-Za-z0-9-_]+)(/([A-Za-z0-9-_]+))?|) or return '';
    ($type, $subtype) = (lc($1), lc($3 || 'x-subtype-unknown'));
    "$type/$subtype";
}

#------------------------------------------------------------
# multipart_boundary
#------------------------------------------------------------

=item multipart_boundary

If this is a header for a multipart message, return the 
"encapsulation boundary" used to separate the parts.  The boundary
is returned exactly as given in the C<Content-type:> field; that
is, the leading double-hyphen (C<-->) is I<not> prepended.

(Well, I<almost> exactly... from RFC-1521:

   (If a boundary appears to end with white space, the white space 
   must be presumed to have been added by a gateway, and must be deleted.)  

so we oblige and remove any trailing spaces.)

Returns undef (B<not> the empty string) if either the message is not
multipart, if there is no specified boundary, or if the boundary is
illegal (e.g., if it is empty after all trailing whitespace has been
removed).

=cut

sub multipart_boundary {
    my $self = shift;

    # Is this even a multipart message?
    my ($type) = split('/', $self->mime_type);
    $DEBUG and print STDERR "type = $type\n";
    return undef if ($type ne 'multipart');

    # Get the boundary:
    my $params = $self->params('content-type');
    return undef if (!defined($$params{'boundary'}));
    
    # Remove trailing spaces, and return:
    my $boundary = $$params{'boundary'};
    $boundary =~ s/\s+$//;
    (($boundary eq '') ? undef : $boundary);       # legal or not?
}

#------------------------------------------------------------
# recommended_filename
#------------------------------------------------------------

=item recommended_filename

Return the recommended external filename.  This is used when
extracting the data from the MIME stream.

Returns undef if no filename could be suggested.

=cut

sub recommended_filename {
    my $self = shift;

    # Start by trying to get 'filename' from the 'content-disposition':
    my $params = $self->params('content-disposition');
    return $$params{'filename'} if $$params{'filename'};

    # No?  Okay, try to get 'name' from the 'content-type':
    $params = $self->params('content-type');
    return $$params{'name'} if $$params{'name'};
    
    # Sorry:
    undef;
}



#------------------------------------------------------------

=back

=head2 Compatibility tweaks

=over 4

=cut

#------------------------------------------------------------
# tweak_FROM_parsing
#------------------------------------------------------------

=item tweak_FROM_parsing CHOICE

I<Class method.>
The parser may be tweaked so that any line in the header stream that 
begins with C<"From "> will be either B<ignored>, flagged as an 
B<error>, or B<coerced> into the special field C<"Mail-from:"> 
(the default; this approach was inspired by Emacs's "Babyl" format).
Though not valid for a MIME header, this will provide compatibility 
with some Unix mail messages. Just do this:

    MIME::Head->tweak_FROM_parsing($choice)

Where C<$choice> is one of C<'IGNORE'>, C<'ERROR'>, or C<'COERCE'>.

=cut

sub tweak_FROM_parsing {
    my $choice = uc(shift);
    $choice =~ /^(IGNORE|ERROR|COERCE)$/ 
	or die "bad FROM-parsing tweak: '$choice'";
    $FROM_PARSING = $choice;
}


#------------------------------------------------------------

=back

=head1 DESIGN ISSUES


=head2 Why have separate objects for the head and the entity?

See the documentation under MIME::Entity for the rationale behind
this decision.


=head2 Why assume that MIME headers are email headers?

I quote from Achim Bohnet, who gave feedback on v.1.9 (I think
he's using the word I<header> where I would use I<field>; e.g.,
to refer to "Subject:", "Content-type:", etc.):

    There is also IMHO no requirement [for] MIME::Heads to look 
    like [email] headers; so to speak, the MIME::Head [simply stores] 
    the attributes of a complex object, e.g.:

        new MIME::Head type => "text/plain",
                       charset => ...,
                       disposition => ..., ... ;

See the next question for an answer to this one.  

=head2 Why is MIME::Head so complex, and yet lacking in composition methods?

Sigh.

I have often wished that the original RFC-822 designers had taken
a different approach, and not given every other field its own special
grammar: read RFC-822 to see what I mean.  As I understand it, in Heaven,
all mail message headers have a very simple syntax that encodes
arbitrarily-nested objects; a consistent, generic representation for 
exchanging OO data structures.

But we live in an imperfect world, where there's nonsense like this
to put up with:

    From: Yakko Warner <yakko@tower.wb.com>
    Subject: Hello, nurse!
    Received: from gsfc.nasa.gov by eryq.pr.mcs.net  with smtp
        (Linux Smail3.1.28.1 #5) id m0tStZ7-0007X4C; Thu, 21 Dec 95 16:34 CST
    Received: from rhine.gsfc.nasa.gov by gsfc.nasa.gov (5.65/Ultrix3.0-C)
        id AA13596; Thu, 21 Dec 95 17:20:38 -0500
    Content-type: text/html; charset=US-ASCII; 
        name="nurse.html"

I quote from Achim Bohnet, who gave feedback on v.1.9 (I think
he's using the word I<header> where I would use I<field>; e.g.,
to refer to "Subject:", "Content-type:", etc.):

    MIME::Head is too big. A better approach IMHO would be to 
    have a general header class that knows about allowed characters, 
    line length, and some (formatting) output routines.  There 
    should be other classes that handle special headers and that 
    are aware of the semantics/syntax of [those] headers...

        From, to, reply-to, message-id, in-reply-to, x-face ...

    MIME::Head should only handle MIME specific headers.  

As he describes, each kind of field really merits its own small 
class (e.g, Mail::Field::Subject, Mail::Field::MessageId, Mail::Field::XFace,
etc.), each of which provides a from_field() method for parsing 
field data I<into> a class object, and a to_field() method for 
generating that field I<from> a class object.

I kind of like the elegance of this approach.  We could then
have a generic Mail::Head class, instances of which would consist 
simply of one or more instances of subclasses of a generic Mail::Field 
class.  Unrecognized fields would be represented as instances of Mail::Field 
by default.

There would be a MIME::Field class, with subclasses like
MIME::Field::ContentType that would allow us to get fields like this:

   $type    = $head->field('content-type')->type;
   $subtype = $head->field('content-type')->subtype;
   $charset = $head->field('content-type')->charset;

And set fields like this:

   $head->field('content-type')->type('text');
   $head->field('content-type')->subtype('html');
   $head->field('content-type')->charset('us-ascii');

And, with that same MIME::Head object, get at other fields, like:

   $subject     = $head->field('subject')->text;  # just the flat text
   $sender_name = $head->field('from')->name;     # e.g., Yakko Warner
   $sender_addr = $head->field('from')->addr;     # e.g., yakko@tower.wb.com

So why a special MIME::Head subclass of Mail::Head?  Why, to enable
us to add MIME-specific wrappers, like this:

   package MIME::Head;
   @ISA = qw(Mail::Head);
   
   sub recommended_filename {
       my $self = shift;
       my $try;
       
       # First, try to get it from the content-disposition:
       ($try = $self->field('content-disposition')->filename) and return $try;
       
       # Next, try to get it from the content-type:
       ($try = $self->field('content-type')->name) and return $try;
       
       # Give up:
       undef;
   }


=head2 Why all this "occurence" jazz?  Isn't every field unique?

Aaaaaaaaaahh....no.

Looking at a typical mail message header, it is sooooooo tempting to just
store the fields as a hash of strings, one string per hash entry.  
Unfortunately, there's the little matter of the C<Received:> field, 
which (unlike C<From:>, C<To:>, etc.) will often have multiple 
occurences; e.g.:

    Received: from gsfc.nasa.gov by eryq.pr.mcs.net  with smtp
        (Linux Smail3.1.28.1 #5) id m0tStZ7-0007X4C; Thu, 21 Dec 95 16:34 CST
    Received: from rhine.gsfc.nasa.gov by gsfc.nasa.gov (5.65/Ultrix3.0-C)
        id AA13596; Thu, 21 Dec 95 17:20:38 -0500
    Received: (from eryq@localhost) by rhine.gsfc.nasa.gov (8.6.12/8.6.12) 
        id RAA28069; Thu, 21 Dec 1995 17:27:54 -0500
    Date: Thu, 21 Dec 1995 17:27:54 -0500
    From: Eryq <eryq@rhine.gsfc.nasa.gov>
    Message-Id: <199512212227.RAA28069@rhine.gsfc.nasa.gov>
    To: eryq@eryq.pr.mcs.net
    Subject: Stuff and things

The C<Received:> field is used for tracing message routes, and although
it's not generally used for anything other than human debugging, I
didn't want to inconvenience anyone who actually wanted to get at that
information.  

I I<also> didn't want to make this a special case; after all, who
knows what B<other> fields could have multiple occurences in the
future?  So, clearly, multiple entries had to somehow be stored
multiple times... and the different occurences had to be retrievable.


=head1 SEE ALSO

MIME::Decoder,
MIME::Entity,
MIME::Head,
MIME::Parser.

=head1 AUTHOR

Copyright (c) 1996 by Eryq / eryq@rhine.gsfc.nasa.gov  

All rights reserved.  This program is free software; you can redistribute 
it and/or modify it under the same terms as Perl itself.

The more-comprehensive filename extraction is courtesy of 
Lee E. Brotzman, Advanced Data Solutions.

=head1 VERSION

$Revision: 1.16 $ $Date: 1996/06/19 04:04:35 $

=cut


#------------------------------------------------------------
# Execute simple test if run as a script.
#------------------------------------------------------------
{ 
  package main; no strict;
  $INC{'MIME/Head.pm'} = 1;
  eval join('',<main::DATA>) || die "$@ $main::DATA" unless caller();
}
1;           # end the module
__END__

# Pick up other MIME stuff, just in case...
BEGIN { unshift @INC, "./etc" }

my $head;
$^W = 1;

print "* Reading MIME header from STDIN...\n";
$head = MIME::Head->new->read(\*STDIN) or die "couldn't parse input";

print "* Listing all fields...\n";
print "    ", join(', ', sort $head->fields), "\n";

print "* Forcing content-type of 'text/plain' if none given...\n";
unless ($head->exists('content-type')) {
    $head->set('content-type', 'text/plain');
}

print "* Forcing US-ASCII charset if none given...\n";
unless ($head->get('content-type') =~ m/\bcharset=/) {
    $head->add_text('content-type', '; charset="US-ASCII"');
}

print "* Creating custom field 'X-Files'...\n";
$head->set('X-Files', 'default ; name="X Files Test"; length=60 ;setting="6"');

print "* Parameters of X-Files...\n";
my $params = $head->params('X-Files');
while (($key, $val) = each %$params) {
    print "    \u$key = <$val>\n" if defined($val);
}

print "* Adding two 'received' fields...\n";
$head->add('received', 'from kermit.net by gonzo.net with smtp');
$head->add('received', 'from gonzo.net by muppet.net with smtp');

print "\n* Printing original text to STDOUT...\n";
print '=' x 60, "\n";
print $head->original_text;
print '=' x 60, "\n\n";

print "\n* Dumping current header to STDOUT...\n";
print '=' x 60, "\n";
$head->print(\*STDOUT);
print '=' x 60, "\n\n";

print "\n* Unfolding and dumping again...\n";
$head->unfold;
print '=' x 60, "\n";
$head->print(\*STDOUT);
print '=' x 60, "\n\n";

# So we know everything went well...
exit 0;

#------------------------------------------------------------
1;
