#
# File: lib/Devel/Ladybug/Enum/Flatfile.pm
#
# Copyright (c) 2010 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Enum::Flatfile;

use Devel::Ladybug::Enum qw| None YAML JSON XML |;

=head1 NAME

Devel::Ladybug::Enum::Flatfile - Database type enumeration

=head1 DESCRIPTION

Uses L<Devel::Ladybug::Enum> to provide constants which are used to
specify database types. The class variable C<__useFlatfile> should
return one of the constants in this package.

=head1 SYNOPSIS

  create "YourApp::YourClass" => {
    __useFlatfile => Devel::Ladybug::Enum::Flatfile::<Type>,

  };

=head1 CONSTANTS

=over 4

=item * C<Devel::Ladybug::Enum::Flatfile::None>

Specify no flatfile type (0)

=item * C<Devel::Ladybug::Enum::Flatfile::YAML>

Specify YAML as a flatfile type (1)

=item * C<Devel::Ladybug::Enum::Flatfile::JSON>

Specify JSON as a flatfile type (2)

=back

=head1 SEE ALSO

L<Devel::Ladybug::Enum>, L<Devel::Ladybug::Persistence>

This file is part of L<Devel::Ladybug>.

=cut

1;
