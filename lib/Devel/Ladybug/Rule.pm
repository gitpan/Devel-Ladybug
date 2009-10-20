#
# File: lib/Devel/Ladybug/Rule.pm
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

Devel::Ladybug::Rule - Object class for regular expressions

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Str>

=head1 SYNOPSIS

  use Devel::Ladybug::Rule;

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut

package Devel::Ladybug::Rule;

use strict;
use warnings;

use Devel::Ladybug::Enum::Bool;

use overload '=~' => sub {
  my $self  = shift;
  my $value = shift;
  my $reg   = qr/$self/x;

  return $value =~ /$reg/;
};

use base qw| Devel::Ladybug::Str |;

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isRule,
    @rules );

  return $class->__assertClass()->new(%parsed);
}

sub isa {
  my $class = shift;
  my $what  = shift;

  if ( $what eq 'Regexp' ) {
    return true;
  }

  return UNIVERSAL::isa( $class, $what );
}

sub sprint {
  my $self = shift;

  return "$self";
}

true;
