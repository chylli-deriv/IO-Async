#!/usr/bin/perl

use strict;
use warnings;

use IO::Async::Test;

use Test::More;
use Test::Fatal;

use POSIX qw( WIFEXITED WEXITSTATUS );

use IO::Async::Loop;

my $loop = IO::Async::Loop->new_builtin;

testing_loop( $loop );

my $exitcode;

$loop->open_child(
   code => sub { 0 },
   on_finish => sub { ( undef, $exitcode ) = @_; },
);

undef $exitcode;
wait_for { defined $exitcode };

ok( WIFEXITED($exitcode),      'WIFEXITED($exitcode) after sub { 0 }' );
is( WEXITSTATUS($exitcode), 0, 'WEXITSTATUS($exitcode) after sub { 0 }' );

$loop->open_child(
   command => [ $^X, "-e", 'exit 5' ],
   on_finish => sub { ( undef, $exitcode ) = @_; },
);

undef $exitcode;
wait_for { defined $exitcode };

ok( WIFEXITED($exitcode),      'WIFEXITED($exitcode) after perl -e exit 5' );
is( WEXITSTATUS($exitcode), 5, 'WEXITSTATUS($exitcode) after perl -e exit 5' );

ok( exception { $loop->open_child(
         command => [ $^X, "-e", 1 ]
      ) },
   'Missing on_finish fails'
);

ok( exception { $loop->open_child( 
         command => [ $^X, "-e", 1 ],
         on_finish => "hello"
      ) },
   'on_finish not CODE ref fails'
);

ok( exception { $loop->open_child(
         command => [ $^X, "-e", 1 ],
         on_finish => sub {},
         on_exit => sub {},
      ) },
   'on_exit parameter fails'
);

done_testing;
