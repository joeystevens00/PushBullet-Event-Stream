use strict;
use warnings;
use FindBin;
use PerlSpeak;
use Data::Dumper;
use feature 'say';
use Carp;
BEGIN { unshift @INC, "$FindBin::Bin/../lib" }

use PushBulletWebSocket;
my $perlspeak = PerlSpeak->new(tts_engine=>"festival");

# truncate_str($str, $len, $end_c)
# Truncates string to length appending end_characters (defaults to elipsis)
# End characters length is accounted for in truncating so returned string will be length not length+end_c
# params:
# $str : string to truncate
# $len : length to truncate to
# $end_c : end characters to append to string (default: ...)
sub truncate_str {
  my ($str, $len, $end_c) = (shift, shift, shift);
  croak "Usage: truncate_str(string, length, end_char(default:'...'))" unless $str && $len;
  $end_c = "..." unless $end_c; # Default: Elipsis
  my $end_c_len = length $end_c;
  $str = length $str < $len ? $str : substr($str, 0, ($len-$end_c_len)) . $end_c;
  $str;
}

# notify_phone_call($push)
#
sub notify_phone_call {
  my $push = shift;
  my $caller = $push->body;
  my $notification_msg = "Call from, $caller";
  $perlspeak->say($notification_msg);
  return 1;
}

# notify_text_message($message->push->notifications->[$i])
# args:
# notification: Individual push notification
# named_contacts_only: Bool (default true) : Don't read text messages from phone numbers/short codes (Note: Sender is contact preference name or phone number)
# no_email_addresses: Bool (default true) : Don't read text messages from email addresses
sub notify_text_message {
  my $notification = shift;
  my $named_contacts_only = shift || 1; # Skip messages from non-contacts
  my $no_email_addresses = shift || 1; # Skip messages from email addresses
  my $email_chars = qr/(\w|\.|-|_)/;
  return 0 unless ref $notification eq 'HASH';

  my $sender = $notification->{title};

  return 0 if $named_contacts_only && $sender =~ /^\d+$/;
  return 0 if $no_email_addresses && $sender =~ /^\w$email_chars+\w\@\w$email_chars+\w$/; # Close enough
  my $notification_msg = "Text Message From, " . $sender . ": " . truncate_str($notification->{body}, 80);
  $perlspeak->say($notification_msg);
  return 1;
}

# notify_outlook_meeting($message->push)
# uses Outlook's push notifications to do a PerlSpeak notification
# Outlook's pushes fire in minute intervals
# when a meeting is about to start, started, or has ended
sub notify_outlook_meeting {
  my $push = shift;
  my $meeting_time = $push->body;
  my $meeting = $push->title;
  # $time_til_meeting:
  # $meeting_time: '9:30 AM (in 10 minutes)'
  # capture: in 10 minutes
  # '9:30 AM (meeting has started)'
  # capture: meeting has started
  # 2:00 PM (meeting has ended)
  # capture: meeting has ended
  (my $time_til_meeting = $meeting_time) =~ s/(.*?)\((.*?)\)/$2/;
  return unless $time_til_meeting =~ /10|started/; # Notify at 10 minutes and when meeting starts
  my $notification_msg = "$meeting: $time_til_meeting";
  $perlspeak->say($notification_msg);
}

# parse_mirror_notifications($message)
# Calls notification routines for mirror notifications  (i.e push type 'mirror')
sub parse_mirror_notifications {
  my $message = shift;
  notify_outlook_meeting($message->push) if $message->push->application_name =~ /outlook/i;
  notify_phone_call($message->push) if $message->push->title =~ /incoming call/i;
}

# parse_push_notifications($message)
# Calls notification routines for push notifications
sub parse_push_notifications {
  my $message = shift;
  my $push_notifications = $message->push->notifications;
  if($push_notifications) {
    foreach my $notification (@$push_notifications) {
      notify_text_message($notification) if $message->push->type eq 'sms_changed';
    }
  }
  parse_mirror_notifications($message) if $message->push->type eq 'mirror';
}

my $api_key = $ENV{'PUSHBULLET_API_KEY'};
my $pushbullet = PushBulletWebSocket->new(api_key=>$api_key, debug=>1);

$pushbullet->events->on(message => sub {
  my ($events, $message) = @_;
  parse_push_notifications($message) if $message->type eq 'push';
});

$pushbullet->connect_websocket;
