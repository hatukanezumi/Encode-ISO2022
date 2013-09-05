#-*- perl -*-
#-*- coding: us-ascii -*-

package Encode::ISO2022;

use 5.007003;
use strict;
use warnings;
use base qw(Encode::Encoding);

our $VERSION = '0.0_01';

use Carp qw(carp croak);
use Encode qw(:fallback_all);
use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

my $err_encode_nomap = '"\x{%04X}" does not map to %s';
my $err_decode_nomap = '%s "\x%*v02X" does not map to Unicode';

sub decode {
    my ($self, $str, $chk) = @_;

}

my $ccs_ascii = {
    desig => "\e\x28\x42",
    encoding => $Encode::Encoding{'ascii'},
};

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

    $self->init_state unless $self->{State};

    while (length $utf8) {
	my $conv;

	$conv = $self->_encode($utf8);
	if (defined $conv) {
	    $str .= $conv;
	    next;
	}

	$errChar = substr($utf8, 0, 1);
	if ($chk & DIE_ON_ERR) {
	    $self->init_state;
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
	$str .= $self->designate($ccs_ascii);
	$self->init_state;
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

sub init_state {
    my $self = shift;

    delete $self->{Status};
}

sub designate {
    my ($self, $ccs) = @_;

    my $desig = $ccs->{desig};
    my $g;
    unless ($desig) {
	return '';
    } elsif (index($desig, "\e\x28") == 0) {
	$g = 'g0';
    } elsif (index($desig, "\e\x29") == 0) {
	$g = 'g1';
    } elsif (index($desig, "\e\x2A") == 0) {
	$g = 'g2';
    } elsif (index($desig, "\e\x2B") == 0) {
	$g = 'g3';
    } elsif (index($desig, "\e\x2D") == 0) {
	$g = 'g1';
    } elsif (index($desig, "\e\x2E") == 0) {
	$g = 'g2';
    } elsif (index($desig, "\e\x2F") == 0) {
	$g = 'g3';
    } elsif ($desig =~ /^\e\x24[\x40-\x42]/) {
	$g = 'g0';
    } elsif (index($desig, "\e\x24\x28") == 0) {
	$g = 'g0';
    } elsif (index($desig, "\e\x24\x29") == 0) {
	$g = 'g1';
    } elsif (index($desig, "\e\x24\x2A") == 0) {
	$g = 'g2';
    } elsif (index($desig, "\e\x24\x2B") == 0) {
	$g = 'g3';
    } elsif (index($desig, "\e\x24\x2D") == 0) {
	$g = 'g1';
    } elsif (index($desig, "\e\x24\x2E") == 0) {
	$g = 'g2';
    } elsif (index($desig, "\e\x24\x2F") == 0) {
	$g = 'g3';
    } else {
	die sprintf 'Unknown designation sequence: \x%*vX', '\x', $desig;
    }

    return ''
	if $self->{Status}->{$g} and $self->{Status}->{$g} eq $desig;
    return $self->{Status}->{$g} = $desig;
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
	    if $self->{Status}->{$g} eq $ccs->{ls};
	return ($self->{Status}->{$g} = $ccs->{ls}) . $str;
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

=item desig => STRING

Escape sequence to designate this CCS, if it should be designated explicitly.

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

=item Init => SEQUENCE

FIXME FIXME

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
