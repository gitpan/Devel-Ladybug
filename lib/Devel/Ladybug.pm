#
# File: Devel/Ladybug.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#

package Devel::Ladybug;

our $VERSION = '0.410';

use strict;
use diagnostics;

use 5.008_008; # Perl 5.8.8+

#
# Abstract classes
#
use Devel::Ladybug::Class qw| create true false |;
use Devel::Ladybug::Type qw| subtype |;
use Devel::Ladybug::Subtype;
use Devel::Ladybug::Object;
use Devel::Ladybug::Node;

#
# Core object classes
#
use Devel::Ladybug::Array qw| yield emit break |;
use Devel::Ladybug::Bool;
use Devel::Ladybug::DateTime;
use Devel::Ladybug::Double;
use Devel::Ladybug::ExtID;
use Devel::Ladybug::Float;
use Devel::Ladybug::Hash;
use Devel::Ladybug::ID;
use Devel::Ladybug::Int;
use Devel::Ladybug::Name;
use Devel::Ladybug::Num;
use Devel::Ladybug::Rule;
use Devel::Ladybug::Scalar;
use Devel::Ladybug::Serial;
use Devel::Ladybug::Str;
use Devel::Ladybug::TimeSpan;

use base qw| Exporter |;

our @EXPORT_OK = (

  #
  # From Devel::Ladybug::Class:
  #
  "create", "true", "false",

  #
  # From Devel::Ladybug::Type:
  #
  "subtype",

  #
  # From Devel::Ladybug::Array:
  #
  "yield", "emit", "break"
);

our %EXPORT_TAGS = (
  create => [qw| create subtype |],
  bool   => [qw| true false |],
  yield  => [qw| yield emit break |],
  all    => \@EXPORT_OK,
);

true;
__END__

=pod

=head1 NAME

Devel::Ladybug - Data modeling framework

=head1 SYNOPSIS

  use strict;
  use warnings;

  use Devel::Ladybug qw| :all |;

  create "YourApp::YourClass" => { };

See PROTOTYPE COMPONENTS in L<Devel::Ladybug::Class> for detailed
examples.

=head1 DESCRIPTION

Devel::Ladybug is a framework for creating and working with data
models.

Using the C<create()> function, developers may assert rules for
classes. Devel::Ladybug creates a permanent backing store for these
classes, and can also handle object-relational mapping and input
validation.

Supported storage types are YAML or JSON flatfile, MySQL (InnoDB
engine), PostgreSQL, and SQLite. Memcached, DBIx::TextIndex, and
RCS may be used in conjunction with the permanent backing store.

=head1 VERSION

This documentation is for version B<0.410> of Devel::Ladybug.

=head1 FRAMEWORK ASSUMPTIONS

As with any framework, a number of things "just happen" by design.
Trying to go against the flow of any of these base assumptions is
not recommended.

=head2 Configuration

See CONFIGURATION AND ENVIRONMENT in this document.

=head2 Table Creation

Database schemas are derived from the assertions contained
in object classes. Devel::Ladybug creates any needed tables.

=head2 Default Base Attributes

Persistent objects B<always> have "id", "name", "ctime", and "mtime".

=over 4

=item * C<id> => L<Devel::Ladybug::ID>

C<id> is the primary key at the database table level. The gets used in
database table indexes, and should generally not be altered once
assigned.

Base64-encoded Globally Unique IDs are used by default, though it is
possible to assert any scalar Devel::Ladybug object class for the C<id>
column. See L<Devel::Ladybug::ID>, L<Devel::Ladybug::Serial>.

=item * C<name> => L<Devel::Ladybug::Name>

C<name> is a secondary human-readable key.

The assertions for the name attribute may be changed to suit a class's
requirements, and the name value for any object may be freely changed.

For more information on named objects, see L<Devel::Ladybug::Name>.

=item * C<ctime> => L<Devel::Ladybug::DateTime>

C<ctime> is an object's creation timestamp. Devel::Ladybug sets this
when saving an object for the first time.

This is not the same as, and should not be confused with, the
C<st_ctime> filesystem attribute returned by the C<fstat> system call,
which represents inode change time for files. If this ends up being too
confusing or offensive, Devel::Ladybug may use a name other than
C<ctime> for creation time in a future version. It is currently being
left alone.

For more information on timestamps, see L<Devel::Ladybug::DateTime>.

=item * C<mtime> => L<Devel::Ladybug::DateTime>

C<mtime> is the Unix timestamp representing an object's last modified
time. Devel::Ladybug updates this each time an object is saved.

Again, this is an object attribute, and is unrelated to the C<st_mtime>
filesystem attribute returned by the C<fstat> system call.
Devel::Ladybug may use a different name in a future version.

=back

=head2 C<undef> Requires Assertion

Undefined values in objects translate to NULL in the database, and
Devel::Ladybug does not permit this to happen by default.

Instance variables may not be undef, and the corresponding table
column may not be NULL, unless the instance variable was explicitly
asserted as B<optional> in the class prototype. To do so, provide
"optional" as an assertion argument, as in the following example:

  create "YourApp::Example" => {
    ### Do not permit NULL:
    someMandatoryDate => Devel::Ladybug::DateTime->assert,

    ### Permit NULL:
    someOptionalDate => Devel::Ladybug::DateTime->assert(
      subtype(
        optional => true,
      )
    ),

    # ...
  };

=head2 Namespace Matters

Devel::Ladybug's core packages live under the Devel::Ladybug::
namespace. Your classes should live in their own top-level namespace,
e.g. "YourApp::YourClass".

The top level namespace (eg "YourApp") translates, in lower case,
to the name of the app's database. The database name may be overridden
by implementing class method C<databaseName>.

Namespace elements beyond the top-level translate to lower case table
names. In cases of nested namespaces, Perl's "::" delineator is swapped
out for an underscore (_). The table name may be overridden by
implementing class method C<tableName>.

  create "YourApp::Example::Foo" => {
    # overrides default value of "yourapp"
    databaseName => sub {
      my $class = shift;

      return "some_legacy_db";
    },

    # overrides default value of "example_foo"
    tableName => sub {
      my $class = shift;

      return "some_legacy_table";
    },

    # ...
  };

=head1 OBJECT TYPES

Devel::Ladybug object types are used when asserting attributes within a
class, and are also suitable for instantiation or subclassing in a
self-standing manner.

The usage of these types is not mandatory outside the context of
creating a new class-- Devel::Ladybug always returns attributes from
the database in object form, but these object types are not a
replacement for Perl's native data types in general usage, unless the
developer wishes them to be.

These modes of usage are shown below, and covered in greater detail in
specific object class docs.

=head2 DECLARING AS SUBCLASS

By default, a superclass of L<Devel::Ladybug::Node> is used for new
classes. This may be overridden using __BASE__:

  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    __BASE__ => "Devel::Ladybug::Hash",

    # ...
  };

=head2 ASSERTING AS ATTRIBUTES

When defining the allowed instance variables for a class, the
C<assert()> method is used:

  #
  # File: Example.pm
  #
  use Devel::Ladybug qw| :all |;

  create "YourApp::Example" => {
    someString => Devel::Ladybug::Str->assert,
    someInt    => Devel::Ladybug::Int->assert,

  };

=head2 INSTANTIATING AS OBJECTS

When instantiating, the class method C<new()> is used, typically with a
prototype object for its argument.

  #
  # File: somecaller.pl
  #
  use strict;
  use warnings;

  use YourApp::Example;

  my $example = YourApp::Example->new(
    name       => "Hello",
    someString => "foo",
    someInt    => 12345,
  );

  $example->save;

  $example->print;

=head2 IN METHODS

Constructors and setter methods accept both native Perl 5 data types
and their Devel::Ladybug object class equivalents. The setters 
automatically handle any necessary conversion, or throw an exception if
the received arg doesn't quack like a duck.

To wit, native types are OK for constructors:

  my $example = YourApp::Example->new(
    someString => "foo",
    someInt    => 123,
  );

  #
  # someStr became a string object:
  #
  say $example->someString->class;
  # "Devel::Ladybug::Str"

  say $example->someString->length;
  # "3"

  say $example->someString;
  # "foo"

  #
  # someInt became an integer object:
  #
  say $example->someInt->class;
  # "Devel::Ladybug::Int"

  say $example->someInt->sqrt;
  # 11.0905365064094

  say $example->someInt;
  # 123

Native types are OK for setters:

  $example->setSomeInt(456);

  say $example->someInt->class;
  # "Devel::Ladybug::Int"


=head1 CORE OBJECT TYPES

The basic types listed here may be instantiated as objects, and
asserted as inline attributes.

=over 4

=item * L<Devel::Ladybug::Array> - List

=item * L<Devel::Ladybug::Bool> - Overloaded boolean

=item * L<Devel::Ladybug::DateTime> - Overloaded time object

=item * L<Devel::Ladybug::Double> - Overloaded double-precision number

=item * L<Devel::Ladybug::ExtID> - Overloaded foreign key

=item * L<Devel::Ladybug::Float> - Overloaded floating point number

=item * L<Devel::Ladybug::Hash> - Hashtable

=item * L<Devel::Ladybug::ID> - Overloaded GUID primary key

=item * L<Devel::Ladybug::Int> - Overloaded integer

=item * L<Devel::Ladybug::Name> - Unique secondary key

=item * L<Devel::Ladybug::Num> - Overloaded number

=item * L<Devel::Ladybug::Rule> - Regex reference (qr/ /)

=item * L<Devel::Ladybug::Serial> - Auto-incrementing primary key

=item * L<Devel::Ladybug::Str> - Overloaded unicode string

=item * L<Devel::Ladybug::TimeSpan> - Overloaded time range object

=back

=head1 CONSTANTS & ENUMERATIONS

=over 4

=item * L<Devel::Ladybug::Constants> -  "dot rc" values as constants 

=item * L<Devel::Ladybug::Enum> - C-style enumerated types as constants

=back

=head1 ABSTRACT CLASSES & MIX-INS

=over 4

=item * L<Devel::Ladybug::Class> - Abstract "Class" class

=item * L<Devel::Ladybug::Class::Dumper> - Introspection mix-in

=item * L<Devel::Ladybug::Node> - Abstract stored object class

=item * L<Devel::Ladybug::Object> - Abstract object class

=item * L<Devel::Ladybug::Persistence> - Storage and retrieval mix-in

=item * L<Devel::Ladybug::Persistence::Generic> - Abstract base for DBI mixins

=item * L<Devel::Ladybug::Persistence::MySQL> - MySQL/InnoDB overrides

=item * L<Devel::Ladybug::Persistence::PostgreSQL> - PostgreSQL overrides

=item * L<Devel::Ladybug::Persistence::SQLite> - SQLite overrides

=item * L<Devel::Ladybug::Stream> - Buffered iterator for table rows

=item * L<Devel::Ladybug::Scalar> - Base class for scalar values

=item * L<Devel::Ladybug::Subtype> - Instance variable subtyping

=item * L<Devel::Ladybug::Type> - Instance variable typing

=back

=head1 HELPER MODULES

=over 4

=item * L<Devel::Ladybug::Utility> - System functions required globally

=item * L<Devel::Ladybug::Exceptions> - Errors thrown by Devel::Ladybug

=back

=head1 TOOLS

=over 4

=item * C<ladybug-conf> - Generate a .ladybugrc on the local machine

=item * C<ladybug-edit> - Edit Devel::Ladybug objects using VIM and YAML

=item * C<ladybug-dump> - Dump Devel::Ladybug objects to STDOUT in various formats

=back

=head1 EXPORT TAGS

All exports are optional. Specify a tag or symbol by name to import it
into your caller's namespace.

  use Devel::Ladybug qw| :all |;

=over 4

=item * :all

This imports each of the symbols listed below.

=item * :create

This imports the C<create> and C<subtype> class prototyping functions.

=item * :bool

This imports C<true> and C<false> boolean constants.

=item * :yield

This imports the C<yield>, C<emit>, and C<break> functions for array
collectors; see L<Devel::Ladybug::Array>.

=back

=head1 CONFIGURATION AND ENVIRONMENT

=head2 Devel::Ladybug and your DBA

If using MySQL or PostgreSQL, your app's database and the "ladybug"
database should exist with the proper access prior to use - see
L<Devel::Ladybug::Persistence::MySQL>,
L<Devel::Ladybug::Persistence::PostgreSQL>.

=head2 LADYBUG_HOME and .ladybugrc

Devel::Ladybug looks for its config file, C<.ladybugrc>, under
$ENV{LADYBUG_HOME}. LADYBUG_HOME defaults to the current user's home
directory.

To generate a first-time config for the local machine, copy the
.ladybugrc (included with this distribution as C<ladybugrc-dist>) to
the proper location, or run C<ladybug-conf> (also included with this
distribution) as the user running Devel::Ladybug.

See L<Devel::Ladybug::Constants> for information regarding customizing
and extending the local rc file.

=head2 Devel::Ladybug and mod_perl

Devel::Ladybug-based classes used in a mod_perl app should be preloaded
by a startup script. LADYBUG_HOME must be set in the script's BEGIN
block.

For example, in a file C<startup.pl>:

  use strict;
  use warnings;

  BEGIN {
    #
    # Directory with the .ladybugrc:
    #
    $ENV{LADYBUG_HOME} = '/your/ladybug/home';
  }

  use YourApp::Component;
  use YourApp::OtherComponent;

  1;

The startup script should be specified in httpd.conf. Additionally,
you may need to include a B<PerlSetEnv> directive, for example:

  PerlRequire /path/to/your/startup.pl

  <LocationMatch "/.*\.html$">
    SetHandler perl-script

    PerlHandler HTML::Mason::ApacheHandler
    PerlSetEnv LADYBUG_HOME /your/ladybug/home
  </LocationMatch>

=head1 INSTALLATION

Ease of installation is one of Devel::Ladybug's goals. The only
build requirements are a compiler (C<gcc> or equivalent is needed
by CPAN to build a few dependencies), and a working Perl 5 (5.8.8
or greater). Devel::Ladybug's prerequisite Perl packages are handled
by CPAN, and generally install with no fuss. These are listed in
Makefile.PL.

=head2 FROM CPAN (RECOMMENDED)

The recommended way to install Devel::Ladybug is via CPAN:

  perl -MCPAN -e 'install Devel::Ladybug'

Answer "yes" when prompted to install dependencies. You must (of
course) have permission on your local system to do so, which means
you either have superuser access, or your user owns the Perl install.

Devel::Ladybug does not depend on any particular DBI driver-- the
package of your choice needs to be installed separately in order
to be usable by Devel::Ladybug as a backing store type. Currently
supported drivers are: L<DBD::mysql>, L<DBD::Pg>, and L<DBD::SQLite>.

=head2 FROM SOURCE

Assuming dependencies have been installed, installation may also
be done manually:

  cd Devel-Ladybug-xxxx
  perl Makefile.PL # Warns if system is missing prereqs
  make test
  make install

=head2 INSTALL PROBLEMS?

The most common installation problem is due to a compiler not being
present on the local machine. After installing gcc, you may need
to purge the contents of the CPAN build directory to avoid cached
failed build results (e.g. ~root/.cpan/build/*), and re-run the
installation.

Refer to recent CPAN Testers results to see if Devel::Ladybug
"should" work with your particular software stack. Installation
problems may be reported to the author via email (please include
the output from C<make test>)

  http://static.cpantesters.org/distro/D/Devel-Ladybug.html

=head1 SEE ALSO

L<Devel::Ladybug::TLDR>

L<Devel::Ladybug::Class>

Devel::Ladybug is on GitHub: http://github.com/aayars/ladybug

=head1 SUPPORT

Support is available from the author via email.

=head1 AUTHOR

  Alex Ayars <pause@nodekit.org>

=head1 LICENSE AND COPYRIGHT

  Copyright (c) 2009 TiVo Inc.
 
  All rights reserved. This program and the accompanying materials
  are made available under the terms of the Common Public License v1.0
  which accompanies this distribution, and is available at
  http://opensource.org/licenses/cpl1.0.txt

=cut
