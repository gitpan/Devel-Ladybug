#
# File: lib/Devel/Ladybug/Scalar.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Scalar;

use strict;
use warnings;

use Devel::Ladybug::Class qw| true false |;

use overload
  fallback => true,
  '""'     => sub { shift->value() },
  'ne'     => sub {
  my $first  = shift;
  my $second = shift;

  "$first" ne "$second";
  },
  'eq' => sub {
  my $first  = shift;
  my $second = shift;

  "$first" eq "$second";
  },
  '==' => sub { shift eq shift },
  '!=' => sub { shift eq shift };

use base qw| Devel::Ladybug::Class::Dumper Devel::Ladybug::Object |;

=pod

=head1 NAME

Devel::Ladybug::Scalar - Scalar object class

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Object> to handle Perl scalar values as
Devel::Ladybug Objects.

=head1 INHERITANCE

This class inherits additional class and object methods from the
following packages:

L<Devel::Ladybug::Class> > L<Devel::Ladybug::Object> >
Devel::Ladybug::Scalar

=head1 SYNOPSIS

  use Devel::Ladybug::Scalar;

  {
    my $scalar = Devel::Ladybug::Scalar->new("Hello World");
    print "$scalar\n";

    # Hello World
  }

  {
    my $scalar = Devel::Ladybug::Scalar->new(5);
    my $result = $scalar + $scalar;
    print "$scalar + $scalar = $result\n";

    # 5 + 5 = 10
  }


=head1 PUBLIC CLASS METHODS

=over 4

=item * $class->new($scalar)

Instantiate a new Devel::Ladybug::Scalar. Accepts an optional scalar
value as a prototype object

Usage is cited in the SYNOPSIS section of this document.

=cut

sub new {
  my $class = shift;
  my $self  = shift;

# throw Devel::Ladybug::InvalidArgument("$class instances may not be undefined")
#  if !defined $self;

# Devel::Ladybug::Type::insist $self, Devel::Ladybug::Type::isScalar;

  if ( ref($self) && overload::Overloaded($self) ) {
    return bless $self, $class;    # ONE OF US NOW
  } elsif ( ref($self) ) {
    throw Devel::Ladybug::InvalidArgument(
      "$class->new() requires a non-ref arg, not a " . ref($self) );
  } else {
    return bless \$self, $class;
  }
}

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( sub { 1 },
    @rules );

  return $class->__assertClass()->new(%parsed);
}

=pod

=back

=head1 PUBLIC INSTANCE METHODS

=over 4

=item * $self->get()

Abstract method, not implemented.

Delegates to superclass if class method.

=cut

sub get {
  my $self = shift;
  my @args = @_;

  if ( $self->class() ) {
    my ( $package, $filename, $line ) = caller(1);

    throw Devel::Ladybug::MethodIsAbstract(
          "get() not implemented for scalars"
        . " (you asked for \""
        . join( ", ", @args )
        . "\" at $package:$line" );
  } else {
    return $self->SUPER::get(@args);
  }
}

=pod

=item * $self->set( )

Abstract method, not implemented.

Delegates to superclass if class method.

=cut

sub set {
  my $self = shift;
  my @args = @_;

  if ( $self->class() ) {
    throw Devel::Ladybug::MethodIsAbstract(
      "set() not implemented for scalars");
  } else {
    return $self->SUPER::set(@args);
  }
}

=pod

=item * $self->length

Object wrapper for Perl's built-in C<length()> function. Functionally
the same as C<length(@$ref)>.

  my $scalar = Devel::Ladybug::Scalar->new("Testing");

  my $length = $scalar->length(); # returns 7

=cut

### imported function size() is redef'd
do {
  no warnings "redefine";

  sub size {
    my $self = shift;

    warn "depracated usage, please use length() instead";

    return $self->length();
  }
};

###

=pod

=item * $self->isEmpty()

Returns a true value if self contains no values, otherwise false.

  my $array = Devel::Ladybug::Scalar->new("");

  if ( $self->isEmpty() ) {
    print "Is Empty\n";
  }

  # Expected Output:
  #
  # Is Empty
  #

=cut

sub isEmpty {
  my $self = shift;

  return ( $self->length() == 0 );
}

=pod

=item * $self->clear()

Truncate self to zero length.

=cut

sub clear {
  my $self = shift;

  ${$self} = "";

  return $self;
}

=pod

=item * $self->value()

Returns the actual de-referenced value of self. Same as ${ $self };

=cut

sub value {
  my $self = shift;

  return ${$self};
}

=pod

=item * $self->sprint()

Overrides superclass to sprint the actual de-referenced value of self.

=cut

sub sprint {
  my $self = shift;

  return "$self";
}

=pod

=item * $self->say()

Prints the de-referenced value of self with a line break at the end.

=cut

sub say {
  my $self = shift;

  $self->print();

  print "\n";
}

=back

=head1 SEE ALSO

L<perlfunc>

This file is part of L<Devel::Ladybug>.

=head1 REVISION

$Id: $

=cut

true;
