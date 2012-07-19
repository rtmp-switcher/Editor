#!/usr/bin/perl
use strict;
use IO::File;
use Time::Local;
use LWP;
use Data::Dumper;
use Mozilla::CA;
use JSON;

### Configuration parameters #####################################################
my $CHANNELS_DIR="c:/videosw/channels/";
my $LOG_DIR="c:/videosw/log/";
my $permitted_url="ustream\.tv|youtube\.com";
my $server_vsw="1.2.3.4:443";
my $server_vsw_realm="VideoSwitcher";
my $server_vsw_user="";
my $server_vsw_password="";
my $GET_CHANNEL_URL="https://1.2.3.4/video_switcher/control.php?getChannels";
my $POST_CHANNEL_URL="https://1.2.3.4/video_switcher/control.php";

### Don't edit after this line ###################################################

### Global VARs ##################################################################
my $browser;

### Subs #########################################################################

sub my_time ()
{
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =  localtime(time);
 my $time = sprintf "%4d-%02d-%02d_%02d_%02d_%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec;

 # my $time_in_sec = timegm ($sec, $min,$hour, $mday, $mon, $year);

 return $time;
}

sub url_trans ($)
{ my $url=shift @_;

  $url=~s/\n//g;
  $url=~s/^\s*//g;
  $url=~s/\s.*$//g;
  $url=~s/^http://ig;
  $url=~s/^\/+//g;
 
  return $url; 
}

#--------------------------------

sub logg ($)
{ 
 my $str = shift @_;

 ## determine local time
 my $time = my_time;
 my $time_short = $time;
 $time_short =~ s/_\d+_\d+$//;

 ## determine local file name for video parameters
 my $log_file="$LOG_DIR/videosw_$time_short.log";

 open (FH, ">> $log_file") || die "can't write log file: $log_file with error: $!";

 print FH "$time:\t $str\n";

 close FH;

}

#--------------------------------

sub connect_to_video_server ($) 
{ my $browser = shift @_;

 ## connect to video switcher
 $$browser = LWP::UserAgent->new (ssl_opts => { verify_hostname => 0 });
 $$browser->ssl_opts( SSL_ca_file => Mozilla::CA::SSL_ca_file() );
 $$browser->agent('Mozilla');

 $$browser->credentials(
   $server_vsw,
   $server_vsw_realm,
   $server_vsw_user => $server_vsw_password
 );
logg "Start connect to: $server_vsw";
return;
}

#--------------------------------

sub write_to_file ($) 
{ my $ch_parameters = shift @_;

 ## determine local time
 my $time = my_time;

 ## determine local file name for video parameters
 my $input_file="$CHANNELS_DIR/videosw_channel_".$$ch_parameters{channel};

 ## open file for write video parameters
 open (FH, "> $input_file") || die "can't write input file: $input_file with error: $!";

 ## write file to IN directory
 print FH "$time : ";
 print FH to_json($ch_parameters);

 close FH;
 return;
}

#--------------------------------
sub get_from_vsw_server ($$)
{
 my ($channels, $bw) =  @_;

 my $response = $$bw->get($GET_CHANNEL_URL);
 logg "Get from video server URL: $GET_CHANNEL_URL";

 ## Reformat JSON from server
 my $str=$response->content;


 logg "String from video server: $str";
 #$str='['.$str.']';
 #$str=~s/}\s*{/}\,{/ig;

 my $json = new JSON;

 ## these are some nice json options to relax restrictions a bit:
 $$channels = $json->allow_nonref->relaxed->decode($str);

 return;
}

#--------------------------------
sub send_to_vsw_server ($$)
{  my ($ch_parameters, $bw) =  @_;
  
   my $str=to_json($ch_parameters);
   my  $document = $$bw->post($POST_CHANNEL_URL, { dataType=> 'channelDetails', data => $str });
   logg "Send to video server: $str";

   return;
}  

#--------------------------------
sub read_channels_from_files ($)
{ my $channels= shift @_;

  ## read dir with channels file
  opendir ( DIR, $CHANNELS_DIR );
  my @ch_files= readdir(DIR); 

  ## process channels file
  foreach my $file (@ch_files) {

    ## determine file name
    if ( $file =~ /^videosw_channel_\d+$/ ) {
      open (FH, "<$CHANNELS_DIR/$file");
      my $str=<FH>;

      ## determine file format
      if ( $str=~/(^[\d_-]+\s*:)\s*(\{.*\})/ ) {

           ## decode channel info from JSON in file
           my $json = new JSON;
           my $channel = $json->allow_nonref->relaxed->decode($2);

           ## write info to channels_from_files hash
           $$channels { $$channel{channel} } = $channel;

      } else {
           logg ("Can't find valid channel config in: $file");
      }## end if

    }## end if 

  }## end foreach

}




### Main ########################################################################

## initialize video parameters hash
my %ch_parameters;

## process command line arguments
foreach my $command_element (@ARGV) {

  ## determine that string with our parameters
  if ( $command_element =~ /^\s*VIDEO_(.*?):/i ) {

     my ($key,$val)=$command_element=~/^\s*VIDEO_(.*?):\s*(.*)/i;

     ## skip local filename
     $key=lc ($key);
     next if ($key =~ /^file$/);

     ## skip not permitted url
     if ($key =~ /^pageurl$/i && $val !~ /(^|\/|\.)($permitted_url)(\/|$)/i) {
        logg ("Not permitted $key: $val. Exit.");
        exit; 
     } else {
        $val=url_trans($val);
        
     } ## end if

     ## full video parameters hash
     $ch_parameters{$key}=$val; 
     
  }## end_if

}## end foreach

my $a=to_json(\%ch_parameters);
logg "-- Start -------------------------------";
logg ("Read from NET card: $a");

## process channels from local files

my %channels_from_file=();
read_channels_from_files (\%channels_from_file);

## connect to video switcher
my $bw;
connect_to_video_server (\$bw);

## get channels params from video server
my $channels;
get_from_vsw_server (\$channels,\$bw);

## process hash with channels URL from video_server
foreach my $ch_from_server (@$channels) {
   print "---";
   ## update channel URL
   if ( url_trans( $ch_from_server->{uri} ) eq $ch_parameters{pageurl} ) {

       ## write to log if channel is correct and server know it
       logg ( 'Editor PC find channel '. $ch_from_server->{id} .' URL '.$ch_parameters{pageurl});   

       ## set channel id
       $ch_parameters{channel} = $ch_from_server->{id} ;

       ## write channel status to file
       write_to_file (\%ch_parameters);
       
       ## write to video server
       send_to_vsw_server (\%ch_parameters, \$bw);  

   }## end if
   
}##end foreach
logg "-- Stop --------------------------------";

exit;