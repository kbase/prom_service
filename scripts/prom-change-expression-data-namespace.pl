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
      prom-change-expression-data-namespace -- change gene names in an exp. data

SYNOPSIS
      prom-change-expression-data-namespace [OPTIONS]

DESCRIPTION
      Given an expression data collection saved to a workspace, this script will
      update the gene names in the expression data sets.  Note that unlike
      prom-change-regulatory-network-namespace, this method makes changes in
      place, so that no workspace IDs for the expression data or expression data
      collection will change.  In order to undo the change, the data object
      would need to be reverted.  Also note that if a gene name is not found in
      the mapping, it is ignored and the original name is left in place (thus,
      expression data matricies will retain the same row/col size).  This also
      means that the updated expression data may then have genes in two different
      namespaces if not all genes could be mapped.  Importantly, a side effect is
      that if nothing could be updated, the method will still look like it was
      successful.  Be sure to run with the verbose option to get a log message
      of how many genes could be mapped in each expression data set. This method
      will exit with zero if the method was successful, or one if something failed.
      Run with the verbose option to get a log and status message of how many
      genes were mapped.
      
      -e [EXP_ID], --expression-data [EXP_ID]
                        indicate the id of the expression data collection with
                        which to operate on in the workspace
        
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
      > prom-change-expression-data-namespace -m 'map.txt' -e '7FECB606-6B0F-11E2-970A-1C7ABC200E61'
      7AD26AD0-6B0A-11E2-8DAE-9375BC200E61

SEE ALSO
      prom-load-expression-data

AUTHORS
      Michael Sneddon (mwsneddon\@lbl.gov)
      
";

my $help = '';
my $verbose = '';
my $exp_data_id = '';
my $mapFilePath = '';
my $ws = workspace();
my $opt = GetOptions (
        "help" => \$help,
        "verbose" => \$verbose,
        "expression-data=s" => \$exp_data_id,
        "map=s" => \$mapFilePath,
        "workspace=s" => \$ws
        );

if($help) {
     print $DESCRIPTION;
     exit 0;
}

my $n_args = $#ARGV+1;
if($n_args==0) {
    if($exp_data_id) {
        if($mapFilePath) {
            #load the feature map
            my $feature_map = {};
            chomp($mapFilePath);
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
            my $status;
            eval {
              $status =
                 $prom->change_expression_data_namespace($exp_data_id,$feature_map,$ws, $token);
            };
    
            if(!$status) {
                print "FAILURE - unknown internal server error. Run with --help for usage.\n";
                exit 1;
            }
            if($verbose) { print $status."\n"; }
            if($status =~ m/FAILURE/) {
                print $status."\n";
                exit 1;
            }
            exit 0;
        } else {
            print "FAILURE - no map file specified.  Run with --help for usage.\n";
            exit 1;
        }
    } else {
        print "FAILURE - no expression data collection specified.  Run with --help for usage.\n";
        exit 1;
    }
}

print "Bad options / Invalid number of arguments.  Run with --help for usage.\n";
exit 1;

