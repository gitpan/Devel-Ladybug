#
# File: lib/Devel/Ladybug/Hash.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Hash;

use strict;
use warnings;

use Devel::Ladybug::Array qw| yield |;
use Devel::Ladybug::Class qw| true false |;

use base qw| Devel::Ladybug::Class::Dumper Devel::Ladybug::Object |;

use Error qw| :try |;

=pod

=head1 NAME

Devel::Ladybug::Hash - Hashtable object

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Object> to handle Perl HASH refs as
Devel::Ladybug Objects. Provides constructor, getters, setters,
"Ruby-esque" collection, and other methods which one might expect a
Hash table object to respond to.

=head1 SYNOPSIS

  use Devel::Ladybug::Hash;

  my $hash = Devel::Ladybug::Hash->new();

  my $hashFromNonRef = Devel::Ladybug::Hash->new(%hash); # Makes new ref

  my $hashFromRef = Devel::Ladybug::Hash->new($hashref); # Keeps orig ref

=head1 PUBLIC CLASS METHODS

=over 4

=item * $class->assert(*@rules)

Returns a Devel::Ladybug::Type::Hash instance encapsulating the
received subtyping rules.

Really, don't do this. If you think you need to assert a Hash, please
see "AVOIDING HASH ASSERTIONS" at the end of this document for an
alternative approach.

=cut

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isHash,
    @rules );

  $parsed{default} ||= {};
  $parsed{columnType} ||= 'TEXT';

  return $class->__assertClass()->new(%parsed);
}

=pod

=back

=head1 PUBLIC INSTANCE METHODS

=over 4

=item * $hash->each($sub), yield(item, [item, ...]), emit(item, [item...])

Ruby-esque key iterator method. Returns a new L<Devel::Ladybug::Array>,
containing the yielded results of calling the received sub for each key
in $hash.

$hash->each is shorthand for $hash->keys->each, so you're really
calling C<each> in L<Devel::Ladybug::Array>. C<yield> and C<emit>
are exported by L<Devel::Ladybug::Array>. Please see the documentation
for Devel::Ladybug::Array regarding usage of C<each>, C<yield>, and
C<emit>.

  #
  # For example, quickly wrap <a> tags around array elements:
  #
  my $tagged = $object->each( sub {
    my $key = shift;

    print "Key $key is $object->{$key}\n";

    emit "<a name=\"$key\">$object->{$key}</a>";
  } );

=cut

sub each {
  my $self = shift;
  my $sub  = shift;

  return $self->keys()->each($sub);
}

=pod

=item * $self->keys()

Returns an L<Devel::Ladybug::Array> object containing self's alpha
sorted keys.

  my $hash = Devel::Ladybug::Hash->new(foo=>'alpha', bar=>'bravo');

  my $keys = $hash->keys();

  print $keys->join(','); # Prints out "bar,foo"

=cut

sub keys {
  my $self = shift;

  return Devel::Ladybug::Array->new( sort keys %{$self} );
}

=pod

=item * $self->values()

Returns an L<Devel::Ladybug::Array> object containing self's values,
alpha sorted by key.

  my $hash = Devel::Ladybug::Hash->new(foo=>'alpha', bar=>'bravo');

  my $values = $hash->values();

  print $values->join(','); # Prints out "bravo,alpha"

=cut

sub values {
  my $self = shift;

  return $self->keys()->each(
    sub {
      my $key = shift;

      yield( $self->{$key} );
    }
  );
}

=pod

=item * $self->set($key,$value);

Set the received instance variable. Extends
L<Devel::Ladybug::Object>::set to always use Devel::Ladybug::Hash and
L<Devel::Ladybug::Array> when it can.

  my $hash = Devel::Ladybug::Hash->new(foo=>'alpha', bar=>'bravo');

  $hash->set('bar', 'foxtrot'); # bar was "bravo", is now "foxtrot"

=cut

sub set {
  my $self  = shift;
  my $key   = shift;
  my @value = @_;

  my $class = $self->class();

  #
  # Call set() as a class method if $self was a class
  #
  return $self->SUPER::set( $key, @value )
    if !$class;

  my $type = $class->asserts()->{$key};

  return $self->SUPER::set( $key, @value )
    if !$type;

  throw Devel::Ladybug::InvalidArgument(
    "Too many args received by set(). Usage: set(\"$key\", VALUE)")
    if @value > 1;

  my $value = $value[0];

  my $valueType = ref($value);

  my $attrClass = $type->class()->get("objectClass");

  if ( defined($value)
    && ( !$valueType || !UNIVERSAL::isa( $value, $attrClass ) ) )
  {
    $value = $attrClass->new($value);
  }

  return $self->SUPER::set( $key, $value );
}

=pod

=item * $self->count

Returns the number of key/value pairs in self

=cut

### imported function size() is redef'd
do {
  no warnings "redefine";

  sub size {
    my $self = shift;

    warn "depracated usage, please use count() instead";

    return scalar( CORE::keys( %{$self} ) );
  }
};

sub count {
  my $self = shift;

  return scalar( CORE::keys( %{$self} ) );
}

###

=pod

=item * $self->isEmpty()

Returns true if self's count is 0, otherwise false.

=cut

sub isEmpty {
  my $self = shift;

  return $self->count() ? false : true;
}

=pod

=back

=head1 AVOIDING HASH ASSERTIONS

One might think to assert the Hash type in order to store hashtables
inside of objects in a free-form manner.

Devel::Ladybug could technically do this, but this documentation is
here to tell you not to. A recommended approach to associating
arbitrary key/value pairs with database-backed Devel::Ladybug objects
is provided below.

Do not do this:

  #
  # File: Example.pm
  #
  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    someInlineHash => Devel::Ladybug::Hash->assert()
  };

Rather, explicitly create a main class, and also an extrinsics class
which handles the association of linked values. Manually creating
linked classes in this manner is not as quick to code for or represent
in object form, but it mitigates the creation of deeply nested, complex
objects and "sprawling" sets of possible values which may arise from
systems with lots of users populating data. Something akin to the
following is the recommended approach:

  #
  # File: Example.pm
  #
  # This is the main class:
  #
  create "YourApp::Example" => {
    #
    # Assertions and methods here...
    #
  };

  #
  # File: Example/Attrib.pm
  #
  # This is where we tuck extrinsic attributes:
  #
  use Devel::Ladybug qw| :all |;
  use YourApp::Example;

  create "YourApp::Example::Attrib" => {
    exampleId => YourApp::Example->assert,

    elementKey => Devel::Ladybug::Str->assert(
      #
      # ...
      #
    ),

    elementValue => Devel::Ladybug::Str->assert(
      # Assert any vector or scalar Devel::Ladybug object class, as needed.
      #
      # Devel::Ladybug::Str can act as a catch-all for scalar values.
      #
      # ...
    ),
  }

An extension of this approach is to create multiple extrinsincs
classes, providing specific subtyping rules for different kinds of
key/value pairs. For example, one might create a table of linked values
which are always either true or false:

  #
  # File: Example: BoolAttrib.pm
  #

  use Devel::Ladybug qw| :all |;
  use YourApp::Example;

  create "YourApp::Example::BoolAttrib" => {
    exampleId => Devel::Ladybug::ExtId->assert( "YourApp::Example" ),

    elementKey => Devel::Ladybug::Str->assert( ),

    elementValue => Devel::Ladybug::Bool->assert( ),
  };
  
=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut

1;
