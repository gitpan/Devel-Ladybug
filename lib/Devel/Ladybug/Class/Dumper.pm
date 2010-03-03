#
# File: lib/Devel/Ladybug/Class/Dumper.pm
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

Devel::Ladybug::Class::Dumper - Class and object introspection mix-in

=head1 PUBLIC CLASS MIX-IN METHODS

=over 4

=cut

package Devel::Ladybug::Class::Dumper;

use strict;
use warnings;

use Devel::Ladybug::Enum::Bool;
use JSON::Syck;
use YAML::Syck;

$YAML::Syck::UseCode  = true;
$YAML::Syck::LoadCode = true;
$YAML::Syck::DumpCode = true;

=pod

=item * $class->members()

Return an Devel::Ladybug::Array containing the names of all valid messages (symbols)
in this class.

=cut

sub members {
  my $class = shift;

  return Devel::Ladybug::Array->new(
    Devel::Ladybug::Class::members($class) );
}

=pod

=item * $class->membersHash()

Return an Devel::Ladybug::Hash containing the CODE refs of all valid
messages in this class, keyed on message (symbol) name.

=cut

sub membersHash {
  my $class = shift;

  return Devel::Ladybug::Hash->new(
    Devel::Ladybug::Class::membersHash($class) );
}

=pod

=item * $class->asserts()

Returns all assertions for this class, including those which were
inherited.

  my $asserts = $class->asserts();

=cut

sub asserts {
  my $class = shift;

  my $asserts = $class->get('ASSERTS');

  if ( !$asserts ) {
    my %baseAsserts = %{ $class->__baseAsserts() };

    $asserts = Devel::Ladybug::Hash->new(%baseAsserts);   # Re-reference

    $class->set( 'ASSERTS', $asserts );
  }

  return $asserts;
}

=pod

=item * $class->__baseAsserts()

Returns the assertions which were inherited from the current class's
superclass.

=cut

sub __baseAsserts {
  my $class = shift;

  my $asserts = $class->get("__baseAsserts");

  if ( !defined $asserts ) {
    $asserts = Devel::Ladybug::Hash->new();

    for my $super ( $class->SUPER ) {
      next if !$super->isa("Devel::Ladybug::Object") || !$super->can("asserts");

      my $theseAsserts = $super->asserts || next;

      $theseAsserts->each( sub {
        my $key = shift;

        $asserts->{$key} = $theseAsserts->{$key};
      } );
    }

    $class->set( "__baseAsserts", $asserts );
  }

  return ( clone $asserts );
}

=pod

=back

=head1 PUBLIC INSTANCE MIX-IN METHODS

=over 4

=item * $self->sprint(), $self->toYaml()

Object introspection method.

Returns a string containing a YAML representation of the current object.

  $r->content_type('text/plain');

  $r->print($object->toYaml());

=cut

sub toYaml {
  my $self = shift;

  if ( !$self->isa("Devel::Ladybug::Hash") ) {
    return YAML::Syck::Dump($self);
  }

  return YAML::Syck::Dump( $self->escape );

  # return YAML::Syck::Dump($self);
}

sub sprint {
  my $self = shift;

  return $self->toYaml();
}

=pod

=item * $self->print()

Prints a YAML representation of the current object to STDOUT. 

=cut

sub print {
  my $self = shift;

  return CORE::print( $self->sprint() );
}

=pod

=item * $self->prettySprint();

Returns a nicely formatted string representing the contents of self

=cut

sub prettySprint {
  my $self = shift;

  my $str = "";

  print "-----\n";
  for my $key ( $self->class()->attributes() ) {
    my $prettyKey = $self->class()->pretty($key);

    my $value = $self->get($key) || "";

    print "$prettyKey: $value\n";
  }
}

=pod

=item * $self->prettyPrint();

Prints a nicely formatted string representing self to STDOUT

=cut

sub prettyPrint {
  my $self = shift;

  return CORE::print( $self->prettySprint() );
}

sub escape {
  my $self = shift;

  my $class = $self->class;

  return $self if !$class;

  my $asserts = $class->asserts;

  my $escaped;

  if ( $self->isa("Devel::Ladybug::Hash") && !$self->isa("Devel::Ladybug::Node") ) {
    $escaped = Devel::Ladybug::Hash->new;

    $self->each(
      sub {
        if ( UNIVERSAL::isa( $self->{$_}, "Devel::Ladybug::Object" ) ) {
          $escaped->{$_} = $self->{$_}->escape();
        } else {
          $escaped->{$_} = $self->{$_};
        }
      }
    );
  } elsif ( $self->isa("Devel::Ladybug::Array") ) {
    $escaped = $self->each(
      sub {
        if ( UNIVERSAL::isa( $_, "Devel::Ladybug::Object" ) ) {
          Devel::Ladybug::Array::yield( $_->escape() );
        } else {
          Devel::Ladybug::Array::yield($_);
        }
      }
    );
  } elsif (
    $self->isa("Devel::Ladybug::Scalar")
    || $self->isa("Devel::Ladybug::DateTime")     # Scalar-like
    || $self->isa("Devel::Ladybug::EmailAddr")    # Scalar-like
    )
  {
    $escaped = "$self";
  } else {
    $escaped = $self;
  }

  return ref($escaped)
    ? bless( $escaped, $class )
    : $escaped;
}

sub toJson {
  my $self = shift;

  return JSON::Syck::Dump( $self->escape() );
}

=pod

=back

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut

true;
