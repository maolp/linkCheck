#!/usr/bin/perl -w
#
# Script to automatically run the following tests for modems
# Ping, FTP Download and FTP Upload
#
# Additionally the script collects information from the modem
#
# Supported Modems:
# 1. Cradlepoint CBA750B
# 2. Cradlepoint IBR350L
# 3. Zyxel DSL Modem P-6551
#
#
# See the associated configuration file for details. This file
# doesn't needs to be modified by a user.
#
# Author: Gaurav Sabharwal (gaurav.sabharwal@hughes.com)
#
# Version   Date        Comment
# 1.0       02/22/15    Initial Version
# 1.1       03/01/15    updated sshpass to timeout after 5 seconds
#
# To Do:
# 1. Auto detect modem
# 2. Automatically generate files for upload and download
# 3. Run more than once - Run a for loop for the time being. E.g.:
#
# for i in {1..100}; do perl linkCheck.pl; done
#
# 4. Based on the configuration file run only the tests defined
# 5. Add other modem related requirements such as SNMP, SSH, etc checks

use strict;
use warnings;
use Net::FTP;
use File::stat;
use Config::General;
use Data::Dumper;

my $conf   = Config::General->new("linkCheck.cfg");
my %config = $conf->getall;

my $logFile = $config{logFile};
my $debug   = $config{debug};

my %parm = (
    ftphost => $config{ftpHost},
    ftpuser => $config{ftpUser},
    ftppass => $config{ftpPass}
);

my %file = (
    source => $config{downFile},
    dest   => $config{upFile}
);

my $header1;
my $modem = $config{modemType};
if ( $modem eq '1' ) {
    print "Modem: Cradlepoint\n" if $debug;
    $header1 = $config{cpHeader};
}
elsif ( $modem eq '2' ) {
    print "Modem: Zyxel\n" if $debug;
    $header1 = $config{zyHeader};
}
else {
    print "Undefined Modem\n" if $debug;
    my $modem;
    $header1 = 'Modem Not Defined';
}

my $pingCount = $config{pingCount};
if ( $#ARGV == 5 ) {
    $pingCount = $ARGV[5];
}

my $header = $config{header};
if ( !( -e $logFile ) ) {
    open( LOG, ">$logFile" ) or die "Error opening $logFile: $!";
    my $headRow = $header . $header1;
    print LOG "$headRow\n";
    close LOG or die "Error closing $logFile: $!";
    print "# $logFile Created #\n" if $debug;
}

open( LOG, ">>$logFile" ) or die "Error opening $logFile: $!";
unless ( -r $file{source} ) {
    LogIt( 'exit', "No read permission on file $file{source}.\n" );
}

#ping the ftp server first
my $pingRes = `ping -c $pingCount $parm{ftphost}`;

my ( $minTime, $maxTime, $avgTime );
if ( $pingRes =~ /TTL/i ) {

    #The max, min and avg stats come after the last ':' character
    my $pingStatsStr = substr( $pingRes, rindex( $pingRes, '=' ) + 2 );

    my @pingStatsArr = split( '/', $pingStatsStr );

    #print Dumper \@pingStatsArr;
    $minTime = $pingStatsArr[0];
    $avgTime = $pingStatsArr[1];
    $maxTime = $pingStatsArr[2];

}
else {
    LogIt( 'exit', "Ping failed. Host unreachable." );
}

#now collect the FTP test data

my $ftp = Net::FTP->new( $parm{ftphost}, Debug => 0 )
  or LogIt( 'exit', "Error connecting. Network or server problem," );

$ftp->login( $parm{ftpuser}, $parm{ftppass} )
  or LogIt( 'exit', "Error logging in. Check username/password." );

#use the binary mode
$ftp->binary();

my $sizeOfFile = ${ ( stat( $file{source} ) ) }[7];    #7th index is file size
my $startTime = time;
my ( $upSpeed, $dlSpeed );

$ftp->put( $file{source}, $file{dest} )
  or LogIt( 'exit', "Error uploading. Disk space or permissions problems?" );

my $uploadTime = time - $startTime;

if ( $uploadTime != 0 ) {
    $upSpeed = ( ( $sizeOfFile / $uploadTime ) / 1000 );
}
else {
    $upSpeed = $sizeOfFile;
}

$sizeOfFile = $ftp->size( $file{dest} );
$startTime  = time;

#print "\nSizeof file(Dn): $sizeOfFile\n";

$ftp->get( $file{dest} )
  or LogIt( 'exit', "Error downloading. Disk space or permissions problems?" );

my $downldTime = time - $startTime;

#print "\nget completed. $downldTime\n";
if ( $downldTime != 0 ) {
    $dlSpeed = ( ( $sizeOfFile / $downldTime ) / 1000 );
}
else {
    $dlSpeed = $sizeOfFile;
}

$ftp->quit()
  or LogIt( 'exit', "Error disconnecting." );

if ( $modem eq '99' ) {
    LogIt( 'noexit', "$minTime,$maxTime,$avgTime,$upSpeed,$dlSpeed" );
    close LOG or die "Error closing $logFile: $!";
}
else {
    print "$minTime,$maxTime,$avgTime,$upSpeed,$dlSpeed\n" if $debug;
}

if ( $modem eq '1' ) {
    my $cpStats = &getCpStats;
    print "CP Stats: $cpStats\n" if $debug;
    LogIt( 'noexit', "$minTime,$maxTime,$avgTime,$upSpeed,$dlSpeed,$cpStats" );
}
elsif ( $modem eq '2' ) {
    my $zyStats =
      &getZyxelStats( $config{zyIp}, $config{zyUser}, $config{zyPass} );
    LogIt( 'noexit', "$minTime,$maxTime,$avgTime,$upSpeed,$dlSpeed,$zyStats" );
    print "Zyxel Stats: $zyStats\n" if $debug;
}
close LOG or die "Error closing $logFile: $!";

###########################################################################
# Print message with date+timestamp to logfile.
# Abort program if instructed to.
sub LogIt {
    my $exit = $_[0];
    my $msg  = $_[1];
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      (localtime);
    $year = $year + 1900;
    $mon  = $mon + 1;
    my $time = "$year-$mon-$mday $hour:$min:$sec";

    print LOG "$time,$msg\n";

    if ( $exit eq 'exit' ) {
        close LOG or die "Error closing $logFile: $!";
        exit;
    }
}

###########################################################################
sub getCpStats {

    my $user      = $config{cpUser};
    my $password  = $config{cpPass};
    my $ipaddress = $config{cpIp};

    # Retrieve configuration and status using ssh if the unit is reachable
    my $cpconfig = `sshpass -p $password ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $user\@$ipaddress "get" 2>&1`;

    if ( $cpconfig =~ /Permission denied/ ) {
        &LogIt("Invalid password");
    }
    elsif ( $cpconfig =~ /Connection timed out/ ) {
        &LogIt("Unable to connect using SSH. Please enable SSH");
    }
    print $cpconfig if $debug;

    my (
        $activeapn, $getcommunity, $setcommunity, $modemid,
        $mdn,       $imsi,         $rsrp,         $group,
        $rsrq,      $sinr,         $gpgga,        $carrid,
        $rssi
    );

    # Get Active APN
    $cpconfig =~ m/"Active APN: (.*?)"/s;
    $activeapn = $1;

    # Get SNMP communities and hostname
    $cpconfig =~ m/system\":\s+{\n(.*?)\"wan\":\s+{(.*)/s;
    my @sysconfig = $1;

    print "System Config: @sysconfig\n" if $debug;
    foreach (@sysconfig) {
        if ( $_ =~ /"get_community": "(.*)"/ ) {
            print "$1\n" if $debug;
            $getcommunity = $1;
        }
        if ( $_ =~ /"set_community": "(.*)"/ ) {
            print "$1\n" if $debug;
            $setcommunity = $1;
        }
        if ( $_ =~ /"system_id": "(.*)"/ ) {
            print "$1\n" if $debug;
            $modemid = $1;
        }
    }

    # Get firmware version
    my ( $buildversion, $major, $minor, $patch );
    $cpconfig =~ m/fw_info\":\s+{\n(.*?)\"gpio\":\s+{(.*)/s;
    my @firmwareinfo = $1;

    print "Firmware Info: @firmwareinfo\n" if $debug;
    foreach (@firmwareinfo) {
        if ( $_ =~ /"build_version": (.*?),/ ) {
            print "$1\n" if $debug;
            $buildversion = $1;
        }
        if ( $_ =~ /"major_version": (.*?),/ ) {
            print "$1\n" if $debug;
            $major = $1;
        }
        if ( $_ =~ /"minor_version": (.*?),/ ) {
            print "$1\n" if $debug;
            $minor = $1;
        }
        if ( $_ =~ /"patch_version": (.*?),/ ) {
            print "$1\n" if $debug;
            $patch = $1;
        }
    }

    my $firmware = "$major.$minor.$patch.$buildversion";

    print "$firmware\n" if $debug;

    # Get group
    $cpconfig =~ m/"Group": "(.*?)"/s;
    $group = $1;

    # Get CARRID
    $cpconfig =~ m/"CARRID": "(.*?)"/s;
    $carrid = $1;

    # Get MDN
    $cpconfig =~ m/"MDN": "(.*?)"/s;
    $mdn = $1;

    # Get IMSI
    $cpconfig =~ m/"IMSI": "(.*?)"/s;
    $imsi = $1;

    # Get RSSI
    $cpconfig =~ m/"DBM": "(.*?)"/s;
    $rssi = $1;

    # Get RSRP
    $cpconfig =~ m/"RSRP": "(.*?)"/s;
    $rsrp = $1;

    # Get RSRQ
    $cpconfig =~ m/"RSRQ": "(.*?)"/s;
    $rsrq = $1;

    # Get SINR
    $cpconfig =~ m/"SINR": "(.*?)"/s;
    $sinr = $1;

    if ($debug) {
        print "Site Parameters\n";
        print "Modem ID = $modemid\n";
        print "Cradlepoint Group = $group\n";
        print "Modem MDN = $mdn\n";
        print "Carrier ID = $carrid\n";
        print "IMEI = $imsi\n";
        print "RSSI = $rssi\n";
        print "RSRP = $rsrp\n";
        print "RSRQ = $rsrq\n";
        print "SINR = $sinr\n";
        print "Firmware Version = $firmware\n";
    }

    return
      "$modemid,$group,$mdn,$carrid,$imsi,$rssi,$rsrp,$rsrq,$sinr,$firmware";
}

################################################################################
# METHOD NAME  : getZyxelStats
################################################################################
# DESCRIPTION : This subroutine will be used to fetch stats from zyxel
# INPUT PARMS  :
#   1. IP - Management IP of CPE with which site is reachable from NOC.
#   2. Username
#   3. Password
#
# RETURN VALUE :
#              1.Status: Integer Flag indicating status of operation. 1 Success or -1 failure.
#              2.Error Text: String returned in case of failure.
#              3.Stats: Stats hash
#################################################################################
sub getZyxelStats {

    my ( $ipaddress, $user, $password ) = @_;

# Retrieve configuration and status using ssh if the unit is reachable
    my $zyconfig =
`echo "adsl info --stats" | sshpass -p $password ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $user\@$ipaddress 2>&1`;

    if ( $zyconfig =~ /Permission denied/ ) {
        &LogIt("Invalid password");
    }
    elsif ( $zyconfig =~ /Connection timed out/ ) {
        &LogIt("Unable to connect using SSH. Please enable SSH");
    }
    print $zyconfig if $debug;

    my ( $dslstatus, $dsrate, $uprate, $dssnr, $upsnr );

    # Get DSL Status
    $zyconfig =~ m/Status:\s+(\w+)/s;
    $dslstatus = $1;

    # Get DSL Upstream/Downstream Rate
    # Channel:  FAST, Upstream rate = 384 Kbps, Downstream rate = 2528 Kbps
    $zyconfig =~
m/Channel:(.*),\s+Upstream rate =\s+(\d+)\s+\w+, Downstream rate = (\d+)\s+\w+?/s;
    $uprate = $2;
    $dsrate = $3;

    # Get DSL Upstream/Downstream SNR
    $zyconfig =~ m/SNR \(dB\):\s+([\d\.]+)\s+([\d\.]+)/s;
    $dssnr = $1;
    $upsnr = $2;

    return "$dslstatus,$dsrate,$uprate,$dssnr,$upsnr";
}
