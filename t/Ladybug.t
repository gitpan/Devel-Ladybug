package Devel::Ladybug::Runtime;

our $Backends;

package main;

use strict;
use diagnostics;

use Test::More qw| no_plan |;

use File::Tempdir;

use constant false => 0;
use constant true  => 1;

use vars qw| $tempdir $path $nofs %classPrototype %instancePrototype |;

BEGIN {
  $tempdir = File::Tempdir->new;

  $path = $tempdir->name;

  if ( !-d $path ) {
    $nofs = "Couldn't find usable tempdir for testing";
  }
}

#####
##### Set up environment
#####

SKIP: {
  skip( $nofs, 2 ) if $nofs;

  require_ok("Devel::Ladybug::Runtime");
  ok( Devel::Ladybug::Runtime->import($path), 'setup environment' );
}

do {
  %classPrototype = (
    testArray =>
      Devel::Ladybug::Array->assert( Devel::Ladybug::Str->assert() ),
    testBool     => Devel::Ladybug::Bool->assert(),
    testDouble   => Devel::Ladybug::Double->assert(),
    testFloat    => Devel::Ladybug::Float->assert(),
    testInt      => Devel::Ladybug::Int->assert(),
    testNum      => Devel::Ladybug::Num->assert(),
    testRule     => Devel::Ladybug::Rule->assert(),
    testStr      => Devel::Ladybug::Str->assert(
      Devel::Ladybug::Type::subtype( indexed => true ),
    ),
    testStr2      => Devel::Ladybug::Str->assert(
      Devel::Ladybug::Type::subtype( indexed => true ),
    ),
    testTimeSpan => Devel::Ladybug::TimeSpan->assert(),
  );

  %instancePrototype = (
    testArray    => [ "foo", "bar", "baz", "rebar", "rebaz" ],
    testBool     => true,
    testDouble   => 1234.5678901,
    testFloat    => 3.14159265,
    testInt      => 23,
    testNum      => 42,
    testRule     => qr/foo/,
    testStr      => "☃☃☃ - example - ☃☃☃",
    testStr2     => "the rain in spain falls gently",
    testTimeSpan => 60 * 24,
  );
};

#####
##### Test auto-detected backing store type
#####

SKIP: {
  skip( $nofs, 2 ) if $nofs;

  my $class = "Devel::Ladybug::AutoTest01";
  ok(
    testCreate( $class => {%classPrototype} ),
    "Class allocate w/ auto-detected backing store"
  );

  kickClassTires($class);
}

#####
##### Test YAML flatfile backing store
#####

SKIP: {
  skip( $nofs, 4 ) if $nofs;

  do {
    my $class = "Ladybug::YAMLTest";
    ok(
      testCreate(
        $class => {
          __useDbi       => false,
          __useFlatfile  => true,
          __useMemcached => 5,
          __useRcs       => true,
          %classPrototype
        }
      ),
      "Class allocate w/ YAML"
    );

    kickClassTires($class);
  };

  do {
    my $class = "Ladybug::JSONTest";
    ok(
      testCreate(
        $class => {
          __useDbi       => false,
          __useFlatfile  => 2, # JSON Backend
          __useMemcached => 5,
          %classPrototype
        }
      ),
      "Class allocate w/ JSON"
    );

    kickClassTires($class);
  };

  ok(
    testExtID(
      "Ladybug::ExtIDTest",
      {
        __useDbi  => false,
        __useFlatfile => true,
      }
    ),
    "ExtID support for YAML"
  );
}

#####
##### SQLite Tests
#####

SKIP: {
  if ($nofs) {
    skip( $nofs, 5 );
  } elsif ( !$Devel::Ladybug::Runtime::Backends->{"SQLite"} ) {
    my $reason = "DBD::SQLite not installed";

    skip( $reason, 5 );
  }

  my $class = "Ladybug::SQLiteTest01";
  ok(
    testCreate(
      $class => {
        __useDbi       => 2,
        __useMemcached => 5,
        __useRcs       => true,
        __useFlatfile  => true,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ SQLite (1)"
  );

  kickClassTires($class);

  $class = "Ladybug::SQLiteTest02";
  ok(
    testCreate(
      $class => {
        __useDbi       => 2,
        __useMemcached => 5,
        __useRcs       => true,
        __useFlatfile  => true,
        id             => Devel::Ladybug::Serial->assert,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ SQLite (2)"
  );

  kickClassTires($class);

  ok(
    testExtID(
      "Ladybug::ExtIDTest",
      {
        __useDbi => 2
      }
    ),
    "ExtID support for SQLite"
  );
}

#####
##### MySQL/InnoDB Tests
#####

SKIP: {
  if ($nofs) {
    skip( $nofs, 5 );
  } elsif ( !$Devel::Ladybug::Runtime::Backends->{"MySQL"} ) {
    my $reason = "DBD::mysql not installed or 'ladybug' db not ready";

    skip( $reason, 5 );
  }

  my $class = "Devel::Ladybug::MySQLTest01";
  ok(
    testCreate(
      $class => {
        __useDbi       => 1,
        __useMemcached => 5,
        __useRcs       => true,
        __useFlatfile  => true,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ MySQL (1)"
  );

  kickClassTires($class);

  $class = "Devel::Ladybug::MySQLTest02";
  ok(
    testCreate(
      $class => {
        __useDbi       => 1,
        __useMemcached => 5,
        __useRcs       => true,
        __useFlatfile  => true,
        id             => Devel::Ladybug::Serial->assert,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ MySQL (2)"
  );

  kickClassTires($class);

  ok(
    testExtID(
      "Devel::Ladybug::MySQL::ExtIDTest",
      {
        __useDbi => 1
      }
    ),
    "ExtID support for MySQL"
  );
}

#####
##### PostgreSQL
#####

SKIP: {
  if ($nofs) {
    skip( $nofs, 5 );
  } elsif ( !$Devel::Ladybug::Runtime::Backends->{"PostgreSQL"} ) {
    my $reason = "DBD::Pg not installed or 'ladybug' db not ready";

    skip( $reason, 5 );
  }

  my $class = "Devel::Ladybug::PgTest01";
  ok(
    testCreate(
      $class => {
        __useDbi       => 3,
        __useMemcached => 5,
        __useRcs       => true,
        __useFlatfile  => true,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ PostgreSQL (1)"
  );

  kickClassTires($class);

  $class = "Devel::Ladybug::PgTest02";
  ok(
    testCreate(
      $class => {
        __useDbi       => 3,
        __useMemcached => 5,
        __useRcs       => true,
        __useFlatfile  => true,
        id             => Devel::Ladybug::Serial->assert,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ PostgreSQL (2)"
  );

  kickClassTires($class);

  ok(
    testExtID(
      "Devel::Ladybug::PgSQL::ExtIDTest",
      {
        __useDbi => 3
      }
    ),
    "ExtID support for PostgreSQL"
  );
}

#####
#####
#####

sub kickClassTires {
  my $class = shift;

  return if $nofs;

  return if !UNIVERSAL::isa( $class, "Devel::Ladybug::Object" );

  if ( $class->__useDbi ) {

 #
 # Just in case there was already a table, make sure the schema is fresh
 #
    ok( $class->__dropTable(), "Drop existing table" );

    ok( $class->__createTable, "Re-create table" );
  }

  my $asserts = $class->asserts;

  do {
    my $obj;
    isa_ok(
      $obj = $class->new(
        name => Devel::Ladybug::Utility::randstr(),
        %instancePrototype
      ),
      $class
    );
    ok( $obj->save, "Save to backing store" );

    my $success;

    ok( $success = $obj->exists, "Exists in backing store" );

    #
    # If the above test failed, then we know the rest will too.
    #
    if ($success) {
      kickObjectTires($obj);
    }
  };

  if ( $class->__useDbi ) {
    my $query = "rain gently";

    my $ids;

    ok( $ids = $class->search($query), "Full-text search" );

    ok( $ids && $ids->count > 0, "Search hit count is > 0" );

    if ( $ids ) {
      $ids->each( sub {
        my $id = shift;
        my $obj;
        isa_ok( $obj = $class->load($id), $class );

        kickObjectTires($obj);
      } );
    }
  };

  my $i = 0;

  my $count = $class->count;

  ok( $count > 0, "Count from backing store is > 0" );

  $class->each(
    sub {
      my $id = shift;

      my $obj;
      isa_ok( $obj = $class->load($id), $class );

      kickObjectTires($obj);

      ok( $obj->remove, "Remove from backing store" );

      ok( !$obj->exists, "Object was removed" );

      undef $obj;

      if ( $class->__useRcs ) {
        isa_ok( $obj = $class->restore( $id, '1.1' ),
          $class, "Object restored from RCS archive" );

        kickObjectTires($obj);
      }

      $i++;
    }
  );

  is( $i, $count);

  if ( $class->__useDbi ) {
    ok( $class->__dropTable(), "Drop table" );
  }
}

sub kickObjectTires {
  my $obj = shift;

  my $class   = $obj->class;
  my $asserts = $class->asserts;

  $asserts->each(
    sub {
      my $key  = shift;
      my $type = $asserts->{$key};

      if ( exists $instancePrototype{$key} ) {
        ok(
          ( $obj->{$key} == $instancePrototype{$key} )
           && ( $obj->{$key} ne "Bogus Crap" )
           && ( $obj->{$key} ne [ "Bogus Crap" ] ),
          "$class: $key '$obj->{$key}' matches orig value '$instancePrototype{$key}'"
        );
      }

      isa_ok( $obj->{$key}, $type->objectClass );

      if ( $obj->{$key}->isa("Devel::Ladybug::Array") ) {
        is( $obj->{$key}->count, 5, "Compare element count" );
      }
    }
  );
}

#
#
#
sub testCreate {
  my $class          = shift;
  my $classPrototype = shift;

  $Devel::Ladybug::Persistence::dbi = {};

  eval { Devel::Ladybug::create( $class, $classPrototype ); };

  return $class->isa($class);
}

sub testExtID {
  my $class     = shift;
  my $prototype = shift;

  $Devel::Ladybug::Persistence::dbi = {};

  ok( testCreate( $class => $prototype ), "Allocate parent class" );

  my $childClass = join( "::", $class, "Child" );

  ok(
    testCreate(
      $childClass => {
        %{$prototype},

        parentId => $class->assert,

        multiParentId => Devel::Ladybug::Array->assert(
          $class->assert
        )
      }
    ),
    "Allocate child class"
  );

  if ( $class->__useDbi ) {
    ok( $childClass->__dropTable(), "Drop " . $childClass->tableName );
    ok( $class->__dropTable(),      "Drop " . $class->tableName );

    ok( $class->__createTable(), "Create " . $class->tableName );
    ok(
      $childClass->__createTable(),
      "Create " . $childClass->tableName
    );
  }

  my $parent = $class->new( name => "Parent" );

  ok( $parent->save(), "Save parent object" );

  my $child = $childClass->new(
    name     => "Child",
    parentId => $parent->id,
    multiParentId => [ $parent->id ],
  );

  ok( $child->save(), "Save child object" );

  my $memberClass = $childClass->memberClass("parentId");
  is($memberClass, $class);
  isa_ok($memberClass->load( $child->parentId ), $class);

  my $multiMemberClass = $childClass->memberClass("multiParentId");
  is($multiMemberClass, $class);
  ok($child->multiParentId->count > 0, "Multi-parent count > 0");
  $child->multiParentId->each( sub {
    my $thisParentId = shift;
    isa_ok($memberClass->load( $thisParentId ), $class);
  } );

  is($childClass->memberClass("parentId"), $class);

  ok( $child->remove(),  "Remove child object" );
  ok( $parent->remove(), "Remove parent object" );

  my $worked;

  eval {
    $child->setParentId("garbageIn");
    $child->save();

    $child->remove;
  };

  if ($@) {

    #
    # This means the operation failed because constraints worked
    #
    $worked++;
  }

  if ( $class->__useDbi ) {
    ok( $childClass->__dropTable(), "Drop " . $childClass->tableName );
    ok( $class->__dropTable(),      "Drop " . $class->tableName );
  }

  return testSelfReferentialClass($class, $prototype);
}

sub testSelfReferentialClass {
  my $class     = shift;
  my $prototype = shift;

  $Devel::Ladybug::Persistence::dbi = {};

  $class .= "_SelfRef";

  ok(
    testCreate(
      $class => {
        %{$prototype},

        parentId => Devel::Ladybug::ExtID->assert( $class,
          Devel::Ladybug::Type::subtype( optional => true )
        ),
      }
    ),
    "Allocate self-referential class"
  );

  if ( $class->__useDbi ) {
    ok( $class->__dropTable(),      "Drop " . $class->tableName );

    ok( $class->__createTable(), "Create " . $class->tableName );
  }

  my $parent = $class->new( name => "Parent" );
  ok( $parent->save(), "Save parent object" );

  my $child = $class->new(
    name     => "Child",
    parentId => $parent->id
  );

  ok( $child->save(), "Save child object" );

  ok( $child->remove(),  "Remove child object" );
  ok( $parent->remove(), "Remove parent object" );

  my $worked;

  eval {
    $child->setParentId("garbageIn");
    $child->save();

    $child->remove;
  };

  if ($@) {

    #
    # This means the operation failed because constraints worked
    #
    $worked++;
  }

  if ( $class->__useDbi ) {
    ok( $class->__dropTable(),      "Drop " . $class->tableName );
  }

  return $worked;
}
