=head1 NAME

Bio::KBase::PROM::Util

=head1 DESCRIPTION


PROM (Probabilistic Regulation of Metabolism) Service

This module encapsulates a set of utility methods for setting up a Prom Constraints object in
a KBase user workspace, including a method to calculate interaction probabilities from gene expression
and 


created 1/10/2013 - msneddon

=cut

package Bio::KBase::PROM::Util;

use strict;
use warnings;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(computeInteractionProbabilities getPromURL get_prom_client get_auth_token);

our $defaultPromURL = "http://kbase.us/services/prom";



# Expected structure of the regulatory network:
# a regulatory network is a list where each element is a list in the form [TF, target, p1, p2]
#
# Expected strucure of the expression data object
# this structure is a list, where each element cooresponds to an expermental condition, as in:
# [
#    {
#       geneCalls => {g1 => 1, g2 => -1 ... },
#       description => ,
#       media => 'Complete',
#       label => 'exp1'
#    },
#    { ... }
#    ...
# ]
sub computeInteractionProbabilities {
    my ($reg_network, $expression_data, $id_2_uuid_map) = @_;
    
    # should throw in some error checking at some point.
    
    my $status = '';
    
    # maps the numbers in the input to numbers in the output.  Here we assume that unknown expresson states
    # is mapped to ON.  But is this actually the right thing to do???
    # NOTE: empty values are mapped to 1, which means that we will NOT catch cases in which we do not find the TF or
    # target in the data
    my %isOn = (-1 => 0,0 => 1,1 => 1,''=>1); 

    ## calculate P(target = ON|TF = OFF) and P(target = ON|TF = ON)
    my $tfTempMap = {};
    foreach my $i (@$reg_network) {
        my $TF = $i->[0]; my $TF_UUID = '';
        my $TARGET = $i->[1]; my $TARGET_UUID = '';
        
        #map them to the new ID namespace
        if( exists $id_2_uuid_map->{$TF}) {
            $TF_UUID = $id_2_uuid_map->{$TF};
        } else {
            $status .= "  -> WARNING: could not find $TF in genome annotations!  Skipping this TF!\n";
            next;
        }
        if( exists $id_2_uuid_map->{$TARGET}) {
            $TARGET_UUID = $id_2_uuid_map->{$TARGET};
        } else {
            $status .= "  -> WARNING: could not find $TF in genome annotations!  Skipping this TARGET!\n";
            next;
        }
        
        
        my $TF_off_count = 0;
        my $TF_off_TARGET_on_count = 0;
        my $TF_on_count = 0;
        my $TF_on_TARGET_on_count = 0;
        
        foreach my $experiment (@$expression_data) {
            if( 1==$isOn{$experiment->{geneCalls}->{$TF}}  ) {
                $TF_on_count++;
                if( 1==$isOn{$experiment->{geneCalls}->{$TARGET}}  ) {
                    $TF_on_TARGET_on_count++;
                } elsif( -1==$isOn{$experiment->{geneCalls}->{$TARGET}} ) {
                    $status .= "  -> WARNING: could not find $TARGET in expression data ".$experiment->{label}."!\n";
                }
            } elsif( 0==$isOn{$experiment->{geneCalls}->{$TF}} ) {
                $TF_off_count++;
                if( 1==$isOn{$experiment->{geneCalls}->{$TARGET}}  ) {
                    $TF_off_TARGET_on_count++;
                } elsif( -1==$isOn{$experiment->{geneCalls}->{$TARGET}} ) {
                    $status .= "  -> WARNING: could not find $TARGET in expression data ".$experiment->{label}."!\n";
                }
            } else {
                # if we are here that we weren't able to find the TF in the experimental data list!!! What to do then!?!?!
                $status .= "  -> WARNING: could not find $TF in expression data ".$experiment->{label}."!";
            }
        }
        # we need to perform a conversion once we have the genome annotation object
        my $tfMapTarget = {"target_uuid" => $TARGET_UUID }; # $geneid2featureid{$TARGET}};
	if ($TF_on_count != 0) { 
	    $tfMapTarget->{"tfOnProbability"} = $TF_on_TARGET_on_count / $TF_on_count;
            #print "p1:".$tfMapTarget->{"tfOnProbability"}."\n";
	} else { $tfMapTarget->{"tfOnProbability"} = 1; }
	if ($TF_off_count != 0) {
	    $tfMapTarget->{"tfOffProbability"} = $TF_off_TARGET_on_count / $TF_off_count;
            #print "p2:".$tfMapTarget->{"tfOffProbability"}."\n";
	} else { $tfMapTarget->{"tfOffProbability"} = 1; }
        if(exists $tfTempMap->{$TF_UUID}) {
            push @{$tfTempMap->{$TF_UUID}}, $tfMapTarget;
        } else {
            $tfTempMap->{$TF_UUID} = [$tfMapTarget];
        }
    }
    
    # repackage into the object that runFBA is expecting, which is not a hash, but a list of hashes
    my $tfMaps = [];
    foreach my $TF_UUID (keys %$tfTempMap) {
        push @{$tfMaps}, {"transcriptionFactor_uuid"=>$TF_UUID,"transcriptionFactorMapTargets"=>$tfTempMap->{$TF_UUID}};
    }
    
    return ($status,$tfMaps);
        
# original code that was adapted here
#    my @genes = split;
#    my $tf = shift @genes;
#    my $tfMapTargets;
#    foreach my $target (@genes) {
#	my $tf_off_count = 0;
#	my $tf_off_tg_on_count = 0;
#	my $tf_on_count = 0;
#	my $tf_on_tg_on_count = 0;
#
#	for(my $i=0; $i < @{$parsed}; $i++) {  
#	    if ($isOn{$parsed->[$i]->{geneCalls}->{$tf}}) {
#		$tf_on_count++;
#		$tf_on_tg_on_count++ if ($isOn{$parsed->[$i]->{geneCalls}->{$target}});
#	    }
#	    else {
#		$tf_off_count++;
#		$tf_off_tg_on_count++ if ($isOn{$parsed->[$i]->{geneCalls}->{$target}});
#	    }
#	}
#	my $tfMapTarget = {"target_uuid" => $geneid2featureid{$target}};
#	if ($tf_on_count != 0) { 
#	    $tfMapTarget->{"tfOnProbability"} = $tf_on_tg_on_count / $tf_on_count;
#	}
#	if ($tf_off_count != 0) {
#	    $tfMapTarget->{"tfOffProbability"} = $tf_off_tg_on_count / $tf_on_count;
#	}
#	push @$tfMapTargets, $tfMapTarget;
#    }
#    push @$tfMaps, {"transcriptionFactor_uuid" => $geneid2featureid{$tf}, "transcriptionFactorMapTargets" => $tfMapTargets };
#}

};

# simply returns a new copy of the PROM client based on the currently set URL
sub get_prom_client {
    return Bio::KBase::PROM::Client->new(getPromURL());
}


# auth method used by scripts, copied from workspace services Helper.pm
sub get_auth_token {
    my $token = shift;
    if ( defined $token ) {
        if (defined($ENV{KB_RUNNING_IN_IRIS})) {
                $ENV{KB_AUTH_TOKEN} = $token;
        } else {
                my $filename = "$ENV{HOME}/.kbase_auth";
                open(my $fh, ">", $filename) || return;
                print $fh $token;
                close($fh);
        }
    } else {
        my $filename = "$ENV{HOME}/.kbase_auth";
        if (defined($ENV{KB_RUNNING_IN_IRIS})) {
                $token = $ENV{KB_AUTH_TOKEN};
        } elsif ( -e $filename ) {
                open(my $fh, "<", $filename) || return;
                $token = <$fh>;
                chomp($token);
                close($fh);
        }
    }
    return $token;
}


sub getPromURL {
    my $set = shift;
    my $CurrentURL;
    if (defined($set)) {
    	if ($set eq "default") {
            $set = $defaultPromURL;
        }
    	$CurrentURL = $set;
    	if (!defined($ENV{KB_RUNNING_IN_IRIS})) {
	    my $filename = "$ENV{HOME}/.kbase_promURL";
	    open(my $fh, ">", $filename) || return;
	    print $fh $CurrentURL;
	    close($fh);
    	} else {
    	    $ENV{KB_PROMURL} = $CurrentURL;
    	}
    } elsif (!defined($CurrentURL)) {
    	if (!defined($ENV{KB_RUNNING_IN_IRIS})) {
	    my $filename = "$ENV{HOME}/.kbase_promURL";
	    if( -e $filename ) {
		open(my $fh, "<", $filename) || return;
		$CurrentURL = <$fh>;
		chomp $CurrentURL;
		close($fh);
	    } else {
	    	$CurrentURL = $defaultPromURL;
	    }
    	} elsif (defined($ENV{KB_PROMURL})) {
	    	$CurrentURL = $ENV{KB_PROMURL};
	    } else {
		$CurrentURL = $defaultPromURL;
    	} 
    }
    return $CurrentURL;
}





1;