#-*- perl -*-
#-*- coding: us-ascii -*-

package Encode::ISO2022;

use 5.007003;
use strict;
use warnings;
use base qw(Encode::Encoding);
our $VERSION = '0.000_07';

use Carp qw(carp croak);
use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

my $err_encode_nomap = '"\x{%*v04X}" does not map to %s';
my $err_decode_nomap = '%s "\x%*v02X" does not map to Unicode';

my $DIE_ON_ERR = Encode::DIE_ON_ERR();
my $FB_QUIET = Encode::FB_QUIET();
my $HTMLCREF = Encode::HTMLCREF();
my $LEAVE_SRC = Encode::LEAVE_SRC();
my $PERLQQ = Encode::PERLQQ();
my $RETURN_ON_ERR = Encode::RETURN_ON_ERR();
my $WARN_ON_ERR = Encode::WARN_ON_ERR();
my $XMLCREF = Encode::XMLCREF();

# decode method

sub decode {
    my ($self, $str, $chk) = @_;

    my $chk_sub;
    my $utf8 = '';
    my $errChar;

    if (ref $chk eq 'CODE') {
	$chk_sub = $chk;
	$chk = $PERLQQ | $LEAVE_SRC;
    }

    $self->init_state(1);

    pos($str) = 0;
    my $chunk = '';
  CHUNKS:
    while (
	$str =~ m{
	    \G
	    (
		( # designation (FIXME)
		    \e\x24?[\x28-\x2B\x2D-\x2F][\x20-\x2F]*[\x40-\x7E] |
		    \e\x24[\x40-\x42] |
		) |
		( # locking shift
		    \x0E|\x0F|\e[\x6E\x6F\x7C\x7D\x7E]
		) |
	    )
	    (
		( # single shift 2
		    \x8E|\e\x4E
		) |
		( # single shift 3
		    \x8F|\e\x4F
		) |
	    )
	    (
		[^\x0E\x0F\e\x8E\x8F]*
	    )
	}gcx
    ) {
	my ($func, $g_seq, $ls, $ss, $ss2, $ss3, $chunk) =
	    ($1, $2, $3, $4, $5, $6, $7);

	if (length $g_seq) {
	    unless ($self->designate_dec($g_seq)) {
		#XXX;
	    }
	} elsif (length $ls) {
	    unless ($self->invoke_dec($ls)) {
		#XXX;
	    }
	}

	while (length $chunk) {
	    my ($conv, $bytes);

	    ($conv, $bytes) = $self->_decode($chunk, $ss);
	    if (defined $conv) {
		$utf8 .= $conv;

		if ($conv =~ /[\r\n]/ and $self->{LineInit}) {
		    $self->init_state(1);
		}
		next;
	    }

	    $errChar = substr($chunk, 0, $bytes || 1);
	    if ($chk & $DIE_ON_ERR) {
		croak sprintf $err_decode_nomap, $self->name, '\x', $errChar;
	    }
	    if ($chk & $WARN_ON_ERR) {
		carp sprintf $err_decode_nomap, $self->name, '\x', $errChar;
	    }
	    if ($chk & $RETURN_ON_ERR) {
		last CHUNKS;
	    }

	    substr($chunk, 0, $bytes || 1) = '';

	    if ($chk_sub) {
		$conv = $chk_sub->($errChar);
		$conv = Encode::decode_utf8($conv)
		    unless Encode::is_utf8($conv);
	    } elsif ($chk & $PERLQQ) {
		$conv = sprintf '\x%*v02X', '\x', $errChar;
	    } else {
		$conv = "\x{FFFD}";
	    }
	    $utf8 .= $conv;
	}
    }
    pos($str) -= length($chunk);
    $_[1] = substr($str, pos $str) unless $chk & $LEAVE_SRC;

    return $utf8;
}

sub _decode {
    my ($self, $chunk, $ss) = @_;

    my @ccs;
    my $conv;
    my $bytes_min;

    if ($ss) {
	@ccs = grep {
	    $_->{_designated_to} and
	    $_->{ss} and $_->{ss} eq $ss
	} @{$self->{CCS} || []};
    } else {
	@ccs = grep {
	    $_->{_invoked_to} or
	    not ($_->{g} or $_->{g_init} or $_->{ls} or $_->{ss})
	} @{$self->{CCS} || []};
    }

    foreach my $ccs (@ccs) {
	next unless $ccs and $ccs->{encoding}; #FIXME

	my $residue;
	if ($ss) {
	    $residue = substr($chunk, $ccs->{bytes} || 1);
	    $chunk = substr($chunk, 0, $ccs->{bytes} || 1);
	} else {
	    $residue = '';
	}

	if ($ccs->{gr}) {
	    unless ($chunk =~ /^[\xA0-\xFF]/) {
		$chunk .= $residue;
		next;
	    }
	    $chunk =~ tr/\x20-\x7F\xA0-\xFF/\xA0-\xFF\x20-\x7F/;
	    $conv = $ccs->{encoding}->decode($chunk, $FB_QUIET);
	    $chunk =~ tr/\x20-\x7F\xA0-\xFF/\xA0-\xFF\x20-\x7F/;
	} else {
	    $conv = $ccs->{encoding}->decode($chunk, $FB_QUIET);
	}
	$bytes_min = $ccs->{bytes}
	    if $ccs->{bytes} and
	    (not defined $bytes_min or $ccs->{bytes} < $bytes_min);

	$chunk .= $residue;

	if (defined $conv and length $conv) {
	    $_[1] = $chunk;
	    $_[2] = $_[3] = undef;
	    return $conv;
        }
    }
    $_[2] = $_[3] = undef;
    return (undef, $bytes_min);
}

sub designate_dec {
    my ($self, $g_seq) = @_;

    my $ccs = (grep {
	$_->{g_seq} and $_->{g_seq} eq $g_seq
    } @{$self->{CCS} || []})[0];
    return undef unless $ccs;

    return $self->designate($ccs);
}

sub invoke_dec {
    my ($self, $ls) = @_;

    my $ccs = (grep {
	$_->{_designated_to} and
	$_->{ls} and $_->{ls} eq $ls
    } @{$self->{CCS} || []})[0];
    return undef unless $ccs;

    return $self->invoke($ccs);
}

# encode method

sub encode {
    my ($self, $utf8, $chk) = @_;

    my $chk_sub;
    my $str = '';
    my $errChar;
    my $subChar;

    if (ref $chk eq 'CODE') {
	$chk_sub = $chk;
	$chk = $PERLQQ | $LEAVE_SRC;
    }

    $self->init_state(1);

    while (length $utf8) {
	my $conv;

	$conv = $self->_encode($utf8);
	if (defined $conv) {
	    $str .= $conv;

	    if ($conv =~ /[\r\n]/ and $self->{LineInit}) {
		$self->init_state(1);
	    }
	    next;
	}

	$errChar = substr($utf8, 0, 1);
	if ($chk & $DIE_ON_ERR) {
	    croak sprintf $err_encode_nomap, '}\x{', $errChar, $self->name;
	}
	if ($chk & $WARN_ON_ERR) {
	    carp sprintf $err_encode_nomap, '}\x{}', $errChar, $self->name;
	}
	if ($chk & $RETURN_ON_ERR) {
	    last;
	}

	substr($utf8, 0, 1) = '';

	if ($chk_sub) {
	    $subChar = $chk_sub->(ord $errChar);
	} elsif ($chk & $PERLQQ) {
	    $subChar = sprintf '\x{%04X}', ord $errChar;
	} elsif ($chk & $XMLCREF) {
	    $subChar = sprintf '&#x%X;', ord $errChar;
	} elsif ($chk & $HTMLCREF) {
	    $subChar = sprintf '&#%d;', ord $errChar;
	} else {
	    $subChar = $self->{SubChar} || '?';
	}
	$conv = $self->_encode($subChar);
	if (defined $conv) {
	    $str .= $conv;
	}
    }
    $_[1] = $utf8 unless $chk & $LEAVE_SRC;

    if (length $str) {
	$str .= $self->init_state();
    }
    return $str;
}

sub _encode {
    my ($self, $utf8) = @_;

    foreach my $ccs (@{$self->{CCS} || []}) {
	next if $ccs->{dec_only};

	my $conv = $ccs->{encoding}->encode($utf8, $FB_QUIET);
	if (defined $conv and length $conv) {
	    $_[1] = $utf8;
	    return $self->designate($ccs) . $self->invoke($ccs, $conv);
	}
    }
    return undef;
}

sub init_state {
    my ($self, $reset) = @_;

    if ($reset) {
	foreach my $ccs (@{$self->{CCS} || []}) {
	    delete $ccs->{_designated_to};
	    delete $ccs->{_invoked_to};
	}
	delete $self->{_state};
    }

    my $ret = '';
    foreach my $ccs (grep { $_->{g_init} } @{$self->{CCS} || []}) {
	$ret .= $self->designate($ccs);
    }
    return $ret;
}

sub designate {
    my ($self, $ccs) = @_;

    my $g = $ccs->{g} || $ccs->{g_init};
    die sprintf 'Cannot designate %s', $ccs->{encoding}->name
	unless $g;
    my $g_seq = $ccs->{g_seq};

    my @ccs;
    if ($g_seq) { # explicit designation
	@ccs = grep {
	    $_->{g_seq} and $_->{g_seq} eq $g_seq
	} @{$self->{CCS} || []};
    } else { # static designation
	@ccs = grep {
	    not $_->{g_seq} and
	    ($_->{g} and $_->{g} eq $g or $_->{g_init} and $_->{g_init} eq $g)
	} @{$self->{CCS} || []};
    }
    # Already designated: do nothing
    return ''
	unless grep {
	    not ($_->{_designated_to} and $_->{_designated_to} eq $g)
	} @ccs;

    # modify designation
    foreach my $_ (@{$self->{_state}->{$g} || []}) {
	delete $_->{_designated_to};
	delete $_->{_invoked_to};
    }
    my %invoked = (gr => [], gl => []);
    foreach my $_ (@ccs) {
	$_->{_designated_to} = $g;
	unless ($_->{ls} or $_->{ss}) {
	    my $i = $_->{gr} ? 'gr' : 'gl';

	    $_->{_invoked_to} = $i;
	    push @{$invoked{$i}}, $_;
	}
    }

    # modify invokation
    foreach my $i (qw/gr gl/) {
	next unless @{$invoked{$i} || []};

	foreach my $_ (@{$self->{_state}->{$i} || []}) {
	    delete $_->{_invoked_to};
	}
	$self->{_state}->{$i} = $invoked{$i};
    }

    $self->{_state}->{$g} = [@ccs];
    return $g_seq || '';
}

sub invoke {
    my ($self, $ccs, $str) = @_;
    $str = '' unless defined $str;

    my $i = $ccs->{gr} ? 'gr' : 'gl';

    if ($i eq 'gr') {
	$str =~ tr/\x20-\x7F/\xA0-\xFF/;
    }

    if ($ccs->{ss}) {
	my $out = '';
	while (length $str) {
	    $out .= $ccs->{ss} . substr($str, 0, ($ccs->{bytes} || 1), '');
	}
	return $out;	
    } elsif ($ccs->{ls}) {
	my $ls = $ccs->{ls};
	my $g_seq = $ccs->{g_seq};
	my $g = $ccs->{g} || $ccs->{g_init};

	my @ccs;
	if ($g_seq) {
	    @ccs = grep {
		$_->{g_seq} and $_->{g_seq} eq $g_seq and
		$_->{ls} and $_->{ls} eq $ls and
		($_->{gr} ? 'gr' : 'gl') eq $i
	    } @{$self->{CCS} || []};
	} else {
	    @ccs = grep {
		not $_->{g_seq} and ($_->{g} || $_->{g_init}) eq $g and
		$_->{ls} and $_->{ls} eq $ls and
		($_->{gr} ? 'gr' : 'gl') eq $i
	    } @{$self->{CCS} || []};
	}
	# Already invoked: add nothing
	return $str
	    unless grep {
		not ($_->{_invoked_to} and $_->{_invoked_to} eq $i)
	    } @ccs;

	foreach my $_ (@{$self->{_state}->{$i} || []}) {
	    delete $_->{_invoked_to};
	}
	foreach my $_ (@ccs) {
	    $_->{_invoked_to} = $i;
	}

	$self->{_state}->{$i} = [@ccs];
	return $ccs->{ls} . $str;
    } else {
	return $str;
    }
}

1;
__END__

=head1 NAME

Encode::ISO2022 - ISO/IEC 2022 character encoding scheme

=head1 SYNOPSIS

  package FooEncoding;
  use Encode::ISO2022;
  our @ISA = qw(Encode::ISO2022);
  
  $Encode::Encoding{'foo-encoding'} = bless {
    Name => 'foo-encoding',
    CCS => [ {...CCS #1...}, {...CCS #2...}, ....]
  } => __PACKAGE__;

=head1 DESCRIPTION

This module provides a character encoding scheme (CES) switching a set of
multiple coded character sets (CCS).

Instances of L<Encode::ISO2022> have following hash items.

=over 4

=item Name => STRING

The name of this encoding as L<Encode::Encoding> object.

=item CCS => [ FEATURE, FEATURE, ...]

List of features defining CCSs used by this encoding.
Each item is a hash reference containing following items.

=over 4

=item bytes => NUMBER

Number of bytes to represent each character.
Default is 1.

=item dec_only => BOOLEAN

If true value is set, this CCS will be used only for decoding.

=item encoding => ENCODING

L<Encode::Encoding> object used as CCS.
Mandatory.

Encodings used for CCS must provide "raw" conversion.
Namely, they must be stateless and fixed-length conversion over 94^n or 96^n
code tables.
L<Encode::ISO2022::CCS> lists available CCSs.

=item gr => BOOLEAN

If true value is set, each character will be invoked to GR.

=item g => STRING

=item g_init => STRING

Working set this CCS may be designated to:
C<'g0'>, C<'g1'>, C<'g2'> or C<'g3'>.

If C<g_init> is set, this CCS will be designated at beginning of coversion
implicitly, and at end of conversion explicitly.

If C<g> or C<g_init> is set and neither of C<ls> nor C<ss> is not set,
this CCS will be invoked when it is designated.

If neither of C<g>, C<g_init>, C<ls> nor C<ss> is set,
this CCS is invoked always.

=item g_seq => STRING

Escape sequence to designate this CCS, if it can be designated explicitly.

=item ls => STRING

=item ss => STRING

Escape sequence or control character to invoke this CCS,
if it should be invoked explicitly.

If C<ss> is set, this CCS will be invoked for only one character.

=back

=item LineInit => BOOLEAN

If it is true, designation and invokation states will be initialized at
beginning of lines.

=item SubChar => STRING

Unicode string to be used for substitution character.

=back

To know more about use of this module,
the source of L<Encode::ISO2022JP2> may be an example.

=head1 SEE ALSO

ISO/IEC 2022
I<Information technology - Character code structure and extension techniques>.

L<Encode>, L<Encode::ISO2022::CCS>.

=head1 AUTHOR

Hatuka*nezumi - IKEDA Soji, E<lt>nezumi@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Hatuka*nezumi - IKEDA Soji

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
