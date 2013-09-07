#-*- perl -*-
#-*- coding: us-ascii -*-

package Encode::ISO2022;

use 5.007003;
use strict;
use warnings;
use base qw(Encode::Encoding);

our $VERSION = '0.0_02';

use Carp qw(carp croak);
use Encode qw(:fallback_all);
use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

my $err_encode_nomap = '"\x{%04X}" does not map to %s';
my $err_decode_nomap = '%s "\x%*v02X" does not map to Unicode';

sub decode {
    my ($self, $str, $chk) = @_;

    my $chk_sub;
    my $utf8 = '';
    my $errChar;

    if (ref $chk eq 'CODE') {
	$chk_sub = $chk;
	$chk = PERLQQ | LEAVE_SRC;
    }

    delete $self->{State};
    $self->init_decoder;

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
	my ($func, $desig_seq, $ls, $ss, $ss2, $ss3, $chunk) =
	    ($1, $2, $3, $4, $5, $6, $7);

	if (length $desig_seq) {
	    unless ($self->designate_dec($desig_seq)) {
		;
	    }
	} elsif (length $ls) {
	    unless ($self->invoke_dec($ls)) {
		;
	    }
	}

	if (length $ss2) {
	    ;
	} elsif (length $ss3) {
	    ;
	}

	while (length $chunk) {
	    my $conv;

	    $conv = $self->_decode($chunk);
	    if (defined $conv) {
		$utf8 .= $conv;

		if ($conv =~ /[\r\n]/ and $self->{LineInit}) {
		    delete $self->{State};
		    $self->init_decoder;
		}
		next;
	    }

	    $errChar = substr($chunk, 0, 1); # FIXME
	    if ($chk & DIE_ON_ERR) {
		croak sprintf $err_decode_nomap, $self->name, '\x', $errChar;
	    }
	    if ($chk & WARN_ON_ERR) {
		carp sprintf $err_decode_nomap, $self->name, '\x', $errChar;
	    }
	    if ($chk & RETURN_ON_ERR) {
		last CHUNKS;
	    }

	    substr($chunk, 0, 1) = ''; # FIXME

	    if ($chk_sub) {
		$conv = $chk_sub->($errChar);
		$conv = Encode::decode_utf8($conv)
		    unless Encode::is_utf8($conv);
	    } elsif ($chk & PERLQQ) {
		$conv = sprintf '\x%*v02X', '\x', $errChar;
	    } else {
		$conv = "\x{FFFD}";
	    }
	    $utf8 .= $conv;
	}
    }
    pos($str) -= length($chunk);
    $_[1] = substr($str, pos $str) unless $chk & LEAVE_SRC;

    return $utf8;
}

sub _decode {
    my ($self, $chunk) = @_;

    foreach my $ccs (@{$self->{State}->{gl} || []}) {
	next unless $ccs->{encoding};

	my $conv = $ccs->{encoding}->decode($chunk, FB_QUIET);
	if (defined $conv and length $conv) {
	    $_[1] = $chunk;
	    return $conv;
        }
    }

    $chunk =~ tr/\x00-\x7F\x80-\xFF/\x80-\xFF\x00-\x7F/;
    foreach my $ccs (@{$self->{State}->{gr} || []}) {
	my $conv = $ccs->{encoding}->decode($chunk, FB_QUIET);
	if (defined $conv and length $conv) {
	    $chunk =~ tr/\x00-\x7F\x80-\xFF/\x80-\xFF\x00-\x7F/;
	    $_[1] = $chunk;
	    return $conv;
	}
    }
    return undef;
}

sub init_decoder {
    my $self = shift;

    foreach my $ccs (grep { $_->{desig_init} } @{$self->{CCS} || []}) {
	my $g = _parse_desig($ccs->{desig_seq});
	$self->{State}->{$g} = [$ccs];
    }
}

sub designate_dec {
    my ($self, $desig_seq) = @_;

    my $g = _parse_desig($desig_seq);
    return undef unless defined $g;

    my $ccs = 
	[grep {
	    $_->{desig_seq} and $_->{desig_seq} eq $desig_seq
	 } @{$self->{CCS} || []}];
    $self->{State}->{$g} = $ccs;
    unless ($ccs->[0]->{ls} or $ccs->[0]->{ss}) {
	if ($ccs->[0]->{gr}) {
	    $self->{State}->{gr} = $ccs;
	} else {
	    $self->{State}->{gl} = $ccs;
	}
    }
}

sub invoke_dec {
    my ($self, $inv) = @_;

    my ($g, $gg) = _parse_inv($inv);
    return undef unless defined $g;

    $self->{State}->{$gg} = $self->{State}->{$g};
}

sub _parse_inv {
    my $inv = shift;

    ;
}

sub encode {
    my ($self, $utf8, $chk) = @_;

    my $chk_sub;
    my $str = '';
    my $errChar;
    my $subChar;

    if (ref $chk eq 'CODE') {
	$chk_sub = $chk;
	$chk = PERLQQ | LEAVE_SRC;
    }

    delete $self->{State};
    $self->init_encoder;

    while (length $utf8) {
	my $conv;

	$conv = $self->_encode($utf8);
	if (defined $conv) {
	    $str .= $conv;

	    if ($conv =~ /[\r\n]/ and $self->{LineInit}) {
		delete $self->{State};
		$self->init_encoder;
	    }
	    next;
	}

	$errChar = substr($utf8, 0, 1);
	if ($chk & DIE_ON_ERR) {
	    croak sprintf $err_encode_nomap, ord $errChar, $self->name;
	}
	if ($chk & WARN_ON_ERR) {
	    carp sprintf $err_encode_nomap, ord $errChar, $self->name;
	}
	if ($chk & RETURN_ON_ERR) {
	    last;
	}

	substr($utf8, 0, 1) = '';

	if ($chk_sub) {
	    $subChar = $chk_sub->(ord $errChar);
	} elsif ($chk & PERLQQ) {
	    $subChar = sprintf '\x{%04X}', ord $errChar;
	} elsif ($chk & XMLCREF) {
	    $subChar = sprintf '&#x%X;', ord $errChar;
	} elsif ($chk & HTMLCREF) {
	    $subChar = sprintf '&#%d;', ord $errChar;
	} else {
	    $subChar = $self->{SubChar} || '?';
	}
	$conv = $self->_encode($subChar);
	if (defined $conv) {
	    $str .= $conv;
	}
    }
    $_[1] = $utf8 unless $chk & LEAVE_SRC;

    if (length $str) {
	$str .= $self->init_encoder;
    }
    return $str;
}

sub _encode {
    my ($self, $utf8) = @_;

    foreach my $ccs (@{$self->{CCS} || []}) {
	my $conv = $ccs->{encoding}->encode($utf8, FB_QUIET);
	if (defined $conv and length $conv) {
	    $_[1] = $utf8;
	    return $self->designate($ccs) . $self->invoke($ccs, $conv);
	}
    }
    return undef;
}

sub init_encoder {
    my $self = shift;

    my $ret = '';
    foreach my $ccs (grep { $_->{desig_init} } @{$self->{CCS} || []}) {
	$ret .= $self->designate($ccs);
    }
    return $ret;
}

sub designate {
    my ($self, $ccs) = @_;

    my $desig_seq = $ccs->{desig_seq};

    my $g = _parse_desig($desig_seq);
    die sprintf 'Unknown designation sequence: \x%*vX', '\x', $desig_seq
	unless defined $g;

    return ''
	if $self->{State}->{$g} and $self->{State}->{$g} eq $desig_seq;
    return $self->{State}->{$g} = $desig_seq;
}

sub _parse_desig {
    my $desig_seq = shift;

    my $g;
    unless ($desig_seq) {
	return '';
    } elsif (index($desig_seq, "\e\x28") == 0) {
	$g = 'g0';
    } elsif (index($desig_seq, "\e\x29") == 0) {
	$g = 'g1';
    } elsif (index($desig_seq, "\e\x2A") == 0) {
	$g = 'g2';
    } elsif (index($desig_seq, "\e\x2B") == 0) {
	$g = 'g3';
    } elsif (index($desig_seq, "\e\x2D") == 0) {
	$g = 'g1';
    } elsif (index($desig_seq, "\e\x2E") == 0) {
	$g = 'g2';
    } elsif (index($desig_seq, "\e\x2F") == 0) {
	$g = 'g3';
    } elsif ($desig_seq =~ /^\e\x24[\x40-\x42]/) {
	$g = 'g0';
    } elsif (index($desig_seq, "\e\x24\x28") == 0) {
	$g = 'g0';
    } elsif (index($desig_seq, "\e\x24\x29") == 0) {
	$g = 'g1';
    } elsif (index($desig_seq, "\e\x24\x2A") == 0) {
	$g = 'g2';
    } elsif (index($desig_seq, "\e\x24\x2B") == 0) {
	$g = 'g3';
    } elsif (index($desig_seq, "\e\x24\x2D") == 0) {
	$g = 'g1';
    } elsif (index($desig_seq, "\e\x24\x2E") == 0) {
	$g = 'g2';
    } elsif (index($desig_seq, "\e\x24\x2F") == 0) {
	$g = 'g3';
    } else {
	return undef;
    }
    return $g;
}

sub invoke {
    my ($self, $ccs, $str) = @_;

    my $g;
    if ($ccs->{ls} and $ccs->{ls} =~ /^\e[\x7C\x7D\x7E]$/ or
	$ccs->{gr}) {
	$g = 'gr';
    } else {
	$g = 'gl';
    }

    if ($g eq 'gr') {
	$str =~ s/([\x20-\x7F])/chr(ord($1) | 0x80)/eg;
    }

    if ($ccs->{ss}) {
	my $out = '';
	while (length $str) {
	    $out .= $ccs->{ss} . substr($str, 0, ($ccs->{bytes} || 1), '');
	}
	return $out;	
    } elsif ($ccs->{ls}) {
	return $str
	    if $self->{State}->{$g} eq $ccs->{ls};
	return ($self->{State}->{$g} = $ccs->{ls}) . $str;
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
  use base 'Encode::ISO2022';
  $Encode::Encoding{'foo-encoding'} = bless {
    Name => 'foo-encoding',
    CCS => [ {...CCS #1...}, {...CCS #2...}, ....]
  } => __PACKAGE__;

=head1 DESCRIPTION

This module provides a character encoding scheme (CES) switching a set of
multiple coded character sets (CCS).

Instances of L<Encode::ISO2022> have following hash items.

=over 4

=item Name => NAME

The name of this encoding as L<Encode::Encoding> object.

=item CCS => [ FEATURE, FEATURE, ...]

List of features defining CCSs used by this encoding.
Each item is a hash reference containing following items.

=over 4

=item bytes => NUMBER

Number of bytes to represent each character.
Default is 1.

=item encoding => ENCODING

L<Encode::Encoding> object used as CCS.
Mandatory.

Encodings used for CCS must provide "raw" conversion.
Namely, they must be stateless and fixed-length conversion over 94^n or 96^n
code tables.
L<Encode::ISO2022::CCS> lists available CCSs.

=item desig_seq => STRING

Escape sequence to designate this CCS, if it should be designated explicitly.

=item desig_init => BOOLEAN

If this flag is set, this CCS will be designated at beginning of coversion
implicitly, and at end of conversion explicitly.

=item gr => BOOLEAN

If true value is set, each character will be invoked to GR.
Otherwise it will be invoked to GL.

=item ls => STRING

Escape sequence or control character to invoke this CCS, if it should be
invoked explicitly.

=item ss => STRING

Escape sequence or control character to invoke this CCS for only one
character, if it should be invoked explicitly.

=back

=item LineInit => BOOLEAN

If it is true, designation and invokation states will be initialized at
beginning of lines.

=item SubChar => STRING

Unicode string to be used for substitution character.

=back

To know more about use of this module,
the source of L<Encode::ISO2022JP2> may be an example.

FIXME FIXME

=head1 SEE ALSO

L<Encode>, L<Encode::ISO2022::CCS>.

=head1 AUTHOR

Hatuka*nezumi - IKEDA Soji, E<lt>nezumi@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Hatuka*nezumi - IKEDA Soji

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
