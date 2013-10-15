#!/usr/bin/perl

use warnings;
use strict;

use JMX::Jmx4Perl;
use JMX::Jmx4Perl::Request;  
use Nagios::Plugin;
use POSIX;
use Data::Dumper;   #Debug

my $code = UNKNOWN;
my $path = '/jolokia';
my $host = "";
my $port = "";

if ($#ARGV < 1 ){
        die ("Usage:
                script.pl <host> <port> [context of jmx-agent]
                <host> and <port> are necessary
                [context of jmx-agent] is the path to e.g. jolokia"
        );
}else   {
        $host = $ARGV[0];
        $port = $ARGV[1];
}

if ( $#ARGV == 3 ){
        $path = $ARGV[2];
}
        
my $np = Nagios::Plugin->new( shortname => "HeapMemoryUsage",);

my $jmx = new JMX::Jmx4Perl(
                             url => "http://${host}:${port}/${path}",
                             product => "", #if product is unset jolokia will tell us
                            );
my $request = new JMX::Jmx4Perl::Request({
                                          type => READ,
                                          mbean => "java.lang:type=Memory",
                                          attribute => "HeapMemoryUsage",
                                         });
#print(Dumper($request));
my $response = $jmx->request($request);
#print(Dumper($response));
if (  $response->status() != 200 or $response->value() eq "" ){
        $np->nagios_die( "There seems to be a Problem");
}

##Debug Output
#print(Dumper($response));

my $used_memory=$response->value()->{'used'};
my $max_memory=$response->value()->{'max'};

if ( ! isdigit $used_memory or ! isdigit $max_memory){
                $np->nagios_die( "There seems to be a Problem" );
}

my $warning=$max_memory*0.8;
my $critical=$max_memory*0.9;

$code = $np->check_threshold(
        check => $used_memory,
        warning => $warning,
        critical => $critical,
);

my $max_memory_mb=$max_memory/1024/1024;
my $used_memory_mb=$used_memory/1024/1024;

$np->add_perfdata(
        label => "HeapMemory",
        value => $used_memory_mb,
        uom => "MB",
        max => $max_memory_mb,
);

##Debug Output
#print "max: $max_memory_mb MB\n";
#print "used: $used_memory_mb MB\n";

$np->nagios_exit( $code,"used memory: ".$used_memory_mb." MB; max memory: ".$max_memory_mb." MB" );
