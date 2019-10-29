#!/usr/bin/perl -w

use strict;

use Test::More tests => 19;
use Test::Exception;

use IO::Async::TimeQueue;

my $queue = IO::Async::TimeQueue->new();

ok( defined $queue, '$queue defined' );
is( ref $queue, "IO::Async::TimeQueue", 'ref $queue is IO::Async::TimeQueue' );

is( $queue->next_time, undef, '->next_time when empty is undef' );

dies_ok( sub { $queue->enqueue( code => sub { "DUMMY" } ) },
         'enqueue no time or delay fails' );

dies_ok( sub { $queue->enqueue( time => 123 ) },
         'enqueue no code fails' );

dies_ok( sub { $queue->enqueue( delay => 4 ) },
         'enqueue no code fails (2)' );

dies_ok( sub { $queue->enqueue( delay => 5, code => 'HELLO' ) },
         'enqueue code not CODE ref fails' );

$queue->enqueue( time => 1000, code => sub { "DUMMY" } );
is( $queue->next_time, 1000, '->next_time after single enqueue' );

my $fired = 0;

$queue->enqueue( time => 500, code => sub { $fired = 1; } );
is( $queue->next_time, 500, '->next_time after second enqueue' );

$queue->fire( now => 700 );

is( $fired, 1, '$fired after fire at time 700' );
is( $queue->next_time, 1000, '->next_time after fire at time 700' );

$queue->fire( now => 900 );
is( $queue->next_time, 1000, '->next_time after fire at time 900' );

$queue->fire( now => 1200 );

is( $queue->next_time, undef, '->next_time after fire at time 1200' );

$queue->enqueue( time => 1300, code => sub{ $fired++; } );
$queue->enqueue( time => 1301, code => sub{ $fired++; } );

$queue->fire( now => 1400 );

is( $fired, 3, '$fired after fire at time 1400' );
is( $queue->next_time, undef, '->next_time after fire at time 1400' );

my $id = $queue->enqueue( time => 1500, code => sub { $fired++ } );
$queue->enqueue( time => 1505, code => sub { $fired++ } );

is( $queue->next_time, 1500, '->next_time before cancel()' );

$queue->cancel( $id );

is( $queue->next_time, 1505, '->next_time after cancel()' );

$fired = 0;
$queue->fire( now => 1501 );

is( $fired, 0, '$fired after fire at time 1501' );

$queue->fire( now => 1510 );

is( $fired, 1, '$fired after fire at time 1510' );