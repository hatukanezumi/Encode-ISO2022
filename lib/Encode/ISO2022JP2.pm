package Encode::ISO2022JP2;

use strict;
use warnings;
use Encode::ISO2022;
our @ISA = qw/Encode::ISO2022/;
our $VERSION = '0.01';

use Encode::ISOIRSingle;
use Encode::JISLegacy;
use Encode::CN;
use Encode::KR;

Encode::define_alias(qr/\biso-?2022-?jp-?2$/i => '"iso-2022-jp-2"');
$Encode::Encoding{'iso-2022-jp-2'} = bless {
    'CCS' => [
	{
	    desig_init => 1,
	    designates("\e\x28\x42" => 'g0'),
	    encoding => $Encode::Encoding{'ascii'},
	},
	{
	    designates("\e\x24\x42" => 'g0', 2),
	    encoding => $Encode::Encoding{'jis0208-raw'},
	},
	{
	    designates("\e\x24\x41" => 'g0', 2),
	    encoding => $Encode::Encoding{'gb2312-raw'},
	},
	{
	    designates("\e\x24\x28\x43" => 'g0', 2),
	    encoding => $Encode::Encoding{'ksc5601-raw'},
	},
	# Secondary encodings.
	{
	    designates("\e\x28\x4A" => 'g0'),
	    encoding => $Encode::Encoding{'iso-646-jp'},
	},
	{
	    designates("\e\x2E\x41" => 'g2'),
	    encoding => $Encode::Encoding{'iso-8859-1-right'},
	    ss => "\e\x4E",
	},
	{
	    designates("\e\x2E\x46" => 'g2'),
	    encoding => $Encode::Encoding{'iso-8859-7-right'},
	    ss => "\e\x4E",
	},
	{
	    designates("\e\x24\x28\x44" => 'g0', 2),
	    encoding => $Encode::Encoding{'jis0212-raw'},
	},
	{
	    designates("\e\x24\x40" => 'g0', 2),
	    encoding => $Encode::Encoding{'jis0208-1978-raw'},
	},
    ],
    LineInit => 1,
    Name => 'iso-2022-jp-2',
    SubChar => "\x{3013}", 
} => __PACKAGE__;

sub mime_name { shift->{Name} }

sub perlio_ok { 0 }

1;
__END__
=head1 NAME

Encode::ISO2022JP2 - iso-2022-jp-2, extended iso-2022-jp character set

=head1 SYNOPSIS

    use Encode::ISO2022JP2;
    use Encode qw/encode decode/;
    $byte = encode("iso-2022-jp-2", $utf8);
    $utf8 = decode("iso-2022-jp-2", $byte);

=head1 ABSTRACT

This module provides iso2022-jp-2 encoding.

  Canonical       Alias                           Description
  --------------------------------------------------------------
  iso-2022-jp-2   qr/\biso-?2022-?jp-?2$/i        RFC 1554
  --------------------------------------------------------------

=head1 DESCRIPTION

To find out how to use this module in detail, see L<Encode>.

=head1 CAVEAT

iso-2022-jp-2 may not be used with PerlIO layer,
because it keeps designation state beyond lines.

=head1 SEE ALSO

RFC 1554
I<ISO-2022-JP-2: Multilingual Extension of ISO-2022-JP>.

L<Encode>, L<Encode::JP>, L<Encode::JISX0213>.

=head1 AUTHOR

Hatuka*nezumi - IKEDA Soji <hatuka(at)nezumi.nu>

=head1 COPYRIGHT

Copyright (C) 2013 Hatuka*nezumi - IKEDA Soji.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

