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

=head1 SCHEMA ADVISEMENT

Many of these rules affect database schema attributes-- meaning if you
change them after the table already exists, the table will need to be
administratively ALTERed (or moved aside to a new name, re-created, and
migrated). A class's table is created when its package is loaded for
the first time.

Schema updates should be performed using carefully reviewed commands.
Always back up the current table before executing an ALTER.

=head1 SUBTYPE ARGS

Instance variable assertions may be modified by providing the following
arguments to subtype():

=head2 columnType => $colType

Override a database column type, eg "VARCHAR(128)".

=head2 default => $value

Set the default value for a given instance variable and database table
column.

Unless C<optional()> is given, the default value must also be included
as an allowed value.

=head2 min => $num

Specifies the minimum allowed numeric value for a given instance
variable.

=head2 minSize => $num

Specifies the minimum length or scalar size for a given instance
variable.

=head2 max => $num

Specifies the maximum allowed numeric value for a given instance
variable.

=head2 maxSize => $num

Specifies the maximum length or scalar size for a given instance
variable.

=head2 optional => true

Permit a NULL (undef) value for a given instance variable.

=head2 regex => qr/.../

Specifies an optional regular expression which the value of the given
instance variable must match.

=head2 size => $num

Specify that values must always be of a fixed size. The "size" is the
value obtained through the built-in function C<length()> (string
length) for Scalars, C<scalar(...)> (element count) for Arrays, and
C<scalar keys()> (key count) for Hashes.

=head2 sqlValue => $str, sqlInsertValue => $str, sqlUpdateValue => $str

Override an asserted attribute's "insert" value when writing to a SQL
database. This is useful if deriving a new value from existing table
values at insertion time.

C<::sqlInsertValue> and C<::sqlUpdateValue> override any provided value
for ::sqlValue, but only on INSERT and UPDATE statements, respectively.

  create "YourApp::Example::" => {
    foo => Devel::Ladybug::Int->assert(...,
      subtype(
        sqlValue => "(coalesce(max(foo),-1)+1)",
      )
    ),

    # ...
  };

=head2 unique => true

Specify UNIQUE database table columns.

  create "YourApp::Example::" => {
    #
    # Your must either specify true or false...
    #
    foo => Devel::Ladybug::Str->assert(...,
      subtype(
        unique => true
      )
    ),

    #
    # ... or specify a name for "joined" combinatory keys,
    # as used in statement UNIQUE KEY ("foo","bar")
    #
    # To join with more than one key, provide an array reference
    # of key names.
    #
    # For example, to make sure bar+foo is always unique:
    #
    bar => Devel::Ladybug::Str->assert(...,
      subtype(
        unique => "foo"
      )
    ),

    # ...
  };

=head2 uom => $str

Specify an attribute's unit of measurement label.

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
