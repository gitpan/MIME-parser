package MIME::Decoder;


=head1 NAME

MIME::Decoder - an object for decoding the body part of a MIME stream

I<B<WARNING: This code is in an evaluation phase until 1 August 1996.>
Depending on any comments/complaints received before this cutoff date, 
the interface B<may> change in a non-backwards-compatible manner.>


=head1 DESCRIPTION

This abstract class, and its private concrete subclasses (see below)
provide an OO front end to the action of decoding a MIME-encoded
stream.  

The constructor for MIME::Decoder takes the name of an encoding
(C<base64>, C<7bit>, etc.), and returns an instance of a I<subclass>
of MIME::Decoder whose C<decode()> method will perform the appropriate
decoding action.  

You can even create your own subclasses and "install" them so that
MIME::Decoder will know about them, via the C<install()> method

Want to know if a given encoding is currently supported? 
Use the C<supported()> class method.


=head1 SYNOPSIS

Here's a simple filter program to read quoted-printable data from STDIN
and write the decoded data to STDOUT:

    #!/usr/bin/perl
    use MIME::Decoder;

    $encoding = 'quoted-printable';
    
    $decoder = new MIME::Decoder $encoding or die "$encoding unsupported";
    $decoder->decode(\*STDIN, \*STDOUT);

The decode() method will always eat up all input to the end of file.

=cut


# use FileHandle;
# use Carp;
# defined(&FileHandle::input_record_separator) or
#     croak "Ack! There's no &FileHandle::input_record_separator!;
				

#------------------------------------------------------------
#
# Globals
# 
#------------------------------------------------------------

# The stream decoders:
%DecoderFor = (
    '7bit'      => 'MIME::Decoder::Xbit',
    '8bit'      => 'MIME::Decoder::Xbit',
    'base64'    => 'MIME::Decoder::Base64',
    'binary'    => 'MIME::Decoder::Binary',
    'none'      => 'MIME::Decoder::Binary',
    'quoted-printable' => 'MIME::Decoder::QuotedPrint',
);


# The package version, both in 1.23 style *and* usable by MakeMaker:
$VERSION = undef;
( $VERSION ) = '$Revision: 1.9 $ ' =~ /\$Revision:\s+([^\s]+)/;




#------------------------------

=head1 PUBLIC INTERFACE

If all you are doing is I<using> this class, here's all you'll need...

=over 4

=cut

#------------------------------

#------------------------------------------------------------
# new 
#------------------------------------------------------------

=item new ENCODING

I<Class method>.
Create and return a new decoder object which can handle the 
given ENCODING.

    my $decoder = new MIME::Decoder "7bit";

Returns the undefined value if no known decoders are appropriate.

=cut

sub new {
    my ($class, $encoding) = @_;
    my $concrete;

    # Coerce the type to be legit:
    $encoding = lc($encoding || '');

    # Create the new object (if we can):
    ($concrete = $DecoderFor{$encoding}) or return undef;
    bless {}, $concrete;
}

#------------------------------------------------------------
# decode 
#------------------------------------------------------------

=item decode INSTREAM,OUTSTREAM

Decode the document waiting in the MIME input filehandle INSTREAM,
writing the decoded information to the output filehandle OUTSTREAM.

=cut

sub decode {
    my ($self, $in, $out) = @_;
    
    # Set up the default input record separator to be CRLF:
    # $in->input_record_separator("\012\015");
    
    # Do it!
    $self->decode_it($in, $out);   # invoke back-end method to do the work
}

#------------------------------------------------------------
# supported
#------------------------------------------------------------

=item supported [ENCODING]

I<Class method>.
With one arg (an ENCODING name), returns truth if that encoding
is currently handled, and falsity otherwise.  The ENCODING will
be automatically coerced to lowercase:

    if (MIME::Decoder->supported('7BIT')) {
        # yes, we can handle it...
    }
    else {
        # drop back six and punt...
    } 

With no args, returns all the available decoders as a hash reference... 
where the key is the encoding name (all lowercase, like '7bit'),
and the associated value is true (it happens to be the name of the class 
that handles the decoding, but you probably shouldn't rely on that).
Hence:

    my $supported = MIME::Decoder->supported;
    if ($supported->{7bit}) {
        # yes, we can handle it...
    }
    elsif ($supported->{8bit}) {
        # yes, we can handle it...
    }

You may safely modify this hash; it will I<not> change the way the 
module performs its lookups.  Only C<install> can do that.

I<Thanks to Achim Bohnet for suggesting this method.>

=cut

sub supported {
    my ($class, $decoder) = @_;
    
    if (defined($decoder)) {     # is this decoder available?
	return $DecoderFor{lc($decoder)};
    }
    else {                       # return 'em all!
	my %safecopy = %DecoderFor;
	return \%safecopy;
    }
}

#------------------------------

=back

=head1 SUBCLASS INTERFACE

If you are writing/installing a new decoder, here's some other stuff
you'll need:

=over 4

=cut

#------------------------------



#------------------------------------------------------------
# install 
#------------------------------------------------------------

=item install ENCODING

I<Class method>.
Install this class so that ENCODING is handled by it.

=cut

sub install {
    my ($class, $encoding) = shift;
    $DecoderFor{lc($encoding)} = $class;
}

#------------------------------------------------------------
# decode_it -- private: abstract internal decode method
#------------------------------------------------------------
sub decode_it {
    my $self = shift;
    die "attempted to use abstract 'decode_it' method!";
}



#------------------------------------------------------------

=back

=head1 PRIVATE BUILT-IN DECODERS

You don't need to C<"use"> any other Perl modules; the
following are included as part of MIME::Decoder.

=cut

#------------------------------------------------------------


# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

=head2 MIME::Decoder::Base64

The built-in decoder for the C<"base64"> encoding.

The name was chosen to jibe with the pre-existing MIME::Base64
utility package, which this class actually uses to translate each line.

=cut


package MIME::Decoder::Base64;
@ISA = qw(MIME::Decoder);

use MIME::Base64;

#------------------------------------------------------------
# decode_it
#------------------------------------------------------------
sub decode_it {
    my ($self, $in, $out) = @_;

    while (<$in>) {
	my $decoded = decode_base64($_);
	print $out $decoded;
    }
    1;
}



# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

=head2 MIME::Decoder::Binary

The built-in decoder for a C<"binary"> encoding (in other words,
no encoding).  

The C<"binary"> decoder is a special case, since it's ill-advised
to read the input line-by-line: after all, an uncompressed image file might
conceivably have loooooooooong stretches of bytes without a C<"\n"> among
them, and we don't want to risk blowing out our core.  So, we 
read-and-write fixed-size chunks.

=cut

package MIME::Decoder::Binary;
@ISA = qw(MIME::Decoder);

#------------------------------------------------------------
# decode_it
#------------------------------------------------------------
sub decode_it {
    my ($self, $in, $out) = @_;

    my $buf = '';         # read/write buffer
    my $nread;            # number of bytes read
    while ($nread = read($in, $buf, 4096)) {
	print $out $buf;
    }
    defined($nread) or return undef;      # check for error
    1;
}




# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = 

=head2 MIME::Decoder::QuotedPrint

The built-in decoder the for C<"quoted-printable"> encoding.

The name was chosen to jibe with the pre-existing MIME::QuotedPrint
utility package, which this class actually uses to translate each line.

=cut

package MIME::Decoder::QuotedPrint;
@ISA = qw(MIME::Decoder);

use MIME::QuotedPrint;

#------------------------------------------------------------
# decode_it
#------------------------------------------------------------
sub decode_it {
    my ($self, $in, $out) = @_;

    while (<$in>) {
	my $decoded = decode_qp($_);
	print $out $decoded;
    }
    1;
}




# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

=head2 MIME::Decoder::Xbit

The built-in decoder for both C<"7bit"> and C<"8bit"> encodings,
which guarantee short lines (a maximum of 1000 characters per line) 
of US-ASCII data compatible with RFC-821.

This decoder does a line-by-line pass-through from input 
to output, leaving the data unchanged I<except> that an
end-of-line sequence of CRLF is converted to a newline "\n".

=cut

package MIME::Decoder::Xbit;
@ISA = qw(MIME::Decoder);

#------------------------------------------------------------
# decode_it
#------------------------------------------------------------
sub decode_it {
    my ($self, $in, $out) = @_;
    
    while (<$in>) {
	s/\015\012$/\n/;
	print $out $_;
    }
    1;
}




# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

=head1 WRITING A DECODER

If you're experimenting with your own encodings, you'll probably want
to write a decoder.  Here are the basics:

=over 4

=item 1.

Create a module, like "MyDecoder::", for your decoder.
Declare it to be a subclass of MIME::Decoder.

=item 2.

Create the instance method C<MyDecoder::decode_it()>, as follows:

Your method should take as arguments 
the C<$self> object (natch),
a filehandle opened for input, called C<$in>, and
a filehandle opened for output, called C<$out>.

Your method should read from the input filehandle, decode this input, 
and print its decoded output to the C<$out> filehandle.  You may
do this however you see fit, so long as the end result is the same.

Your method must return either C<undef> (to indicate failure),
or C<1> (to indicate success).

=item 3.

In your application program, activate your decoder for one or
more encodings like this:

    require MyDecoder;

    install MyDecoder "7bit";        # use MyDecoder to decode "7bit"    
    install MyDecoder "x-foo";       # also, use MyDecoder to decode "x-foo"

=back

To illustrate, here's a custom decoder class for the C<base64> encoding:

    package MyBase64Decoder;

    @ISA = qw(MIME::Decoder);    
    use MIME::Decoder;
    use MIME::Base64;
    
    # decode_it - the private decoding method
    sub decode_it {
        my ($self, $in, $out) = @_;

        while (<$in>) {
            my $decoded = decode_base64($_);
	    print $out $decoded;
        }
        1;
    }

That's it.

The task was pretty simple because the C<"base64"> encoding can easily 
and efficiently be parsed line-by-line... as can C<"quoted-printable">,
and even C<"7bit"> and C<"8bit"> (since all these encodings guarantee 
short lines, with a max of 1000 characters).
The good news is: it is very likely that it will be similarly-easy to 
write a MIME::Decoder for any future standard encodings.

The C<"binary"> decoder, however, really required block reads and writes:
see L<"MIME::Decoder::Binary"> for details.


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

$Revision: 1.9 $ $Date: 1996/06/24 19:02:31 $

=cut


#------------------------------------------------------------
# Execute simple test if run as a script...
#------------------------------------------------------------
{ 
  package main; no strict;
  $INC{'MIME/Decoder.pm'} = 1;
  eval join('',<main::DATA>) || die "$@ $main::DATA" unless caller();
}
1;           # end the module
__END__

BEGIN { unshift @INC, "./etc" }

require MIME::Decoder;
    
my $decoder = new MIME::Decoder 'quoted-printable';

die "yow! no quoted-print!" if (!(supported MIME::Decoder "quoted-PRINTABLE"));
print STDOUT "* Cool: quoted-printable is supported...\n";
print STDOUT "* Waiting for quoted-printable data on STDIN...\n";
$decoder->decode(\*STDIN, \*STDOUT);

1;
