package Devel::Ladybug::Stream;

use strict;
use warnings;

use Devel::Ladybug::Class qw| true false |;

use base qw| Devel::Ladybug::Class::Dumper Devel::Ladybug::Object |;

use constant DefaultLimit => 50;

sub new {
  my $class      = shift;
  my $queryClass = shift;

  Devel::Ladybug::InvalidArgument->throw("Invalid Query Class")
    if !$queryClass || !UNIVERSAL::isa( $queryClass, "Devel::Ladybug::Node" );

  my $self = {
    queryClass => $queryClass,
    limit      => DefaultLimit,
    query      => $queryClass->__tupleStatement,
  };

  return bless $self, $class;
}

sub each {
  my $self    = shift;
  my $sub     = shift;
  my $asTuple = shift;

  my $queryClass = $self->queryClass;

  my $limit  = $self->limit             || DefaultLimit;
  my $offset = $self->offset            || 0;
  my $count  = $self->queryClass->count || 0;

  my $queryTemplate = $self->query;

  $queryTemplate .= '        limit %i offset %i';

  my $collected = Devel::Ladybug::Array->new;

  while ( $offset < $count ) {
    my $query = sprintf( $queryTemplate, $limit, $offset );

    my $array = $queryClass->selectMulti($query);

    my $thisCollected = $asTuple ? $array->eachTuple($sub) : $array->each($sub);

    $thisCollected->each(
      sub {
        $collected->push(shift);
      }
    );

    $offset += $limit;
  }

  return $collected;
}

sub eachTuple {
  my $self = shift;
  my $sub  = shift;

  return $self->each( $sub, true );
}

true;
__END__

=pod

=head1 NAME

Devel::Ladybug::Stream - Buffered list iteration for Devel::Ladybug tables

=head1 PUBLIC CLASS METHODS

=over 4

=item * $class->new($queryClass);

Use $queryClass->stream instead.

Create a new buffered stream, for iterating through results from
the received class.

=back

=head1 PUBLIC INSTANCE METHODS

=over 4

=item * $self->limit

Returns the current limit value.

=item * $self->setLimit($int)

Sets the maximum number of rows to query before asking the database
for the next chunk. Default is 50.

=item * $self->offset

Returns the current offset value.

=item * $self->setOffset($int)

Sets the starting row number. Default is 0.

This value grows by the C<limit> value each time a chunk is loaded.

=item * $self->queryClass

Returns the current query class

=item * $self->setQueryClass($newClass)

Sets the query class to the received value

=item * $self->query

Returns the current query fragment.

=item * $self->setQuery($newQuery)

Replaces the query fragment used to select from this table.

=item * $self->each(), $self->eachTuple()

These methods are wrappers and work-alikes to the same-named methods
in L<Devel::Ladybug::Array>.

=back

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut
