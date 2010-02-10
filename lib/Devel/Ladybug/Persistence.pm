#
# File: lib/Devel/Ladybug/Persistence.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::TextIndex;

use strict;
use warnings;

use base qw| DBIx::TextIndex |;

#
#
#
sub remove {
  my $self = shift;

  return if ref( $_[0] ) && !$_->[0];

  $self->SUPER::remove(@_);
}

package Devel::Ladybug::Persistence;

=pod

=head1 NAME

Devel::Ladybug::Persistence - Serialization mix-in

=head1 DESCRIPTION

Configurable class mix-in for storable Devel::Ladybug objects.

This package will typically be used indirectly. Subclasses created
with Devel::Ladybug's C<create> function will respond to these
methods by default.

Connection settings are controlled via C<.ladybugrc> (See
L<Devel::Ladybug::Constants>), or may be overridden on a per-class
basis (See C<__dbHost> or C<__dbUser>, in this document).

Database and table names are automatically derived, but may be
overridden on a per-class basis (See C<databaseName> or C<tableName>,
in this document).

See C<__use[Feature]>, in this document, for directions on how to
disable or augment specific backing store options when subclassing.

=cut

use strict;
use warnings;

#
# Third-party packages
#
use Cache::Memcached::Fast;
use Carp::Heavy;
use Clone qw| clone |;
use Error qw| :try |;
use File::Copy;
use File::Path;
use File::Find;
use IO::File;
use JSON::Syck;
use Rcs;
use Sys::Hostname;
use Time::HiRes qw| time |;
use YAML::Syck;

#
# Devel::Ladybug
#
use Devel::Ladybug::Class qw| create true false |;
use Devel::Ladybug::Constants qw|
  yamlHost yamlRoot scratchRoot sqliteRoot
  dbHost dbPass dbPort dbUser
  memcachedHosts
  rcsBindir rcsDir
  |;
use Devel::Ladybug::StorageType;
use Devel::Ladybug::Exceptions;
use Devel::Ladybug::Stream;
use Devel::Ladybug::Utility;

#
# Devel::Ladybug Object Classes
#
use Devel::Ladybug::Array;
use Devel::Ladybug::ID;
use Devel::Ladybug::Str;
use Devel::Ladybug::Int;
use Devel::Ladybug::DateTime;
use Devel::Ladybug::Name;

use Devel::Ladybug::Type;

use Devel::Ladybug::Redefines;

#
# RCS setup
#
Rcs->arcext(',v');
Rcs->bindir(rcsBindir);
Rcs->quiet(true);

#
# Class variable and memcached setup
#
our ( $dbi, $memd, $transactionLevel, $errstr );

if ( memcachedHosts
  && ref(memcachedHosts)
  && ref(memcachedHosts) eq 'ARRAY' )
{
  $memd = Cache::Memcached::Fast->new( { servers => memcachedHosts } );

  # $Storable::Deparse = true;
}

#
# Package constants
#
use constant DefaultPrimaryKey => "id";

=pod

=head1 PUBLIC CLASS METHODS

=over 4

=item * $class->load($id)

Retrieve an object by ID from the backing store.

This method will delegate to the appropriate private backend method. It
returns the requested object, or throws an exception if the object was
not found.

  my $object;

  try {
    $object = $class->load($id);
  } catch Error with {
    # ...

  };

=cut

sub load {
  my $class = shift;
  my $id    = shift;

  return $class->__localLoad( $class->__primaryKeyClass->new($id) );
}

=pod

=item * $class->query($query)

Runs the received query, and returns a statement handle which may be
used to iterate through the query's result set.

Reconnects to database, if necessary.

  sub($) {
    my $class = shift;

    my $query = sprintf(
      q| SELECT id FROM %s where foo like "%bar%" |,
      $class->tableName()
    );

    my $sth = $class->query($query);

    while ( my ( $id ) = $sth->fetchrow_array() ) {
      my $obj = $class->load($id);

      # ...
    }

    $sth->finish();
  }

=cut

sub query {
  my $class = shift;
  my $query = shift;

  return $class->__wrapWithReconnect( sub { return $class->__query($query) } );
}

=pod

=item * $class->write($query)

Runs the received query against the database, using the DBI do()
method. Returns number of rows updated.

Reconnects to database, if necessary.

  sub($$) {
    my $class = shift;
    my $value = shift;

    my $query = sprintf('update %s set foo = %s',
      $class->tableName(), $class->quote($value)
    )

    return $class->write($query);
  }

=cut

sub write {
  my $class = shift;
  my $query = shift;

  return $class->__wrapWithReconnect( sub { return $class->__write($query) } );
}

=pod

=item * $class->search($hash)

Wrapper to L<DBIx::TextIndex>'s full-text C<search> method.

Returns a L<Devel::Ladybug::Hash> of hit IDs, or C<undef> if the class
contains no indexed fields.

Attributes which are asserted as C<indexed> will be automatically
added to the class's fulltext index at save time. This is not
recommended for frequently changing data.

  #
  # In class YourApp/SearchExample.pm:
  #
  use Devel::Ladybug qw| :all |;

  create "YourApp::SearchExample" => {
    field1 => Devel::Ladybug::Str->assert(
      subtype( indexed => true )
    ),
    field2 => Devel::Ladybug::Str->assert(
      subtype( indexed => true )
    ),
  };

Meanwhile...

  #
  # In caller, mysearch.pl:
  #
  use YourApp::SearchExample;

  my $class = "YourApp::SearchExample";

  #
  # See DBIx::TextIndex
  #
  my $ids = $class->search({
    field1 => '+andword -notword orword "phrase words"',
    field2 => 'more words',
  });

  #
  # Or, just provide a string:
  #
  # my $ids = $class->search("hello world");

  $ids->each( sub {
    my $id = shift;

    my $obj = $class->load($id);
  } );

=cut

sub search {
  my $class = shift;
  my $query = shift || return;

  my $index = $class->__textIndex;

  return if !$index;

  if ( !ref($query) ) {
    my $text = $query;
    $query = {};
    $class->__indexedFields->each(
      sub {
        my $field = shift;

        $query->{ lc($field) } = $text;
      }
    );
  } else {
    my $lcQuery = {};

    for my $field ( keys %{$query} ) {
      $lcQuery->{ lc($field) } = $query->{field};
    }

    $query = $lcQuery;
  }

  return Devel::Ladybug::Hash->new( $index->search($query) );
}

=pod

=item * $class->selectScalar($query)

Returns the results of the received query, as a singular scalar value.

=cut

sub selectScalar {
  my $class = shift;
  my $query = shift;

  return Devel::Ladybug::Scalar->new( $class->selectSingle($query)->shift );
}

=pod

=item * $class->selectBool($query)

Returns the results of the received query, as a binary true or false
value.

=cut

sub selectBool {
  my $class = shift;
  my $query = shift;

  return $class->selectScalar($query) ? true : false;
}

sub __selectBool {
  warn "Depracated usage; please use selectBool";

  return selectBool(@_);
}

=pod

=item * $class->selectSingle($query)

Returns the first row of results from the received query, as a
one-dimensional Devel::Ladybug::Array.

  sub($$) {
    my $class = shift;
    my $name = shift;

    my $query = sprintf( q|
        SELECT mtime, ctime FROM %s WHERE name = %s
      |,
      $class->tableName(), $class->quote($name)
    );

    return $class->selectSingle($query);
  }

  #
  # Flat array of selected values, ie:
  #
  #   [ *userId, *ctime ]
  #

=cut

sub selectSingle {
  my $class = shift;
  my $query = shift;

  my $sth = $class->query($query);

  my $out = Devel::Ladybug::Array->new();

  while ( my @row = $sth->fetchrow_array() ) {
    $out->push(@row);
  }

  $sth->finish();

  return $out;
}

sub __selectSingle {
  warn "Depracated usage; please use selectSingle";

  return selectSingle(@_);
}

=pod

=item * $class->selectMulti($query)

Returns each row of results from the received query, as a
one-dimensional Devel::Ladybug::Array.

  my $query = "SELECT userId FROM session";

  #
  # Flat array of User IDs, ie:
  #
  #   [
  #     *userId,
  #     *userId,
  #     ...
  #   ]
  #
  my $userIds = $class->selectMulti($query);


Returns a two-dimensional Devel::Ladybug::Array of
Devel::Ladybug::Arrays, if * or multiple columns are specified in the
query.

  my $query = "SELECT userId, mtime FROM session";

  #
  # Array of arrays, ie:
  #
  #   [
  #     [ *userId, *mtime ],
  #     [ *userId, *mtime ],
  #     ...
  #   ]
  #
  my $idsWithTime = $class->selectMulti($query);

=cut

sub selectMulti {
  my $class = shift;
  my $query = shift;

  my $sth = $class->query($query);

  my $results = Devel::Ladybug::Array->new();

  while ( my @row = $sth->fetchrow_array() ) {
    $results->push( @row > 1 ? Devel::Ladybug::Array->new(@row) : $row[0] );
  }

  $sth->finish();

  return $results;
}

sub __selectMulti {
  warn "Depracated usage; please use selectMulti";

  return selectMulti(@_);
}

=pod

=item * $class->allIds()

Returns a L<Devel::Ladybug::Array> of all IDs in the receiving class.

  my $ids = $class->allIds();

  #
  # for loop way
  #
  for my $id ( @{ $ids } ) {
    my $object = $class->load($id);

    # Stuff ...
  }

  #
  # collector way
  #
  $ids->each( sub {
    my $object = $class->load($_);

    # Stuff ...
  } );

=cut

sub allIds {
  my $class = shift;

  if ( $class->__useFlatfile() && !$class->__useDbi() ) {
    return $class->__fsIds();
  }

  my $sth = $class->__allIdsSth();

  my $ids = Devel::Ladybug::Array->new();

  while ( my ($id) = $sth->fetchrow_array() ) {
    $ids->push($id);
  }

  $sth->finish();

  return $ids;
}

=pod

=item * $class->count;

Returns the number of rows in this class's backing store.

=cut

sub count {
  my $class = shift;

  if ( $class->__useFlatfile && !$class->__useDbi ) {
    return $class->allIds->count;
  }

  return $class->selectScalar($class->__countStatement);
}

=pod

=item * $class->stream

Returns a L<Devel::Ladybug::Stream> of all IDs and Names in this table.

  my $stream = $class->stream;

  $stream->eachTuple( sub {
    my $id = shift;
    my $name = shift;

    print "Have ID $id, Name $name\n";
  } );

=cut

sub stream {
  my $class = shift;
  my $sub = shift;

  my $stream = Devel::Ladybug::Stream->new($class);

  return $stream;
}

=pod

=item * $class->each

Iterator for each ID in the current class.

See collector usage in L<Devel::Ladybug::Array> docs.

  $class->each( sub {
    my $id = shift;

    my $obj = $class->load($id);
  } );

=cut

sub each {
  my $class = shift;
  my $sub = shift;

  #
  # Delegate for instance method usage:
  #
  return Devel::Ladybug::Hash::each($class, $sub) if $class->class;

  if ( $class->__useFlatfile && !$class->__useDbi ) {
    return $class->allIds->each($sub);
  }

  my $stream = $class->stream;

  $stream->setQuery( $class->__allIdsStatement );

  return $stream->eachTuple($sub);
}

=pod

=item * $class->tuples

Returns a L<Devel::Ladybug::Array> of all IDs and Names in this table.

  my $tuples = $class->tuples;

  $tuples->eachTuple( sub {
    my $id = shift;
    my $name = shift;

    print "Have ID $id, Name $name\n";
  } );

=cut

sub tuples {
  my $class = shift;

  if ( $class->__useFlatfile && !$class->__useDbi ) {
    Devel::Ladybug::MethodIsAbstract->throw(
      "tuples method not yet implemented for YAML backing stores"
    );
  }

  return $class->selectMulti($class->__tupleStatement);
}

=pod

=item * $class->memberClass($attribute)

Only usable for foreign keys.

Returns the class of object referenced by the named attribute.

  #
  # In a class prototype, there was an ExtID assertion:
  #

  # ...
  use YourApp::OtherClass;
  use YourApp::AnotherClass;

  create "YourApp::Example" => {
    #
    # OtherClass asserts ExtID by default:
    #
    userId => YourApp::OtherClass->assert,

    #
    # This is a one-to-many ExtID assertion:
    #
    categoryId => Devel::Ladybug::Array->assert(
      YourApp::AnotherClass->assert
    ),

    # ...
  };


Meanwhile, in caller...

  # ...
  use YourApp::Example;

  my $class = "YourApp::Example";

  my $exa = $class->load("Foo");

  do {
    # Ask for the foreign class, eg "YourApp::OtherClass":
    my $memberClass = $class->memberClass("userId");

    # Use the persistence methods in the foreign class:
    my $user = $memberClass->load($exa->userId());

    $user->print;
  };

One-to-many example:

  do {
    # Ask for the foreign class, eg "YourApp::AnotherClass":
    my $memberClass = $class->memberClass("categoryId");

    # Use the persistence methods in the foreign class:
    $exa->categoryId->each( sub {
      my $memberId = shift;

      my $category = $memberClass->load($memberId);

      $category->print;
    } );
  };

=cut

sub memberClass {
  my $class = shift;
  my $key   = shift;

  throw Devel::Ladybug::AssertFailed("$key is not a member of $class")
    if !$class->isAttributeAllowed($key);

  my $type = $class->asserts->{$key}->externalClass;
}

=pod

=item * $class->doesIdExist($id)

Returns true if the received ID exists in the receiving class's table.

=cut

sub doesIdExist {
  my $class = shift;
  my $id    = shift;

  if ( $class->__useDbi ) {
    return $class->selectBool(
      $class->__doesIdExistStatement( $class->__primaryKeyClass->new($id) ) );
  } else {
    my $path =
      join( "/", $class->__basePath,
      Devel::Ladybug::ID->new($id)->as_string() );

    return -e $path;
  }
}

=pod

=item * $class->doesNameExist($name)

Returns true if the received ID exists in the receiving class's table.

  my $name = "Bob";

  my $object = $class->doesNameExist($name)
    ? $class->loadByName($name)
    : $class->new( name => $name, ... );

=cut

sub doesNameExist {
  my $class = shift;
  my $name  = shift;

  return $class->selectBool( $class->__doesNameExistStatement($name) );
}

#
# Override
#
sub pretty {
  my $class = shift;
  my $key   = shift;

  my $pretty = $key;

  $pretty =~ s/(.)([A-Z])/$1 $2/gxsm;

  $pretty =~ s/(\s|^)Id(\s|$)/${1}ID${2}/gxsmi;
  $pretty =~ s/(\s|^)Ids(\s|$)/${1}IDs${2}/gxsmi;
  $pretty =~ s/^Ctime$/Creation Time/gxsmi;
  $pretty =~ s/^Mtime$/Modified Time/gxsmi;

  return ucfirst $pretty;
}

=pod

=item * $class->loadByName($name)

Loader for named objects. Works just as load().

  my $object = $class->loadByName($name);

=cut

sub loadByName {
  my $class = shift;
  my $name  = shift;

  if ( !$name ) {
    my $caller = caller();

    throw Devel::Ladybug::InvalidArgument(
      "BUG (Check $caller): empty name sent to loadByName(\$name)");
  }

  my $id = $class->idForName($name);

  if ( defined $id ) {
    return $class->load($id);
  } else {
    my $table = $class->tableName();
    my $db    = $class->databaseName();

    ### old way
    # warn "Object name \"$name\" does not exist in table $db.$table";
    # return undef;

    throw Devel::Ladybug::ObjectNotFound(
      "Object name \"$name\" does not exist in table $db.$table");
  }
}

=pod

=item * $class->spawn($name)

Loader for named objects. Works just as load(). If the object does not
exist on backing store, a new object with the received name is
returned.

  my $object = $class->spawn($name);

=cut

sub spawn {
  my $class = shift;
  my $name  = shift;

  my $id = $class->idForName($name);

  if ( defined $id ) {
    return $class->load($id);
  } else {
    my $self = $class->proto;

    $self->setName($name);

    # $self->save(); # Let caller do this

    my $key = $class->__primaryKey();

    return $self;
  }
}

=pod

=item * $class->idForName($name)

Return the corresponding row id for the received object name.

  my $id = $class->idForName($name);

=cut

sub idForName {
  my $class = shift;
  my $name  = shift;

  return $class->selectSingle( $class->__idForNameStatement($name) )->shift;
}

=pod

=item * $class->nameForId($id)

Return the corresponding name for the received object id.

  my $name = $class->nameForId($id);

=cut

sub nameForId {
  my $class = shift;
  my $id    = shift;

  return $class->selectSingle(
    $class->__nameForIdStatement( $class->__primaryKeyClass->new($id) ) )
    ->shift;
}

=pod

=item * $class->allNames()

Returns a list of all object ids in the receiving class. Requires DBI.

  my $names = $class->allNames();

  $names->each( sub {
    my $object = $class->loadByName($_);

    # Stuff ...
  } );

=cut

sub allNames {
  my $class = shift;

  if ( !$class->__useDbi() ) {
    throw Devel::Ladybug::MethodIsAbstract(
      "Sorry, allNames() requires a DBI backing store");
  }

  my $sth = $class->__allNamesSth();

  my $names = Devel::Ladybug::Array->new();

  while ( my ($name) = $sth->fetchrow_array() ) {
    $names->push($name);
  }

  $sth->finish();

  return $names;
}

=pod

=item * $class->quote($value)

Returns a DBI-quoted (escaped) version of the received value. Requires
DBI.

  my $quoted = $class->quote($hairy);

=cut

sub quote {
  my $class = shift;
  my $value = shift;

  return $class->__dbh()->quote($value);
}

=pod

=item * $class->databaseName()

Returns the name of the receiving class's database. Corresponds to the
lower-cased first-level Perl namespace, unless overridden in subclass.

  do {
    #
    # Database name is "yourapp"
    #
    my $dbname = YourApp::Example->databaseName();
  };

=cut

sub databaseName {
  my $class = shift;

  my $dbName = $class->get("__databaseName");

  if ( !$dbName ) {
    if ( $class =~ /Devel::Ladybug::/ ) {
      $dbName = 'ladybug';
    } else {
      $dbName = lc($class);
      $dbName =~ s/:.*//;
    }

    $class->set( "__databaseName", $dbName );
  }

  return $dbName;
}

=pod

=item * $class->tableName()

Returns the name of the receiving class's database table. Corresponds
to the second-and-higher level Perl namespaces, using an underscore
delimiter.

Will probably want to override this, if subclass lives in a deeply
nested namespace.

  do {
    #
    # Table name is "example"
    #
    my $table = YourApp::Example->tableName();
  };

  do {
    #
    # Table name is "example_job"
    #
    my $table = YourApp::Example::Job->tableName();
  };

=cut

sub tableName {
  my $class = shift;

  my $tableName = $class->get("__tableName");

  if ( !$tableName ) {
    $tableName = $class;

    if ( $class =~ /Devel::Ladybug::/ ) {
      $tableName =~ s/Devel::Ladybug:://;
    } else {
      $tableName =~ s/.*?:://;
    }

    $tableName =~ s/::/_/g;
    $tableName = lc($tableName);

    $class->set( "__tableName", $tableName );
  }

  return $tableName;
}

=pod

=item * $class->loadYaml($string)

Load the received string containing YAML into an instance of the
receiving class.

Warns and returns undef if the load fails.

  my $string = q|---
  foo: alpha
  bar: bravo
  |;

  my $object = $class->loadYaml($string);

=cut

sub loadYaml {
  my $class = shift;
  my $yaml  = shift;

  throw Devel::Ladybug::InvalidArgument("Empty YAML stream received")
    if !$yaml;

  my $hash;

  eval {
    $hash = YAML::Syck::Load($yaml) || die $@;
  };

  throw Devel::Ladybug::DataConversionFailed($@) if $@;

  return $class->new($hash);
}

=pod

=item * $class->loadJson($string)

Load the received string containing JSON into an instance of the
receiving class.

Warns and returns undef if the load fails.

=cut

sub loadJson {
  my $class = shift;
  my $json  = shift;

  throw Devel::Ladybug::InvalidArgument("Empty YAML stream received")
    if !$json;

  my $hash = JSON::Syck::Load($json);

  throw Devel::Ladybug::DataConversionFailed($@) if $@;

  return $class->new($hash);
}

=pod

=item * $class->restore($id, [$version]);

Returns the object with the received ID from the RCS backing store.
Does not call C<save>, caller must do so explicitly.

Uses the latest RCS revision if no version number is provided.

  do {
    my $self = $class->restore("LmBkxTee3hGGZgM418LRwQ==", "1.1");

    $self->save("Restoring from RCS archive");
  };

=cut

sub restore {
  my $class   = shift;
  my $id      = shift;
  my $version = shift;

  if ( !$id ) {
    Devel::Ladybug::InvalidArgument->throw("No ID received");
  }

  if ( !$class->__useRcs() ) {
    Devel::Ladybug::RuntimeError->throw(
      "$class instances do not have RCS history");
  }

  my $self = $class->proto;
  $self->setId($id);

  return $self->revert($version);
}

=pod

=back

=head1 PRIVATE CLASS METHODS

The __use<Feature> methods listed below can be overridden simply by
setting a class variable with the same name, as the examples
illustrate.

=over 4

=item * $class->__useFlatfile()

Return a true value or constant value from
L<Devel::Ladybug::StorageType>, to maintain a flatfile backend for
all saved objects.

Default inherited value is auto-detected for the local system. Set
class variable to override.

Flatfile and DBI backing stores are not mutually exclusive. Classes
may use either, both, or neither, depending on use case.

  #
  # Flatfile backing store only-- no DBI:
  #
  create "YourApp::Example::NoDbi" => {
    __useFlatfile => true,
    __useDbi  => false,
  };

  #
  # Maintain version history, but otherwise use DBI for everything:
  #
  create "YourApp::Example::DbiPlusRcs" => {
    __useFlatfile => true,
    __useRcs  => true,
    __useDbi  => true,
  };

To use JSON format, use the constant value from
L<Devel::Ladybug::StorageType>.

  #
  # Javascript could handle these objects as input:
  #
  create "YourApp::Example::JSON" => {
    __useFlatfile => Devel::Ladybug::StorageType::JSON
  };

Use C<__yamlHost> to enforce a master flatfile host.

=cut

sub __useYaml {
  my $class = shift;

  warn "__useYaml is depracated, please use __useFlatfile";

  return $class->__useFlatfile;
}

sub __useFlatfile {
  my $class = shift;

  my $useFlatfile = $class->get("__useFlatfile");

  if ( !defined $useFlatfile ) {
    my %args = $class->__autoArgs();

    $useFlatfile = $args{"__useFlatfile"};

    $class->set( "__useFlatfile", $useFlatfile );
  }

  return $useFlatfile;
}

=pod

=item * $class->__useRcs()

Returns a true value if the current class keeps revision history with
its YAML backend, otherwise false.

Default inherited value is false. Set class variable to override.

__useRcs does nothing for classes which do not also use YAML. The RCS
archive is derived from the physical files in the YAML backing store.

  create "YourApp::Example" => {
    __useFlatfile => true, # Must be YAML
    __useRcs => true

  };

=cut

sub __useRcs {
  my $class = shift;

  if ( !defined $class->get("__useRcs") ) {
    $class->set( "__useRcs", false );
  }

  my $use = $class->get("__useRcs");

  my $backend = $class->__useFlatfile;

  if ( $use &&
    ( !$backend || $backend != Devel::Ladybug::StorageType::YAML )
  ) {
    Devel::Ladybug::RuntimeError->throw(
      "RCS requires a flatfile type of YAML");
  }

  return $use;
}

=pod

=item * $class->__yamlHost()

Optional; Returns the name of the RCS/YAML master host.

If defined, the value for __yamlHost must *exactly* match the value
returned by the local system's C<hostname> command, including
fully-qualified-ness, or any attempt to save will throw an exception.
This feature should be used if you don't want files to accidentally be
created on the wrong host/filesystem.

Defaults to the C<yamlHost> L<Devel::Ladybug::Constants> value (ships
as C<undef>), but may be overridden on a per-class basis.

  create "YourApp::Example" => {
    __useFlatfile  => true,
    __useRcs       => true,
    __yamlHost     => "host023.example.com".

  };

=cut

sub __yamlHost {
  my $class = shift;

  my $host = $class->get("__yamlHost");

  if ( !$host && yamlHost ) {
    $host = yamlHost;

    $class->set( "__yamlHost", $host );
  }

  return $host;
}

=pod

=item * $class->__useMemcached()

Returns a TTL in seconds, if the current class should attempt to use
memcached to minimize database load.

Returns a false value if this class should bypass memcached.

If the memcached server can't be reached at package load time, callers
will load from the physical backing store.

Default inherited value is 300 seconds (5 minutes). Set class variable
to override.

  create "YourApp::CachedExample" => {
    #
    # Ten minute TTL on cached objects:
    #
    __useMemcached => 600
  };

Set to C<false> or 0 to disable caching.

  create "YourApp::NeverCachedExample" => {
    #
    # No caching in play:
    #
    __useMemcached => false
  };

=cut

sub __useMemcached {
  my $class = shift;

  if ( !defined $class->get("__useMemcached") ) {
    $class->set( "__useMemcached", 300 );
  }

  return $class->get("__useMemcached");
}

=pod

=item * $class->__useDbi

Returns a constant from the L<Devel::Ladybug::StorageType>
enumeration, which represents the DBI type to be used.

Default inherited value is auto-detected for the local system. Set
class variable to override.

  create "YourApp::Example" => {
    __useDbi => Devel::Ladybug::StorageType::SQLite
  };

=cut

sub __dbiType {
  my $class = shift;

  warn "__dbiType is depracated, use __useDbi instead";

  return $class->useDbi;
}

sub __useDbi {
  my $class = shift;

  my $type = $class->get("__useDbi");

  if ( !defined($type) ) {
    my %args = $class->__autoArgs();

    $type = $args{__useDbi};

    $class->set( "__useDbi", $type );
  }

  return $type;
}

my %createArgs;

sub __autoArgs {
  my $class = shift;

  return %createArgs if %createArgs;

  $createArgs{__useDbi}  = false;
  $createArgs{__useFlatfile} = true;

  if ( $class->__supportsSQLite() ) {
    $createArgs{__useFlatfile} = false;
    $createArgs{__useDbi} = Devel::Ladybug::StorageType::SQLite;
  }

  if ( $class->__supportsPostgreSQL() ) {
    $createArgs{__useFlatfile} = false;
    $createArgs{__useDbi} = Devel::Ladybug::StorageType::PostgreSQL;
  }

  if ( $class->__supportsMySQL() ) {
    $createArgs{__useFlatfile} = false;
    $createArgs{__useDbi} = Devel::Ladybug::StorageType::MySQL;
  }

  return %createArgs;
}

sub __supportsSQLite {
  my $class = shift;

  my $worked;

  eval {
    require DBD::SQLite;

    $worked++;
  };

  return $worked;
}

sub __supportsMySQL {
  my $class = shift;

  my $worked;

  eval {
    require DBD::mysql;

    my $dbname = $class->databaseName;

    my $dsn = sprintf( 'DBI:mysql:database=%s;host=%s;port=%s',
      $dbname, $class->__dbHost, $class->__dbPort || 3306 );

    my $dbh =
      DBI->connect( $dsn, $class->__dbUser, $class->__dbPass,
      { RaiseError => 1 } )
      || die DBI->errstr;

    my $sth = $dbh->prepare("show tables") || die $dbh->errstr;
    $sth->execute || die $sth->errstr;
    $sth->fetchall_arrayref() || die $sth->errstr;

    $worked++;
  };

  return $worked;
}

sub __supportsPostgreSQL {
  my $class = shift;

  my $worked;

  eval {
    require DBD::Pg;

    my $dbname = $class->databaseName;

    my $dsn = sprintf( 'DBI:Pg:database=%s;host=%s;port=%s',
      $dbname, $class->__dbHost, $class->__dbPort || 5432 );

    my $dbh =
      DBI->connect( $dsn, $class->__dbUser, $class->__dbPass,
      { RaiseError => 1 } )
      || die DBI->errstr;

    my $sth = $dbh->prepare("select count(*) from information_schema.tables")
      || die $dbh->errstr;

    $sth->execute || die $sth->errstr;

    $sth->fetchall_arrayref() || die $sth->errstr;

    $worked++;
  };

  return $worked;
}

=pod

=item * $class->__baseAsserts()

Assert base-level inherited assertions for objects. These include: id,
name, mtime, ctime.

  __baseAsserts => sub($) {
    my $class = shift;

    my $base = $class->SUPER::__baseAsserts();

    $base->{parentId} = Devel::Ladybug::Str->assert();

    return Clone::clone( $base );
  }

=cut

sub __baseAsserts {
  my $class = shift;

  my @dtArgs;

  if ( $class->get("__useDbi") ) {
    @dtArgs = ( columnType => $class->__datetimeColumnType() );
  }

  my $asserts = $class->get("__baseAsserts");

  if ( !defined $asserts ) {
    $asserts = Devel::Ladybug::Hash->new(
      id => Devel::Ladybug::ID->assert(
        Devel::Ladybug::Type::subtype(
          descript => "The primary GUID key of this object"
        )
      ),
      name => Devel::Ladybug::Name->assert(
        Devel::Ladybug::Type::subtype(
          descript => "A human-readable secondary key for this object",
        )
      ),
      mtime => Devel::Ladybug::DateTime->assert(
        Devel::Ladybug::Type::subtype(
          descript => "The last modified timestamp of this object",
          @dtArgs
        )
      ),
      ctime => Devel::Ladybug::DateTime->assert(
        Devel::Ladybug::Type::subtype(
          descript => "The creation timestamp of this object",
          @dtArgs
        )
      ),
    );

    $class->set( "__baseAsserts", $asserts );
  }

  return ( clone $asserts );
}

=pod

=item * $class->__basePath()

Return the base filesystem path used to store objects of the current
class.

By default, this method returns a directory named after the current
class, under the directory specified by C<yamlRoot> in the local
.ladybugrc file.

  my $base = $class->__basePath();

  for my $path ( <$base/*> ) {
    print $path;
    print "\n";
  }

To override the base path in subclass if needed:

  __basePath => sub($) {
    my $class = shift;

    return join( '/', customPath, $class );
  }

=cut

sub __basePath {
  my $class = shift;

  $class =~ s/::/\//g;

  return join( '/', yamlRoot, $class );
}

=pod

=item * $class->__baseRcsPath()

Returns the base filesystem path used to store revision history files.

By default, this just tucks "RCS" onto the end of C<__basePath()>.

=cut

sub __baseRcsPath {
  my $class = shift;

  return join( '/', $class->__basePath(), rcsDir );
}

=pod

=item * $class->__primaryKey()

Returns the name of the attribute representing this class's primary ID.
Unless overridden, this method returns the string "id".

=cut

sub __primaryKey {
  my $class = shift;

  my $key = $class->get("__primaryKey");

  if ( !defined $key ) {
    $key = DefaultPrimaryKey;

    $class->set( "__primaryKey", $key );
  }

  return $key;
}

=pod

=item * $class->__primaryKeyClass()

Returns the object class used to represent this class's primary keys.

=cut

sub __primaryKeyClass {
  my $class = shift;

  return $class->asserts->{ $class->__primaryKey }->objectClass();
}

=pod

=item * $class->__localLoad($id)

Load the object with the received ID from the backing store.

  my $object = $class->__localLoad($id);

=cut

sub __localLoad {
  my $class = shift;
  my $id    = shift;

  if ( $class->__useDbi() ) {
    return $class->__loadFromDatabase($id);
  } elsif ( $class->__useFlatfile() ) {
    return $class->__loadYamlFromId($id);
  } else {
    throw Devel::Ladybug::MethodIsAbstract(
      "Backing store not implemented for $class");
  }
}

=pod

=item * $class->__loadFromMemcached($id)

Retrieves an object from memcached by ID. Returns nothing if the object
wasn't there.

=cut

sub __loadFromMemcached {
  my $class = shift;
  my $id    = shift;

  my $cacheTTL = $class->__useMemcached();

  if ( $memd && $cacheTTL ) {
    my $cachedObj = $memd->get( $class->__cacheKey($id) );

    if ($cachedObj) {
      return $class->new($cachedObj);
    }
  }

  return;
}

=pod

=item * $class->__loadFromDatabase($id)

Instantiates an object by id, from the database rather than the YAML
backing store.

  my $object = $class->__loadFromDatabase($id);

=cut

sub __loadFromDatabase {
  my $class = shift;
  my $id    = shift;

  my $cachedObj = $class->__loadFromMemcached($id);

  return $cachedObj if $cachedObj;

  my $query = $class->__selectRowStatement($id);

  my $self = $class->__loadFromQuery($query);

  if ( !$self || !$self->exists() ) {
    my $table = $class->tableName();
    my $db    = $class->databaseName();

    throw Devel::Ladybug::ObjectNotFound(
      "Object id \"$id\" does not exist in table $db.$table");
  }

  return $self;
}

=pod

=item * $class->__marshal($hash)

Loads any complex datatypes which were dumped to the database when
saved, and blesses the received hash as an instance of the receiving
class.

Returns true on success, otherwise throws an exception.

  while ( my $object = $sth->fetchrow_hashref() ) {
    $class->__marshal($object);
  }

=cut

sub __marshal {
  my $class = shift;
  my $self  = shift;

  bless $self, $class;

  #
  # Catch fire and explode on unexpected input.
  #
  # None of these things should ever happen:
  #
  if ( !$self ) {
    my $caller = caller();

    throw Devel::Ladybug::InvalidArgument( "BUG: (Check $caller): "
        . "$class->__marshal() received an undefined or false arg" );
  }

  my $refType = ref($self);

  if ( !$refType ) {
    my $caller = caller();

    throw Devel::Ladybug::InvalidArgument( "BUG: (Check $caller): "
        . "$class->__marshal() received a non-reference arg ($self)" );
  }

  if ( !UNIVERSAL::isa( $self, 'HASH' ) ) {
    my $caller = caller();

    throw Devel::Ladybug::InvalidArgument( "BUG: (Check $caller): "
        . "$class->__marshal() received a non-HASH arg ($refType)" );
  }

  my $asserts = $class->asserts();

  #
  # Re-assemble complex structures using data from linked tables.
  #
  # For arrays, "elementIndex" is the array index, and "elementValue"
  # is the actual element value. Each element is a row in the linked table.
  #
  # For hashes, "elementKey" is the key, and "elementValue" is the value.
  # Each key/value pair is a row in the linked table.
  #
  # The parent object is referenced by id in parentId.
  #
  $asserts->each(
    sub {
      my $key = $_;

      my $type = $asserts->{$key};

      if ($type) {
        if ( $type->objectClass()->isa('Devel::Ladybug::Array') ) {
          my $elementClass = $class->__elementClass($key);

          my $array = $type->objectClass()->new();

          $array->clear();

          my $sth = $elementClass->query(
            sprintf q|
            SELECT %s FROM %s
              WHERE %s = %s
              ORDER BY %s + 0
          |,
            $elementClass->__selectColumnNames()->join(", "),
            $elementClass->tableName(),
            $class->__elementParentKey(),
            $elementClass->quote( $self->{ $class->__primaryKey() } ),
            $class->__elementIndexKey(),
          );

          while ( my $element = $sth->fetchrow_hashref() ) {
            if ( $element->{elementValue}
              && $element->{elementValue} =~ /^---\s/ )
            {
              $element->{elementValue} =
                YAML::Syck::Load( $element->{elementValue} );
            }

            $element = $elementClass->__marshal($element);

            $array->push( $element->elementValue() );
          }

          $sth->finish();

          $self->{$key} = $array;

        } elsif ( $type->objectClass()->isa('Devel::Ladybug::Hash') ) {
          my $elementClass = $class->__elementClass($key);

          my $hash = $type->objectClass()->new();

          my $sth = $elementClass->query(
            sprintf q|
            SELECT %s FROM %s WHERE %s = %s
          |,
            $elementClass->__selectColumnNames()->join(", "),
            $elementClass->tableName(),
            $class->__elementParentKey(),
            $elementClass->quote( $self->{ $class->__primaryKey() } )
          );

          while ( my $element = $sth->fetchrow_hashref() ) {
            if ( $element->{elementValue}
              && $element->{elementValue} =~ /^---\s/ )
            {
              $element->{elementValue} =
                YAML::Syck::Load( $element->{elementValue} );
            }

            $element = $elementClass->__marshal($element);

            $hash->{ $element->elementKey() } = $element->elementValue();
          }

          $sth->finish();

          $self->{$key} = $hash;
        }
      }
    }
  );

  #
  # Piggyback on this class's new() method to sanity-check the
  # input which was received, and to load any default instance
  # variables.
  #
  return $class->new($self);
}

=pod

=item * $class->__allIdsSth()

Returns a statement handle to iterate over all ids. Requires DBI.

  my $sth = $class->__allIdsSth();

  while ( my ( $id ) = $sth->fetchrow_array() ) {
    my $object = $class->load($id);

    # Stuff ...
  }

  $sth->finish();

=cut

sub __allIdsSth {
  my $class = shift;

  throw Devel::Ladybug::MethodIsAbstract(
    "$class->__allIdsSth() requires DBI in class")
    if !$class->__useDbi();

  return $class->query( $class->__allIdsStatement() );
}

=pod

=item * $class->__allNamesSth()

Returns a statement handle to iterate over all names in class. Requires
DBI.

  my $sth = $class->__allNamesSth();

  while ( my ( $name ) = $sth->fetchrow_array() ) {
    my $object = $class->loadByName($name);

    # Stuff ...
  }

  $sth->finish();

=cut

sub __allNamesSth {
  my $class = shift;

  throw Devel::Ladybug::MethodIsAbstract(
    "$class->__allNamesSth() requires DBI in class")
    if !$class->__useDbi();

  return $class->query( $class->__allNamesStatement() );
}

=pod

=item * $class->__cacheKey($id)

Returns the key for storing and retrieving this record in Memcached.

  #
  # Remove a record from the cache:
  #
  my $key = $class->__cacheKey($object->get($class->__primaryKey()));

  $memd->delete($key);

=cut

sub __cacheKey {
  my $class = shift;
  my $id    = shift;

  if ( !defined($id) ) {
    my $caller = caller();

    throw Devel::Ladybug::InvalidArgument(
      "BUG (Check $caller): $class->__cacheKey(\$id) received undef for \$id" );
  } elsif (
    $class->asserts->{ $class->__primaryKey }->isa("Devel::Ladybug::ID")
  ) {
    return $id;
  } else {
    my $key = join( ':', $class, $id );

    return $key;
  }
}

sub __write {
  my $class = shift;
  my $query = shift;

  my $rows;

  eval { $rows = $class->__dbh()->do($query) };

  if ($@) {
    my $err = $class->__dbh()->errstr() || $@;

    Devel::Ladybug::DBQueryFailed->throw( join( ': ', $class, $err, $query ) );
  }

  return $rows;
}

sub __query {
  my $class = shift;
  my $query = shift;

  my $dbh = $class->__dbh()
    || throw Devel::Ladybug::DBConnectFailed "Unable to connect to database";

  my $sth;

  eval { $sth = $dbh->prepare($query) || die $@; };

  if ($@) {
    throw Devel::Ladybug::DBQueryFailed( $dbh->errstr || $@ );
  }

  eval { $sth->execute() || die $@; };

  if ($@) {
    throw Devel::Ladybug::DBQueryFailed( $sth->errstr || $@ );
  }

  return $sth;
}

=pod

=item * $class->__loadFromQuery($query)

Returns the first row of results from the received query, as an
instance of the current class. Good for simple queries where you don't
want to have to deal with while().

  sub($$) {
    my $class = shift;
    my $id = shift;

    my $query = $class->__selectRowStatement($id);

    my $object = $class->__loadFromQuery($query) || die $@;

    # Stuff ...
  }

=cut

sub __loadFromQuery {
  my $class = shift;
  my $query = shift;

  my $sth = $class->query($query)
    || throw Devel::Ladybug::DBQueryFailed($@);

  my $self;

  while ( my $row = $sth->fetchrow_hashref() ) {
    $self = $row;

    last;
  }

  $sth->finish();

  return ( $self && ref($self) )
    ? $class->__marshal($self)
    : undef;
}

=pod

=item * $class->__dbh()

Creates a new DB connection, or returns the one which is currently
active.

  sub($$) {
    my $class = shift;
    my $query = shift;

    my $dbh = $class->__dbh();

    my $sth = $dbh->prepare($query);

    while ( my $hash = $sth->fetchrow_hashref() ) {
      # Stuff ...
    }

    $sth->finish();
  }

=cut

sub __dbhKey {
  my $class = shift;

  return join( "_", $class->databaseName, $class->__useDbi );
}

sub __dbh {
  my $class = shift;

  my $useDbi = $class->__useDbi;

  if ( !$useDbi ) {
    Devel::Ladybug::RuntimeError->throw(
      "BUG: $class was asked for its DBH, but it does not use DBI.");
  }

  my $dbName = $class->databaseName();
  my $dbKey  = $class->__dbhKey();

  $dbi ||= Devel::Ladybug::Hash->new();
  $dbi->{$dbKey} ||= Devel::Ladybug::Hash->new();

  if ( !$dbi->{$dbKey}->{$$} ) {
    if ( $useDbi == Devel::Ladybug::StorageType::MySQL ) {
      my %creds = (
        database => $dbName,
        host     => dbHost,
        pass     => dbPass,
        port     => dbPort || 3306,
        user     => dbUser
      );

      $dbi->{$dbKey}->{$$} =
        Devel::Ladybug::Persistence::MySQL::connect(%creds);
    } elsif ( $useDbi == Devel::Ladybug::StorageType::SQLite ) {
      my %creds = ( database => join( '/', sqliteRoot, $dbName ) );

      $dbi->{$dbKey}->{$$} =
        Devel::Ladybug::Persistence::SQLite::connect(%creds);
    } elsif ( $useDbi == Devel::Ladybug::StorageType::PostgreSQL ) {
      my %creds = (
        database => $dbName,
        host     => dbHost,
        pass     => dbPass,
        port     => dbPort || 5432,
        user     => dbUser
      );

      $dbi->{$dbKey}->{$$} =
        Devel::Ladybug::Persistence::PostgreSQL::connect(%creds);
    } else {
      throw Devel::Ladybug::InvalidArgument(
        sprintf( 'Unknown DBI Type %s returned by class %s', $useDbi, $class )
      );
    }
  }

  my $err = $dbi->{$dbKey}->{$$}->{_lastErrorStr};

  if ($err) {
    throw Devel::Ladybug::DBConnectFailed($err);
  }

  return $dbi->{$dbKey}->{$$};
}

=pod

=item * $class->__loadYamlFromId($id)

Return the instance with the received id (returns new instance if the
object doesn't exist on disk yet)

  my $object = $class->__loadYamlFromId($id);

=cut

sub __loadYamlFromId {
  my $class = shift;
  my $id    = shift;

  if ( UNIVERSAL::can( $id, "as_string" ) ) {
    $id = $id->as_string();
  }

  my $joinStr = ( $class->__basePath() =~ /\/$/ ) ? '' : '/';

  my $self =
    $class->__loadYamlFromPath( join( $joinStr, $class->__basePath(), $id ) );

  # $self->set( $class->__primaryKey(), $id );

  return $self;
}

=pod

=item * $class->__loadYamlFromPath($path)

Return an instance from the YAML at the received filesystem path

  my $object = $class->__loadYamlFromPath('/tmp/foobar.123');

=cut

sub __loadYamlFromPath {
  my $class = shift;
  my $path  = shift;

  if ( -e $path ) {
    my $yaml = $class->__getSourceByPath($path);

    my $backend = $class->__useFlatfile;

    if ( $backend == Devel::Ladybug::StorageType::JSON ) {
      return $class->loadJson($yaml);
    } else {
      return $class->loadYaml($yaml);
    }
  } else {
    throw Devel::Ladybug::FileAccessError("Path $path does not exist on disk");
  }
}

=pod

=item * $class->__getSourceByPath($path)

Quickly return the file contents for the received path. Basically
C<cat> a file into memory.

  my $example = $class->__getSourceByPath("/etc/passwd");

=cut

sub __getSourceByPath {
  my $class = shift;
  my $path  = shift;

  return undef unless -e $path;

  my $lines = Devel::Ladybug::Array->new();

  my $file = IO::File->new( $path, 'r' );

  while (<$file>) { $lines->push($_) }

  return $lines->join("");
}

=pod

=item * $class->__fsIds()

Return the id of all instances of this class on disk.

  my $ids = $class->__fsIds();

  $ids->each( sub {
    my $object = $class->load($_);

    # Stuff ...
  } );

=cut

sub __fsIds {
  my $class = shift;

  my $basePath = $class->__basePath();

  my $ids = Devel::Ladybug::Array->new();

  return $ids unless -d $basePath;

  find(
    sub {
      my $id = $File::Find::name;

      my $shortId = $id;
      $shortId =~ s/\Q$basePath\E\///;

      if ( -f $id
        && !( $id =~ /,v$/ )
        && !( $id =~ /\~$/ ) )
      {
        $ids->push($shortId);
      }
    },
    $basePath
  );

  return $ids;
}

=pod

=item * $class->__checkYamlHost

Throws an exception if the current host is not the correct place for
YAML/RCS filesystem ops.

=cut

sub __checkYamlHost {
  my $class = shift;

  #
  # See if we are on the correct host before proceeding...
  #
  if ( $class->__useFlatfile() ) {
    my $yamlHost = $class->__yamlHost();

    if ($yamlHost) {
      my $thisHost = hostname();

      if ( $thisHost ne $yamlHost ) {
        Devel::Ladybug::WrongHost->throw(
          "YAML archives must be saved on host $yamlHost, not $thisHost" );
      }
    }
  }
}

=pod

=item * $class->__init()

Override Devel::Ladybug::Class->__init() to automatically create any
missing tables in the database.

Callers should invoke this at some point, if overriding in superclass.

=cut

my $alreadyWarnedForMemcached;
my $alreadyWarnedForRcs;

sub __init {
  my $class = shift;

  if ( $class->__useRcs ) {
    if ( $^O eq 'openbsd' ) {

      #
      # XXX Contacted OpenRCS author re: arch dir probs, will fix this later
      #
      $class->set( "__useRcs", false );

      if ( !$alreadyWarnedForRcs ) {
        warn "Disabling RCS support (OpenRCS not currently supported)\n";

        $alreadyWarnedForRcs++;
      }
    } else {
      my $ci = join( '/', rcsBindir, 'ci' );
      my $co = join( '/', rcsBindir, 'co' );

      if ( !-e $ci || !-e $co ) {
        $class->set( "__useRcs", false );

        if ( !$alreadyWarnedForRcs ) {
          warn "Disabling RCS support (\"ci\"/\"co\" not found)\n";

          $alreadyWarnedForRcs++;
        }
      }
    }
  }

  if (!$alreadyWarnedForMemcached
    && $class->__useMemcached
    && ( !$memd || !%{ $memd->server_versions } ) )
  {
    warn "Disabling memcached support (no servers found)";

    $alreadyWarnedForMemcached++;
  }

  if ( !$class->__useDbi ) {
    return;
  }

  $class->__INIT();

  #
  # Initialize classes for inline elements
  #
  my $asserts = $class->asserts;

  my $indexed = Devel::Ladybug::Array->new;

  $asserts->each(
    sub {
      my $key    = shift;
      my $assert = $asserts->{$key};

      if ( $assert->indexed ) {
        $indexed->push($key);
      }

      if ( $assert->isa("Devel::Ladybug::Type::Array")
        || $assert->isa("Devel::Ladybug::Type::Hash") )
      {
        $class->__elementClass($key);
      }
    }
  );

  #
  #
  #
  if ( $indexed->count > 0 ) {
    my $index = Devel::Ladybug::TextIndex->new(
      {
        index_dbh  => $class->__dbh,
        collection => join( "_", $class->tableName, "idx" ),
        doc_fields => $indexed->each(
          sub {
            my $field = shift;

            Devel::Ladybug::Array::yield( lc($field) );
          }
        ),
      }
    );

    $class->set( "__textIndex",     $index );
    $class->set( "__indexedFields", $indexed );
  }

  return true;
}

sub __textIndex {
  my $class = shift;

  return $class->get("__textIndex");
}

=pod

=item * __dbUser, __dbPass, __dbHost, __dbPort

These items may be set on a per-class basis.

Unless overridden, credentials from the global C<.ladybugrc> will
be used.

  #
  # Set as class variables in the prototype:
  #
  create "YourApp::YourClass" => {
    __dbUser => "user",
    __dbPass => "pass",
    __dbHost => "example.com",
    __dbPort => 12345,

  };

  #
  # Or, set at runtime (such as from apache startup):
  #
  my $class = "YourApp::YourClass";

  YourApp::YourClass->__dbUser("user");
  YourApp::YourClass->__dbPass("pass");
  YourApp::YourClass->__dbHost("example.com");
  YourApp::YourClass->__dbPort(12345);

=cut

sub __dbUser {
  my $class = shift;

  if ( scalar(@_) ) {
    my $newValue = shift;
    $class->set( "__dbUser", $newValue );
  }

  return $class->get("__dbUser") || dbUser;
}

sub __dbPass {
  my $class = shift;

  if ( scalar(@_) ) {
    my $newValue = shift;
    $class->set( "__dbPass", $newValue );
  }

  return $class->get("__dbPass") || dbPass;
}

sub __dbHost {
  my $class = shift;

  if ( scalar(@_) ) {
    my $newValue = shift;
    $class->set( "__dbHost", $newValue );
  }

  return $class->get("__dbHost") || dbHost;
}

sub __dbPort {
  my $class = shift;

  if ( scalar(@_) ) {
    my $newValue = shift;
    $class->set( "__dbPort", $newValue );
  }

  return $class->get("__dbPort") || dbPort;
}

=pod

=item * $class->__elementClass($key);

Returns the dynamic subclass used for an Array or Hash attribute.

Instances of the element class represent rows in a linked table.

  #
  # File: Example.pm
  #
  create "YourApp::Example" => {
    testArray => Devel::Ladybug::Array->assert( ... )

  };

  #
  # File: testcaller.pl
  #
  my $elementClass = YourApp::Example->__elementClass("testArray");

  print "$elementClass\n"; # YourApp::Example::testArray

In the above example, YourApp::Example::testArray is the name of the
dynamic subclass which was allocated as a container for
YourApp::Example's array elements.

=cut

sub __elementClass {
  my $class = shift;
  my $key   = shift;

  return if !$class->__useDbi;

  my $elementClasses = $class->get("__elementClasses");

  if ( !$elementClasses ) {
    $elementClasses = Devel::Ladybug::Hash->new();

    $class->set( "__elementClasses", $elementClasses );
  }

  if ( $elementClasses->{$key} ) {
    return $elementClasses->{$key};
  }

  my $asserts = $class->asserts();

  my $type = $asserts->{$key};

  my $elementClass;

  if ($type) {
    my $base = $class->__baseAsserts();
    delete $base->{name};

    if ( $type->objectClass()->isa('Devel::Ladybug::Array') ) {
      $elementClass = join( "::", $class, $key );

      create $elementClass => {
        __useDbi => $class->__useDbi,

        name => Devel::Ladybug::Name->assert(
          Devel::Ladybug::Type::subtype( optional => true )
        ),
        parentId     => $class->assert,
        elementIndex => Devel::Ladybug::Int->assert,
        elementValue => $type->memberType,
      };

    } elsif ( $type->objectClass()->isa('Devel::Ladybug::Hash') ) {
      $elementClass = join( "::", $class, $key );

      my $memberClass = $class->memberClass($key);

      create $elementClass => {
        __useDbi => $class->__useDbi,

        name => Devel::Ladybug::Name->assert(
          Devel::Ladybug::Type::subtype( optional => true )
        ),
        parentId     => $class->assert,
        elementKey   => Devel::Ladybug::Str->assert,
        elementValue => Devel::Ladybug::Str->assert,
      };
    }
  }

  $elementClasses->{$key} = $elementClass;

  return $elementClass;
}

=pod

=back

=head1 PUBLIC INSTANCE METHODS

=over 4

=item * $self->save($comment)

Saves self to all appropriate backing stores.

Comment is ignored for classes not using RCS.

  $object->save("This is a checkin comment");

=cut

sub save {
  my $self    = shift;
  my $comment = shift;

  my $class = $self->class();

  #
  # new() does value sanity tests and data normalization nicely:
  #
  # %{ $self } = %{ $class->new($self) };

  $class->new($self);

  $self->presave();

  return $self->_localSave($comment);
}

=pod

=item * $self->presave();

Abstract callback method invoked just prior to saving an object.

Implement this method in subclass, if additional object sanity tests
are needed.

=cut

sub presave {
  my $self = shift;

  #
  # Abstract method
  #
  return true;
}

=pod

=item * $self->remove()

Remove self's DB record, and unlink the YAML backing store if present.

Does B<not> delete RCS history, if present.

  $object->remove();

=cut

sub remove {
  my $self   = shift;
  my $reason = shift;

  my $class = $self->class();

  $class->__checkYamlHost();

  my $asserts = $class->asserts;

  if ( $class->__useDbi() ) {
    my $began = $class->__beginTransaction();

    if ( !$began ) {
      throw Devel::Ladybug::TransactionFailed($@);
    }

    #
    # Purge multi-value elements residing in linked tables
    #
    for ( keys %{$asserts} ) {
      my $key = $_;

      my $type = $asserts->{$_};

      next
        if !$type->objectClass->isa("Devel::Ladybug::Array")
          && !$type->objectClass->isa("Devel::Ladybug::Hash");

      my $elementClass = $class->__elementClass($key);

      next if !$elementClass;

      $elementClass->write(
        sprintf 'DELETE FROM %s WHERE %s = %s', $elementClass->tableName,
        $class->__elementParentKey,             $class->quote( $self->key )
      );
    }

    #
    # Try to run a 'delete' on an existing row
    #
    $class->write( $self->_deleteRowStatement() );

    my $committed = $class->__commitTransaction();

    if ( !$committed ) {

      #
      # If this happens, freak out.
      #
      throw Devel::Ladybug::TransactionFailed("COMMIT failed on remove");
    }
  }

  $self->_removeFromMemcached;

  my $index = $class->__textIndex;
  if ($index) {
    $self->_removeFromTextIndex($index);
  }

  if ( $class->__useFlatfile() ) {
    $self->_fsDelete();
  }

  return true;
}

=pod

=item * $self->revert([$version])

Reverts self to the received version, which must be in the object's RCS
file. This method is not usable unless __useRcs in the object's class
is true.

Uses the latest RCS revision if no version number is provided.

Does not call C<save>, caller must do this explicitly.

  do {
    $self->revert("1.20"); # Load previous version from RCS

    $self->save("Restoring from RCS archive");
  };

=cut

sub revert {
  my $self    = shift;
  my $version = shift;

  my $class = $self->class();

  if ( !$class->__useRcs() ) {
    throw Devel::Ladybug::RuntimeError("Can't revert $class instances");
  }

  my $rcs = $self->_rcs();

  if ($version) {
    $rcs->co( "-r$version", $self->_path() );
  } else {
    $rcs->co( $self->_path() );
  }

  %{$self} = %{ $class->__loadYamlFromId( $self->id() ) };

  # $self->save("Reverting to version $version");

  return $self;
}

=pod

=item * $self->exists()

Returns true if this object has ever been saved.

  my $object = YourApp::Example->new();

  my $false = $object->exists();

  $object->save();

  my $true = $object->exists();

=cut

sub exists {
  my $self = shift;

  return false if !defined( $self->{id} );

  my $class = $self->class;

  return $class->__useDbi
    ? $self->class->doesIdExist( $self->id )
    : -e $self->_path;
}

=pod

=item * $self->key()

Returns the value for this object's primary database key, since the
primary key may not always be "id".

Equivalent to:

  $self->get( $class->__primaryKey() );

Which, in most cases, yields the same value as:

  $self->id();

=cut

sub key {
  my $self = shift;

  my $class = $self->class();

  return $self->get( $class->__primaryKey() );
}

=pod

=item * $self->setIdsFromNames($attr, @names)

Convenience setter for attributes which contain either an ExtID or an
Array of ExtIDs.

Sets the value for the received attribute name in self to the IDs of
the received names. If a name is provided which does not correspond to
a named object in the foreign table, a new object is created and saved,
and the new ID is used.

If the named objects do not yet exist, and have required attributes
other than "name", then this method will raise an exception. The
referenced object will need to be explicitly saved before the referent.

  #
  # Set "parentId" in self to the ID of the object named "Mom":
  #
  $obj->setIdsFromNames("parentId", "Mom");

  #
  # Set "categoryIds" in self to the ID of the objects
  # named "Blue" and "Red":
  #
  $obj->setIdsFromNames("categoryIds", "Blue", "Red");

=cut

sub setIdsFromNames {
  my $self  = shift;
  my $attr  = shift;
  my @names = @_;

  my $class   = $self->class;
  my $asserts = $class->asserts;

  my $type = $asserts->{$attr}
    || Devel::Ladybug::InvalidArgument->throw(
    "$attr is not an attribute of $class");

  if ( $type->isa("Devel::Ladybug::Type::ExtID") ) {
    Devel::Ladybug::InvalidArgument->throw("Too many names received")
      if @names > 1;

  } elsif ( $type->isa("Devel::Ladybug::Type::Array")
    && $type->memberType->isa("Devel::Ladybug::Type::ExtID") )
  {

    #
    #
    #

  } else {
    Devel::Ladybug::InvalidArgument->throw("$attr does not represent an ExtID");
  }

  my $names = Devel::Ladybug::Array->new(@names);

  my $extClass = $type->externalClass;

  my $newIds = $names->each(
    sub {
      my $obj = $extClass->spawn($_);

      if ( !$obj->exists ) {
        $obj->save;
      }

      Devel::Ladybug::Array::yield( $obj->id );
    }
  );

  my $currIds = $self->get($attr);

  if ( !$currIds ) {
    $currIds = Devel::Ladybug::Array->new;
  } elsif ( !$currIds->isa("Devel::Ladybug::Array") ) {
    $currIds = Devel::Ladybug::Array->new($currIds);
  }

  if ( $type->isa("Devel::Ladybug::Type::ExtID") ) {
    $self->set( $attr, $newIds->shift );
  } else {
    $self->set( $attr, $newIds );
  }

  return true;
}

=pod

=item * $self->revisions()

Return an array of all of this object's revision numbers

=cut

sub revisions {
  my $self = shift;

  return $self->_rcs()->revisions();
}

=pod

=item * $self->revisionInfo()

Return a hash of info for this file's checkins

=cut

sub revisionInfo {
  my $self = shift;

  my $rcs = $self->_rcs();

  my $loghead;

  my $revisionInfo = Devel::Ladybug::Hash->new();

  for my $line ( $rcs->rlog() ) {
    next if $line =~ /----------/;

    last if $line =~ /==========/;

    if ( $line =~ /revision (\d+\.\d+)/ ) {
      $loghead = $1;

      next;
    }

    next unless $loghead;

    $revisionInfo->{$loghead} = '' unless $revisionInfo->{$loghead};

    $revisionInfo->{$loghead} .= $line;
  }

  return $revisionInfo;
}

=pod

=item * $self->head()

Return the head revision number for self's backing store.

=cut

sub head {
  my $self = shift;

  return $self->_rcs()->head();
}

=pod

=back

=head1 PRIVATE INSTANCE METHODS

=over 4

=item * $self->_newId()

Generates a new ID for the current object. Default is GUID-style.

  _newId => sub {
    my $self = shift;

    return Devel::Ladybug::Utility::randstr();
  }

=cut

sub _newId {
  my $self = shift;

  my $class = $self->class;

  my $assert = $class->asserts->{ $class->__primaryKey };

  return $assert->objectClass->new();
}

=pod

=item * $self->_localSave($comment)

Saves self to all applicable backing stores.

=cut

sub _localSave {
  my $self                 = shift;
  my $comment              = shift;
  my $alreadyInTransaction = shift;

  my $class = $self->class();
  my $now   = time();

  #
  # Will restore original object values if any part of the
  # save doesn't work out.
  #
  my $orig_id    = $self->key();
  my $orig_ctime = $self->{ctime};
  my $orig_mtime = $self->{mtime};

  my $idKey = $class->__primaryKey();

  if ( !defined( $self->{$idKey} ) ) {
    $self->{$idKey} = $self->_newId();
  }

  if ( !defined( $self->{ctime} ) || $self->{ctime} == 0 ) {
    $self->setCtime($now);
  }

  $self->setMtime($now);

  my $useDbi = $class->__useDbi();

  if ( $useDbi && !$alreadyInTransaction ) {
    my $began = $class->__beginTransaction();

    if ( !$began ) {
      throw Devel::Ladybug::TransactionFailed($@);
    }
  }

  my $saved;

  try {
    $saved = $self->_localSaveInsideTransaction($comment);

    $self->_saveToMemcached;
  }
  catch Error with {
    $Devel::Ladybug::Persistence::errstr = shift || "No message";

    undef $saved;
  };

  if ($saved) {

    #
    # If using DBI, commit the transaction or die trying:
    #
    if ( $useDbi && !$alreadyInTransaction ) {
      my $committed = $class->__commitTransaction();

      if ( !$committed ) {

        #
        # If this happens, freak out.
        #
        throw Devel::Ladybug::TransactionFailed(
              "Could not COMMIT! Check DB and compare history for "
            . "$idKey $self->{$idKey} in class $class" );
      }
    }
  } else {
    $self->{$idKey} = $orig_id;
    $self->{ctime}  = $orig_ctime;
    $self->{mtime}  = $orig_mtime;

    my $details = sprintf '[class: %s] [id: %s] [name: %s]',
      $self->class,
      $orig_id || "No ID",
      $self->name || "No Name";

    if ( $useDbi && !$alreadyInTransaction ) {
      my $rolled = $class->__rollbackTransaction();

      if ( !$rolled ) {
        my $quotedID = $class->quote( $self->{$idKey} );

        #
        # If this happens, superfreak out.
        #
        throw Devel::Ladybug::TransactionFailed(
              "ROLLBACK FAILED - Check DB and compare history:\n  "
            . "$details\n  "
            . $Devel::Ladybug::Persistence::errstr );
      } else {
        throw Devel::Ladybug::TransactionFailed(
          "Transaction failed - $details\n  "
            . $Devel::Ladybug::Persistence::errstr );
      }
    } else {
      throw Devel::Ladybug::TransactionFailed(
        "Save failed - $details\n  " . $Devel::Ladybug::Persistence::errstr );
    }
  }

  my $index = $class->__textIndex;
  if ($index) {
    $self->_saveToTextIndex($index);
  }

  return $saved;
}

=pod

=item * $self->_localSaveInsideTransaction($comment);

Private backend method called by _localSave() when inside of a database
transaction.

=cut

sub _localSaveInsideTransaction {
  my $self    = shift;
  my $comment = shift;

  my @caller = caller();

  my $class = $self->class();

  $class->__checkYamlHost();

  my $idKey = $class->__primaryKey();

  my $useDbi = $class->__useDbi();

  my $saved;

  #
  # Update the DB row, if using DBI.
  #
  if ($useDbi) {
    $saved = $self->_updateRecord();

    if ($saved) {
      my $asserts = $class->asserts();

      #
      # Save complex objects to their respective tables
      #
      for ( keys %{$asserts} ) {
        my $key = $_;

        my $type = $asserts->{$_};

        next
          if !$type->objectClass->isa("Devel::Ladybug::Array")
            && !$type->objectClass->isa("Devel::Ladybug::Hash");

        my $elementClass = $class->__elementClass($key);

        $elementClass->write(
          sprintf 'DELETE FROM %s WHERE %s = %s',
          $elementClass->tableName(),
          $class->__elementParentKey(),
          $class->quote( $self->key() )
        );

        next if !defined $self->{$key};

        if ( $type->objectClass->isa('Devel::Ladybug::Array') ) {
          my $i = 0;

          for my $value ( @{ $self->{$key} } ) {
            my $element = $elementClass->new(
              parentId     => $self->key(),
              elementIndex => $i,
              elementValue => $value,
            );

            $saved = $element->_localSave( $comment, 1 );

            return if !$saved;

            $i++;
          }
        } elsif ( $type->objectClass->isa('Devel::Ladybug::Hash') ) {
          for my $elementKey ( keys %{ $self->{$key} } ) {
            my $value = $self->{$key}->{$elementKey};

            my $element = $elementClass->new(
              parentId     => $self->key(),
              elementKey   => $elementKey,
              elementValue => $value,
            );

            $saved = $element->_localSave( $comment, 1 );

            return if !$saved;
          }
        }
      }
    }

    return if !$saved;

    $self->{$idKey} ||= $saved;
  }

  #
  # Update the YAML backing store if using YAML
  #
  if ( $class->__useFlatfile() ) {
    my $path = $self->_path();

    my $useRcs = $class->__useRcs();

    my $rcs;

    #
    # Update the RCS history file if using RCS
    #
    # Initial checkout:
    #
    if ($useRcs) {
      my $rcsBase = $class->__baseRcsPath();

      if ( !-d $rcsBase ) {
        eval { mkpath($rcsBase) };
        if ($@) {
          Devel::Ladybug::FileAccessError->($@);
        }
      }

      $rcs = $self->_rcs();

      $self->_checkout( $rcs, $path );
    }

    #
    # Write YAML to filesystem
    #
    $self->_fsSave();

    #
    # Checkin the new file if using RCS
    #
    if ($useRcs) {
      $self->_checkin( $rcs, $path, $comment );
    }
  }

  return $self->{$idKey};
}

=pod

=item * $self->_saveToMemcached

Saves a copy of self to the memcached cluster

=cut

sub _saveToMemcached {
  my $self = shift;

  my $class = $self->class;

  my $cacheTTL = $class->__useMemcached();

  if ( $memd && $cacheTTL ) {
    $self->_removeFromMemcached;

    my $key = $class->__cacheKey( $self->key() );

    return $memd->set( $key, $self, $cacheTTL );
  }

  return;
}

=pod

=item * $self->_saveToTextIndex

Adds indexed values to this class's DBIx::TextIndex collection

=cut

sub _saveToTextIndex {
  my $self  = shift;
  my $index = shift;

  return if !$self->exists;
  return if !$index;

  my $save = {};

  $self->class->__indexedFields->each(
    sub {
      my $field = shift;

      $save->{ lc($field) } = $self->{$field};
    }
  );

  my $key = $self->key;

  $self->_removeFromTextIndex($index);

  $index->add( $key => $save );
}

=pod

=item * $self->_removeFromTextIndex

Removes indexed values from this class's DBIx::TextIndex collection

=cut

sub _removeFromTextIndex {
  my $self  = shift;
  my $index = shift;

  return if !$self->exists;
  return if !$index;

  return $index->remove( $self->key );
}

=pod

=item * $self->_removeFromMemcached

Removes self's cached entry in memcached

=cut

sub _removeFromMemcached {
  my $self = shift;

  my $class = $self->class;

  if ( $memd && $class->__useMemcached() ) {
    my $key = $class->__cacheKey( $self->key() );

    $memd->delete($key);
  }
}

=pod

=item * $self->_updateRecord()

Executes an INSERT or UPDATE for this object's record. Callback method
invoked from _localSave().

Returns number of rows on UPDATE, or ID of object created on INSERT.

=cut

sub _updateRecord {
  my $self = shift;

  my $class = $self->class();

  #
  # Try to run an 'update' on an existing row
  #
  my $return = $class->write( $self->_updateRowStatement() );

  #
  # Row does not exist, must populate it
  #
  if ( $return == 0 ) {
    $return = $class->write( $self->_insertRowStatement() );

    my $priKey = $class->__primaryKey;

    #
    # If the ID was database-assigned (auto-increment), update self:
    #
    if ( $class->asserts->{$priKey}->isa("Devel::Ladybug::Type::Serial") ) {
      my $lastId =
        $class->__dbh->last_insert_id( undef, undef, $class->tableName,
        $priKey );

      $self->set( $priKey, $lastId );
    }
  }

  return $return;
}

=pod

=item * $self->_quotedValues()

Callback method used to construct the values portion of an UPDATE or
INSERT query.

=cut

#
#
#
our $ForceInsertSQL;
our $ForceUpdateSQL;

=pod

=item * $self->_fsDelete()

Unlink self's YAML datafile from the filesystem. Does not dereference
self from memory.

=cut

sub _fsDelete {
  my $self = shift;

  unlink $self->_path();

  return true;
}

=pod

=item * $self->_fsSave()

Save $self as YAML to a local filesystem. Path is $class->__basePath +
$self->id();

=cut

sub _fsSave {
  my $self = shift;

  $self->{ $self->class()->__primaryKey() } ||= $self->_newId();

  return $self->_saveToPath( $self->_path() );
}

=pod

=item * $self->_path()

Return the filesystem path to self's YAML data store.

=cut

sub _path {
  my $self = shift;

  my $key = $self->key();

  my @caller = caller();

  Devel::Ladybug::PrimaryKeyMissing->throw("Self has no primary key set")
    if !defined $key;

  if ( UNIVERSAL::can( $key, "as_string" ) ) {
    $key = $key->as_string();
  }

  return join( '/', $self->class()->__basePath(), $key );
}

=pod

=item * $self->_saveToPath($path)

Save $self as YAML to a the received filesystem path

=cut

sub _saveToPath {
  my $self = shift;
  my $path = shift;

  my $class = $self->class();

  my $base = $path;
  $base =~ s/[^\/]+$//;

  if ( !-d $base ) {
    eval { mkpath($base) };
    if ($@) {
      throw Devel::Ladybug::FileAccessError($@);
    }
  }

  my $id = $self->key();
  if ( UNIVERSAL::can( $id, "as_string" ) ) {
    $id = $id->as_string();
  }

  my $tempPath = sprintf '%s/%s-%s', scratchRoot, $id,
    Devel::Ladybug::Utility::randstr();

  my $tempBase = $tempPath;
  $tempBase =~ s/[^\/]+$//;

  if ( !-d $tempBase ) {
    eval { mkpath($tempBase) };
    if ($@) {
      throw Devel::Ladybug::FileAccessError($@);
    }
  }

  my $backend = $class->__useFlatfile;

  my $yaml;

  if ( $backend == Devel::Ladybug::StorageType::JSON ) {
    $yaml = $self->toJson();
  } else {
    $yaml = $self->toYaml();
  }

  open( TEMP, "> $tempPath" );
  print TEMP $yaml;
  close(TEMP);

  chmod '0644', $path;

  move( $tempPath, $path );

  return true;
}

=pod

=item * $self->_rcsPath()

Return the filesystem path to self's RCS history file.

=cut

sub _rcsPath {
  my $self = shift;

  my $key = $self->key();

  return false unless ($key);

  my $class = ref($self);

  my $joinStr = ( $class->__baseRcsPath() =~ /\/$/ ) ? '' : '/';

  return
    sprintf( '%s%s', join( $joinStr, $class->__baseRcsPath(), $key ), ',v' );
}

=pod

=item * $self->_checkout($rcs, $path)

Performs the RCS C<co> command on the received path, using the received
L<Rcs> object.

=cut

sub _checkout {
  my $self = shift;
  my $rcs  = shift;
  my $path = shift;

  return if !-e $path;

  eval {

    #
    # It hides the STDERR from us, and we hates it
    #
    $rcs->co('-l');
  };

  if ($@) {
    my $error = "RCS Checkout failed with status $@; Check STDERR";

    Devel::Ladybug::RCSError->throw($error);
  }
}

=pod

=item * $self->_checkin($rcs, $path, [$comment])

Performs the RCS C<ci> command on the received path, using the received
L<Rcs> object.

=cut

sub _checkin {
  my $self    = shift;
  my $rcs     = shift;
  my $path    = shift;
  my $comment = shift;

  my $user = $ENV{REMOTE_USER} || $ENV{USER} || 'nobody';

  $comment ||= "No checkin comment provided by $user";

  eval {
    $rcs->ci( '-t-Programmatic checkin from ' . $self->class(),
      '-u', '-wLadybug', "-mEdited by user $user with comment: $comment" );
  };

  if ($@) {
    my $error = "RCS Checkin failed with status $@; Check STDERR";

    Devel::Ladybug::RCSError->throw($error);
  }
}

=pod

=item * $self->_rcs()

Return an instance of the Rcs class corresponding to self's backing
store.

=cut

sub _rcs {
  my $self = shift;

  my $rcs = Rcs->new();

  $self->_path() =~ /(.*)\/(.*)/;

  my $directory = $1;
  my $filename  = $2;

  $rcs->file($filename);
  $rcs->rcsdir( join( "/", $directory, rcsDir ) );
  $rcs->workdir($directory);

  return $rcs;
}

=pod

=back

=head1 SEE ALSO

L<Cache::Memcached::Fast>, L<Rcs>, L<YAML::Syck>, L<DBI>

This file is part of L<Devel::Ladybug>.

=cut

true;
