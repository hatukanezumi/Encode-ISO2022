#-*- perl -*-
#-*- coding: us-ascii -*-

package Encode::ISOIRSingle;

use strict;
use warnings;
use base qw(Encode::Encoding);
our $VERSION = '0.01';

use Encode::Byte;
use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

1;
__END__

=head1 NAME

Encode::ISOIRSingle - ISO-IR single byte coded charcter sets

=head1 DESCRIPTION

See L<Encode::ISO2022::CCS>.

=cut
