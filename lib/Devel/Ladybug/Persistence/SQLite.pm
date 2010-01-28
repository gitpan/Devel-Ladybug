#
# File: lib/Devel/Ladybug/Persistence/SQLite.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Persistence::SQLite;

=pod

=head1 NAME

Devel::Ladybug::Persistence::SQLite - Vendor-specific overrides for
SQLite

=head1 FUNCTION

=over 4

=item * C<connect(%args)>

Constructor for a SQLite DBI object.

C<%args> is a hash with a key for C<database> (database name), which in
SQLite is really a local filesystem path (/path/to/db).

Returns a new L<DBI> instance.

=back

=cut

use strict;
use warnings;

use Error qw| :try |;
use File::Path;
use Devel::Ladybug::Enum::Bool;
use Devel::Ladybug::Constants qw| sqliteRoot |;

use base qw| Devel::Ladybug::Persistence::Generic |;

sub connect {
  my %args = @_;

  my $dsn = sprintf( 'DBI:SQLite:dbname=%s', $args{database} );

  return DBI->connect( $dsn, '', '', { RaiseError => 1 } );
}

=pod

=head1 SEE ALSO

L<DBI>, L<DBD::SQLite>

L<Devel::Ladybug::Persistence>

This file is part of L<Devel::Ladybug>.

=cut

########
######## The remainder of this module contains vendor-specific overrides
########

sub __wrapWithReconnect {
  my $class = shift;
  my $sub   = shift;

  return &$sub(@_);
}

sub __INIT {
  my $class = shift;

  if ( $class =~ /::Abstract/ ) {
    return false;
  }

  if ( !-e sqliteRoot ) {
    mkpath(sqliteRoot);
  }

  $class->write('PRAGMA foreign_keys = ON');

  my $sth = $class->query('select tbl_name from sqlite_master');

  my %tables;
  while ( my ($table) = $sth->fetchrow_array() ) {
    $tables{$table}++;
  }

  $sth->finish();

  if ( !$tables{ $class->tableName() } ) {
    $class->__createTable();
  }

  return true;
}

sub __quoteDatetimeInsert {
  my $class = shift;
  my $value = shift;

  return sprintf( 'datetime(%i, "unixepoch")', $value->escape );
}

sub __quoteDatetimeSelect {
  my $class = shift;
  my $attr  = shift;

  return "strftime('\%s', $attr) AS $attr";
}

sub __useForeignKeys {
  my $class = shift;

  my $use = $class->get("__useForeignKeys");

  if ( !defined $use ) {
    $use = false;

    $class->set( "__useForeignKeys", $use );
  }

  return $use;
}

true;
