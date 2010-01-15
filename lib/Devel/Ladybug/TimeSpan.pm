#
# File: lib/Devel/Ladybug/TimeSpan.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::TimeSpan;

use strict;
use warnings;

use Devel::Ladybug::Class qw| true false |;

use base qw| Devel::Ladybug::Float |;

use overload
  fallback => true,
  '<=>'    => '_compare',
  %Devel::Ladybug::Num::overload;

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed = Devel::Ladybug::Type::__parseTypeArgs(
    sub {
      UNIVERSAL::isa( $_[0], "DateTime" )
        || Scalar::Util::looks_like_number("$_[0]")
        || throw Devel::Ladybug::AssertFailed(
        "Received value is not a time");
    },
    @rules
  );

  $parsed{min} = 0     if !defined $parsed{min};
  $parsed{max} = 2**32 if !defined $parsed{max};
  $parsed{default} ||= "0.0000" if !defined $parsed{default};
  $parsed{columnType} ||= 'DOUBLE(15,4)';

  return $class->__assertClass()->new(%parsed);
}

sub _compare {
  my $date1 = $_[2] ? $_[1] : $_[0];
  my $date2 = $_[2] ? $_[0] : $_[1];

  $date1 ||= 0;
  $date2 ||= 0;

  return "$date1" <=> "$date2";
}

true;

__END__

=pod

=head1 NAME

Devel::Ladybug::TimeSpan - Time range object class

=head1 SYNOPSIS

  use Devel::Ladybug::TimeSpan;

  my $time = Devel::Ladybug::TimeSpan->new( 60*5 );

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Float>.

Stringifies as number of seconds unless overridden.

=head1 PUBLIC CLASS METHODS

=over 4

=item * C<assert(Devel::Ladybug::Class $class: *@rules)>

Returns a new Devel::Ladybug::Type::TimeSpan instance which
encapsulates the received L<Devel::Ladybug::Subtype> rules.

  create "YourApp::Example" => {
    someTime  => Devel::Ladybug::TimeSpan->assert(...),

    # ...
  };

=item * C<new(Devel::Ladybug::Class $class: Num $secs)>

Returns a new Devel::Ladybug::TimeSpan instance which encapsulates the
received value.

  my $object = Devel::Ladybug::TimeSpan->new($secs);

=back

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut
