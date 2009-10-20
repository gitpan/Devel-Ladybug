#
# File: lib/Devel/Ladybug/Serial.pm
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

Devel::Ladybug::Serial - Auto incrementing integer primary key

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Int>.

=head1 SYNOPSIS

  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    id => Devel::Ladybug::Serial->assert,

  };

=head1 SEE ALSO

L<Devel::Ladybug::ID>

This file is part of L<Devel::Ladybug>.

=cut

package Devel::Ladybug::Serial;

use strict;
use warnings;

use Devel::Ladybug::Enum::Bool;

use base qw| Devel::Ladybug::Int |;

sub new {
  my $class = shift;
  my $value = shift || 0;

  return bless \$value, $class;
}

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isInt,
    @rules );

  $parsed{serial}   = true;
  $parsed{optional} = true;
  $parsed{columnType} ||= 'INTEGER';

  return $class->__assertClass()->new(%parsed);
}

true;
