#
# File: lib/Devel/Ladybug/Int.pm
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

Devel::Ladybug::Int - Overloaded object class for integers

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Num>

=head1 SYNOPSIS

  use Devel::Ladybug::Int;

  my $int = Devel::Ladybug::Int->new(42);

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut

package Devel::Ladybug::Int;

use strict;
use warnings;

use Devel::Ladybug::Enum::Bool;

use base qw| Devel::Ladybug::Num |;

use overload fallback => true, %Devel::Ladybug::Num::overload;

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isInt,
    @rules );

  $parsed{maxSize}    ||= 11;
  $parsed{columnType} ||= 'INT(11)';

  return $class->__assertClass()->new(%parsed);
}

true;
