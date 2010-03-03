#
# File: lib/Devel/Ladybug/Persistence/MySQL.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Persistence::PostgreSQL;

=pod

=head1 NAME

Devel::Ladybug::Persistence::PostgreSQL - Vendor-specific overrides for
PostgreSQL

=head1 DESCRIPTION

Enables the PostgreSQL backing store.

If using PostgreSQL, you must create and grant access to your
application's database and the "ladybug" database, for the user
specified in your C<ladybugrc>. If there is no ladybugrc, a default
username of "ladybug" with empty password will be used for credentials.
See L<Devel::Ladybug::Constants>.

=head1 FUNCTION

=over 4

=item * C<connect(%args)>

Constructor for a PostgreSQL DBI object.

C<%args> is a hash with keys for C<database> (database name), C<host>,
C<port>, C<user>, and C<pass>.

Returns a new L<DBI> instance.

=back

=cut

use strict;
use warnings;

use Devel::Ladybug::Enum::Bool;
use Error qw| :try |;

use base qw| Devel::Ladybug::Persistence::Generic |;

sub connect {
  my %args = @_;

  my $dsn = sprintf( 'dbi:Pg:database=%s;host=%s;port=%s',
    $args{database}, $args{host}, $args{port} );

  my $dbh = DBI->connect( $dsn, $args{user}, $args{pass}, {
    RaiseError => 1,
    pg_server_prepare => 0,
  } );

  $dbh->do("set client_min_messages = 'warning'");

  return $dbh;
}

=pod

=head1 SEE ALSO

L<DBI>, L<DBD::Pg>

L<Devel::Ladybug::Persistence>

This file is part of L<Devel::Ladybug>.

=cut

########
######## The remainder of this module contains vendor-specific overrides
########

sub __INIT {
  my $class = shift;

  if ( $class =~ /::Abstract/ ) {
    return false;
  }

  my $sth = $class->query(
    q|
    select table_name from information_schema.tables
  |
  );

  my %tables;
  while ( my ($table) = $sth->fetchrow_array() ) {
    $tables{ lc $table }++;
  }

  $sth->finish();

  if ( !$tables{ lc $class->tableName() } ) {
    $class->__createTable();
  }

  return true;
}

sub __datetimeColumnType {
  my $class = shift;

  return "FLOAT";
}

sub __quoteDatetimeInsert {
  my $class = shift;
  my $value = shift;

  return $value->escape;
}

sub __quoteDatetimeSelect {
  my $class = shift;
  my $attr  = shift;

  return "\"$attr\"";
}

sub __wrapWithReconnect {
  my $class = shift;
  my $sub   = shift;

  my $return;

  while (1) {
    try {
      $return = &$sub;
    }
    catch Error with {
      my $error = shift;

      if ( $error =~ /Is the server running/is ) {
        my $dbName = $class->databaseName;

        my $sleepTime = 1;

        #
        # Try to reconnect on failure...
        #
        print STDERR "Lost connection - PID $$ re-connecting to "
          . "\"$dbName\" database.\n";

        sleep $sleepTime;

        $class->__dbi->db_disconnect;

        delete $Devel::Ladybug::Persistence::dbi->{$dbName}->{$$};
        delete $Devel::Ladybug::Persistence::dbi->{$dbName};
      } else {

        #
        # Rethrow
        #
        throw $error;
      }
    };

    last if $return;
  }

  return $return;
}

sub __statementForColumn {
  my $class     = shift;
  my $attribute = shift;
  my $type      = shift;

  if ( $type->objectClass()->isa("Devel::Ladybug::Hash")
    || $type->objectClass()->isa("Devel::Ladybug::Array") )
  {

    #
    # Value lives in a link table, not in this class's table
    #
    return "";
  }

  #
  # Using this key as an AUTO_INCREMENT primary key?
  #
  return join( " ", "\"$attribute\"", $class->__serialType )
    if $type->serial;

  #
  #
  #
  my $datatype = $type->columnType || 'TEXT';

  if ( $datatype =~ /^INT/ ) {
    warnOnce($datatype,"$datatype will be INT in Postgres");
    $datatype = "INT";
  } elsif ( $datatype =~ /^DOUBLE/ ) {
    warnOnce($datatype,"$datatype will be FLOAT in Postgres");
    $datatype = "FLOAT";
  }

  #
  # Some database declare UNIQUE constraints inline with the column
  # spec, not later in the table def like mysql does. Handle that
  # case here:
  #
  my $uniqueInline = $type->unique ? 'UNIQUE' : '';

  #
  # Same with PRIMARY KEY, MySQL likes them at the bottom, other DBs
  # want it to be inline.
  #
  my $primaryInline =
    ( $class->__primaryKey eq $attribute ) ? "PRIMARY KEY" : "";

  #
  # Permitting NULL/undef values for this key?
  #
  my $notNull = !$type->optional && !$primaryInline ? 'NOT NULL' : '';

  my $fragment = Devel::Ladybug::Array->new();

  if ( defined $type->default
    && $datatype !~ /^text/i
    && $datatype !~ /^blob/i )
  {

    #
    # A "default" value was specified by a subtyping rule,
    # so plug it in to the database table schema:
    #
    my $quotedDefault = $class->quote( $type->default );

    $fragment->push( "\"$attribute\"", $datatype, 'DEFAULT', $quotedDefault );
  } else {

    #
    # No default() was specified:
    #
    $fragment->push( "\"$attribute\"", $datatype );
  }

  $fragment->push($notNull)       if $notNull;
  $fragment->push($uniqueInline)  if $uniqueInline;
  $fragment->push($primaryInline) if $primaryInline;

  if ( $type->objectClass->isa("Devel::Ladybug::ExtID") ) {
    my $memberClass = $type->memberClass();

    #
    # Value references a foreign key
    #
    $fragment->push(
      sprintf(
        'references %s("%s")',
        $memberClass->tableName, $memberClass->__primaryKey
      )
    );
  }

  return $fragment->join(" ");
}

sub __serialType {
  my $class = shift;

  return "SERIAL PRIMARY KEY";
}

sub __useForeignKeys {
  my $class = shift;

  return true;
}

sub __selectColumnNames {
  my $class = shift;

  my $asserts = $class->asserts();

  return $class->columnNames->each(
    sub {
      my $attr = shift;

      my $type = $asserts->{$attr};

      my $objectClass = $type->objectClass;

      return if $objectClass->isa("Devel::Ladybug::Array");
      return if $objectClass->isa("Devel::Ladybug::Hash");

      if ( $objectClass->isa("Devel::Ladybug::DateTime")
        && ( $type->columnType eq 'DATETIME' ) )
      {

       # Devel::Ladybug::Array::yield("UNIX_TIMESTAMP($attr) AS $attr");
        Devel::Ladybug::Array::yield( $class->__quoteDatetimeSelect($attr) );

      } else {
        Devel::Ladybug::Array::yield("\"$attr\"");
      }
    }
  );
}

sub __updateColumnNames {
  my $class = shift;

  my $priKey = $class->__primaryKey;

  return $class->columnNames->each(
    sub {
      my $name = shift;

      return if $name eq $priKey;
      return if $name eq 'ctime';

      Devel::Ladybug::Array::yield("\"$name\"");
    }
  );
}

sub __insertColumnNames {
  my $class = shift;

  my $priKey = $class->__primaryKey;

  #
  # Omit "id" from the SQL statement if we're using auto-increment
  #
  if ( $class->asserts->{$priKey}->isa("Devel::Ladybug::Type::Serial") ) {
    return $class->columnNames->each(
      sub {
        my $name = shift;

        return if $name eq $priKey;

        Devel::Ladybug::Array::yield("\"$name\"");
      }
    );

  } else {
    return $class->columnNames->each( sub {
      my $name = shift;

      Devel::Ladybug::Array::yield("\"$name\"");
    } );
  }
}

sub __elementParentKey {
  my $class = shift;

  return "\"parentId\"";
}

sub __elementIndexKey {
  my $class = shift;

  return "\"name\"";
}

my $warned = { };

sub warnOnce {
  my $key = shift;
  my $warning = shift;

  return if exists $warned->{$key};

  warn $warning;

  $warned->{$key}++;
}

1;
