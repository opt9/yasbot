#!/usr/bin/perl

use strict;
use warnings;

use LWP::Simple;
use Encode;
use Encode::Alias;
use encoding 'utf8';
use Data::Dumper;

use POE qw(
            Component::IRC 
            Component::IRC::State
            Component::IRC::Plugin::URI::Find 
            Component::IRC::Plugin::Google::Calculator
            Component::IRC::Plugin::Logger
         );

use POE::Component::IRC::Plugin::Google::Calculator;
define_alias( qr/65001/ => '"utf-8"' );
define_alias( qr/(?:x-)?uhc$/i => '"cp949"');
define_alias( qr/(?:x-)?windows-949$/i => '"cp949"');
define_alias( qr/ks_c_5601-1987$/i     => '"cp949"');

binmode STDOUT, ":utf8";

use constant NICK => 'toad';
use constant IRCNAME => 'toad';
use constant USERNAME => 'toad';
use constant ALIAS => 'frog';
use constant IRCLOG => $ENV{"HOME"} . '/log/ircbot/';

my $server = 'irc.hanirc.org';
my $naver_map_url = 'http://map.naver.com/?query=';
my @channels = ('#security');
#my @channels = ('#tailbot');

$| = 1;
my $irc = POE::Component::IRC->spawn( 
                                     nick => NICK,
                                     ircname => IRCNAME,
                                     username => USERNAME,
                                     alias => ALIAS,
                                     server => $server,
                                     plugin_debug => 0,
                                     debug => 0,
                                    ) or die "Oh noooo! $!";

POE::Session->create(
                     package_states => [
                                        main => [ qw(
                                                      _default 
                                                      _start 
                                                      irc_001 
                                                      irc_join 
                                                      irc_public 
                                                      irc_urifind_uri 
                                                      irc_google_calculator
                                                   ) 
                                                ],
                                       ],
                     heap => { irc => $irc },
                    );

POE::Kernel->run();
exit;

sub _start {
  my $heap = $_[HEAP];
  my $irc = $heap->{irc};

  # Initialize plugins
  $irc->plugin_add('UriFind' => POE::Component::IRC::Plugin::URI::Find->new);
  $irc->plugin_add('GoogleCalc' => POE::Component::IRC::Plugin::Google::Calculator->new(
                                                                                        trigger          => qr/^!calc\s+(?=\S)/i,
                                                                                        addressed        => 0,
                                                                                        auto             => 1,
                                                                                        debug            => 0,
                                                                                        response_event   => 'irc_google_calculator',
                                                                                        listen_for_input => [ qw(public notice privmsg) ],
                                                                                       ));
  $irc->plugin_add('Logger', POE::Component::IRC::Plugin::Logger->new(
                                                                      Path    => IRCLOG,
                                                                      DCC     => 0,
                                                                      Private => 0,
                                                                      Public  => 1,
                                                                      Notices => 1,
                                                                      Sort_by_date => 1,
                                                                      Strip_color => 1,
                                                                      Strip_formatting => 1,
                                                                     ));

  $irc->yield( register => 'all' );
  $irc->yield( connect => {} );
  return;
}

sub irc_001 {
  my $sender = $_[SENDER];
  my $irc = $sender->get_heap();

  print "Connected to ", $irc->server_name(), "\n";

  # we join our channels
  $irc->yield( join => $_ ) for @channels;
  return;
}

sub irc_join {
  my ($sender, $who, $where) = @_[SENDER, ARG0, ARG1];
  my ($nick, $host) = split /!/, $who;
  my $channel = $where;

  if ($nick ne $irc->nick_name()) {
    $nick= decode("euc-kr", $nick);
    print STDOUT "$nick is joined.\n";
    $irc->yield( privmsg => $channel => $nick . " : Hello" );
  }
  return;
}

sub irc_public {
  my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];

  if ($what =~ /^!([a-z0-9]+)\s?(.*?)?$/) {
    my ($command, $desc)=($1, $2);

    if ($command eq 'map') {
      my $address=$naver_map_url . URI::Escape::uri_escape($desc);
      print STDOUT ":Requester $nick -> :Map " . Encode::decode("euc-kr", $desc) . "\n";
      $irc->yield(privmsg => $channel => $address);
    }

    # add new commands
  }

  return;
}

sub irc_urifind_uri {
  my ($who, $channel, $url, $obj, $msg) = @_[ARG0 .. ARG4];
  my $nick = ( split /!/, $who )[0];

  my $ua=LWP::UserAgent->new;
  $ua->agent("Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1");

  #print STDOUT Dumper($obj);
  print STDOUT ":Requester $nick -> :Visit $url\n";
  my $response = $ua->get($url);
  if ($response->is_success) {
    my $encoding = $response->content_type_charset;
    my $title = $response->header('Title');
    $title = decode("$encoding", $title);
    print STDOUT ":Title $title\n";
    $irc->yield(notice => $channel => $title);
  } else {
    print STDOUT ":Connection $url error: $!\n";
  }

  return;
}

sub irc_google_calculator {
  my $href = $_[ARG0];
  my $who = $href->{'who'};
  my $nick = ( split /!/, $who )[0];
  my $channel = $href->{'channel'};
  my $result = $href->{'result'};

  #print STDOUT Dumper($href);
  print STDOUT ":Requester $nick :Channel $channel :Result $result\n";
  $irc->yield(privmsg => $channel => $nick . " $result\n");

  return;
}

sub _default {
  my ($event, $args) = @_[ARG0 .. $#_];
  my @output = ( "$event: " );

  for my $arg (@$args) {
    $arg = decode('euc-kr', $arg);
    if ( ref $arg eq 'ARRAY' ) {
      push( @output, '[' . join(', ', @$arg ) . ']' );
    } else {
      push ( @output, "'$arg'" );
    }
  }
  print join ' ', @output, "\n";
  return 0;
}
