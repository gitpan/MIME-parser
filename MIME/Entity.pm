package MIME::Entity;


=head1 NAME

MIME::Entity - class for parsed-and-decoded MIME message


=head1 ALPHA-RELEASE WARNING

I<B<This code is in an evaluation phase until 1 August 1996.>
Depending on any comments/complaints received before this cutoff date, 
the interface B<may> change in a non-backwards-compatible manner.>


=head1 DESCRIPTION

This package provides a class for representing MIME message entities,
as specified in RFC 1521, I<Multipurpose Internet Mail Extensions>.

Here are some excerpts from RFC-1521 explaining the terminology:
each is accompanied by the equivalent in MIME:: terms:

=over 4

=item Message

From RFC-1521:

    The term "message", when not further qualified, means either the
    (complete or "top-level") message being transferred on a network, or
    a message encapsulated in a body of type "message".

There currently is no explicit package for messages; under MIME::, 
messages may be read in from readable files or filehandles.
A future extension will allow them to be read from any object 
reference that responds to a special "next line" method.

=item Body part

From RFC-1521:

    The term "body part", in this document, means one of the parts of the
    body of a multipart entity. A body part has a header and a body, so
    it makes sense to speak about the body of a body part.

Since a body part is just a kind of entity (see below), a body part 
is represented by an instance of MIME::Entity.

=item Entity

From RFC-1521:

    The term "entity", in this document, means either a message or a body
    part.  All kinds of entities share the property that they have a
    header and a body.

An entity is represented by an instance of MIME::Entity.
There are instance methods for recovering the header (a MIME::Head)
and the body (see below).

=item Body

From RFC-1521:

    The term "body", when not further qualified, means the body of an
    entity, that is the body of either a message or of a body part.

Well, this is a toughie.  Both Mail::Internet (1.17) and Mail::MIME (1.03)
represent message bodies in-core; unfortunately, this is not always the
best way to handle things, especially for MIME streams that contain
multi-megabyte tar files.

=back


=head1 THE NITTY GRITTY

A B<MIME::Entity> is composed of the following elements:

=over 4

=item *

A I<head>, which is a reference to a MIME::Head object.

=item *

A I<body>, which (currently) is a path to a file containing the decoded
body.  It is possible for a multipart entity to have a body; this simply
means that the body file contains a MIME message that hasn't yet
been split into its component parts.

=item *

A list of zero or more I<parts>, each of which is a MIME::Entity 
object.  The number of parts will only be nonzero if the content-type 
is some subtype of C<"multipart">.

=back



=head1 DESIGN ISSUES

=head2 To subclass or not to subclass?

When I rewrote this module for the CPAN, I agonized for a long
time about whether or not it really should just be a subclass
of B<Mail::Internet> (or the experimental B<Mail::MIME>).  
There were plusses:

=over 4

=item *

Software reuse.

=item *

Inheritance of the mail-sending utilities.

=item *

Elimination and stamping out of repetitive redundancies.

=back

And, unfortunately, minuses:

=over 4

=item *

The Mail::Internet model of messages as being short enough to fit into
in-core arrays is excellent for most email applications; however, it
seemed ill-suited for generic MIME applications, where MIME streams 
could be megabytes long.

=item *

The current implementation of Mail::Internet (version 1.17) is excellent 
for certain kinds of header manipulation; however, the get() method 
(for retrieveing a field's value) does a brute-force, regexp-based search 
through a linear array of the field values - worse, with a 
dynamically-compiled search pattern.  Even given small headers, I was 
simply too uncomfortable with this approach for the MIME header applications,
which could be fairly get()-intensive.

=item *

In my heart of hearts, I honestly feel that the head should be encapsulated
as a first-class object, separate from any attached body.  Notice that 
this approach allows the head to be folded into the entity in the future;
that is:

    $entity->head->get('subject');

...can work even if C<MIME::Head> objects are eliminated, and 
C<MIME::Entity> objects become the ones that handle the C<get()> 
method.   To do this, we'd simply define C<MIME::Entity::head()> to return
the "self" object, which would "pretend" to be the "header" object.  
Like this:

    sub head { $_[0] }

=item *

While MIME streams follow RFC-822 syntax, they are not, strictly speaking, 
limited to email messages: HTTP is an excellent example of non-email-based
MIME.  So the inheritance from Mail::Internet was not without question
anyway.

=back


B<The compromise.>  Currently, MIME::Head is its own module.  However:

=over 4

=item *

When a MIME::Head is constructed using C<read()> (or C<from_file()>), 
the original parsed header is stored, in all its flat-text glory,
in the MIME::Head object, and may be recovered via the C<original_text()>
method.

=item *

The conversion methods C<from_mail()> and C<to_mail()> are provided in 
MIME::Entity class.

=back

=head2 Some things just can't be ignored

In multipart messages, the I<"preamble"> is the portion that precedes
the first encapsulation boundary, and the I<"epilogue"> is the portion
that follows the last encapsulation boundary.

According to RFC-1521:

    There appears to be room for additional information prior to the
    first encapsulation boundary and following the final boundary.  These
    areas should generally be left blank, and implementations must ignore
    anything that appears before the first boundary or after the last
    one.

    NOTE: These "preamble" and "epilogue" areas are generally not used
    because of the lack of proper typing of these parts and the lack
    of clear semantics for handling these areas at gateways,
    particularly X.400 gateways.  However, rather than leaving the
    preamble area blank, many MIME implementations have found this to
    be a convenient place to insert an explanatory note for recipients
    who read the message with pre-MIME software, since such notes will
    be ignored by MIME-compliant software.

In the world of standards-and-practices, that's the standard.  
Now for the practice: 

I<Some MIME mailers may incorrectly put a "part" in the preamble>,
Since we have to parse over the stuff I<anyway>, in the future I
will allow the parser option of creating special MIME::Entity objects 
for the preamble and epilogue, with bogus MIME::Head objects.




=head1 PUBLIC INTERFACE

=cut

#------------------------------------------------------------


require MIME::Head;

#------------------------------
#
# Globals...
#
#------------------------------

# The package version, in 1.23 style:
$VERSION = sprintf("%d.%02d", q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/);


#------------------------------------------------------------
# error -- private: register unhappiness
#------------------------------------------------------------
sub error { 
    warn @_; return (wantarray ? () : undef);
}




#------------------------------

=head2 Constructors and converters

=over 4

=cut

#------------------------------

#------------------------------------------------------------
# new
#------------------------------------------------------------

=item new

I<Class method.>
Create a new, empty MIME entity.

=cut

sub new {
    my $class = shift;
    my $self = {};
    $self->{Parts} = [];         # no parts extracted
    $self->{PartType} = '';
    bless $self, $class;
}

#------------------------------------------------------------
# from_mail
#------------------------------------------------------------

=item from_mail MAIL

I<Class method.>
Create a new MIME entity from a MAIL::Internet object.
B<Currently unimplemented>. 

=cut

sub from_mail {
    die "from_mail() is not yet implemented: email me if you need it";
}

#------------------------------------------------------------
# to_mail
#------------------------------------------------------------

=item to_mail 

I<Instance method.>
Convert a MIME entity to a MAIL::Internet object.
B<Currently unimplemented>. 

=cut

sub to_mail {
    die "to_mail() is not yet implemented: email me if you need it";
}



#------------------------------

=back

=head2 Instance methods

=over 4

=cut

#------------------------------

#------------------------------------------------------------
# add_part
#------------------------------------------------------------

=item add_part

Assuming we are a multipart message, add a body part (a MIME::Entity)
to the array of body parts.  Do B<not> call this for single-part messages;
i.e., don't call it unless the header has a C<"multipart"> content-type.

=cut

sub add_part {
    my ($self, $part) = @_;
    push @{$self->{Parts}}, $part;
}

#------------------------------------------------------------
# all_parts -- PLANNED
#------------------------------------------------------------
#
# =item all_parts
#
# Like C<parts()>, except that for multipart messages, the preamble and
# epilogue parts I<are> returned in the list, as (respectively) the
# first and last elements.
#
# B<WARNING:> if either/both the preamble/epilogue are missing, then
# they will simply not be in the list; i.e., if the preamble is missing,
# the first list element will have a C<packaging> of 'PART', not 'PREAMBLE'.
#
# =cut

sub parts {
    my $self = shift;
    my @all = ();
    push @all, $self->{Preamble} if $self->{Preamble};
    push @all, @{$self->{Parts}};
    push @all, $self->{Epilogue} if $self->{Epilogue};
}

#------------------------------------------------------------
# body
#------------------------------------------------------------

=item body OPTVALUE

Get or set the path to the file containing the body.

If C<OPTVALUE> I<is not> given, the current body file is returned.
If C<OPTVALUE> I<is> given, the body file is set to the new value,
and the previous value is returned.

=cut

sub body {
    my ($self, $newvalue) = @_;
    my $value = $self->{Body};
    $self->{Body} = $newvalue if (@_ > 1);
    $value;
}

#------------------------------------------------------------
# head
#------------------------------------------------------------

=item head OPTVALUE

Get or set the head.

If C<OPTVALUE> I<is not> given, the current head is returned.
If C<OPTVALUE> I<is> given, the head is set to the new value,
and the previous value is returned.

=cut

sub head {
    my ($self, $newvalue) = @_;
    my $value = $self->{Head};
    $self->{Head} = $newvalue if (@_ > 1);
    $value;
}

#------------------------------------------------------------
# is_multipart
#------------------------------------------------------------

=item is_multipart

Does this entity's MIME type indicate that it's a multipart entity?
Returns undef (false) if the answer couldn't be determined, 0 (false)
if it was determined to be false, and true otherwise.

Note that this says nothing about whether or not parts were extracted.

=cut

sub is_multipart {
    my $self = shift;
    $self->head or return undef;        # no head, so no MIME type!
    my ($type, $subtype) = split('/', $self->mime_type);
    (($type eq 'multipart') ? 1 : 0);
}

#------------------------------------------------------------
# packaging -- PLANNED
#------------------------------------------------------------
# 
# =item packaging OPTVALUE
# 
# Get or set the "packaging" of this entity; that is, where was it 
# when we removed it from its MIME stream?
# 
# If C<OPTVALUE> I<is not> given, the current packaging is returned.
# If C<OPTVALUE> I<is> given, the packaging is set to the new value,
# and the previous value is returned.
# 
# The packaging may be any of:
# 
#     (empty)   - either unknown, or nothing has been extracted yet!
#     ALL       - this entity was extracted from a single-part message
#     PREAMBLE  - this entity was the preamble of a multipart message
#     PART      - this entity was a part of a multipart message
#     EPILOGUE  - this entity was the epilogue of a multipart message
# 
# =cut

sub packaging {
    my ($self, $newvalue) = @_;
    my $value = $self->{Packaging};
    $self->{Packaging} = $newvalue if (@_ > 1);
    $value;
}

#------------------------------------------------------------
# parts
#------------------------------------------------------------

=item parts

Return an array of all sub parts (each of which is a MIME::Entity), 
or the empty array if there are none.  

For single-part messages, the empty array will be returned.
For multipart messages, the preamble and epilogue parts are I<not> in the 
list!  If you want them, use C<all_parts()> instead.

=cut

sub parts {
    my $self = shift;
    @{$self->{Parts}};
}


#------------------------------------------------------------
# dump_skeleton
#------------------------------------------------------------

=item dump_skeleton FILEHANDLE

Dump the skeleton of the entity to the given FILEHANDLE, or
to the currently-selected one if none given.

=cut

sub dump_skeleton {
    my ($self, $fh, $indent) = @_;
    $fh or $fh = select;
    my $ind = '    ' x ($indent || 0);
    my $part;

    print $fh $ind, "Content-type: ", 
          ($self->head ? $self->head->mime_type : 'UNKNOWN'), "\n";
    print $fh $ind, "Body-file: ", ($self->body || 'NONE'), "\n";
    print $fh $ind, "Subject: ", $self->head->get('subject'), "\n"
	if $self->head->get('subject');
    my @parts = $self->parts;
    print $fh $ind, "Num-parts: ", int(@parts), "\n" if @parts;
    print $fh $ind, "--\n";
    foreach $part (@parts) {
	$part->dump_skeleton($fh, $indent+1);
    }
}


#------------------------------------------------------------

=back

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

$Revision: 1.7 $ $Date: 1996/04/30 14:32:00 $

=cut


#------------------------------------------------------------
# Execute simple test if run as a script...
#------------------------------------------------------------
{ 
  package main; no strict;
  $INC{'MIME/Entity.pm'} = 1;
  eval join('',<main::DATA>) || die "$@ $main::DATA" unless caller();
}
1;           # end the module

BEGIN { unshift @INC, "./etc" }

__END__


#------------------------------------------------------------
1;
