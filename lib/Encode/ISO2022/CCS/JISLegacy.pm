#-*- perl -*-
#-*- coding: us-ascii -*-

package Encode::ISO2022::CCS::JISLegacy;

use strict;
use warnings;

use base qw(Encode::Encoding);
our $VERSION = '0.01';

use Encode qw(FB_QUIET);
use Encode::JP;

# JIS C6226-1978, 1st revision of JIS X0208.
$Encode::Encoding{'jis0208-1978-raw'} = bless {
    Name => 'jis0208-1978-raw',
    encoding => $Encode::Encoding{'jis0208-raw'},
} => __PACKAGE__;
# JIS X0201 Latin set, ISO/IEC 646 JP.
$Encode::Encoding{'jis0201-left'} = bless {
    Name => 'jis0201-left',
    encoding => $Encode::Encoding{'jis0201-raw'},
} => __PACKAGE__;
# JIS X0201 katakana set.
$Encode::Encoding{'jis0201-right'} = bless {
    Name => 'jis0201-right',
    encoding => $Encode::Encoding{'jis0201-raw'},
} => __PACKAGE__;

# 26 row-cell pairs swapped between JIS C 6226-1978 and JIS X 0208-1983.
# cf. JIS X 0208:1997 Annex 2 Table 1.
my @swap1978 = (
    "\x30\x33" => "\x72\x4D", "\x32\x29" => "\x72\x74",
    "\x33\x42" => "\x69\x5a", "\x33\x49" => "\x59\x78",
    "\x33\x76" => "\x63\x5e", "\x34\x43" => "\x5e\x75",
    "\x34\x52" => "\x6b\x5d", "\x37\x5b" => "\x70\x74",
    "\x39\x5c" => "\x62\x68", "\x3c\x49" => "\x69\x22",
    "\x3F\x59" => "\x70\x57", "\x41\x28" => "\x6c\x4d",
    "\x44\x5B" => "\x54\x64", "\x45\x57" => "\x62\x6a",
    "\x45\x6e" => "\x5b\x6d", "\x45\x73" => "\x5e\x39",
    "\x46\x76" => "\x6d\x6e", "\x47\x68" => "\x6a\x24",
    "\x49\x30" => "\x5B\x58", "\x4b\x79" => "\x50\x56",
    "\x4c\x79" => "\x69\x2e", "\x4F\x36" => "\x64\x46",
    "\x36\x46" => "\x74\x21", "\x4B\x6A" => "\x74\x22",
    "\x4D\x5A" => "\x74\x23", "\x60\x76" => "\x74\x24",
);
my %swap1978 = (@swap1978, reverse @swap1978);

sub encode {
    my ($self, $utf8) = @_; # $chk is assumed to be true.

    my $residue = '';
    my $conv;
    if ($self->name eq 'jis0208-1978-raw') {
	$conv = $self->{encoding}->encode($utf8, FB_QUIET);
	$conv =~ s{([\x21-\x7E]{2})}{$swap1978{$1} || $1}eg;
    } elsif ($self->name eq 'jis0201-left') {
	if ($utf8 =~ s/([\x00-\x1F\x80-\x9F\x{FF61}-\x{FF9F}].*)$//s) {
	    $residue = $1;
	}
	$conv = $self->{encoding}->encode($utf8, FB_QUIET);
    } elsif ($self->name eq 'jis0201-right') {
	if ($utf8 =~ s/([^\x{FF61}-\x{FF9F}].*)$//s) {
	    $residue = $1;
	}
	$conv = $self->{encoding}->encode($utf8, FB_QUIET);
	$conv =~ tr/\xA1-\xDF/\x21-\x5F/;
    }

    $_[1] = $utf8 . $residue;
    return $conv;
}

sub decode {
    my ($self, $str) = @_; # $chk is assumed to be true.

    my $residue = '';
    my $conv;
    if ($self->name eq 'jis0208-1978-raw') {
	$str =~ s{([\x21-\x7E]{2})}{$swap1978{$1} || $1}eg;
	$conv = $self->{encoding}->decode($str, FB_QUIET);
	$str =~ s{([\x21-\x7E]{2})}{$swap1978{$1} || $1}eg;
    } elsif ($self->name eq 'jis0201-left') {
	if ($str =~ s/([^\x20-\x7F].*)$//s) {
	    $residue = $1;
	}
	$conv = $self->{encoding}->decode($str, FB_QUIET);
    } elsif ($self->name eq 'jis0201-right') {
	if ($str =~ s/([^\x21-\x5F].*)$//s) {
	    $residue = $1;
	}
	$str =~ tr/\x21-\x5F/\xA1-\xDF/;
	$conv = $self->{encoding}->decode($str, FB_QUIET);
	$str =~ tr/\xA1-\xDF/\x21-\x5F/;
    }

    $_[1] = $str . $residue;
    return $conv;
}

1;
__END__

=head1 NAME

Encode::ISO2022::CCS::JISLegacy - coded character sets for legacy JIS

=head1 DESCRIPTION

See L<Encode::ISO2022::CCS>.

=cut
