#
# File: lib/Devel/Ladybug/Enum/DBIType.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Enum::DBIType;

use Devel::Ladybug::Enum qw| None MySQL SQLite PostgreSQL |;

=head1 NAME

Devel::Ladybug::Enum::DBIType - Database type enumeration

=head1 DESCRIPTION

Uses L<Devel::Ladybug::Enum> to provide constants which are used to
specify database types. The class variable C<__useDbi> should return
one of the constants in this package.

=head1 SYNOPSIS

  create "YourApp::YourClass" => {
    __useDbi => Devel::Ladybug::Enum::DBIType::<Type>,

  };

=head1 CONSTANTS

=over 4

=item * C<Devel::Ladybug::Enum::DBIType::None>

Specify no DBI support (0)

=item * C<Devel::Ladybug::Enum::DBIType::MySQL>

Specify MySQL as a DBI type (1)

=item * C<Devel::Ladybug::Enum::DBIType::SQLite>

Specify SQLite as a DBI type (2)

=item * C<Devel::Ladybug::Enum::DBIType::PostgreSQL>

Specify PostgreSQL as a DBI type (3)

=back

=head1 SEE ALSO

L<Devel::Ladybug::Enum>, L<Devel::Ladybug::Persistence>

This file is part of L<Devel::Ladybug>.

=cut

1;