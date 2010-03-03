#
# File: lib/Devel/Ladybug/Name.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Name;

use strict;
use warnings;

use Devel::Ladybug::Enum::Bool;

use base qw| Devel::Ladybug::Str |;

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isStr,
    @rules );

  if ( !$parsed{columnType} ) {
    $parsed{columnType} = 'VARCHAR(128)';
    $parsed{maxSize}    = 128;
  }

  #
  # Name must always be unique, one way or another...
  #
  if ( !$parsed{unique} ) {
    $parsed{unique} = true;
  }

  if ( !defined $parsed{optional} ) {
    $parsed{optional} = true;
  }

  return $class->__assertClass()->new(%parsed);
}

true;
__END__

=pod

=head1 NAME

Devel::Ladybug::Name - A unique secondary key

=head1 SYNOPSIS

  use Devel::Ladybug qw| :all |;

  #
  # Permit NULL values for "name":
  #
  create "YourApp::Example" => {
    name => Devel::Ladybug::Name->assert(
      subtype(
        optional => true
      )
    ),

    # ...
  };

=head1 DESCRIPTION

Devel::Ladybug uses "named objects". By default, C<name> is a
human-readable unique secondary key. It's the name of the object being
saved. Like all attributes, C<name> must be defined when saved, unless
asserted as C<optional> (see "C<undef> Requires Assertion" in
L<Devel::Ladybug>.).

The value for C<name> may be changed (as opposed to C<id>, which should
not be tinkered with), as long as the new name does not conflict with
any objects in the same class when saved. Since Devel::Ladybug objects
refer to one another by GUID, names can be changed freely without
impacting dependent objects.

Objects may be loaded by name using the C<loadByName> class method.

  #
  # Rename an object
  #
  my $person = YourApp::Person->loadByName("Bob");

  $person->setName("Jim");

  $person->save(); # Bob is now Jim.


C<name>, or any attribute type in Devel::Ladybug, may be may be keyed
in combination with multiple attributes via the C<unique> subtype
argument, which adds InnoDB reference options to the schema. Provide
the names of the attributes which you are uniquely keying with as
values to the C<unique> subtype arg.

At the time of this writing, total column length for keys in InnoDB
(regardless of if you're using singular or combinatorial keys) may not
exceed 255 bytes (when using UTF8 encoding, as Devel::Ladybug does).

  #
  # Key using a combination of name + other attributes
  #
  create "YourApp::Example" => {
    name => Devel::Ladybug::Name->assert(
      subtype(
        unique => "parentId"
      )
    ),

    parentId => Devel::Ladybug::ExtID->assert("YourApp::Example"),

    # ...
  };


C<name>'s typing rules may be altered in the class prototype to use
Devel::Ladybug classes other than Devel::Ladybug::Name. Subtyping rules
for uniqueness are not provided by default for other Devel::Ladybug
classes, though, so this should be included by the developer when
implementing the class, for example:

  #
  # Make sure that all names are unique, fully qualified hostnames:
  #
  create "YourApp::Example" => {
    name => Devel::Ladybug::Domain->assert(
      subtype(
        unique => true
      ),
    ),

    # ...
  };


=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut
