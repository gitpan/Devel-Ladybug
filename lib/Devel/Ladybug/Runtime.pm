package Devel::Ladybug::Runtime;

use strict;
use warnings;

our $Backends;

sub import {
  my $class = shift;
  my $path  = shift;

  my $caller = caller;

  my $temprc = join( "/", $path, ".ladybugrc" );

  return __setenv( $caller, $path ) if -e $temprc;

  if ( !-d $path ) {
    die "$path is not a directory (weird)";
  } elsif ( !-w $path ) {
    die "$path is not writable (can't make a temp .ladybugrc)";
  }

  if ( !open( OPRC, ">", $temprc ) ) {
    my $reason = $! || "Unusable filesystem ($temprc unwritable)";

    die($reason);
  }

  print OPRC qq|
--- 
dbPass: ~
dbHost: localhost
dbPort: ~
dbUser: ladybug
memcachedHosts: 
  - 127.0.0.1:11211
rcsBindir: /usr/bin
rcsDir: RCS
scratchRoot: $path/scratch
sqliteRoot: $path/sqlite
yamlRoot: $path/yaml
yamlHost: ~
|;
  close(OPRC);

  __setenv( $caller, $path );

  $Backends = Devel::Ladybug::Hash->new;

  $Backends->{"SQLite"} =
    Devel::Ladybug::Persistence::__supportsSQLite();

  $Backends->{"MySQL"} = Devel::Ladybug::Persistence::__supportsMySQL();

  if ( !$Backends->{"MySQL"} ) {
    print
      "----------------------------------------------------------\n";
    print
"If you would like to enable MySQL tests for Devel::Ladybug, please remedy\n";
    print
"the issue shown in the diagnostic message below. You will need\n";
    print
      "to create a local MySQL DB named 'ladybug', and grant access, ie:\n";
    print "\n";
    print "> mysql -u root -p\n";
    print "> create database ladybug;\n";
    print "> grant all on ladybug.* to ladybug\@localhost;\n";

    if ($@) {
      my $error = $@;
      chomp $error;

      print "\n";
      print "Diagnostic message:\n";
      print $error;
      print "\n";
    }
  }

  $Backends->{"PostgreSQL"} =
    Devel::Ladybug::Persistence::__supportsPostgreSQL();

  if ( !$Backends->{"PostgreSQL"} ) {
    print
      "----------------------------------------------------------\n";
    print
"If you would like to enable pgsql tests for Devel::Ladybug, please remedy\n";
    print
"the issue shown in the diagnostic message below. You will need\n";
    print
"to create a local pgsql DB and user named 'ladybug' + grant access.\n";
    print "\n";

    if ($@) {
      my $error = $@;
      chomp $error;

      print "\n";
      print "Diagnostic message:\n";
      print $error;
      print "\n";
    }
  }

  $Backends->{"Memcached"} =
    scalar(
    keys %{ $Devel::Ladybug::Persistence::memd->server_versions } );

  return 1;
}

sub __setenv {
  my $caller = shift;
  my $path   = shift;

  $ENV{LADYBUG_HOME} = $path;

  eval q| use Devel::Ladybug qw(:all) |;

  for (@Devel::Ladybug::EXPORT) {
    do {
      no warnings "once";
      no strict "refs";

      *{"$caller\::$_"} = *{"Devel::Ladybug::$_"};
    };
  }

  return 1;
}

1;
__END__

=pod

=head1 NAME

Devel::Ladybug::Runtime - Initialize Devel::Ladybug at runtime instead
of compile time

=head1 SYNOPSIS

  #
  # Set up a self-destructing Devel::Ladybug environment which evaporates
  # when the process exits:
  #
  use strict;
  use warnings;

  use vars qw| $tempdir $path |;

  BEGIN: {
    $tempdir = File::Tempdir->new;

    $path = $tempdir->name;
  };

  require Devel::Ladybug::Runtime;

  Devel::Ladybug::Runtime->import($path);

=head1 DESCRIPTION

Enables the creation of temporary or sandboxed Devel::Ladybug
environments. Allows loading of the Devel::Ladybug framework at
runtime.

Good for testing, and not much else.

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut
