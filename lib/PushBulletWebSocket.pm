package PushBulletWebSocket::Event::Message::Push;
use Moose;
use Try::Tiny;
has 'push_content' => (is=>'rw', isa=>'HashRef', required=>1);

foreach my $arrayOfhashes_attr (qw/actions notifications/) {
  has $arrayOfhashes_attr => (is => 'rw', isa=>'Maybe[ArrayRef[HashRef]]', lazy=>1, default => sub {
    my $self = shift;
    try { $self->push_content->{$arrayOfhashes_attr} } catch {undef}
  });
}

foreach my $str_attr (qw/title source_device_iden type application_name body icon package_name notification_id source_user_iden notification_tag/) {
  has $str_attr => (is => 'rw', isa=>'Maybe[Str]', lazy=>1, default => sub {
    my $self = shift;
    try { $self->push_content->{$str_attr} } catch {undef}
  });
}

package PushBulletWebSocket::Event::Message;
use Moose;
use Try::Tiny;
has 'events' => (is=>'rw', isa=>'PushBulletWebSocket::Events', weak_ref=>1, required=>1);
has 'body' => (is=>'rw', isa=>'HashRef', required=>1);
has 'type' => (is=>'rw', isa=>'Maybe[Str]', lazy=>1, default=> sub {
  my $self = shift;
  $self->body->{type};
});
has 'push' => (is=>'rw', isa=>'PushBulletWebSocket::Event::Message::Push', lazy=>1, default=> sub {
  my $self = shift;
  my $push_content = $self->body->{push} || {};
  PushBulletWebSocket::Event::Message::Push->new(push_content=>$push_content);
});

around qw(type push) => sub { # GETing is always safe (fail is undef)
  my $orig = shift;
  my $self = shift;

  return try { $self->$orig() } catch { $self->events->error("Unable to call $orig: $_"); undef }
      unless @_;

  return $self->$orig(@_);
};



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
use utf8; # Allow utf8 in source code
use Encode;
use feature 'unicode_strings';
binmode(STDOUT, ":utf8"); # Allow printing UTF8 chars
use Moose;
use JSON;
use Mojo::UserAgent;
use Data::Dumper;
use Try::Tiny;
use PushBulletWebSocket::Event::Message;
use feature 'say';
has 'api_key' => (is=>'rw', isa=>'Str', required=>1);
has 'endpoint' => (is=>'ro', isa=>'Str', lazy=>1, default=> sub { "wss://stream.pushbullet.com/websocket/" . shift->api_key });
has 'ua' => (is=>'ro', isa=>'Mojo::UserAgent', lazy=>1, default=>sub {
  $ENV{'MOJO_CLIENT_DEBUG'}=1 if shift->debug;
  my $ua = Mojo::UserAgent->new;
  $ua->inactivity_timeout(0);
  $ua;
});

has 'debug' => (is=>'rw', isa=>'Bool', default=>sub {$ENV{'DEBUG_PUSHBULLET_WEBSOCKET'}});
has 'events' => (is=>'ro', isa=>'PushBulletWebSocket::Events', default=>sub {PushBulletWebSocket::Events->new});

before 'connect_websocket' => sub {
  my $self = shift;
  $self->install_debug_event_handlers if $self->debug;
};

sub install_debug_event_handlers {
  my $self = shift;
  $self->events->on(message => sub {
    my $events = shift;
    my $message = shift;
    print Dumper $message->body;
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

  my $d_json = try {
    decode_json(encode('utf-8', $json));
  }
  catch {  $self->events->error("decode_json error: $_"); {} };
  PushBulletWebSocket::Event::Message->new(body=>$d_json, events=>$self->events);
}

sub connect_websocket {
  my $self = shift;
  $self->ua->websocket($self->endpoint => sub {
    my ($ua, $tx) = @_;
    $self->events->error('WebSocket handshake failed!') and return unless $tx->is_websocket;
    #say 'Subprotocol negotiation failed!' and return unless $tx->protocol;
    $tx->on(finish => sub {
      my ($tx, $code, $reason) = @_;
      $self->events->reconnect($tx, $code, $reason);
      $self->connect_websocket;
    });
    $tx->on(message => sub {
      my ($tx, $msg) = @_;
      my $msg_content = $self->decode_response($msg);
      $self->events->error('Message isn\'t serialized correctly.') and return unless ref $msg_content eq 'PushBulletWebSocket::Event::Message';
      $self->events->message($msg_content);
    });
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}



no Moose;
__PACKAGE__->meta->make_immutable();

1;

