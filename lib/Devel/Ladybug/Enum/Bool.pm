#
# File: lib/Devel/Ladybug/Enum/Bool.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package Devel::Ladybug::Enum::Bool;

=pod

=head1 NAME

Devel::Ladybug::Enum::Bool - Boolean enumeration

=head1 DESCRIPTION

Bool enumeration. Uses L<Devel::Ladybug::Enum> to provides "true" (1)
and "false" (0) constants for use in Perl applications. Complete
syntactical sugar, basically.

Future versions of Perl will have boolean keywords, at which point this
module should go away.

=head1 SYNOPSIS

  package Foo;

  use Devel::Ladybug::Enum::Bool;

  sub foo {
    ...
    return true;
  }

  sub bar {
    ...
    return false;
  }

  true;

=head1 EXPORTS CONSTANTS

=over 4

=item * C<false>

0

=item * C<true>

1

=back

=cut

use Devel::Ladybug::Enum qw| false true |;

eval { @EXPORT = @EXPORT_OK; };

=pod

=head1 SEE ALSO

L<Devel::Ladybug::Enum>, L<Devel::Ladybug::Class>

This file is part of L<Devel::Ladybug>.

=head1 REVISION

$Id: $

=cut

true;
