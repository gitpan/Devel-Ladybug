#
# File: lib/Devel/Ladybug/ID.pm
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

Devel::Ladybug::ID - Overloaded GUID object class

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Scalar> and L<Data::GUID>

ID objects stringify as base64, which makes them as small as practical.

=head1 SYNOPSIS

  use Devel::Ladybug::ID;

  #
  # Generate a new GUID
  #
  do {
    my $id = Devel::Ladybug::ID->new();

    # ...
  }

  #
  # Instantiate an existing GUID from base64
  #
  do {
    my $id = Devel::Ladybug::ID->new("EO2JXisF3hGSSg+s3t/Aww==");

    # ...
  }

You may also instantiate from and translate between string, hex, or
binary GUID forms using the constructors inherited from L<Data::GUID>.

See L<Data::GUID> and L<Data::UUID> for more details.

=head1 SEE ALSO

L<Devel::Ladybug::Serial>

This file is part of L<Devel::Ladybug>.

=cut

package Devel::Ladybug::ID;

use strict;
use warnings;

use Devel::Ladybug::Enum::Bool;

use URI::Escape;

use overload
  fallback => true,
  '""'     => sub { shift->as_base64() };

use base qw| Data::GUID Devel::Ladybug::Scalar |;

sub new {
  my $class = shift;
  my $self  = shift;

  if ($self) {
    my $len = length("$self");

    if ( $len == 36 ) {
      return Data::GUID::from_string( $class, $self );
    } elsif ( $len == 24 ) {
      return Data::GUID::from_base64( $class, $self );
    } else {
      Devel::Ladybug::AssertFailed->throw(
        "Unrecognized ID format: \"$self\"");
    }
  }

  return Data::GUID::new($class);
}

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isStr,
    @rules );

  $parsed{columnType} ||= 'CHAR(24)';
  $parsed{optional} = true;

  # why? because this won't be set yet inside of new objects.
  # if id is a PRIMARY KEY, it can't be null in the DB, so
  # this works out fine.

  return $class->__assertClass()->new(%parsed);
}

sub escaped {
  my $self = shift;

  return uri_escape( $self->as_base64 );
}

true;
