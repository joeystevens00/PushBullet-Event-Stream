use strict;
use warnings;
use FindBin;
use PerlSpeak;
use Data::Dumper;
use feature 'say';
BEGIN { unshift @INC, "$FindBin::Bin/../lib" }

use PushBulletWebSocket;
my $perlspeak = PerlSpeak->new(tts_engine=>"festival");

# valid_push_sms_msg($message)
# validates $message is push event of type sms_changed
# returns undef on invalid message
# returns message on valid
sub valid_push_sms_msg {
  my $message = shift;
  return unless ref $message->{push} eq 'HASH';
  return unless $message->{push}->{type} eq 'sms_changed';
  return $message;
}

# push_message_tts(pushBulletMessage)
# uses PerlSpeak to read text messages
# returns number of times perlspeak was called
sub push_message_tts {
  my $message = valid_push_sms_msg(shift);
  my $named_contacts_only = shift || 1; # Skip messages from non-contacts
  my $no_email_addresses = shift || 1; # Skip messages from email addresses

  my $num_notifications = 0;
  return $num_notifications unless $message;

  my $email_chars = qr/(\w|\.|-|_)/;
  foreach my $notification (@{$message->{push}->{notifications}}) {
    my $sender = $notification->{title};
    next if $named_contacts_only && $sender =~ /^\d+$/;
    next if $no_email_addresses && $sender =~ /^\w$email_chars+\w\@\w$email_chars+\w$/; # Close enough
    $num_notifications++;
    my $notification_msg = "Text Message From " . $sender . ", " . $notification->{body};
    $perlspeak->say($notification_msg);
  }
  return $num_notifications;
}

my $api_key = $ENV{'PUSHBULLET_API_KEY'};
my $pushbullet = PushBulletWebSocket->new(api_key=>$api_key, debug=>1);

$pushbullet->events->on(message => sub {
  my ($events, $message) = @_;
  push_message_tts($message);
});

$pushbullet->connect_websocket;
