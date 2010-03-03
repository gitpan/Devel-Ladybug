package Devel::Ladybug::Persistence::Generic;

use strict;
use warnings;

use DBI;
use Error qw| :try |;

use Devel::Ladybug::Enum::Bool;

sub columnNames {
  my $class = shift;
  my $raw   = shift;

  my $asserts = $class->asserts();

  return $asserts->each(
    sub {
      my $attr = shift;

      my $type = $asserts->{$attr};

      my $objectClass = $type->objectClass;

      return if $objectClass->isa("Devel::Ladybug::Array");
      return if $objectClass->isa("Devel::Ladybug::Hash");

      Devel::Ladybug::Array::yield($attr);
    }
  );
}

sub __doesIdExistStatement {
  my $class = shift;
  my $id    = shift;

  return (
    sprintf q|
      SELECT count(*) FROM %s WHERE id = %s
    |,
    $class->__selectTableName(),
    $class->quote($id)
  );
}

sub __doesNameExistStatement {
  my $class = shift;
  my $name  = shift;

  return (
    sprintf q|
      SELECT count(*) FROM %s WHERE name = %s
    |,
    $class->__selectTableName(),
    $class->quote($name),
  );
}

sub __idForNameStatement {
  my $class = shift;
  my $name  = shift;

  return (
    sprintf q|
      SELECT %s FROM %s WHERE name = %s
    |,
    $class->__primaryKey(),
    $class->__selectTableName(),
    $class->quote($name)
  );
}

sub __nameForIdStatement {
  my $class = shift;
  my $id    = shift;

  return (
    sprintf q|
      SELECT name FROM %s WHERE %s = %s
    |,
    $class->__selectTableName(),
    $class->__primaryKey(),
    $class->quote($id),
  );
}

sub __beginTransaction {
  my $class = shift;

  if ( !$Devel::Ladybug::Persistence::transactionLevel ) {
    $class->write( $class->__beginTransactionStatement() );
  }

  $Devel::Ladybug::Persistence::transactionLevel++;

  return $@ ? false : true;
}

sub __rollbackTransaction {
  my $class = shift;

  $class->write( $class->__rollbackTransactionStatement() );

  return $@ ? false : true;
}

sub __commitTransaction {
  my $class = shift;

  if ( !$Devel::Ladybug::Persistence::transactionLevel ) {
    throw Devel::Ladybug::TransactionFailed(
      "$class->__commitTransaction() called outside of transaction!!!");
  } elsif ( $Devel::Ladybug::Persistence::transactionLevel == 1 ) {
    $class->write( $class->__commitTransactionStatement() );
  }

  $Devel::Ladybug::Persistence::transactionLevel--;

  return $@ ? false : true;
}

sub __beginTransactionStatement {
  my $class = shift;

  return "BEGIN;\n";
}

sub __commitTransactionStatement {
  my $class = shift;

  return "COMMIT;\n";
}

sub __rollbackTransactionStatement {
  my $class = shift;

  return "ROLLBACK;\n";
}

sub __schema {
  my $class = shift;

  #
  # Make sure the specified primary key is valid
  #
  my $primaryKey = $class->__primaryKey();

  throw Devel::Ladybug::PrimaryKeyMissing(
    "$class has no __primaryKey set, please fix")
    if !$primaryKey;

  my $asserts = $class->asserts();

  throw Devel::Ladybug::PrimaryKeyMissing(
    "$class did not assert __primaryKey $primaryKey")
    if !exists $asserts->{$primaryKey};

  #
  # Tack on any UNIQUE secondary keys at the end of the schema
  #
  my $unique = Devel::Ladybug::Hash->new();

  #
  # Tack on any FOREIGN KEY constraints at the end of the schema
  #
  my $foreign = Devel::Ladybug::Array->new();

  #
  # Start building the CREATE TABLE statement:
  #
  my $schema = Devel::Ladybug::Array->new();

  my $table = $class->tableName();

  $schema->push("CREATE TABLE $table (");

  my $inlineAttribs = Devel::Ladybug::Array->new();

  for my $attribute ( sort $class->attributes() ) {
    my $type = $asserts->{$attribute};

    next if !$type;

    my $statement =
      $class->__statementForColumn( $attribute, $type, $foreign,
      $unique );

    $inlineAttribs->push( sprintf( '  %s', $statement ) )
      if $statement;
  }

  $schema->push( $inlineAttribs->join(",\n") );
  $schema->push(");");
  $schema->push('');

  return $schema->join("\n");
}

sub __concatNameStatement {
  my $class = shift;

  my $asserts = $class->asserts();

  my $uniqueness = $class->asserts()->{name}->unique();

  my $concatAttrs = Devel::Ladybug::Array->new();

  my @uniqueAttrs;

  if ( ref $uniqueness ) {
    @uniqueAttrs = @{$uniqueness};
  } elsif ( $uniqueness && $uniqueness ne '1' ) {
    @uniqueAttrs = $uniqueness;
  } else {
    return join( ".", $class->tableName, "name" ) . " as __name";

    # @uniqueAttrs = "name";
  }

  #
  # For each attribute that "name" is keyed with, include the
  # value in a display name. If the value is an ID, look up the name.
  #
  for my $extAttr (@uniqueAttrs) {
    #
    # Get the class
    #
    my $type = $asserts->{$extAttr};

    if ( $type->objectClass()->isa("Devel::Ladybug::ExtID") ) {
      my $extClass = $type->memberClass();

      my $tableName = $extClass->tableName();

      #
      # Method calls itself--
      #
      # I don't think this will ever infinitely loop,
      # since we use constraints (see query)
      #
      my $subSel = $extClass->__concatNameStatement()
        || sprintf( '%s.name', $tableName );

      $concatAttrs->push(
        sprintf q|
          ( SELECT %s FROM %s WHERE %s.id = %s )
        |,
        $subSel, $tableName, $tableName, $extAttr
      );

    } else {
      $concatAttrs->push($extAttr);
    }
  }

  $concatAttrs->push( join( ".", $class->tableName, "name" ) );

  return if $concatAttrs->isEmpty();

  my $select = sprintf 'concat(%s) as __name',
    $concatAttrs->join(', " / ", ');

  return $select;
}

sub __serialType {
  my $class = shift;

  return "INTEGER PRIMARY KEY AUTOINCREMENT";
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
  return join( " ", $attribute, $class->__serialType )
    if $type->serial;

  #
  #
  #
  my $datatype = $type->columnType || 'TEXT';

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

    $fragment->push( $attribute, $datatype, 'DEFAULT', $quotedDefault );
  } else {

    #
    # No default() was specified:
    #
    $fragment->push( $attribute, $datatype );
  }

  $fragment->push($notNull)       if $notNull;
  $fragment->push($uniqueInline)  if $uniqueInline;
  $fragment->push($primaryInline) if $primaryInline;

  if ( $class->__useForeignKeys()
    && $type->objectClass->isa("Devel::Ladybug::ExtID") )
  {
    my $memberClass = $type->memberClass();

    #
    # Value references a foreign key
    #
    $fragment->push(
      sprintf(
        'references %s(%s)',
        $memberClass->tableName, $memberClass->__primaryKey
      )
    );
  }

  return $fragment->join(" ");
}

sub __dropTable {
  my $class = shift;

  $class->asserts->each(
    sub {
      my $key = shift;

      my $elementClass = $class->__elementClass($key);

      return if !$elementClass;

      $elementClass->__dropTable();
    }
  );

  my $table = $class->tableName();

  my $query = "DROP TABLE $table;\n";

  my $index = $class->__textIndex;

  if ( $index ) {
    $index->delete if $index->_collection_table_exists;
  }

  return $class->write($query);
}

sub __createTable {
  my $class = shift;

  my $query = $class->__schema();

  $class->write($query);

  $class->asserts->each(
    sub {
      my $key = shift;

      my $elementClass = $class->__elementClass($key);

      return if !$elementClass;

      $elementClass->__init();
    }
  );

  my $index = $class->__textIndex;

  if ( $index ) {
    $index->initialize;
  }

  return true;
}

sub __selectTableName {
  my $class = shift;

  return $class->tableName;
}

sub __selectRowStatement {
  my $class = shift;
  my $id    = shift;

  return sprintf(
    q| SELECT %s FROM %s WHERE %s = %s |,
    $class->__selectColumnNames->join(", "),
    $class->__selectTableName(),
    $class->__primaryKey(), $class->quote($id)
  );
}

sub __allNamesStatement {
  my $class = shift;

  return
    sprintf( q| SELECT name FROM %s |, $class->__selectTableName() );
}

sub __allIdsStatement {
  my $class = shift;

  return sprintf(
    q|
      SELECT %s FROM %s ORDER BY name
    |,
    $class->__primaryKey(),
    $class->__selectTableName(),
  );
}

sub __countStatement {
  my $class = shift;

  return sprintf(
    q|
      SELECT count(*) AS total FROM %s
    |,
    $class->__selectTableName(),
  );
}

sub __tupleStatement {
  my $class = shift;

  return sprintf(
    q|
      SELECT %s, %s FROM %s ORDER BY __name
    |,
    $class->__primaryKey,
    $class->__concatNameStatement,
    $class->tableName
  );
}

sub __wrapWithReconnect {
  my $class = shift;
  my $sub   = shift;

  warn "$class\::__wrapWithReconnect not implemented";

  return &$sub(@_);
}

sub __updateColumnNames {
  my $class = shift;

  my $priKey = $class->__primaryKey;

  return $class->columnNames->each(
    sub {
      my $name = shift;

      return if $name eq $priKey;
      return if $name eq 'ctime';

      Devel::Ladybug::Array::yield($name);
    }
  );
}

sub __insertColumnNames {
  my $class = shift;

  my $priKey = $class->__primaryKey;

  #
  # Omit "id" from the SQL statement if we're using auto-increment
  #
  if ( $class->asserts->{$priKey}->isa("Devel::Ladybug::Type::Serial") )
  {
    return $class->columnNames->each(
      sub {
        my $name = shift;

        return if $name eq $priKey;

        Devel::Ladybug::Array::yield($name);
      }
    );

  } else {
    return $class->columnNames;
  }
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
        Devel::Ladybug::Array::yield(
          $class->__quoteDatetimeSelect($attr) );

      } else {
        Devel::Ladybug::Array::yield($attr);
      }
    }
  );
}

sub __datetimeColumnType {
  my $class = shift;

  return "DATETIME";
}

sub __quoteDatetimeInsert {
  my $class = shift;
  my $value = shift;

  return $value;
}

sub __quoteDatetimeSelect {
  my $class = shift;
  my $attr  = shift;

  return $attr;
}

#
#
#
sub _quotedValues {
  my $self     = shift;
  my $isUpdate = shift;

  my $class = $self->class();

  my $values = Devel::Ladybug::Array->new();

  my $asserts = $class->asserts();

  my $columns =
      $isUpdate
    ? $class->__updateColumnNames
    : $class->__insertColumnNames;

  $columns->each(
    sub {
      my $key = shift;

      my $realKey = $key;
      $realKey =~ s/"//g;

      my $value = $self->get($realKey);

      my $quotedValue;

      my $type = $asserts->{$realKey};
      return if !$type;

      if ( $type->sqlInsertValue
        && $Devel::Ladybug::Persistence::ForceInsertSQL )
      {
        $quotedValue = $type->sqlInsertValue;

      } elsif ( $type->sqlUpdateValue
        && $Devel::Ladybug::Persistence::ForceUpdateSQL )
      {
        $quotedValue = $type->sqlUpdateValue;

      } elsif ( $type->sqlValue() ) {
        $quotedValue = $type->sqlValue();

      } elsif ( $type->optional() && !defined($value) ) {
        $quotedValue = 'NULL';

      } elsif ( !defined($value) || ( !ref($value) && $value eq '' ) ) {
        $quotedValue = "''";

      } elsif ( !ref($value)
        || ( ref($value) && overload::Overloaded($value) ) )
      {
        if ( !UNIVERSAL::isa( $value, $type->objectClass ) ) {

          #
          # Sorry, but you're an object now.
          #
          $value = $type->objectClass->new( Clone::clone($value) );
        }

        if ( $type->objectClass->isa("Devel::Ladybug::DateTime")
          && $type->columnType eq 'DATETIME' )
        {
          $quotedValue = $class->__quoteDatetimeInsert($value);
        } else {
          $quotedValue = $class->quote($value);
        }
      } elsif ( ref($value) ) {
        my $dumpedValue =
          UNIVERSAL::can( $value, "toYaml" )
          ? $value->toYaml
          : YAML::Syck::Dump($value);

        chomp($dumpedValue);

        $quotedValue = $class->quote($dumpedValue);
      }

      if ($isUpdate) {
        $values->push("  $key = $quotedValue");
      } else {    # Is Insert
        $values->push($quotedValue);
      }
    }
  );

  return $values;
}

sub _updateRowStatement {
  my $self = shift;

  my $class = $self->class();

  my $statement = sprintf(
    q| UPDATE %s SET %s WHERE %s = %s; |,
    $class->__selectTableName(),
    $self->_quotedValues(true)->join(",\n"),
    $class->__primaryKey(), $class->quote( $self->key() )
  );

  return $statement;
}

sub _insertRowStatement {
  my $self = shift;

  my $class = $self->class();

  return sprintf(
    q| INSERT INTO %s (%s) VALUES (%s); |,
    $class->__selectTableName(),
    $class->__insertColumnNames->join(', '),
    $self->_quotedValues(false)->join(', '),
  );
}

sub _deleteRowStatement {
  my $self = shift;

  my $idKey = $self->class()->__primaryKey();

  unless ( defined $self->{$idKey} ) {
    throw Devel::Ladybug::ObjectIsAnonymous(
      "Can't delete an object with no ID");
  }

  my $class = $self->class();

  return sprintf(
    q| DELETE FROM %s WHERE %s = %s |,
    $class->__selectTableName(),
    $idKey, $class->quote( $self->{$idKey} )
  );
}

sub __useForeignKeys {
  my $class = shift;

  return false;
}

sub __elementParentKey {
  my $class = shift;

  return "parentId";
}

sub __elementIndexKey {
  my $class = shift;

  return "name";
}

true;

=pod

=head1 NAME

Devel::Ladybug::Persistence::Generic - Abstract base for DBI mix-in
modules

=head1 SYNOPSIS

  package Devel::Ladybug::Persistence::NewDriver;

  use strict;
  use warnings;

  use base qw| Devel::Ladybug::Persistence::Generic |;

  # ...

  1;

=head1 DESCRIPTION

This module will typically be used indirectly.

New DBI types should use this module as a base, and override methods as
needed.

=head1 PUBLIC CLASS METHODS

=over 4

=item * $class->columnNames()

Returns a Devel::Ladybug::Array of all column names in the receiving
class's table.

This will be the same as the list returned by attributes(), minus any
attributes which were asserted as Array or Hash and therefore live in a
seperate linked table.

=back

=head1 PRIVATE CLASS METHODS

=over 4

=item * $class->__useForeignKeys()

Returns a true value if the SQL schema should include foreign key
constraints where applicable. Default is appropriate for the chosen DBI
type.

=item * $class->__datetimeColumnType();

Returns an override column type for ctime/mtime

=item * $class->__beginTransaction();

Begins a new SQL transation.

=item * $class->__rollbackTransaction();

Rolls back the current SQL transaction.

=item * $class->__commitTransaction();

Commits the current SQL transaction.

=item * $class->__beginTransactionStatement();

Returns the SQL used to begin a SQL transaction

=item * $class->__commitTransactionStatement();

Returns the SQL used to commit a SQL transaction

=item * $class->__rollbackTransactionStatement();

Returns the SQL used to rollback a SQL transaction

=item * $class->__schema()

Returns the SQL used to construct the receiving class's table.

=item * $class->__concatNameStatement()

Return the SQL used to look up name concatenated with the other
attributes which it is uniquely keyed with.

=item * $class->__statementForColumn($attr, $type, $foreign, $unique)

Returns the chunk of SQL used for this attribute in the CREATE TABLE
syntax.

=item * $class->__dropTable()

Drops the receiving class's database table.

  use YourApp::Example;

  YourApp::Example->__dropTable();

=item * $class->__createTable()

Creates the receiving class's database table

  use YourApp::Example;

  YourApp::Example->__createTable();

Returns a string representing the name of the class's current table.

For DBs which support cross-database queries, this returns
C<databaseName> concatenated with C<tableName> (eg.
"yourdb.yourclass"), otherwise this method just returns the same value
as C<tableName>.

=item * $class->__selectRowStatement($id)

Returns the SQL used to select a record by id.

=item * $class->__allNamesStatement()

Returns the SQL used to generate a list of all record names

=item * $class->__allIdsStatement()

Returns the SQL used to generate a list of all record ids

=item * $class->__countStatement()

Returns the SQL used to return the number of rows in a table

=item * $class->__doesIdExistStatement($id)

Returns the SQL used to look up the presence of an ID in the current
table

=item * $class->__doesNameExistStatement($name)

Returns the SQL used to look up the presence of a name in the current
table

=item * $class->__nameForIdStatement($id)

Returns the SQL used to look up the name for a given ID

=item * $class->__idForNameStatement($name)

Returns the SQL used to look up the ID for a given name

=item * $class->__serialType()

Returns the database column type used for auto-incrementing IDs.

=item * $class->__updateColumnNames();

Returns a Devel::Ladybug::Array of the column names to include with
UPDATE statements.

=item * $class->__selectColumnNames();

Returns a Devel::Ladybug::Array of the column names to include with
SELECT statements.

=item * $class->__insertColumnNames();

Returns a Devel::Ladybug::Array of the column names to include with
INSERT statements.

=item * $class->__quoteDatetimeInsert();

Returns the SQL fragment used for unixtime->datetime conversion

=item * $class->__quoteDatetimeSelect();

Returns the SQL fragment used for datetime->unixtime conversion

=back

=head1 PRIVATE INSTANCE METHODS

=over 4

=item * $self->_updateRowStatement()

Returns the SQL used to run an "UPDATE" statement for the receiving
object.

=item * $self->_insertRowStatement()

Returns the SQL used to run an "INSERT" statement for the receiving
object.

=item * $self->_deleteRowStatement()

Returns the SQL used to run a "DELETE" statement for the receiving
object.

=back

=head1 SEE ALSO

L<Devel::Ladybug::Persistence>

This file is part of L<Devel::Ladybug>.

=cut
