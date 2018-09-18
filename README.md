```perl
my $pushbullet = PushBulletWebSocket->new(api_key=>$api_key, debug=>($ENV{'DEBUG_PUSHBULLET_WEBSOCKET'}||0));

# Listen for Message Events
$pushbullet->events->on(message => sub {
  my ($events, $message) = @_;
  if($message->type eq 'push') {
    my $push_notifications = $message->push_notifications;
    foreach my $notification(@$push_notifications) {
      my $title = $notification->{title}; # Title/Body will mean different things depending on the type of push notification
      my $body = $notification->{title};
      say $title, ": ", $body;
    }
  }
});

# Connect Websocket. All events should be registered at this point
# Debug event handlers will be called before this if debug=1
$pushbullet->connect_websocket;
```
