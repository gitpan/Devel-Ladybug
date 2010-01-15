#
# File: lib/Devel/Ladybug/DateTime.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#

package Devel::Ladybug::DateTime;

use strict;
use warnings;

use Devel::Ladybug::Class qw| true false |;
use Scalar::Util qw| blessed |;
use Time::Local;

use base qw| Devel::Ladybug::Float |;

use overload
  %Devel::Ladybug::Num::overload,
  '""'  => '_sprint',
  '<=>' => '_compare';

our $datetimeRegex =
  qr/^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)$/;

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed = Devel::Ladybug::Type::__parseTypeArgs(
    sub {
      my $time = $_[0];

      if ( $time && $time =~ $datetimeRegex ) {
        $time = $class->newFrom( $1, $2, $3, $4, $5, $6 );
      }

      Scalar::Util::looks_like_number("$time")
        || Devel::Ladybug::AssertFailed->throw(
        "Received value is not a time");
    },
    @rules
  );

  $parsed{min} = 0     if !defined $parsed{min};
  $parsed{max} = 2**32 if !defined $parsed{max};
  $parsed{columnType} ||= 'DOUBLE(15,4)';
  $parsed{optional} = true if !defined $parsed{optional};

  return $class->__assertClass()->new(%parsed);
}

sub new {
  my $class = shift;
  my $time  = shift;

  if ( $time && $time =~ /$datetimeRegex/ ) {
    return $class->newFrom( $1, $2, $3, $4, $5, $6 );
  }

  my $epoch = 0;

  my $blessed = blessed($time);

  if ( $blessed && $time->can("epoch") ) {
    $epoch = $time->epoch();
  } elsif ( $blessed && overload::Overloaded($time) ) {
    $epoch = "$time";
  } else {
    $epoch = $time;
  }

  Devel::Ladybug::Type::insist( $epoch, Devel::Ladybug::Type::isFloat );

  my $self = \$epoch;

  return bless $self, $class;
}

#   Num $year, Num $month, Num $day, Num $hour, Num $minute, Num $sec
sub newFrom {
  my $class  = shift;
  my $year   = shift;
  my $month  = shift;
  my $day    = shift;
  my $hour   = shift;
  my $minute = shift;
  my $sec    = shift;

  return $class->new(
    Time::Local::timelocal(
      $sec, $minute, $hour, $day, $month - 1, $year - 1900
    )
  );
}

#
# Allow comparison of overloaded objects and native types
#
sub _compare {
  my $date1 = $_[2] ? $_[1] : $_[0];
  my $date2 = $_[2] ? $_[0] : $_[1];

  if ( blessed($date1) && $date1->can("epoch") ) {
    $date1 = $date1->epoch();
  }

  if ( blessed($date2) && $date2->can("epoch") ) {
    $date2 = $date2->epoch();
  }

  $date1 ||= 0;
  $date2 ||= 0;

  return "$date1" <=> "$date2";
}

sub _sprint {
  return shift->value();
}

true;
__END__

=pod

=head1 NAME

Devel::Ladybug::DateTime - Overloaded Time object class

=head1 SYNOPSIS

  use Devel::Ladybug::DateTime;

From Epoch:

  my $time = Devel::Ladybug::DateTime->new( time() );

From YYYY MM DD hh mm ss:

  my $time = Devel::Ladybug::DateTime->newFrom(1999,12,31,23,59,59);

=head1 DESCRIPTION

Time object.

Extends L<Devel::Ladybug::Float>. Overloaded for
numeric comparisons, stringifies as unix epoch seconds unless
overridden.

=head1 PUBLIC CLASS METHODS

=over 4

=item * C<assert(Devel::Ladybug::Class $class: *@rules)>

Returns a new Devel::Ladybug::Type::DateTime instance which
encapsulates the received L<Devel::Ladybug::Subtype> rules.

With exception to C<ctime> and C<mtime>, which default to DATETIME,
DOUBLE(15,4) is the default column type for Devel::Ladybug::DateTime.
This is done in order to preserve sub-second time resolution. This may
be overridden as needed on a per-attribute bases.

To use DATETIME as the column type, specify it as the value to the
C<columnType> subtype arg. When using a DATETIME column, Devel::Ladybug
will automatically ask the database to handle any necessary conversion.

  create "YourApp::Example" => {
    someTimestamp  => Devel::Ladybug::DateTime->assert(
      subtype(
        columnType => "DATETIME",
      )
    ),

    # ...
  };

=item * C<new(Devel::Ladybug::Class $class: Num $epoch)>

Returns a new Devel::Ladybug::DateTime instance which encapsulates the
received value.

  my $object = Devel::Ladybug::DateTime->new($epoch);

=back

=head1 SEE ALSO

This file is part of L<Devel::Ladybug>.

=cut
