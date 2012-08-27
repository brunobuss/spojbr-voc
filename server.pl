use Mojolicious::Lite;
use Mojo::IOLoop;
use Mojo::UserAgent;
use Config::INI::Reader;
use DateTime;
use DateTime::Duration;
use Text::Trim;
use Data::Printer;
use List::MoreUtils qw{any};
use utf8;

#Hypnotoad config to use with nginx:
#app->config(hypnotoad => {listen => ['http://*:10000'], proxy => 1});

my $contests;
my $probe_time = 15;
my $penalty_per_wrong_sub = 20; #in minutes;

get '/' => 'index';


under '/:contest' => sub {
  my $self = shift;

  unless( exists($contests->{$self->param('contest')}) ){
    $self->render(template => "404", status => 404);
    return;
  }

  return 1;
};

get '/' => sub{
  my $self = shift;

  my $c = $self->param('contest');

  $self->stash(probs => [$contests->{$c}->{prob_ids}] ) ;
  $self->stash(users => [$contests->{$c}->{user_ids}] ) ;

} => "contest";

get '/scoreboard' => sub{
  my $self = shift;
  my $c = $self->param('contest');
  $self->render(json => $contests->{$c}->{scoreboard});
};


## Fetch and parse SPOJ subs every $probe_time seconds:
Mojo::IOLoop->recurring(
  $probe_time => sub {

    my $now = DateTime->now(time_zone => 'America/Sao_Paulo')->set_time_zone('UTC');
    my $ua  = Mojo::UserAgent->new;

    foreach my $c (keys(%{$contests})){

      my $c_st = $contests->{$c}->{starttime};
      my $c_et = $contests->{$c}->{starttime} + $contests->{$c}->{duration};

      next if($now < $c_st || $now > $c_et);

      foreach my $u ( @{$contests->{$c}->{user_ids}} ){

        my $url = 'http://br.spoj.pl/status/' . $u . '/signedlist/';
        my $spojres = $ua->get($url)->res->body;

        my $temp = [];

        foreach my $l (split('\n', $spojres)){
          my @s = split('\|', $l);
          shift @s;
          trim @s;

          next unless (int(@s) == 7); #Not a line that we are looking for...
          next unless ($s[0] =~ /\d+/); #A header line...

          #This problem isn't on our contest:
          next unless (any { $_ eq $s[2] } @{$contests->{$c}->{prob_ids}});

          #This problem is in out contest, but out of time submission...
          my $c_st_f = $c_st->ymd . ' ' . $c_st->hms;
          my $c_et_f = $c_et->ymd . ' ' . $c_et->hms;
          next unless ($s[1] le $c_et_f);
          last unless ($s[1] ge $c_st_f);

          #Sub already readed, so this and all that follow are already on our in memory sub db;
          last if exists $contests->{$c}->{sub_index}->{$s[0]};

          $contests->{$c}->{sub_index}->{$s[0]} = int( @{$contests->{$c}->{subs}} );
          unshift @{$temp}, {id => $s[0], problem => $s[2], result => $s[3], user => $u};
        }

        #Processing subs for user $u on the right order now...
        foreach my $s (@{$temp}){

          my $prob_number = $contests->{$c}->{probs_index}->{$s->{problem}} + 3;
          my $user_number = $contests->{$c}->{users_index}->{$u};
          my $res = $s->{result};

          my $r = $contests->{$c}->{scoreboard}->[$user_number];

          if( $r->[prob_number]->[0] == -1 ){

            $r->[prob_number]->[1]++; #One more submission to this problem;

            if( $res eq 'AC' ){

              #TODO: Set the time of correct submission.
              #$r->[prob_number]->[0] = $now - $c_st;

              #Update total penalty.
              $r->[2] += $r->[prob_number]->[1] * $penalty_per_wrong_sub;

            }


          }


        }



        #push @{$contests->{$c}->{subs}}, (@{$temp});

      }

    }

  }
);

# Forward error messages to the application log
Mojo::IOLoop->singleton->reactor->on(error => sub {
  my ($reactor, $err) = @_;
  app->log->error($err);
});


##Startup code:

# Load contests config file and then check if every contest is ok,
# split problem ids and user ids and set the DateTime object for
# the contest.
sub load_contests {

  my $count;

  die "No config file found!" unless -r 'contests.conf';

  $contests = Config::INI::Reader->read_file('contests.conf');

  foreach (keys(%{$contests})){

    $contests->{$_}->{name} = $_ unless exists $contests->{$_}->{name};

    die "Contest $_ don't has a problem list." unless exists $contests->{$_}->{prob_ids};
    die "Contest $_ don't has a user list." unless exists $contests->{$_}->{user_ids};
    die "Contest $_ don't has a start time." unless exists $contests->{$_}->{starttime};
    die "Contest $_ don't has a duration." unless exists $contests->{$_}->{duration};

    $contests->{$_}->{prob_ids} = [split(' ', $contests->{$_}->{prob_ids})];
    $contests->{$_}->{user_ids} = [split(' ', $contests->{$_}->{user_ids})];
    $contests->{$_}->{starttime} = [split(' ', $contests->{$_}->{starttime})];

    $contests->{$_}->{starttime} = DateTime->new(
                                    year   => $contests->{$_}->{starttime}->[0],
                                    month  => $contests->{$_}->{starttime}->[1],
                                    day    => $contests->{$_}->{starttime}->[2],
                                    hour   => $contests->{$_}->{starttime}->[3],
                                    minute => $contests->{$_}->{starttime}->[4],
                                    time_zone => 'America/Sao_Paulo',
                                  )->set_time_zone('UTC');

    $contests->{$_}->{duration} = DateTime::Duration->new(hours => $contests->{$_}->{duration});

    $contests->{$_}->{subs} = [];
    $contests->{$_}->{sub_index} = {};

    $count = 0;
    $contests->{$_}->{probs_index} = {};
    foreach my $p ( @{$contests->{$_}->{prob_ids}} ) {
      $contests->{$_}->{probs_index}->{$p} = $count++;
    }

    $count = 0;
    $contests->{$_}->{users_index} = {};
    foreach my $u ( @{$contests->{$_}->{user_ids}} ) {
      $contests->{$_}->{users_index}->{$u} = $count++;
    }

    $contests->{$_}->{scoreboard} = [];
    foreach my $u ( @{$contests->{$_}->{user_ids}} ){

      my $r = [];
      push @{$r}, $u, 0, 0; #user_id, acs, total_penalty

      foreach my $p ( @{$contests->{$_}->{prob_ids}} ) {
        push @{$r}, [-1, 0]; #Accepted time, Submissions
      }

      push @{$contests->{$_}->{scoreboard}}, $r;

    }


  }

}

load_contests();

app->secret('super_secret_phrase_here');
app->start;
__DATA__
@@index.html.ep
Hello World! :-)

@@contest.html.ep
Contest here :-)

@@404.html.ep
Contest not found =/
