package Devel::Ladybug::StorageType;

use strict;
use warnings;

use Devel::Ladybug::Enum qw(
  None
  MySQL SQLite PostgreSQL
  YAML=1 JSON XML
);

1;
__END__
=pod

=head1 NAME

Devel::Ladybug::StorageType - Storage type enumeration

=head1 DESCRIPTION

Uses L<Devel::Ladybug::Enum> to provide constants which are used to
specify backing store types. The class variables C<__useDbi> and
C<__useFlatfile> should return one of the constants in this package.

=head1 SYNOPSIS

  create "YourApp::YourClass" => {
    __useFlatfile => Devel::Ladybug::StorageType::<Type>,
    __useDbi      => Devel::Ladybug::StorageType::<Type>,

  };

=head1 CONSTANTS

=over 4

=item * C<Devel::Ladybug::StorageType::None>

Specify no support (0)

=item * C<Devel::Ladybug::StorageType::MySQL>

Specify MySQL as a DBI type (1)

=item * C<Devel::Ladybug::StorageType::SQLite>

Specify SQLite as a DBI type (2)

=item * C<Devel::Ladybug::StorageType::PostgreSQL>

Specify PostgreSQL as a DBI type (3)

=item * C<Devel::Ladybug::StorageType::YAML>

Specify YAML as a flatfile type (1)

=item * C<Devel::Ladybug::StorageType::JSON>

Specify JSON as a flatfile type (2)

=back

=head1 SEE ALSO

L<Devel::Ladybug::Enum>, L<Devel::Ladybug::Persistence>

This file is part of L<Devel::Ladybug>.

=cut
