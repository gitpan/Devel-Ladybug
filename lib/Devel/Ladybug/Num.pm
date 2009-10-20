#
# File: lib/Devel/Ladybug/Num.pm
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

Devel::Ladybug::Num - Overloaded object class for numbers

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Scalar>.

=head1 SYNOPSIS

  use Devel::Ladybug::Num;

  my $num = Devel::Ladybug::Num->new(12345);

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut

package Devel::Ladybug::Num;

use strict;
use warnings;

use Devel::Ladybug::Enum::Bool;

use base qw| Devel::Ladybug::Scalar |;

# + - * / % ** << >> x
# <=> cmp
# & | ^ ~
# atan2 cos sin exp log sqrt int

our %overload = (
  '++' => sub { ++${ $_[0] }; shift },    # from overload.pm
  '--' => sub { --${ $_[0] }; shift },
  '+'  => sub { "$_[0]" + "$_[1]" },
  '-'  => sub { "$_[0]" - "$_[1]" },
  '*'  => sub { "$_[0]" * "$_[1]" },
  '/'  => sub { "$_[0]" / "$_[1]" },
  '%'  => sub { "$_[0]" % "$_[1]" },
  '**' => sub { "$_[0]"**"$_[1]" },
  '==' => sub { "$_[0]" == "$_[1]" },
  'eq' => sub { "$_[0]" eq "$_[1]" },
  '!=' => sub { "$_[0]" != "$_[1]" },
  'ne' => sub { "$_[0]" ne "$_[1]" },
);

use overload fallback => true, %overload;

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isFloat,
    @rules );

  $parsed{maxSize}    ||= 11;
  $parsed{columnType} ||= 'INT(11)';

  return $class->__assertClass()->new(%parsed);
}

sub abs {
  my $self = shift;

  return CORE::abs( ${$self} );
}

sub atan2 {
  my $self = shift;
  my $num  = shift;

  return CORE::atan2( ${$self}, $num );
}

sub cos {
  my $self = shift;

  return CORE::cos( ${$self} );
}

sub exp {
  my $self = shift;

  return CORE::exp( ${$self} );
}

sub int {
  my $self = shift;

  CORE::int( ${$self} );
}

sub log {
  my $self = shift;

  return CORE::log( ${$self} );
}

sub rand {
  my $self = shift;

  return CORE::rand( ${$self} );
}

sub sin {
  my $self = shift;

  return CORE::sin( ${$self} );
}

sub sqrt {
  my $self = shift;

  return CORE::sqrt( ${$self} );
}

true;
