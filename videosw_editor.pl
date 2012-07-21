#!c:\Perl\bin\perl.exe


##
## Video Switcher editor PC script
##
## Copyright Oleg Gavrikov <oleg.gavrikov@gmail.com>.  GPL.
##


##Include standart Perl library
use strict;
use IO::File;
use Time::Local;
use LWP;
use Data::Dumper;
use Mozilla::CA;
use JSON;
use POSIX;

## Include common VideoSwitch library
use videosw;

### Don't edit after this line ###################################################

### Global VARs ##################################################################
my $browser;

## read configuration parameters from file
my %global_cfg=();
parse_config(\%global_cfg);


### Subs #########################################################################

sub my_time ()
{
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =  localtime(time);
 return sprintf "%4d-%02d-%02d_%02d_%02d_%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec;
}

sub my_time_short ()
{
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =  localtime(time);
 return sprintf "%4d-%02d-%02d_%02d", $year+1900,$mon+1,$mday,$hour;
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

sub connect_to_video_server ($) 
{ my $browser = shift @_;

 ## connect to video switcher
 $$browser = LWP::UserAgent->new (ssl_opts => { verify_hostname => 0 });
 $$browser->ssl_opts( SSL_ca_file => Mozilla::CA::SSL_ca_file() );
 $$browser->agent('Mozilla');

 $$browser->credentials(
   $global_cfg{server_vsw},
   $global_cfg{server_vsw_realm},
   $global_cfg{server_vsw_user} => $global_cfg{server_vsw_password}
 );
_log "Start connect to: $global_cfg{server_vsw}";
return;
}

#--------------------------------

sub write_to_file ($) 
{ my $ch_parameters = shift @_;

 ## determine local time
 my $time = my_time;

 ## determine local file name for video parameters
 my $input_file="$global_cfg{channels_dir}/videosw_channel_".$$ch_parameters{channel};

 _log "Open file:$input_file for write";

 ## open file for write video parameters
 open (FH, "> $input_file") || log_die "can't write input file: $input_file with error: $!";

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

 my $response = $$bw->get($global_cfg{get_channel_url});
 _log "Get from video server URL: $global_cfg{get_channel_url}";

 ## Reformat JSON from server
 my $str=$response->content;


 _log "String from video server: $str";
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
   my  $document = $$bw->post($global_cfg{post_channel_url}, { dataType=> 'channelDetails', data => $str });
   _log "Send to video server: $str";

   return;
}  

#--------------------------------
sub read_channels_from_files ($)
{ my $channels= shift @_;

  ## read dir with channels file
  opendir ( DIR, $global_cfg{channels_dir} );
  my @ch_files= readdir(DIR); 

  ## process channels file
  foreach my $file (@ch_files) {

    ## determine file name
    if ( $file =~ /^videosw_channel_\d+$/ ) {
      open (FH, "<$global_cfg{channels_dir}/$file");
      my $str=<FH>;

      ## determine file format
      if ( $str=~/(^[\d_-]+\s*:)\s*(\{.*\})/ ) {

           ## decode channel info from JSON in file
           my $json = new JSON;
           my $channel = $json->allow_nonref->relaxed->decode($2);

           ## write info to channels_from_files hash
           $$channels { $$channel{channel} } = $channel;

      } else {
           _log ("Can't find valid channel config in: $file");
      }## end if

    }## end if 

  }## end foreach

}


### Main ########################################################################

## initialize video parameters hash
my %ch_parameters;

## init log file
initLogFile ( $global_cfg{log_dir}."\videosw_editor_".my_time_short.".log" );

## process command line arguments
foreach my $command_element (@ARGV) {

  ## determine that string with our parameters
  if ( $command_element =~ /^\s*VIDEO_(.*?):/i ) {

     my ($key,$val)=$command_element=~/^\s*VIDEO_(.*?):\s*(.*)/i;

     ## skip local filename
     $key=lc ($key);
     next if ($key =~ /^file$/);

     ## skip not permitted url
     if ($key =~ /^pageurl$/i && $val !~ /(^|\/|\.)($global_cfg{permitted_url})(\/|$)/i) {
        log_die ("Not permitted $key: $val. Exit.");
        exit; 
     } else {
        $val=url_trans($val);
        
     } ## end if

     ## full video parameters hash
     $ch_parameters{$key}=$val; 
     
  }## end_if

}## end foreach

my $a=to_json(\%ch_parameters);
_log "-- Start -------------------------------";
_log ("Read from NET card: $a");

## process channels from files
my %channels_from_files=();
read_channels_from_files (\%channels_from_files);

my $is_file_rtmp_url_changed=1;

foreach my $ch_from_file ( keys %channels_from_files ) {

   ## we need channels with known URL
   if ( $ch_parameters{pageurl} eq $channels_from_files{$ch_from_file}{pageurl} ) {

     if ( ( $ch_parameters{url} eq $channels_from_files{$ch_from_file}{url} ) && $ch_parameters{url} !~ /^$/ ) {

          _log ("Channel number $ch_from_file RTMP url unchanged in file"); 

          #reset flag
          $is_file_rtmp_url_changed=0;

     } else {
      
          ## determine channel number from file
          $ch_parameters{channel} = $channels_from_files{$ch_from_file}{channel};

          ## write channel status to file
          write_to_file (\%ch_parameters);
          _log ("Channel number $ch_from_file change RTMP URL to $channels_from_files{$ch_from_file}{url}");

     }## end if
   }## end if
 
}## end foreach

## connect to video switcher
my $bw;
connect_to_video_server (\$bw);

## get channels params from video server
my $channels;
get_from_vsw_server (\$channels,\$bw);

my $is_channel_on_server=0;

## process hash with channels URL from video_server
foreach my $ch_from_server (@$channels) {

   ## determine channel number
   if ( url_trans( $ch_from_server->{uri} ) eq $ch_parameters{pageurl} ) {

       ## write to log if channel is correct and server know it
       _log ( 'Editor PC find on VideoSwitch Server channel '. $ch_from_server->{id} .' URL '.$ch_parameters{pageurl});   

       ## set channel id
       $ch_parameters{channel} = $ch_from_server->{id} ;

       $is_channel_on_server=1;

       ## compare server RTMP URL and URL from RMC                           
       if ( url_trans( $ch_from_server->{last_url} ) ne $ch_parameters{url} ) {
   
         ## write to video server
         send_to_vsw_server (\%ch_parameters, \$bw);  

         ## write channel status to file
         write_to_file (\%ch_parameters);
        
       } else {
        
         _log ('On VideoSwitcher server same RTMP url for channel number:'. $ch_from_server->{id});

       }## end if

   } ## end if
  
}##end foreach

_log ( "$ch_parameters{pageurl} not on VideoSwitcher server $global_cfg{server_vsw}") if ($is_channel_on_server == 0);
_log "-- Stop --------------------------------";

exit;