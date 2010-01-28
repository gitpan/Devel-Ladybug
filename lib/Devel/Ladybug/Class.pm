#
# File: lib/Devel/Ladybug/Class.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Class;

##
## Pragma
##

use strict;
use warnings;

# use diagnostics;
#
# gentle stern harsh cruel brutal
#
# use criticism 'cruel';
use base qw| Exporter |;

##
## Package Constants
##

use constant DefaultSubclass => 'Devel::Ladybug::Node';

##
## Import Libraries
##

use Error qw| :try |;
use Devel::Ladybug::Enum::Bool;
use Devel::Ladybug::Enum::DBIType;
use Devel::Ladybug::Utility;
use Scalar::Util qw| blessed reftype |;

##
## Class Vars & Exports
##

our @EXPORT_OK = (
  qw|
    true false

    create
    |,
);

##
## Private Class Methods
##

#
#
#
sub __checkVarName {
  my $class   = shift;
  my $varName = shift;

  if ( $varName !~ /^[\w\_]{1,64}$/xsm ) {
    throw Devel::Ladybug::InvalidArgument(
      "Bad class var name \"$varName\" specified");
  }

  return true;
}

#
#
#
sub __init {
  my $class = shift;

  return true;
}

##
## Public Class Methods
##

#
#
#
sub create {
  my $class = shift;
  my $args  = shift;

  my $reftype = reftype($args);

  if ( !$reftype ) {
    throw Devel::Ladybug::InvalidArgument(
      "create() needs a HASH ref for an argument");
  }

  if ( $reftype ne 'HASH' ) {
    throw Devel::Ladybug::InvalidArgument(
      "create() needs a HASH ref for an argument, got: " . $reftype );
  }

  $args->{__BASE__} ||= DefaultSubclass;

  my $basereftype = reftype( $args->{__BASE__} );

  my @base;

  if ($basereftype) {
    if ( ( $basereftype eq 'SCALAR' )
      && overload::Overloaded( $args->{__BASE__} ) )
    {
      @base = "$args->{__BASE__}";    # Stringify
    } elsif ( $basereftype eq 'ARRAY' ) {
      @base = @{ $args->{__BASE__} };
    } else {
      throw Devel::Ladybug::InvalidArgument(
        "__BASE__ must be a string or ARRAY reference, not $basereftype"
      );
    }

  } else {
    @base = $args->{__BASE__};
  }

  #
  # Remove from list of actual class members:
  #
  delete $args->{__BASE__};

  for my $base (@base) {
    my $baselib = $base;
    $baselib =~ s/::/\//gxms;
    $baselib .= ".pm";

    eval { require $baselib };

    $base->import();
  }

  #
  # Stealth package allocation! This is about the same as:
  #
  #   eval "package $class; use base @base;"
  #
  # But does so without an eval.
  #
  do {
    no strict "refs";

    @{"$class\::ISA"} = @base;
  };

  for my $key ( keys %{$args} ) {
    my $arg = $args->{$key};

    if ( $key !~ /^__/xsm
      && blessed($arg)
      && $arg->isa("Devel::Ladybug::Type") )
    {

      #
      # Asserting an instance variable
      #
      # e.g. foo => Str(...)
      #
      $class->asserts()->{$key} = $arg;

    } elsif ( ref($arg) && reftype($arg) eq 'CODE' ) {

      #
      # Defining a method
      #
      # e.g. foo => sub { ... }
      #
      do {
        no strict "refs";

        *{"$class\::$key"} = $arg;
      };

    } elsif ( $key =~ /^__\w+$/xsm ) {

      #
      # Setting a class variable
      #
      # e.g. __foo => "Bario"
      #
      $class->set( $key, $arg );

    } else {
      throw Devel::Ladybug::ClassAllocFailed(
"$class member $key needs to be an Devel::Ladybug::Type instance or CODE ref"
      );
    }
  }

  $class->__init();

  return $class;
}

#
#
#
sub get {
  my $class = shift;
  my $key   = shift;

  $class->__checkVarName($key);

  my @value;

  do {
    no strict "refs";
    no warnings "once";

    @value = @{"$class\::$key"};
  };

  return wantarray() ? @value : $value[0];
}

#
#
#
sub members {
  my $class = shift;

  my @members;

  do {
    no strict 'refs';

    @members =
      grep { defined &{"$class\::$_"} } sort keys %{"$class\::"};
  };

  return \@members;
}

#
#
#
sub membersHash {
  my $class = shift;

  my %members;

  for my $key ( @{ $class->members() } ) {
    $members{$key} = \&{"$class\::$key"};
  }

  return \%members;
}

#
#
#
sub pretty {
  my $class = shift;
  my $key   = shift;

  my $pretty = $key;

  $pretty =~ s/(.)([A-Z])/$1 $2/gxsm;

  return ucfirst $pretty;
}

#
#
#
sub set {
  my $class = shift;
  my $key   = shift;
  my @value = @_;

  $class->__checkVarName($key);

  do {
    no strict "refs";
    no warnings "once";

    @{"$class\::$key"} = @value;
  };

  return true;
}

##
## End of package
##

true;

__END__

=pod

=head1 NAME

Devel::Ladybug::Class - Root-level "Class" class


=head1 SYNOPSIS

=head2 Class Allocation

  #
  # File: lib/Devel/Ladybug/Example.pm
  #
  use strict;
  use warnings;

  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    #
    # This is an empty class prototype
    #
  };

=head2 Class Consumer

  #
  # File: testscript.pl
  #
  use strict;
  use warnings;

  use YourApp::Example;

  my $exa = YourApp::Example->new();

  $exa->setName("Hello World");

  # This would also work:
  # $exa->set("name", "Hello World");
  #
  # or, just:
  # my $exa = YourApp::Example->new(name=>"Hello World");

  $exa->save();

  $exa->print();

=head1 DESCRIPTION

Devel::Ladybug::Class is the root-level parent class in Devel::Ladybug,
and also provides the class prototyping function C<create()>.


=head1 METHODS

=head2 Public Class Methods

=over 4

=item * C<get(Devel::Ladybug::Class $class: Str $key)>

Get the named class variable

  my $class = "YourApp::Example";

  my $scalar = $class->get($key);

  my @array = $class->get($key);

  my %hash = $class->get($key);


=item * C<set(Devel::Ladybug::Class $class: Str $key, *@value)>

Set the named class variable to the received value

  my $class = "YourApp::Example";

  $class->set($key, $scalar);

  $class->set($key, @array);

  $class->set($key, %hash);


=item * C<pretty(Devel::Ladybug::Class $class: Str $key)>

Transform camelCase to Not Camel Case

  my $class = "YourApp::Example";

  my $uglyStr = "betterGetThatLookedAt";

  my $prettyStr = $class->pretty($uglyStr);


=item * C<members(Devel::Ladybug::Class $class:)>

Class introspection method.

Return an array ref of all messages supported by this class.

Does not include messages from superclasses.

  my $members = YourApp::Example->members();


=item * C<membersHash(Devel::Ladybug::Class $class:)>

Class introspection method.

Return a hash ref of all messages supported by this class.

Does not include messages from superclasses.

  my $membersHash = YourApp::Example->membersHash();


=back

=head2 Private Class Methods

=over 4

=item * C<init(Devel::Ladybug::Class $class:)>

Abstract callback method invoked immediately after a new class is
allocated via create().

Override in subclass with additional logic, if necessary.


=item * C<__checkVarName(Devel::Ladybug::Class $class: Str $varName)>

Checks the "safeness" of a class variable name.


=back


=head1 PROTOTYPE COMPONENTS

=head2 Class (Package) Name

The B<name> of the class being created is the first argument sent to
C<create()>.

  use Devel::Ladybug qw| :all |;

  #
  # The class name will be "YourApp::Example":
  #
  create "YourApp::Example" => {

  };

=head2 Class Prototype

A B<class prototype> is a hash describing all fundamental
characteristics of an object class. It's the second argument sent to
C<create()>.

  create "YourApp::Example" => {
    #
    # This is an empty prototype (perfectly valid)
    #
  };

=head2 Instance Variables

Instance variables are declared with the C<assert> class method:

  create "YourApp::Example" => {
    favoriteNumber => Devel::Ladybug::Int->assert()

  };

The allowed values for a given instance variable may be specified as
arguments to the C<assert> method.

Instance variables may be augmented with subtyping rules using the
C<subtype> function, which is also sent as an argument to C<assert>.
See Devel::Ladybug::Subtype for a list of allowed subtype arguments.

  create "YourApp::Example" => {
    favoriteColor  => Devel::Ladybug::Str->assert(
      qw| red green blue |,
      subtype(
        optional => true
      )
    ),
  };


=head2 Instance Methods

Instance methods are declared as keys in the class prototype. The name
of the method is the key, and its value in the prototype is a Perl 5
C<sub{}>.

  create "YourApp::Example" => {
    #
    # Add a public instance method, $self->handleFoo()
    #
    handleFoo => sub {
      my $self = shift;

      printf 'The value of foo is %s', $self->foo();
      print "\n";

      return true;
    }
  }

  my $exa = YourApp::Example->new();

  $exa->setFoo("Bar");

  $exa->handleFoo();

  #
  # Expected output:
  #
  # The value of foo is Bar
  #

The Devel::Ladybug convention for private or protected instance methods
is to prefix them with a single underscore.

  create "YourApp::Example" => {
    #
    # private instance method
    #
    _handleFoo => sub {
      my $self = shift;

      say "The value of foo is $self->{foo}";
    }
  };

=head2 Class Variables

Class variables are declared as keys in the class prototype. They
should be prepended with double underscores (__). The value in the
prototype is the literal value to be used for the class variable.

  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    #
    # Override a few class variables
    #
    __useYaml => false,
    __dbiType => Devel::Ladybug::DBIType::MySQL
  };

Devel::Ladybug class variables are just Perl package variables, scoped
in list context.

=head2 Class Methods

Class methods are declared in the same manner as instance methods. The
only difference is that the class will be the receiver.

  create "YourApp::Example" => {
    #
    # Add a public class method
    #
    loadXml => sub {
      my $class = shift;
      my $xml = shift;

      # ...
    }
  };

The Devel::Ladybug convention for private or protected class methods is
to prefix them with double underscores.

  create "YourApp::Example" => {
    #
    # Override a private class method
    #
    __basePath => sub {
      my $class = shift;

      return join('/', '/tmp', $class);
    }
  };

=head2 Inheritance

By default, classes created with C<create()> inherit from
L<Devel::Ladybug::Node>. To override this, include a C<__BASE__>
attribute, specifying the parent class name.

  create "YourApp::Example" => {
    #
    # Override parent class
    #
    __BASE__ => "Acme::CustomClass"
  };


=head1 OPTIONAL EXPORTS

=head2 Constants

=over 4

=item * C<true>, C<false>

Constants provided by L<Devel::Ladybug::Enum::Bool>

=back

=head2 Functions

=over 4

=item * C<create(Str $class: Hash $prototype)>

Allocate a new Devel::Ladybug-derived class.

Objects instantiated from classes allocated with C<create()> have
built-in runtime assertions-- simple but powerful rules in the class
prototype which define runtime and schema attributes. See the
L<Devel::Ladybug::Type> module for more about assertions.

Devel::Ladybug classes are regular old Perl packages. C<create()> is
just a wrapper to the C<package> keyword, with some shortcuts thrown
in.

  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    __someClassVar => true,

    someInstanceVar => Devel::Ladybug::Str->assert(),

    anotherInstanceVar => Devel::Ladybug::Str->assert(),

    publicInstanceMethod => sub {
      my $self = shift;

      # ...
    },

    _privateInstanceMethod => sub {
      my $self = shift;

      # ...
    },

    publicClassMethod => sub {
      my $class = shift;

      # ...
    },

    __privateClassMethod => sub {
      my $class = shift;

      # ...
    },
  };

=back

=head1 SEE ALSO

L<Devel::Ladybug::Type>, L<Devel::Ladybug::Subtype>

This file is part of L<Devel::Ladybug>.

=cut
