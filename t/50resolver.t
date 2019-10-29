#!/usr/bin/perl -w

use strict;

use IO::Async::Test;

use Test::More tests => 17;
use Test::Exception;

use Socket qw( AF_INET SOCK_STREAM pack_sockaddr_in INADDR_LOOPBACK );
use Socket::GetAddrInfo qw(
   :newapi getaddrinfo getnameinfo
   NI_NUMERICHOST NI_NUMERICSERV
);

use IO::Async::Loop::Poll;

my $loop = IO::Async::Loop::Poll->new();

testing_loop( $loop );

my $resolver = $loop->resolver;
isa_ok( $resolver, "IO::Async::Resolver", '$loop->resolver' );

my @pwuid = getpwuid( $< );

{
   my $result;

   $resolver->resolve(
      type => 'getpwuid',
      data => [ $< ], 
      on_resolved => sub { $result = [ @_ ] },
      on_error => sub { die "Test died early" },
   );

   wait_for { $result };

   is_deeply( $result, \@pwuid, 'getpwuid' );
}

{
   my $result;

   $loop->resolve(
      type => 'getpwuid',
      data => [ $< ],
      on_resolved => sub { $result = [ @_ ] },
      on_error => sub { die "Test died early" },
   );

   wait_for { $result };

   is_deeply( $result, \@pwuid, 'getpwuid via $loop->resolve' );
}

SKIP: {
   my $user_name = $pwuid[0];
   skip "getpwnam - No user name", 1 unless defined $user_name;

   my @pwnam = getpwnam( $user_name );

   my $result;

   $resolver->resolve(
      type => 'getpwnam',
      data => [ $user_name ],
      on_resolved => sub { $result = [ @_ ] },
      on_error => sub { die "Test died early" },
   );

   wait_for { $result };

   is_deeply( $result, \@pwnam, 'getpwnam' );
}

my @proto = getprotobyname( "tcp" );

{
   my $result;

   $resolver->resolve(
      type => 'getprotobyname',
      data => [ "tcp" ],
      on_resolved => sub { $result = [ @_ ] },
      on_error => sub { die "Test died early" },
   );

   wait_for { $result };

   is_deeply( $result, \@proto, 'getprotobyname' );
}

SKIP: {
   my $proto_number = $proto[2];
   skip "getprotobynumber - No protocol number", 1 unless defined $proto_number;

   my @proto = getprotobynumber( $proto_number );

   my $result;

   $resolver->resolve(
      type => 'getprotobynumber',
      data => [ $proto_number ],
      on_resolved => sub { $result = [ @_ ] },
      on_error => sub { die "Test died early" },
   );

   wait_for { $result };

   is_deeply( $result, \@proto, 'getprotobynumber' );
}

# Some systems seem to mangle the order of results between PF_INET and
# PF_INET6 depending on who asks. We'll hint AF_INET + SOCK_STREAM to minimise
# the risk of a spurious test failure because of ordering issues

my ( $localhost_err, @localhost_addrs ) = getaddrinfo( "localhost", "www", { family => AF_INET, socktype => SOCK_STREAM } );

{
   my $result;

   $resolver->resolve(
      type => 'getaddrinfo_array',
      data => [ "localhost", "www", "inet", "stream" ],
      on_resolved => sub { $result = [ 'resolved', @_ ] },
      on_error    => sub { $result = [ 'error',    @_ ] },
   );

   wait_for { $result };

   if( $localhost_err ) {
      is( $result->[0], "error", 'getaddrinfo_array - error' );
      is_deeply( $result->[1], "$localhost_err\n", 'getaddrinfo_array - error message' );
   }
   else {
      is( $result->[0], "resolved", 'getaddrinfo_array - resolved' );

      my @got = @{$result}[1..$#$result];
      my @expect = map { [ @{$_}{qw( family socktype protocol addr canonname )} ] } @localhost_addrs;

      is_deeply( \@got, \@expect, 'getaddrinfo_array - resolved addresses' );
   }
}

{
   my $result;

   $resolver->resolve(
      type => 'getaddrinfo_hash',
      data => [ host => "localhost", service => "www", family => "inet", socktype => "stream" ],
      on_resolved => sub { $result = [ 'resolved', @_ ] },
      on_error    => sub { $result = [ 'error',    @_ ] },
   );

   wait_for { $result };

   if( $localhost_err ) {
      is( $result->[0], "error", 'getaddrinfo_hash - error' );
      is_deeply( $result->[1], "$localhost_err\n", 'getaddrinfo_hash - error message' );
   }
   else {
      is( $result->[0], "resolved", 'getaddrinfo_hash - resolved' );

      my @got = @{$result}[1..$#$result];

      is_deeply( \@got, \@localhost_addrs, 'getaddrinfo_hash - resolved addresses' );
   }
}

{
   my $result;

   $resolver->getaddrinfo(
      host     => "localhost",
      service  => "www",
      family   => "inet",
      socktype => "stream",
      on_resolved => sub { $result = [ 'resolved', @_ ] },
      on_error    => sub { $result = [ 'error',    @_ ] },
   );

   wait_for { $result };

   if( $localhost_err ) {
      is( $result->[0], "error", '$resolver->getaddrinfo - error' );
      is_deeply( $result->[1], "$localhost_err\n", '$resolver->getaddrinfo - error message' );
   }
   else {
      is( $result->[0], "resolved", '$resolver->getaddrinfo - resolved' );

      my @got = @{$result}[1..$#$result];

      is_deeply( \@got, \@localhost_addrs, '$resolver->getaddrinfo - resolved addresses' );
   }
}

{
   my $result;

   $resolver->getaddrinfo(
      host     => "127.0.0.1",
      service  => "80",
      socktype => SOCK_STREAM,
      on_resolved => sub { $result = [ 'resolved', @_ ] },
      on_error    => sub { $result = [ 'error',    @_ ] },
   );

   is( $result->[0], 'resolved', '$resolver->getaddrinfo on numeric host/service is synchronous' );

   my @got = @{$result}[1..$#$result];

   is_deeply( \@got, \@localhost_addrs, '$resolver->getaddrinfo resolved addressess synchronously' );
}

my $testaddr = pack_sockaddr_in( 80, INADDR_LOOPBACK );
my ( $testerr, $testhost, $testserv ) = getnameinfo( $testaddr );

{
   my $result;

   $resolver->getnameinfo(
      addr => $testaddr,
      on_resolved => sub { $result = [ 'resolved', @_ ] },
      on_error    => sub { $result = [ 'error',    @_ ] },
   );

   wait_for { $result };

   if( $testerr ) {
      is( $result->[0], "error", '$resolver->getnameinfo - error' );
      is_deeply( $result->[1], "$testerr\n", '$resolver->getnameinfo - error message' );
   }
   else {
      is( $result->[0], "resolved", '$resolver->getnameinfo - resolved' );
      is_deeply( [ @{$result}[1..2] ], [ $testhost, $testserv ], '$resolver->getnameinfo - resolved names' );
   }
}

{
   my $result;

   $resolver->getnameinfo(
      addr => $testaddr,
      flags => NI_NUMERICHOST|NI_NUMERICSERV,
      on_resolved => sub { $result = [ 'resolved', @_ ] },
      on_error    => sub { $result = [ 'error',    @_ ] },
   );

   is_deeply( $result, [ resolved => "127.0.0.1", 80 ], '$resolver->getnameinfo with flags=NI_NUMERICHOST|NI_NUMERICSERV is synchronous' );
}