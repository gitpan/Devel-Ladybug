#
# File: lib/Devel/Ladybug/Array.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#

package Devel::Ladybug::Array::Break;

#
# Break may be thrown inside of each() subs to make Devel::Ladybug stop
# iterating through elements.
#

use strict;
use warnings;

use base qw/ Error::Simple /;

package Devel::Ladybug::Array::YieldedItems;

#
# YieldedItems are thrown by Devel::Ladybug::Array::yield()
#
# This is blatant abuse of Error.pm's ability to play tricks with
# the state of the interpreter... but it works so well!
#

use strict;
use warnings;

use base qw/ Error::Simple /;

sub new {
  my $class = shift;

  my $self = $class->SUPER::new( "", 0 );

  $self->{'-items'} = \@_;

  return $self;
}

sub items {
  my $self = shift;

  exists $self->{'-items'} ? @{ $self->{'-items'} } : undef;
}

package Devel::Ladybug::Array;

use strict;
use warnings;

=pod

=head1 NAME

Devel::Ladybug::Array - Array object class

=head1 DESCRIPTION

Extends L<Devel::Ladybug::Object> to handle Perl ARRAY refs as
Devel::Ladybug Objects. Provides constructor, getters, setters,
"Ruby-esque" collection, and other methods which one might expect an
Array object to respond to.

=head1 SYNOPSIS

  use Devel::Ladybug::Array;

  my $emptyList = Devel::Ladybug::Array->new();

  my $arrayFromList = Devel::Ladybug::Array->new(@list); # Makes new ref

  my $arrayFromRef = Devel::Ladybug::Array->new($ref);   # Keeps orig ref

=cut

use Math::VecStat;

use Error::Simple qw| :try |;

use Devel::Ladybug::Class qw| true false |;

use base
  qw| Exporter Devel::Ladybug::Class::Dumper Devel::Ladybug::Object |;

use overload
  '""' => sub { return shift },
  '==' => sub { compare(shift, shift) },
  'eq' => sub { compare(shift, shift) },
  '!=' => sub { !compare(shift, shift) },
  'ne' => sub { !compare(shift, shift) };

sub compare {
    my $first = shift;
    my $second = shift;

    if ( !UNIVERSAL::isa($first,"ARRAY") || !UNIVERSAL::isa($second,"ARRAY") ) {
      return false;
    }

    my $Asize = scalar(@{ $first });
    my $Bsize = scalar(@{ $second });

    if ( $Asize != $Bsize ) { return false; }

    my $i = 0;

    for ( @{ $first } ) {
      my $A = $first->[$i];
      my $B = $second->[$i];

      if (
        Scalar::Util::looks_like_number($A)
         && Scalar::Util::looks_like_number($B)
      ) {
        return false if "$A" != "$B";
      } else {
        return false if "$A" ne "$B";
      }
    }

    return true;
  };

our @EXPORT_OK = qw| yield emit break |;

sub value {
  my $self = shift;

  return @{$self};
}

=pod

=head1 METHODS

=head2 Public Class Methods

=over 4

=item * $class->new(@list)

Instantiate a new Devel::Ladybug::Array. Accepts an optional array or
array reference as a prototype object

Usage is cited in the SYNOPSIS section of this document.

=cut

sub new {
  my $class = shift;
  my @self  = @_;

  #
  # Received a single argument as self, and it was already a reference.
  #
  if ( @self
    && @self == 1
    && ref $self[0]
    && UNIVERSAL::isa( $self[0], 'ARRAY' ) )
  {
    return bless $self[0], $class;
  }

  #
  # Received an unreferenced array or nothing as self.
  #
  my $self = @self ? \@self : [];

  return bless $self, $class;
}

=pod

=item * $class->assert(Devel::Ladybug::Type $memberType, *@rules)

Return a new Devel::Ladybug::Type::Array instance.

To permit multiple values of a given type, just wrap an Array
assertion around any other assertion.

Each element in the stored array lives in a dynamically subclassed
linked table, with foreign key constraints against the parent table.

  #
  # File: Example.pm
  #

  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    #
    # An array of strings:
    #
    someArr => Devel::Ladybug::Array->assert(
      Devel::Ladybug::Str->assert()
    ),

    ...
  };

In Caller:

  #!/bin/env perl
  #
  # File: somecaller.pl
  #

  use strict;
  use warnings;

  use YourApp::Example;

  my $exa = YourApp::Example->spawn("Array Example");

  $exa->setSomeArr("Foo", "Bar", "Rebar", "D-bar");

  $exa->save();

B<Nested Arrays:> At the cost of performance, array assertions may
be nested. Each assert has independent rules:

  #
  # File: Example.pm
  #

  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    #
    # Fancy... a 3x3 matrix of integers with per-element enforcement of
    # min and max values:
    #
    matrix => Devel::Ladybug::Array->assert(
      Devel::Ladybug::Array->assert(
        Devel::Ladybug::Int->assert( subtype(
          min => 0,
          max => 255
        ) ),
        subtype(
          size => 3,
        ),
      ),
      subtype(
        size => 3
      )
    ),

    # ...
  };

In caller:

  #!/bin/env perl
  #
  # File: somecaller.pl
  #

  use strict;
  use warnings;

  use YourApp::Example;

  my $example = YourApp::Example->spawn("Matrix Example");

  #
  # Data looks like this:
  #
  $example->setMatrix(
    [255, 127, 63],
    [69,  69,  69]
    [42,  23,  5]
  );

  $example->save();

=cut

sub assert {
  my $class      = shift;
  my $memberType = shift;
  my @rules      = @_;

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isArray,
    @rules );

  $parsed{default} ||= [];
  $parsed{columnType} ||= "TEXT";
  $parsed{memberType} = $memberType;

  return $class->__assertClass()->new(%parsed);
}

=pod

=back

=head2 Public Instance Methods

=over 4

=item * $array->get($index)

Get the received array index. Functionally the same as $ref->[$index].

  my $array = Devel::Ladybug::Array->new( qw| foo bar | );

  my $foo = $array->get(0);
  my $bar = $array->get(1);

=cut

sub get {
  my $self  = shift;
  my $index = shift;

  if ( $self->class() ) {
    return $self->[$index];
  } else {
    return $self->SUPER::get($index);
  }
}

=pod

=item * $array->set($index, $value)

Set the received array index to the received value. Functionally the
same as $ref->[$index] = $value.

  my $array = Devel::Ladybug::Array->new( qw| foo bar | );

  $array->set(1, "rebar"); # was "bar", now is "rebar"

=cut

sub set {
  my $self  = shift;
  my $index = shift;
  my @value = @_;

  if ( $self->class() ) {
    throw Devel::Ladybug::RuntimeError("Extra args received by set()")
      if @value > 1;

    $self->[$index] = $value[0];
  } else {
    return $self->SUPER::set( $index, @value );
  }

  return true;
}

=pod

=item * $array->push(@list)

Object wrapper for Perl's built-in C<push()> function.  Functionally
the same as C<push(@$ref, @list)>.

  my $array = Devel::Ladybug::Array->new();

  $array->push($something);

  $array->push( qw| foo bar | );

=cut

sub push {
  my $self  = shift;
  my @value = @_;

  return push( @{$self}, @value );
}

=pod

=item * $array->count()

Object wrapper for Perl's built-in C<scalar()> function. Functionally
the same as C<scalar(@$ref)>.

  my $array = Devel::Ladybug::Array->new( qw| foo bar | );

  my $count = $array->count(); # returns 2

=cut

### imported function size() is redef'd
do {
  no warnings "redefine";

  # method size() {
  sub size {
    my $self = shift;

    warn "depracated usage, please use count() instead";

    return scalar( @{$self} );
  }
};

sub count {
  my $self = shift;

  return scalar( @{$self} );
}

=pod

=item * $array->each($sub)

=item * yield(item, [item, ...]), emit(item, [item, ...]), return, break

List iterator method. C<each> returns a new array with the results
of running the received CODE block once for every element in the
original. Returns the yielded/emitted results in a new
Devel::Ladybug::Array instance.

This Perl implementation of C<each> is borrowed from Ruby's
implementation of C<collect> and C<each>.

To finely control the flow of execution when iterating, several
functions may be used. These are C<yield>, C<emit>, C<break>, and
Perl's own C<return>. These are explained in greater detail in the
B<Collector Control Flow> section of this document.

This collector pattern is used throughout Devel::Ladybug. The following
pseudocode illustrates its possible usage.

  my $array = Devel::Ladybug::Array->new( ... );

  my $sub = sub {
    my $item = shift;

    # ...

    return if $something;       # Equivalent to next()

    break() if $somethingElse;  # Equivalent to last()

    emit($thing1, [$thing2, ...]);  # Upstreams $things,
                                    # and continues current iteration

    # ...

    yield($thing1, [$thing2, ...]); # Upstreams $things,
                                    # and skips to next iteration
  };
 
  my $results = $array->each($sub);

A simple working example - return a new array containing capitalized
versions of each element in the original.

  my $array = Devel::Ladybug::Array->new( qw|
    foo bar baz whiskey tango foxtrot
  | );

  my $capped = $array->each( sub {
    my $item = shift;

    yield uc($item)
  } );

  $capped->each( sub {
    my $item = shift;

    print "Capitalized array contains item: $item\n";
  } );


B<Collector Control Flow>

The flow of the C<each> sub may be controlled using C<return>,
C<yield>, C<emit>, and C<break>.

C<break> invokes Perl's C<last>, breaking execution of the C<each>
loop.

In the context of the C<each> sub, C<return> is like Perl's C<next> or
Javascript's C<continue>- that is, it stops execution of the sub in
progress, and continues on to the next iteration. Because Perl subs
always end with an implicit return, using C<return> to reap yielded
elements is not workable, so we use C<yield> for this instead. Any
arguments to C<return> in this context are ignored.

Like C<return>, C<yield> stops execution of the sub in progress, but
unlike C<return>, items passed as arguments to C<yield> are added
to the end of the returned array.

C<emit> adds items to the returned array, and then resumes execution
of the sub in progress. Emitted items are added to the array returned
by the C<each> sub, just like C<yield>, but you may call C<emit>
as many times as needed per iteration, without breaking execution.

If nothing is yielded or emitted by the C<each> sub in an iteration,
nothing will be added to the returned array for that item. To yield
nothing for an iteration, don't use C<yield>. If you must, use
C<return> instead to skip ahead to the next iteration, to avoid
undefined elements in the returned array.

If yielding multiple items at a time, they are added to the array
returned by C<each> in a "flat" manner-- that is, no array nesting
will occur unless the yielded data is explicitly structured as such.

B<Recap: Return vs Yield vs Emit>

C<yield> adds items to the array returned by the C<each> sub, in
addition to causing Perl to jump ahead to the next iteration, like
C<next> in a C<for> loop would. 

C<return> just returns without adding anything to the return array--
use it in cases where you
just want to  skip ahead without yielding items (ie C<next>).

  #
  # Create a new Array ($quoted) containing quoted elements
  # from the original, omitting items which aren't wanted.
  #
  my $quoted = $array->each( sub {
    my $item = shift;

    print "Have item: $item\n";

    return if $item =~ /donotwant/;

    yield( $myClass->quote($item) );

    print "You will never get here.\n";
  } );

  #
  # The above was roughly equivalent to:
  #
  my $quoted = Devel::Ladybug::Array->new();

  for my $item ( @{ $array } ) {
    print "Have item: $item\n";

    next if $item =~ /donotwant/;

    $quoted->push( $myClass->quote($item) );

    next;

    print "You will never get here.\n";
  }


C<emit> adds items to the array returned by the C<each> sub, but does
so without returning (that is, execution of the sub in progress will
continue uninterrupted). It's just like C<push>ing to an array from
inside a C<for> loop, because that's exactly what it does.

  #
  # For example, create a new Array ($quoted) containing quoted elements
  # from the original, omitting items which aren't wanted.
  #
  my $quoted = $array->each( sub {
    my $item = shift;

    print "Have item: $item\n";

    return if $item =~ /donotwant/;

    emit( $myClass->quote($item) );

    print "You will *always* get here!\n";
  } );

  #
  # The above was a more compact way of doing this:
  #
  my $quoted = Devel::Ladybug::Array->new();

  for ( @{ $array } ) {
    print "Have item: $_\n";

    next if $_ =~ /donotwant/;

    $quoted->push( $myClass->quote($_) );

    print "You will *always* get here!\n";
  }

C<each> provides the index integer as a second argument to the
received CODE block.

  my $new = $array->each( sub {
    my $item = shift;
    my $index = shift;

    print "Working on item $index: $item\n";
  } );

=cut

sub collect {
  my $self = shift;

  warn "depracated usage, please use each() instead";

  return $self->each(@_);
}

sub collectWithIndex {
  my $self = shift;

  warn "depracated usage, please use each() instead";

  return $self->each(@_);
}

sub each {
  my $self      = shift;
  my $sub       = shift;

  my $i = 0;

  local $Devel::Ladybug::Array::EmittedItems =
    Devel::Ladybug::Array->new();

  for ( @{$self} ) {
    local $Error::THROWN = undef;

    eval { &$sub( $_, $i ) };

    $i++;

    if ($@) {
      my $thrown = $Error::THROWN;

      if (
        $thrown
        && UNIVERSAL::isa(
          $thrown, "Devel::Ladybug::Array::YieldedItems"
        )
        )
      {
        $Devel::Ladybug::Array::EmittedItems->push( $thrown->items() );
      } elsif ( $thrown
        && UNIVERSAL::isa( $thrown, "Devel::Ladybug::Array::Break" ) )
      {

        #
        # "break" was called
        #
        last;
      } elsif ( $thrown && UNIVERSAL::isa( $thrown, "Error" ) ) {

        #
        # Rethrow
        #
        $thrown->throw();
      } else {

        #
        # Normal error encountered, just die
        #
        die $@;
      }
    }
  }

  return $Devel::Ladybug::Array::EmittedItems;
}

sub eachWithIndex {
  my $self = shift;

  warn "depracated usage, please use each() instead";

  return $self->each(@_);
}

# sub emit(*@results) {
sub emit {
  $Devel::Ladybug::Array::EmittedItems->push(@_);
}

# sub yield(*@results) {
sub yield {
  Devel::Ladybug::Array::YieldedItems->throw(@_);
}

sub break {
  Devel::Ladybug::Array::Break->throw("");
}

=pod

=item * $array->eachTuple($sub);

Shorthand iterator for multi-dimensional arrays.

  #
  # $array looks like:
  # [
  #   [ "adam", "0" ],
  #   [ "bob",  "1" ],
  #   [ "carl", "2" ],
  #   [ "dave", "3" ],
  # ]
  #

  $array->eachTuple( sub {
    my $first = shift;
    my $second = shift;
    # ...
  } );

  ###
  ### The above was shorthand for:
  ###
  # $array->each( sub {
  #   my $row = shift;
  #   my $first = $row->shift;
  #   my $second = $row->shift;
  #   ...
  # } );

=cut

sub eachTuple {
  my $self = shift;
  my $sub = shift;

  return $self->each( sub {
    my $row = shift;

    if ( UNIVERSAL::isa($row, "ARRAY") ) {
      &$sub(@{ $row });
    } else {
      &$sub($row);
    }
  } );
}

=pod

=item * $array->join($joinStr)

Object wrapper for Perl's built-in C<join()> function. Functionally the
same as C<join($joinStr, @{ $self })>.

  my $array = Devel::Ladybug::Array->new( qw| foo bar | );

  my $string = $array->join(','); # returns "foo,bar"

=cut

sub join {
  my $self   = shift;
  my $string = shift;

  return join( $string, @{$self} );
}

=pod

=item * $array->unshift()

Object wrapper for Perl's built-in C<unshift()> function. Functionally
the same as C<unshift(@{ $self })>.

  my $array = Devel::Ladybug::Array->new('bar');

  $array->unshift('foo'); # Array becomes ('foo', 'bar')

=cut

sub unshift {
  my $self = CORE::shift();

  return CORE::unshift( @{$self}, @_ );
}

=pod

=item * $array->rand()

Returns a pseudo-random array element.

  my $array = Devel::Ladybug::Array->new( qw| heads tails | );

  my $flip = $array->rand(); # Returns 'heads' or 'tails' randomly

=cut

sub rand {
  my $self = shift;

  return $self->[ rand( $self->count ) ];
}

=pod

=item * $array->isEmpty()

Returns a true value if self contains no values, otherwise false.

  my $array = Devel::Ladybug::Array->new();

  if ( $array->isEmpty() ) {
    print "Foo\n";
  }

  $array->push('anything');

  if ( $array->isEmpty() ) {
    print "Bar\n";
  }

  #
  # Expected Output:
  #
  # Foo
  #

=cut

sub isEmpty {
  my $self = shift;

  return ( $self->count() == 0 );
}

=pod

=item * $array->includes($value)

Returns a true value if self includes the received value, otherwise
false.

  my $array = Devel::Ladybug::Array->new( qw| foo bar | );

  for my $key ( qw| foo bar rebar | ) {
    next if $array->includes($key);

    print "$key does not belong here.\n";
  }

  #
  # Expected output:
  #
  # rebar does not belong here.
  #

=cut

sub includes {
  my $self = shift;
  my $item = shift;

  return grep { $_ eq $item } @{$self};
}

=pod

=item * $array->clear()

Removes all items, leaving self with zero array elements.

  my $array = Devel::Ladybug::Array->new( qw| foo bar | );

  my $two = $array->count(); # 2

  $array->clear();

  my $zero = $array->count(); # 0

=cut

sub clear {
  my $self = shift;

  # @{ $self } = ( );
  while ( @{$self} ) {
    $self->shift;
  }

  return $self;
}

=pod

=item * $array->purge()

Explicitly purges each item in self, leaving self with zero array
elements.

Useful in cases of arrays of CODE references, which are not otherwise
cleaned up by Perl's GC.

=cut

sub purge {
  my $self = shift;

  while (1) {
    $self->shift();

    last if $self->isEmpty();
  }

  return $self;
}

=pod

=item * $array->average()

Returns the average of all items in self.

  my $arr = Devel::Ladybug::Array->new( qw|
   54343 645564 89890 32 342 564564
  | );

  my $average = $arr->average();

  print "Avg: $average\n"; # Avg: 225789.166666667

=cut

sub average {
  my $self = shift;

  my $n = Math::VecStat::average( @{$self} );

  return $n;
}

=pod

=item * $array->median()

Returns the median value of all items in self.

  my $arr = Devel::Ladybug::Array->new( qw|
   54343 645564 89890 32 342 564564
  | );

  my $median = $arr->median();

  print "Med: $median\n"; # Med: 89890

=cut

sub median {
  my $self = shift;

  my $median = Math::VecStat::median( @{$self} );

  if ( defined $median ) {
    my $n = shift @{$median};

    return $n;
  } else {
    return;
  }
}

=pod

=item * $array->max()

Returns the highest value of all items in self.

  my $arr = Devel::Ladybug::Array->new( qw|
   54343 645564 89890 32 342 564564
  | );

  my $max = $arr->max();

  print "Max: $max\n"; # Max: 645564

=cut

do {
  no warnings "redefine";

  # method max() {
  sub max {
    my $self = shift;

    my $n = Math::VecStat::max($self);    # Avoid VecStat wantarray

    return $n;
  }
};

=pod

=item * $array->min()

Returns the lowest value of all items in self.

  my $arr = Devel::Ladybug::Array->new( qw|
   54343 645564 89890 32 342 564564
  | );
   
  my $min = $arr->min();

  print "Min: $min\n"; # Min: 32  

=cut

do {
  no warnings "redefine";

  # method min() {
  sub min {
    my $self = shift;

    my $n = Math::VecStat::min($self);    # Avoid VecStat wantarray

    return $n;
  }
};

=pod

=item * $array->sum()

Returns the sum of all items in self.

  my $arr = Devel::Ladybug::Array->new( qw|
   54343 645564 89890 32 342 564564
  | );

  my $sum = $arr->sum();

  print "Sum: $sum\n"; # Sum: 1354735

=cut

sub sum {
  my $self = shift;

  my $n = Math::VecStat::sum( @{$self} );

  return $n;
}

=pod

=item * $array->stddev()

Return the standard deviation of the current set.

  my $array = Devel::Ladybug::Array->new(2, 4, 4, 4, 5, 5, 7, 9);

  my $stddev = $array->stddev;
  # 2

=cut

sub stddev {
  my $self = shift;

  my $avg = $self->average;

  return sqrt(
    $self->each(
      sub {
        my $i = shift;

        Devel::Ladybug::Array::yield( ( $i - $avg )**2 );
      }
      )->average
  );
}

=pod

=item * $array->sort([$function])

Wrapper to Perl's built-in C<sort> function.

Accepts an optional argument, a sort function to be used. Sort function
should take $a and $b as arguments.

  my $alphaSort = $array->sort();

  my $numSort = $array->sort(sub{ shift() <=> shift() });
  
=cut

sub sort {
  my $self     = shift;
  my $function = shift;

  my $newSelf = $self->class()->new();

  if ($function) {
    @{$newSelf} = sort { &$function( $a, $b ) } @{$self};
  } else {
    @{$newSelf} = sort @{$self};
  }

  return $newSelf;
}

=pod

=item * $array->first()

Returns the first item in the array. Same as $array->[0].

  my $array = Devel::Ladybug::Array->new( qw| alpha larry omega | );

  print $array->first();
  print "\n";

  # Prints "alpha\n"

=cut

sub first {
  my $self = shift;

  return $self->isEmpty() ? undef : $self->[0];
}

=pod

=item * $array->last()

Returns the final item in the array. Same as $array->[-1].

  my $array = Devel::Ladybug::Array->new( qw| alpha larry omega | );

  print $array->last();
  print "\n";

  # Prints "omega\n"

=cut

sub last {
  my $self = shift;

  return $self->isEmpty() ? undef : $self->[-1];
}

=pod

=item * $array->uniq();

Returns a copy of self with duplicate elements removed.

=cut

sub uniq {
  my $self = shift;

  my %seen;

  my $class = $self->class();

  my $newSelf = $class->new();

  $self->each(
    sub {
      next if $seen{$_};
      $seen{$_}++;

      $newSelf->push($_);
    }
  );

  return $newSelf;
}

=pod

=item * $array->reversed();

Returns a copy of self with elements in reverse order

=cut

sub reversed {
  my $self = shift;

  my $reversed = $self->class->new;

  $self->each(
    sub {
      $reversed->unshift($_);
    }
  );

  return $reversed;
}

=pod

=item * $array->pop()

Object wrapper for Perl's built-in C<pop()> function. Functionally the
same as C<pop(@{ $self })>.

  my $array = Devel::Ladybug::Array->new( qw| foo bar rebar | );

  while ( my $element = $array->pop() ) {
    print "Popped $element\n";
  }

  if ( $array->isEmpty() ) { print "Now it's empty!\n"; }

  #
  # Expected output (note reversed order):
  #
  # Popped rebar
  # Popped bar
  # Popped foo
  # Now it's empty!
  #

=cut

sub pop {
  my $self = shift;

  return CORE::pop @{$self};
}

=pod

=item * $array->shift()

Object wrapper for Perl's built-in C<shift()> function. Functionally
the same as C<shift(@{ $self })>.

  my $array = Devel::Ladybug::Array->new( qw| foo bar | );

  while( my $element = $array->shift() ) {
    print "Shifted $element\n";
  }

  if ( $array->isEmpty() ) {
    print "Now it's empty!\n";
  }

  #
  # Expected output:
  #
  # Shifted foo
  # Shifted bar
  # Now it's empty!
  #

=cut

sub shift {
  my $self = CORE::shift();

  return CORE::shift( @{$self} );
}

=pod

=back

=head1 SEE ALSO

L<perlfunc>, L<Math::VecStat>

This file is part of L<Devel::Ladybug>.

=cut

true;
