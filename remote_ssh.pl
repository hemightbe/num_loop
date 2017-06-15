#!/usr/bin/perl

use IO::Socket;

sub check_ssh
{
   my $other_port = shift;
   if (!defined $other_port) {
      $other_port = 22;
   }
   @output = `ps auxwww | grep ssh`;
   my $running = 0;
   foreach (@output)
   {
      # ssh -N -f -R 50000:localhost:22 support@support.cache-a.com
      if (/root\s+(\d+)\s+.*?ssh -N -f -. (\d+)\:localhost\:${other_port}\s+support\@support\.cache\-a/)
      {
         $ssh_pid = $1;
         $remote_port = $2;
         $running = 1;
      }
      elsif (/root\s+(\d+)\s+.*?ssh -N -f -. (\d+)\:localhost\:\d+\s+support\@support\.cache\-a/)
      {
         $ssh_pid = $1;
         $remote_port = $2;
         $running = 1;
      }
   }
   return $running;
}
sub list_ssh_connections
{
   @output = `ps auxwww | grep ssh`;
   my $running = 0;
   foreach (@output)
   {
      # ssh -N -f -[LR] 50000:localhost:22 support@support.cache-a.com
      if (/root\s+(\d+)\s+.*?ssh -N -f -(.) (\d+)\:localhost\:(\d+)\s+support\@support\.cache\-a/)
      {
         if ($2 eq "R") {
            print "SSH Telly Side Local Port: $4 Remote Port: $3 PID: $1\n"; 
         }
         elsif ($2 eq "L") {
            print "SSH Server Side Local Port: $3 Remote Port: $4 PID: $1\n"; 
         }
         print $_;
         $running = 1;
      }
   }
   return $running;
}
$version_file = "/usr/cache-a/etc/version.txt";
sub get_id {
 
   my $ret_val = 0;
   @output = `cat $version_file`;
   foreach (@output)
   {
      if (/serial\=(.*?)\&/)
      {
         $ret_val = $1;
         last;
      }
   }
   return $ret_val;
}

$check_status = 0;
$stop_ssh = 0;
$remote_port = "";
$start_support = 0;
$list_connect = 0;
$local_port = "";
$auto_close = "";

## Get command line arguments#
for ($in = 0; $in <= $#ARGV;$in++)
{
   if ($ARGV[$in] eq "-status")
   {
      $check_status = 1;
   }
   elsif ($ARGV[$in] eq "-stop")
   {
      $check_status = 0;
      $stop_ssh = 1;
   }
   elsif ($ARGV[$in] eq "-list")
   {
      $check_status = 0;
      $list_connect = 1;
   }
   elsif ($ARGV[$in] eq "-start")
   {
      $check_status = 0;
      $start_ssh = 1;
   }
   elsif ($ARGV[$in] eq "-auto_close")
   {
      $auto_close = 1;
   }
   elsif ($ARGV[$in] eq "-support")
   {
      $check_status = 0;
      $start_support = 1;
   }
   elsif (($ARGV[$in] eq "-local_port") && (($in+1) <= $#ARGV))
   {
      $local_port = $ARGV[$in+1];
      $in++;
   }
   elsif (($ARGV[$in] eq "-port") && (($in+1) <= $#ARGV))
   {
      $remote_port = $ARGV[$in+1];
      $in++;
   }
}

if ($list_connect == 1)
{
   list_ssh_connections();
   exit;
}
if ($check_status == 1)
{
   if (check_ssh())
   {
      print "Running port $remote_port process $ssh_pid\n";
      exit 0;
   }
   else
   {
      print "Not Running\n";
      exit 1;
   }
}
if ($stop_ssh == 1)
{
   if (check_ssh())
   {
      print "Stopped process $ssh_pid\n";
      `kill -9 $ssh_pid`;
      if (-r "/etc/cron.d/close_remote_ssh") {
         `rm -f /etc/cron.d/close_remote_ssh`;
      }
   }
   else
   {
      print "Not Running\n";
   }
}
if ($start_ssh == 1)
{
   if (check_ssh())
   {
      print "Running process $ssh_pid\n";
      exit 1;
   }

   # now we get the port to start it on
   if ($remote_port eq "")
   {
      $serial = get_id();
      $last_five = substr($serial,length($serial)-5);
      $remote_port = $last_five;
   }
   print "Starting on port: $remote_port\n";
   if ($remote_port ne "")
   {
      system("ssh -N -f -R ${remote_port}:localhost:22 support\@support.cache-a.com");
   }
   # If it is auto_close then we schedule a cron script to delete in 23 hours
   if ($auto_close == 1)
   {
      $cur_hour = -1;
      $_ = `date`;
      if (/.*?\s+.*?\s+.*?\s+(\d+)\:/)
      {
         $cur_hour = $1;
         if ($cur_hour == 0)
         {
            $cur_hour = 23;
         } else {
            $cur_hour -= 1;
         }
      }
      if ($cur_hour != -1)
      {
         if (open(FS,">/etc/cron.d/close_remote_ssh"))
         {
            print FS "# use /bin/sh to run commands\n";
            print FS "SHELL=/bin/sh\n";
            print FS "# mail any output to nothing\n";
            print FS "MAILTO=\"\"\n";
            print FS "#\n";
            print FS "0 $cur_hour * * *       root    /usr/cache-a/bin/remote_ssh.pl -stop > /dev/null 2>&1;rm -f /etc/cron.d/close_remote_ssh\n";
            close(FS);
         }
      }
   }
}
if ($start_support == 1)
{
   if ($remote_port eq "")
   {
      print "Enter Serial #:";
      $serial = <STDIN>;
      chop($serial);
      $last_five = substr($serial,length($serial)-5);
      $server_port = $last_five;
   }
   else {
      $server_port = $remote_port;
   }
   print "Starting on server port: $server_port\n";
   if (check_ssh($server_port))
   {
      print "Running port $remote_port process $ssh_pid\n";
      exit 1;
   }
   if ($server_port ne "")
   {
      if ($local_port eq "") {
         $local_port = 7777;
      }
      system("ssh -N -f -L ${local_port}:localhost:${server_port} support\@support.cache-a.com");
      print "Login by: ssh -p ${local_port} localhost\n";
      print "Copy by: scp -P ${local_port} localhost\n";
      print "You will need the root password of the remote telly\n";
   }
}
