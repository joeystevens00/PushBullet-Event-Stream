package PushBulletWebSocket::Events;
use Mojo::Base 'Mojo::EventEmitter';
# message($deseralized_json)
# given $events_class, deseralized PushBullet Event
sub message {  shift->emit(message => shift) }
# error($errorString)
# given $events_class, $errorString
sub error {  shift->emit(error => shift) }
# reconnect($tx, $code, $reason)
# given $events_class then same args as a Mojo::Transaction finish event : $events_class, $tx, $code, $reason
sub reconnect {  shift->emit(reconnect => shift) }
package PushBulletWebSocket;
use Moose;
use JSON;
use Mojo::UserAgent;
use Data::Dumper;
use Try::Tiny;
use feature 'say';
has 'api_key' => (is=>'rw', isa=>'Str', required=>1);
has 'endpoint' => (is=>'rw', isa=>'Str', lazy=>1, default=> sub { "wss://stream.pushbullet.com/websocket/" . shift->api_key });
has 'ua' => (is=>'rw', isa=>'Mojo::UserAgent', lazy=>1, default=>sub {
  $ENV{'MOJO_CLIENT_DEBUG'}=1 if shift->debug;
  my $ua = Mojo::UserAgent->new;
  $ua->inactivity_timeout(0);
  $ua;
});

has 'debug' => (is=>'rw', isa=>'Bool', default=>sub {$ENV{'DEBUG_PUSHBULLET_WEBSOCKET'}});
has 'events' => (is=>'rw', isa=>'PushBulletWebSocket::Events', default=>sub {PushBulletWebSocket::Events->new});

before 'connect_websocket' => sub {
  my $self = shift;
  $self->install_debug_event_handlers if $self->debug;
};

sub install_debug_event_handlers {
  my $self = shift;
  $self->events->on(message => sub {
    my $events = shift;
    my $message = shift;
    print Dumper $message;
  });
  $self->events->on(reconnect => sub {
    my ($events, $tx, $code, $reason) = @_;
    $reason = $reason ? $reason : "";
    $code = $code ? $code : "";
    say "WebSocket closed with status $code due to $reason";
    warn "Reconnecting websocket...";
  });
  $self->events->on(error => sub {
    my ($events, $error) = @_;
    warn "Error caught: $error";
  });
}

sub decode_response {
  my $self = shift;
  my $json = shift;
  try { decode_json $json }
  catch {  $self->events->error("decode_json error: $_") };
}

sub connect_websocket {
  my $self = shift;
  $self->ua->websocket($self->endpoint => sub {
    my ($ua, $tx) = @_;
    $self->events->error('WebSocket handshake failed!') and return unless $tx->is_websocket;
    #say 'Subprotocol negotiation failed!' and return unless $tx->protocol;
    $tx->on(finish => sub {
      my ($tx, $code, $reason) = @_;
      $self->events->reconnect($tx, $code, $reason) and return unless $tx->is_websocket;
      $self->connect_websocket;
    });
    $tx->on(message => sub {
      my ($tx, $msg) = @_;
      my $msg_content = $self->decode_response($msg);
      return unless ref $msg_content eq 'HASH';
      $self->events->message($msg_content);
    });
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}



no Moose;
__PACKAGE__->meta->make_immutable();

1;
