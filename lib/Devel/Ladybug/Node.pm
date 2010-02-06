#
# File: lib/Devel/Ladybug/Node.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Node;

=head1 NAME

Devel::Ladybug::Node - Abstract storable object class

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Hash> and L<Devel::Ladybug::Persistence> to
form an abstract base storable object class.

Subclasses should override the class callback methods inherited from
L<Devel::Ladybug::Persistence> to customize backing store options.

=head1 INHERITANCE

This class inherits additional class and object methods from the
following packages:

L<Devel::Ladybug::Class> > L<Devel::Ladybug::Object> >
L<Devel::Ladybug::Hash> > Devel::Ladybug::Node

L<Devel::Ladybug::Persistence> > Devel::Ladybug::Node

=cut

use strict;
use warnings;

#
# include() isn't invoked on "use base", so this is needed here too:
#
use Devel::Ladybug::Hash;
use Devel::Ladybug::ExtID;

use base qw| Devel::Ladybug::Persistence Devel::Ladybug::Hash |;

sub assert {
  my $class = shift;
  my @rules = @_;

  return Devel::Ladybug::ExtID->assert( $class, @rules );
}

sub new {
  my $class = shift;
  my @args  = @_;

  my $self = $class->SUPER::new(@args);

  return $self;
}

sub save {
  my $self = shift;
  my @args = @_;

  $self->SUPER::save(@args);
}

=pod

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut

true;
