#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;

use Bio::KBase::PROM::Client;
use Bio::KBase::PROM::Util qw(get_prom_client get_auth_token);
use Bio::KBase::workspaceService::Helpers qw(workspace);


my $DESCRIPTION =
"
NAME
      prom-change-regulatory-network-namespace -- change gene names in a reg. network

SYNOPSIS
      prom-change-regulatory-network-namespace [OPTIONS]

DESCRIPTION
      Given a regulatory network saved to a workspace, this script will update
      the gene names in the regulatory network, and save the results as a new
      regulatory network.  It will exit with zero if the method was successful, or
      one if something failed.  The method will return to standard out the new
      ID of the regulatory network that was created in the new namespace.  Run
      with the verbose option to get a log and status message of how many genes
      were mapped and which genes could not be mapped.
      
      -r [REG_NET_ID], --regulatory-network [REG_NET_ID]
                        indicate the id of the regulatory network with which to
                        operate on in the workspace by providing the regulatory
                        network ID
        
      -m [FILE], --map [FILE]
                        indicate the name of the file that contains the mapping
                        information.  The format of the file should be a two
                        column, tab-delimited ASCII text file without a header
                        line where the original gene names are listed in the left
                        column and the cooresponding gene name replacements are
                        listed in the right column.
        
      -w [WORKSPACE_ID], --workspace [WORKSPACE_ID]
                        specify the workspace to use.  If left blank, the default
                        workspace that is configured by the workspace service
                        scripts is used
                        
      -v, --verbose
                        in addition to the expression data collection ID, which
                        will be on the last line, status messages are displayed.
                        
      -h, --help
                        diplay this help message, ignore all arguments
                        
                        

EXAMPLES
      Change the regulatory namespace of a network given the map file 'map.txt'
      > head -n5 map.txt
      kb|g.20848.CDS.0	kb|g.371.peg.4031
      kb|g.20848.CDS.1	kb|g.371.peg.2814
      kb|g.20848.CDS.10	kb|g.371.peg.200
      kb|g.20848.CDS.1000	kb|g.371.peg.756
      kb|g.20848.CDS.1001	kb|g.371.peg.861
      > prom-change-regulatory-network-namespace -m 'map.txt' -r 'AF74A066-6B03-11E2-8DAE-9375BC200E61'
      7AD26AD0-6B0A-11E2-8DAE-9375BC200E61

SEE ALSO
      prom-load-regulatory-network

AUTHORS
      Michael Sneddon (mwsneddon\@lbl.gov)
      
";

my $help = '';
my $verbose = '';
my $reg_network_id = '';
my $mapFilePath = '';
my $ws = workspace();
my $opt = GetOptions (
        "help" => \$help,
        "verbose" => \$verbose,
        "regulatory-network=s" => \$reg_network_id,
        "map=s" => \$mapFilePath,
        "workspace=s" => \$ws
        );

if($help) {
     print $DESCRIPTION;
     exit 0;
}

my $n_args = $#ARGV+1;
if($n_args==0) {
    if($reg_network_id) {
        if($mapFilePath) {
            #load the feature map
            chomp($mapFilePath);
            my $feature_map = {};
            if( -e $mapFilePath ) {
		open(my $IN, "<", $mapFilePath);
                if($IN) {
                    while (<$IN>) {
                        my $line = $_; chomp($line);
                        if($line ne '') {
                            my @tokens = split("\t",$line);
                            $feature_map->{$tokens[0]} = $tokens[1];
                        }
                    }
                } else {
                    print "FAILURE - unable to open map file.\n";
                    exit 1;
                }	      
                close $IN;
            } else {
                print "FAILURE - map file not found.\n";
                exit 1;
            }
	    
            #create client
            my $prom;
            eval{
                $prom = get_prom_client();
            };
            if(!$prom) {
                print "FAILURE - unable to create prom service client.  Is you PROM URL correct? see prom-url.\n";
                exit 1;
            }
            #grab auth info
            my $token = get_auth_token();
            #make the call
            my $status; my $new_reg_network_id; 
            eval {
              ($status,$new_reg_network_id) =
                 $prom->change_regulatory_network_namespace($reg_network_id,$feature_map,$ws, $token);
            };
    
            if(!$status) {
                print "FAILURE - unknown internal server error. Run with --help for usage.\n";
                exit 1;
            }
            if($verbose) { print $status."\n"; }
            if($new_reg_network_id ne '') {
                print $new_reg_network_id."\n";
                exit 0;
            } else {
                print $status."\n";
                exit 1;
            }
        } else {
            print "FAILURE - no map file specified.  Run with --help for usage.\n";
            exit 1;
        }
    } else {
        print "FAILURE - no regulatory network specified.  Run with --help for usage.\n";
        exit 1;
    }
}

print "Bad options / Invalid number of arguments.  Run with --help for usage.\n";
exit 1;

