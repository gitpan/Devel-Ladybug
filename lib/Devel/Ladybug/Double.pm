#
# File: lib/Devel/Ladybug/Double.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#

=pod

=head1 NAME

Devel::Ladybug::Double - Overloaded double-precision number object

=head1 DESCRIPTION

Double-precision floating point number, only not really.

This class just avoids E notation when stringifying, and uses
DOUBLE(30,10) for its database column type. Otherwise, it is overloaded
to work like a native number in numeric and string operations, which
means it does B<not> handle high-precision or bignum math operations,
such as those supported by L<Math::BigFloat>, without floating point
lossiness.

Extends L<Devel::Ladybug::Float>.

=head1 SYNOPSIS

  use Devel::Ladybug::Double;

  my $double = Devel::Ladybug::Double->new(.0000001);

  print "$double\n";

  print "$double * 2 = ". ( $double*2 ) ."\n";

=head1 DIAGNOSTICS

Devel::Ladybug::Double is overloaded to just work like a native number.

It does so by treating the most and least significant values as
string-like, or integer-like, depending on the situation. In short,
it's a big hack. Precision is not guaranteed.

Should the unlikely event arise that you need to know what the backing
reference value looks like-- it's an ARRAY ref. Position 0 contains the
most significant value (left side of decimal), and position 1 contains
a zero-padded string of the least significant value (right side of
decimal).

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut

package Devel::Ladybug::Double;

use strict;
use warnings;

use Devel::Ladybug::Enum::Bool;

use base qw| Devel::Ladybug::Float |;

use overload
  fallback => true,
  %Devel::Ladybug::Num::overload,
  '*' => sub { my $a = shift; my $b = shift; return "$a" * "$b" };

sub new {
  my $class   = shift;
  my $greater = shift;
  my $lesser  = shift;

  my $self;

  if ( defined $lesser ) {
    Devel::Ladybug::Type::insist( $greater,
      Devel::Ladybug::Type::isInt );
    Devel::Ladybug::Type::insist( $lesser,
      Devel::Ladybug::Type::isInt );

    $self = join( ".", $greater, $lesser );
  } else {
    $self = $greater;
  }

  throw Devel::Ladybug::InvalidArgument(
    "$class->new() requires a non-undef arg")
    if !defined($self);

  $self = "$self";

  Devel::Ladybug::Type::insist( $self, Devel::Ladybug::Type::isFloat );

  my ( $msv, $lsv );

  if ( $self =~ /e/ ) {
    ( $msv, $lsv ) = split( /\./, sprintf( '%.10f', $self ) );

  } elsif ( $self !~ /\./ ) {
    $msv = $self;
    $lsv = 0;
  } elsif ( $self =~ /^\./ ) {
    $msv = 0;
    $lsv = $self;
    $lsv =~ s/\.//;
  } else {
    ( $msv, $lsv ) = split( /\./, $self );
  }

  return bless [ $msv, $lsv ], $class;
}

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isFloat,
    @rules );

  $parsed{default} = "0.0000000000" if !exists $parsed{default};
  $parsed{columnType} ||= 'DOUBLE(30,10)';

  return $class->__assertClass()->new(%parsed);
}

sub value {
  my $self = shift;

  my $value;

  do {
    no warnings "numeric";

    $value = join( ".",
      sprintf( '%i', $self->[0] ),
      sprintf( '%s', $self->[1] ) );
  };

  return $value;
}

1;
