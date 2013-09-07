#-*- perl -*-
#-*- coding: us-ascii -*-

package Encode::ISOIRSingle;

use strict;
use warnings;
use base qw(Encode::Encoding);
our $VERSION = '0.01';

use Encode qw(FB_QUIET);
use Encode::Byte;
use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

foreach my $n (1..11, 13..16) {
    $Encode::Encoding{"iso-8859-$n-right"} = bless {
	Name => "iso-8859-$n-right",
	encoding => $Encode::Encoding{"iso-8859-$n"},
    } => __PACKAGE__;
}

sub encode {
    my ($self, $utf8) = @_; # $chk is assumed to be true.

    my $residue = '';
    if ($utf8 =~ s/([\x00-\x9F].*)$//s) {
	$residue = $1;
    }
    my $conv = $self->{encoding}->encode($utf8, FB_QUIET);
    $conv =~ tr/\xA0-\xFF/\x20-\x7F/;

    $_[1] = $utf8 . $residue;
    return $conv;
}

sub decode {
    my ($self, $str) = @_; # $chk is assumed to be true.

    my $residue = '';
    if ($str =~ s/[^\x20-\x7F].*$//s) {
	$residue = $1;
    }
    $str =~ tr/\x20-\x7F/\xA0-\xFF/;
    my $conv = $self->{encoding}->decode($str, FB_QUIET);
    $str =~ tr/\xA0-\xFF/\x20-\x7F/;

    $_[1] = $str . $residue;
    return $conv;
}

1;
__END__

=head1 NAME

Encode::ISOIRSingle - ISO-IR single byte coded charcter sets

=head1 DESCRIPTION

See L<Encode::ISO2022::CCS>.

=cut
