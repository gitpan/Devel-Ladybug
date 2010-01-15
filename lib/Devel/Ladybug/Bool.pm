#
# File: lib/Devel/Ladybug/Bool.pm
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

Devel::Ladybug::Bool - Overloaded object class for booleans

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Num>.

=head1 SYNOPSIS

  #
  # File: YourApp/Example.pm
  #
  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    myBool => Devel::Ladybug::Bool->assert()

    # ...
  };

  #
  # File: somecaller.pl
  #
  use YourApp::Example;

  my $ex = YourApp::Example->new(...);

  if ( $ex->myBool ) {
    print "True\n";
  } else {
    print "False\n";
  }

  $ex->setMyBool(true);

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut

package Devel::Ladybug::Bool;

use strict;
use warnings;

use Devel::Ladybug::Enum::Bool;
use Devel::Ladybug::Num;

use base qw| Devel::Ladybug::Num |;

use overload %Devel::Ladybug::Num::overload;

sub new {
  my $class = shift;
  my $self  = shift;

  Devel::Ladybug::Type::insist $self, Devel::Ladybug::Type::isBool;

  return $class->SUPER::new($self);
}

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isBool,
    @rules );

  $parsed{allowed}  = [ false, true ];
  $parsed{optional} = false;
  $parsed{default}  = false if !defined $parsed{default};
  $parsed{columnType} ||= 'INTEGER(1)';

  return $class->__assertClass()->new(%parsed);
}

sub isTrue {
  my $self = shift;

  my $class = $self->class();

  return $self
    ? $class->new(true)
    : $class->new(false);
}

sub isFalse {
  my $self = shift;

  my $class = $self->class();

  return $self
    ? $class->new(false)
    : $class->new(true);
}

true;
