use strict;
use warnings;
use FindBin;
use PerlSpeak;
use Data::Dumper;
use feature 'say';
BEGIN { unshift @INC, "$FindBin::Bin/../lib" }

use PushBulletWebSocket;
my $perlspeak = PerlSpeak->new(tts_engine=>"festival");

# push_message_tts(pushBulletMessage)
# uses PerlSpeak to read text messages
# returns 1 if it called PerlSpeak backend at least once
# returns 0 if no PerlSpeak say happened
sub push_message_tts {
  my $message = shift;
  return unless ref $message->{push} eq 'HASH';
  my $push_type = $message->{push}->{type};
  return 0 if $push_type ne 'sms_changed';
  my $hasNotification = 0;
  foreach my $notification (@{$message->{push}->{notifications}}) {
    $hasNotification = 1;
    my $sender = $notification->{title};
    my $notification_msg = "Text Message From " . $sender . ", " . $notification->{body};
    $perlspeak->say($notification_msg);
  }
  return $hasNotification;
}

my $api_key = $ENV{'PUSHBULLET_API_KEY'};
my $pushbullet = PushBulletWebSocket->new(api_key=>$api_key);

$pushbullet->events->on(message => sub {
  my ($events, $message) = @_;
  print Dumper $message;
  push_message_tts($message);
});
$pushbullet->events->on(error => sub {
  my ($events, $error) = @_;
  warn "Error caught: $error";
});
$pushbullet->events->on(reconnect => sub {
  my ($events, $tx, $code, $reason) = @_;
  say "WebSocket closed with status $code.";
  warn "Reconnecting websocket...";
});

$pushbullet->connect_websocket;
