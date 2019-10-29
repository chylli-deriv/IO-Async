#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package IO::Async::Protocol::Stream;

use strict;
use warnings;

our $VERSION = '0.32';

use base qw( IO::Async::Protocol );

use Carp;

=head1 NAME

C<IO::Async::Protocol::Stream> - base class for stream-based protocols

=head1 SYNOPSIS

Most likely this class will be subclassed to implement a particular network
protocol.

 package Net::Async::HelloWorld;

 use strict;
 use warnings;
 use base qw( IO::Async::Protocol::Stream );

 sub on_read
 {
    my $self = shift;
    my ( $buffref, $closed ) = @_;

    return 0 unless $$buffref =~ s/^(.*)\n//;
    my $line = $1;

    if( $line =~ m/^HELLO (.*)/ ) {
       my ( $name ) = @_;

       my $on_hello = $self->{on_hello} || $self->can( 'on_hello' );
       $on_hello->( $self, $name );
    }

    return 1;
 }

 sub send_hello
 {
    my $self = shift;
    my ( $name ) = @_;

    $self->write( "HELLO $name\n" );
 }

This small example elides such details as error handling, which a real
protocol implementation would be likely to contain.

=head1 DESCRIPTION

This subclass of L<IO::Async:Notifier> is intended to stand as a base class
for implementing stream-based protocols. It provides an interface similar to
L<IO::Async::Stream>, primarily, a C<write> method and an C<on_read> event
handler.

It contains an instance of an C<IO::Async::Stream> object which it uses for
actual communication, rather than being a subclass of it, allowing a level of
independence from the actual stream being used. For example, the stream may
actually be an L<IO::Async::SSLStream> to allow the protocol to be used over
SSL.

As with C<IO::Async::Stream>, it is required that by the time the protocol
object is added to a Loop, that it either has an C<on_read> method, or has
been configured with an C<on_read> callback handler.

=cut

=head1 EVENTS

The following events are invoked, either using subclass methods or CODE
references in parameters:

=head2 $ret = on_read \$buffer, $handleclosed

The C<on_read> handler is invoked identically to C<IO::Async::Stream>.

=head2 on_closed

The C<on_closed> handler is optional, but if provided, will be invoked after
the stream is closed by either side (either because the C<close()> method has
been invoked on it, or on an incoming EOF).

=cut

=head1 PARAMETERS

The following named parameters may be passed to C<new> or C<configure>:

=over 8

=item on_read => CODE

CODE reference for the C<on_read> event.

=back

=cut

sub configure
{
   my $self = shift;
   my %params = @_;

   for (qw( on_read )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   $self->SUPER::configure( %params );

   if( $self->get_loop ) {
      $self->{on_read} or $self->can( "on_read" ) or
         croak 'Expected either an on_read callback or to be able to ->on_read';
   }
}

sub _add_to_loop
{
   my $self = shift;

   $self->{on_read} or $self->can( "on_read" ) or
      croak 'Expected either an on_read callback or to be able to ->on_read';
}

sub setup_transport
{
   my $self = shift;
   my ( $transport ) = @_;

   $self->SUPER::setup_transport( $transport );

   $transport->configure( 
      on_read => $self->_capture_weakself( sub {
         my $self = shift;
         my ( $transport, $buffref, $closed ) = @_;

         my $on_read = $self->{on_read} ||
                        $self->can( 'on_read' );

         $on_read->( $self, $buffref, $closed );
      } ),
   );
}

sub teardown_transport
{
   my $self = shift;
   my ( $transport ) = @_;

   $transport->configure(
      on_read => undef,
   );

   $self->SUPER::teardown_transport( $transport );
}

=head1 METHODS

=cut

=head2 $protocol->write( $data )

Writes the given data by calling the C<write> method on the contained
transport stream.

=cut

sub write
{
   my $self = shift;
   my ( $data ) = @_;

   $self->transport->write( $data );
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>