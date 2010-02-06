#
# File: lib/Devel/Ladybug/Subtype.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Subtype;

=pod

=head1 NAME

Devel::Ladybug::Subtype - Subtype rules for L<Devel::Ladybug::Type>
instances

=head1 DESCRIPTION

Subtypes are optional components which may modify the parameters of an
L<Devel::Ladybug::Type>. Subtypes are sent as arguments when calling
L<Devel::Ladybug::Type> constructors.

When you see something like:

  foo => Devel::Ladybug::Str->assert(
    subtype(
      optional => true
    )
  )

"Devel::Ladybug::Str->assert()" was the Type constructor, and
"optional" was part of the Subtype specification. "foo" was name of the
instance variable and database table column which was asserted.

The class variable %Devel::Ladybug::Type::RULES is walked at package
load time, and the necessary rule subclasses are created dynamically.

See L<Devel::Ladybug::Type> for a full list of available subtype args.

=head1 PUBLIC INSTANCE METHODS

=over 4

=item * $self->value()

Return the scalar value which was provided to self's constructor.

=back

=head1 SEE ALSO

L<Devel::Ladybug::Type>

This file is part of L<Devel::Ladybug>.

=cut

use strict;
use warnings;

use base qw| Devel::Ladybug::Class Devel::Ladybug::Class::Dumper |;

sub new {
  my $class = shift;
  my @value = @_;

  my $value = ( scalar(@value) > 1 ) ? \@value : $value[0];

  return bless { __value => $value, }, $class;
}

sub value {
  my $self = shift;

  return $self->{__value};
}

1;
