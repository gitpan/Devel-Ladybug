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

=cut

sub assert {
  my $class = shift;
  my @rules = @_;

  Devel::Ladybug::MethodIsAbstract->throw("Hash is not an assertable type");
}

=pod

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

    yield("<a name=\"$key\">$object->{$key}</a>");
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

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut

1;
