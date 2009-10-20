#
# File: lib/Devel/Ladybug/ExtID.pm
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

Devel::Ladybug::ExtID - Overloaded object class for foreign key
constraints.

Extends L<Devel::Ladybug::Str>.

=head1 SYNOPSIS

  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    categoryId => Devel::Ladybug::ExtID->assert(
      "YourApp::Category"
    ),

  };

=head1 PUBLIC CLASS METHODS

=over 4

=item * $class->assert([$query], @rules)

ExtID assertions are like pointers defining relationships with other
classes, or within a class to define parent/child hierarchy.

Attributes asserted as ExtID must match an id in the specified class's
database table.

ExtID may be wrapped in an Array assertion for handling one-to-many
relationships, at a small performance cost.

If using MySQL, C<ExtID> also enforces database-level foreign key
constraints. In addition to enforcing allowed values on the database
level, this will incur a CASCADE operation on DELETE and UPDATE events
(meaning if a parent is deleted or updated, the corresponding child
rows will be deleted or updated as well; always use parent id in a
child object, rather than child id in a parent object).

The following example illustrates self-referencing and externally
referencing attributes with ExtID, using the "Folder" and "Document"
desktop paradigm. Each saved object becomes a row in a database table.

Create a folder class for documents and other folders:

  #
  # File: ExampleFolder.pm
  #

  use Devel::Ladybug qw| :all |;

  create "YourApp::Example::Folder" => {
    #
    # Folders can go in other folders:
    #
    parentId => Devel::Ladybug::ExtID->assert(
      "YourApp::Example::Folder",
      subtype(
        optional => 1
      )
    ),

    ...
  };

A document class. Documents refer to their parent folder:

  #
  # File: ExampleTextDocument.pm
  #

  use Devel::Ladybug qw| :all |;
  use YourApp::Example::Folder;

  create "YourApp::Example::TextDocument" => {
    #
    # This doc's location in the folder hierarchy
    #
    folderId => Devel::Ladybug::ExtID->assert("YourApp::Example::Folder"),

    #
    # Textual content of the document
    #
    content  => Devel::Ladybug::Str->assert(
      subtype(
        columnType => "TEXT"
      )
    ),

    # ...
  };

Caller example which populates some test folders and docs:

  #!/bin/env perl
  #
  # File: somecaller.pl
  #

  use strict;
  use warnings;

  use YourApp::Example::Folder;
  use YourApp::Example::TextDocument;

  sub main {
    #
    # A parent folder named "General"
    #
    my $folder = YourApp::Example::Folder->spawn("General");
    $folder->save();

    #
    # A child folder named "Specific"
    #
    my $subfolder = YourApp::Example::Folder->spawn("Specific");
    $subfolder->setFolderId( $folder->id() );
    $subfolder->save();

    #
    # Put a test document "README" in the parent folder:
    #
    my $readme = YourApp::Example::TextDocument->spawn("README");
    $readme->setFolderId( $folder->id() );
    $readme->setContent("Lorem Ipsum Foo! Bla bla bla...");
    $readme->save();

    #
    # Put a "Test Text Doc" doc in the sub-folder:
    #
    my $doc = YourApp::Example::TextDocument->spawn("Test Text Doc");
    $doc->setFolderId( $subfolder->id() );
    $doc->setContent("Lorem Ipsum Foo! Bla bla bla...");
    $doc->save();
  }

  main();

If a string is specified as a second argument to ExtID, it will be used
as a SQL query, which selects a subset of Ids used as allowed values at
runtime. If this query is not given, a flat, immutable list of Ids will
be plugged in for allowed values at compile time.

  create "YourApp::Example::" => {
    userId => Devel::Ladybug::ExtID->assert(
      "YourApp::Example::::User",
      "select id from example_user where foo = 1"
    ),

    # ...
  };

=cut

#
# XXX TODO ???: Add support for actions other than CASCADE; allow toggling
# of foreign key constraints; permit lazy checking of values at db rather
# than app level, that is: give the option to ignore allowed(), and let
# the DB take care of it entirely. the app would then let you set()
# invalid values, but the DB wouldn't let you save() them, which might be a
# good option for closer-to-realtime performance. The app-level check is
# still a good early indicator for data problems, but it can be a costly
# operation.
#

=pod

=back

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut

package Devel::Ladybug::ExtID;

use strict;
use warnings;

use base qw| Devel::Ladybug::Str |;

sub assert {
  my $class = shift;
  my @rules = @_;

  my $externalClass = shift @rules;
  my $query         = $rules[0];

  my %parsed =
    Devel::Ladybug::Type::__parseTypeArgs( Devel::Ladybug::Type::isStr,
    @rules );

  $parsed{columnType} = $externalClass->asserts->{id}->columnType;

  if ( $query && !ref $query ) {
    $parsed{allowed} = sub {
      my $type  = shift;
      my $value = shift;

      return $externalClass->selectBool($query)
        || Devel::Ladybug::AssertFailed->throw(
        "Value \"$value\" is not permitted");
    };

  } else {
    $parsed{allowed} = sub {
      my $type  = shift;
      my $value = shift;

      my $memberClass = $type->memberClass;

      my $exists;

      if ( $memberClass->__useDbi ) {
        my $q = sprintf(
          q| SELECT %s FROM %s WHERE %s = %s |,
          $memberClass->__primaryKey, $memberClass->__selectTableName,
          $memberClass->__primaryKey, $memberClass->quote($value)
        );

        $exists = $externalClass->selectBool($q);
      } else {
        $exists = $memberClass->doesIdExist($value);
      }

      return $exists
        || Devel::Ladybug::AssertFailed->throw(
        "Value \"$value\" is not permitted");
    };

  }

  $parsed{memberClass} = $externalClass;

  return $class->__assertClass()->new(%parsed);
}

1;
