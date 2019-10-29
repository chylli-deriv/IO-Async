#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2008,2009 -- leonerd@leonerd.org.uk

package IO::Async::Listener;

use strict;
use warnings;

our $VERSION = '0.21';

use IO::Async::Handle;

use POSIX qw( EAGAIN );
use Socket::GetAddrInfo qw( :Socket6api AI_PASSIVE );

use Socket qw( SO_ACCEPTCONN SO_REUSEADDR );

use Carp;

=head1 NAME

C<IO::Async::Listener> - listen on network sockets for incoming connections

=head1 SYNOPSIS

This object is used indirectly via an C<IO::Async::Loop>:

 use Socket qw( SOCK_STREAM );

 use IO::Async::Stream;

 use IO::Async::Loop;
 my $loop = IO::Async::Loop->new();

 $loop->listen(
    service  => "echo",
    socktype => SOCK_STREAM,

    on_accept => sub {
       my ( $newclient ) = @_;

       $loop->add( IO::Async::Stream->new(
          handle => $newclient,

          on_read => sub {
             my ( $self, $buffref, $closed ) = @_;
             $self->write( $$buffref );
             $$buffref = "";
             return 0;
          },
       ) );
    },

    on_resolve_error => sub { print STDERR "Cannot resolve - $_[0]\n"; },
    on_listen_error  => sub { print STDERR "Cannot listen\n"; },
 );

 $loop->loop_forever;

=head1 DESCRIPTION

This module extends an C<IO::Async::Loop> to give it the ability to create
listening sockets, and accept incoming connections on them.

There are two modes of operation. Firstly, a list of addresses can be provided
which will be listened on. Alternatively as a convenience, if a service name
is provided instead of a list of addresses, then these will be resolved using
the underlying loop's C<resolve()> method into a list of addresses.

=cut

# Internal constructor
sub new
{
   my $class = shift;
   my ( %params ) = @_;

   my $loop = delete $params{loop} or croak "Expected a 'loop'";

   my $self = bless {
      loop => $loop,
   }, $class;

   return $self;
}

=head1 METHODS

=cut

=head2 $loop->listen( %params )

This method sets up a listening socket using the addresses given, and will
invoke a callback each time a new connection is accepted on the socket.
Addresses may be given directly, or they may be looked up using the
system's name resolver. As a convenience, an existing listening socket
can be passed directly instead.

If multiple addresses are given, or resolved from the service and hostname,
then each will be attempted in turn until one succeeds.

In plain address mode, the C<%params> hash takes the following keys:

=over 8

=item addrs => ARRAY

Reference to an array of (possibly-multiple) address structures to attempt to
listen on. Each should be in the layout described for C<addr>. Such a layout
is returned by the C<getaddrinfo> named resolver.

=item addr => ARRAY

Shortcut for passing a single address to listen on; it may be passed directly
with this key, instead of in another array of its own.

The address (or each element of the C<addrs> array) should be a reference to
an array, with at least the following elements:

 [ $family, $socktype, $protocol, $address ]

The first three arguments will be passed to a C<socket()> call and, if
successful, the fourth to a C<bind()> call on the resulting socket. The socket
will then be C<listen()>ed to put it into listening mode. Any trailing
elements in this array will be ignored.

=back

In named resolver mode, the C<%params> hash takes the following keys:

=over 8

=item service => STRING

The service name to listen on.

=item host => STRING

The hostname to listen on. Optional. Will listen on all addresses if not
supplied.

=item family => INT

=item socktype => INT

=item protocol => INT

=item flags => INT

Optional. Other arguments to pass along with C<host> and C<service> to the
C<getaddrinfo()> call.

=item on_resolve_error => CODE

A continuation that is invoked when the name resolution attempt fails. This is
invoked in the same way as the C<on_error> continuation for the C<resolve>
method.

=back

To pass an existing socket handle, the C<%params> hash takes the following
keys:

=over 8

=item handle => IO

The IO handle containing an existing listen-mode socket.

=back

In either case, the following keys are also taken:

=over 8

=item on_accept => CODE

A callback that is invoked whenever a new client connects to the socket. It is
passed the new socket handle

 $on_accept->( $clientsocket );

=item on_listen => CODE

Optional. A callback that is invoked when the listening socket is ready.
Typically this would be used in the name resolver case, in order to inspect
the socket's sockname address, or otherwise inspect the filehandle.

 $on_listen->( $listensocket );

=item on_notifier => CODE

Optional. A callback that is invoked when a C<IO::Async::Handle> object has
been constructed around the listening socket, and added to the underlying
C<IO::Async::Loop> object. Typically this can be used to store a reference to
the notifier so that it can later be removed from the loop.

 $on_notifier->( $notifier )

=item on_listen_error => CODE

A continuation this is invoked after all of the addresses have been tried, and
none of them succeeded. Becasue there is no one error message that stands out
as particularly noteworthy, none is given to this continuation. To track
individual errors, see the C<on_fail> callback.

=item on_fail => CODE

Optional. A callback that is invoked if a syscall fails while attempting to
create a listening sockets. It is passed the name of the syscall that failed,
the arguments that were passed to it, and the error generated. I.e.

 $on_fail->( "socket", $family, $socktype, $protocol, $! );

 $on_fail->( "sockopt", $sock, $optname, $optval, $! );

 $on_fail->( "bind", $sock, $address, $! );

 $on_fail->( "listen", $sock, $queuesize, $! );

=item queuesize => INT

Optional. The queue size to pass to the C<listen()> calls. If not supplied,
then 3 will be given instead.

=item reuseaddr => BOOL

Optional. If true or not supplied then the C<SO_REUSEADDR> socket option will
be set. To prevent this, pass a false value such as 0.

=back

If more than one address is provided or resolved, then a separate listening
socket will be created on each.

=cut

sub listen
{
   my $self = shift;
   my ( %params ) = @_;

   my $on_accept = $params{on_accept};
   ref $on_accept eq "CODE" or croak "Expected 'on_accept' as CODE reference";

   # Shortcut
   if( $params{addr} and not $params{addrs} ) {
      $params{addrs} = [ delete $params{addr} ];
   }

   my $on_notifier = $params{on_notifier}; # optional
   !defined $on_notifier or ref $on_notifier eq "CODE" or croak "Expected 'on_notifier' to be a CODE reference";

   if( my $handle = $params{handle} ) {
      defined eval { $handle->sockname } or croak "IO handle $handle does not have a sockname";

      # So now we know it's at least some kind of socket. Is it listening?
      # SO_ACCEPTCONN would tell us, but not all OSes implement it. Since it's
      # only a best-effort sanity check, we won't mind if the OS doesn't.
      my $acceptconn = eval { $handle->sockopt( SO_ACCEPTCONN ) };
      !defined $acceptconn or $acceptconn or croak "Socket is not accepting connections";

      my $notifier = $self->_listen_sock( $handle, $on_accept );
      $on_notifier->( $notifier ) if defined $on_notifier;

      return;
   }

   my $on_listen = $params{on_listen}; # optional
   !defined $on_listen or ref $on_listen eq "CODE" or croak "Expected 'on_listen' to be a CODE reference";

   if( $params{on_error} ) {
      carp "'on_error' is now deprecated, use 'on_listen_error' instead";
      $params{on_listen_error} = delete $params{on_error};
   }

   my $on_listen_error = $params{on_listen_error};
   ref $on_listen_error eq "CODE" or croak "Expected 'on_listen_error' as a CODE reference";

   my $on_fail = $params{on_fail};
   !defined $on_fail or ref $on_fail eq "CODE" or croak "Expected 'on_fail' to be a CODE reference";

   my $queuesize = $params{queuesize} || 3;

   my $loop = $self->{loop};

   if( my $addrlist = $params{addrs} ) {
      my $reuseaddr = 1;
      $reuseaddr = 0 if defined $params{reuseaddr} and not $params{reuseaddr};

      foreach my $addr ( @$addrlist ) {
         my ( $family, $socktype, $proto, $address ) = @$addr;

         my $sock;

         unless( $sock = $loop->socket( $family, $socktype, $proto ) ) {
            $on_fail->( "socket", $family, $socktype, $proto, $! ) if $on_fail;
            next;
         }

         if( $reuseaddr ) {
            unless( $sock->sockopt( SO_REUSEADDR, 1 ) ) {
               $on_fail->( "sockopt", $sock, SO_REUSEADDR, 1, $! ) if $on_fail;
               next;
            }
         }

         unless( $sock->bind( $address ) ) {
            $on_fail->( "bind", $sock, $address, $! ) if $on_fail;
            next;
         }

         unless( $sock->listen( $queuesize ) ) {
            $on_fail->( "listen", $sock, $queuesize, $! ) if $on_fail;
            next;
         }

         $on_listen->( $sock ) if defined $on_listen;

         my $notifier = $self->_listen_sock( $sock, $on_accept );
         $on_notifier->( $notifier ) if defined $on_notifier;

         return;
      }

      # If we got this far, then none of the addresses succeeded
      $on_listen_error->();
   }

   elsif( defined $params{service} ) {
      my $on_resolve_error = delete $params{on_resolve_error};
      ref $on_resolve_error eq "CODE" or croak "Expected 'on_resolve_error' as CODE reference";

      my $host = delete $params{host} || "";

      my $service = delete $params{service};
      defined $service or $service = ""; # might be 0

      my $family   = delete $params{family} || 0;
      my $socktype = delete $params{socktype} || 0;
      my $protocol = delete $params{protocol} || 0;

      my $flags = ( delete $params{flags} || 0 ) | AI_PASSIVE;

      $loop->resolve(
         type => 'getaddrinfo',
         data => [ $host, $service, $family, $socktype, $protocol, $flags ],

         on_resolved => sub {
            $loop->listen( 
               %params,
               addrs => [ @_ ],
            );
         },

         on_error => $on_resolve_error,
      );
   }

   else {
      croak "Expected either 'service' or 'addrs' or 'addr' arguments";
   }
}

sub _listen_sock
{
   my $self = shift;
   my ( $sock, $on_accept ) = @_;

   my $loop = $self->{loop};

   my $notifier = IO::Async::Handle->new(
      read_handle => $sock,
      on_read_ready => sub {
         my $newclient = $sock->accept();
         if( defined $newclient ) {
            $on_accept->( $newclient );
            # TODO: Consider what it might return
         }
         elsif( $! == EAGAIN ) {
            # No client ready after all. Perhaps we're sharing the listen
            # socket with other processes? Anyway; not fatal, just ignore it
         }
         else {
            die "Cannot accept - $!";
         }
      },
   );

   $loop->add( $notifier );

   return $notifier;
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans E<lt>leonerd@leonerd.org.ukE<gt>
