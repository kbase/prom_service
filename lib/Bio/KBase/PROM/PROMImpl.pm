package Bio::KBase::PROM::PROMImpl;
use strict;
use Bio::KBase::Exceptions;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = "0.1.0";

=head1 NAME

PROM

=head1 DESCRIPTION

PROM (Probabilistic Regulation of Metabolism) Service

This service enables the creation of FBA model constraint objects that are based on regulatory
networks and expression data, as described in [1].  Constraints are constructed by either automatically
aggregating necessary information from the CDS (if available for a given genome), or by adding user
expression and regulatory data.  PROM provides the capability to simulate transcription factor knockout
phenotypes.  PROM model constraint objects are created in a user's workspace, and can be operated on and
used in conjunction with an FBA model with the KBase FBA Modeling Service.

[1] Chandrasekarana S. and Price ND. Probabilistic integrative modeling of genome-scale metabolic and
regulatory networks in Escherichia coli and Mycobacterium tuberculosis. PNAS (2010) 107:17845-50.

created 11/27/2012 - msneddon

=cut

#BEGIN_HEADER

use Bio::KBase::ERDB_Service::Client;
use Bio::KBase::Regulation::Client;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::PROM::Util qw(computeInteractionProbabilities);

# where is ModelSEED in the kbase path???
use lib "/home/msneddon/Desktop/ModelSEED_ENVIRONMENT/ModelSEED/lib";
use ModelSEED::MS::PROMModel;

use Data::Dumper;
use Config::Simple;
use Data::UUID;
use Benchmark;
use JSON;

#END_HEADER

sub new
{
    my($class, @args) = @_;
    my $self = {
    };
    bless $self, $class;
    #BEGIN_CONSTRUCTOR
    
    #load a configuration file to determine where all the services live
    my $c = Config::Simple->new();
    $c->read("deploy.cfg");
    
    # connect to various kbase services that we need
    my $erdb_url = $c->param("prom_service.erdb");
    if($erdb_url) {
	$self->{'erdb'} = Bio::KBase::ERDB_Service::Client->new($erdb_url);
	print "Connecting ERDB Service client  to server: $erdb_url\n";
    } else {
	die "ERROR STARTING SERVICE! prom_config.ini file does not exist, or does not contain 'service-urls.erdb' variable.\n";
    }
    my $reg_url = $c->param("prom_service.regulation");
    if($reg_url) {
	$self->{'regulation'} = Bio::KBase::Regulation::Client->new($reg_url);
	print "Connecting Regulation Service client  to server: $reg_url\n";
    } else {
	die "ERROR STARTING SERVICE! prom_config.ini file does not exist, or does not contain 'service-urls.regulation' variable.\n";
	
    }
    my $workspace_url = $c->param("prom_service.workspace");
    if($workspace_url) {
	$self->{'workspace'} = Bio::KBase::workspaceService::Client->new($workspace_url);
	print "Connecting Workspace Service client to server : $workspace_url\n";
    } else {
	die "ERROR STARTING SERVICE! prom_config.ini file does not exist, or does not contain 'service-urls.workspace' variable.\n";
    }
    
    # find some scratch space we can use when processing data
    my $scratch_space = $c->param("prom_service.scratch-space");
    if($scratch_space) {
	$self->{'scratch_space'} = $scratch_space;
	print "Scratch space for temporary files is set to : $scratch_space\n";
    } else {
	die "ERROR STARTING SERVICE! prom_confg.ini file does not exist, or does not contain 'local-paths.scratch-space' variable.\n";
    }
    
    $self->{'uuid_generator'} = new Data::UUID;
    
    #END_CONSTRUCTOR

    if ($self->can('_init_instance'))
    {
	$self->_init_instance();
    }
    return $self;
}

=head1 METHODS



=head2 get_expression_data_by_genome

  $status, $expression_data_collection_id = $obj->get_expression_data_by_genome($genome_id, $workspace_name, $token)

=over 4

=item Parameter and return types

=begin html

<pre>
$genome_id is a genome_id
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
$expression_data_collection_id is an expression_data_collection_id
genome_id is a kbase_id
kbase_id is a string
workspace_name is a string
auth_token is a string
status is a string
expression_data_collection_id is a string

</pre>

=end html

=begin text

$genome_id is a genome_id
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
$expression_data_collection_id is an expression_data_collection_id
genome_id is a kbase_id
kbase_id is a string
workspace_name is a string
auth_token is a string
status is a string
expression_data_collection_id is a string


=end text



=item Description

This method fetches all gene expression data available in the CDS that is associated with the given genome id.  It then
constructs an expression_data_collection object in the specified workspace.  The method returns the ID of the expression
data collection in the workspace, along with a status message that provides details on what was retrieved and if anything
failed.  If the method does fail, or if there is no data for the given genome, then no expression data collection is
created and no ID is returned.

Note 1: this method currently can take a long time to complete if there are many expression data sets in the CDS
Note 2: the current implementation relies on on/off calls stored in the CDM (correct as of 1/2013).  This will almost
certainly change, at which point logic for making on/off calls will be required as input
Note 3: this method should be migrated to the expression service, which currently does not exist
Note 4: this method should use the type compiler auth, but for simplicity  we now just pass an auth token directly.

=back

=cut

sub get_expression_data_by_genome
{
    my $self = shift;
    my($genome_id, $workspace_name, $token) = @_;

    my @_bad_arguments;
    (!ref($genome_id)) or push(@_bad_arguments, "Invalid type for argument \"genome_id\" (value was \"$genome_id\")");
    (!ref($workspace_name)) or push(@_bad_arguments, "Invalid type for argument \"workspace_name\" (value was \"$workspace_name\")");
    (!ref($token)) or push(@_bad_arguments, "Invalid type for argument \"token\" (value was \"$token\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_expression_data_by_genome:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_expression_data_by_genome');
    }

    my $ctx = $Bio::KBase::PROM::Service::CallContext;
    my($status, $expression_data_collection_id);
    #BEGIN get_expression_data_by_genome
    
    
    # setup the return variables
    $status = "";
    $expression_data_collection_id="";
    
    # make sure we are authentiated (for now auth token is passed directly)
    #if ($ctx->authenticated) {
        #$status .= "  -> user named ".$ctx->user_id." has been authenticated.\n";
	
	#check that the workspace is valid (note: can we get the token directly from ctx somehow?!?)
	# note: this does not actually do any error checking right now.
	my $ws = $self->{'workspace'};
	
	# grab the erdb service
	my $erdb = $self->{'erdb'};

	# GRAB EXPRESSION DATA FROM THE CDM (currently has on/off calls! but this will likely change...)
	$status .= "  -> searching the KBase Central Data Store for expression data for genome: ".$genome_id."\n";
	my $objectNames = 'HadResultsProducedBy ProbeSet HasResultsIn';
	my $filterClause = 'HadResultsProducedBy(from-link)=?';
	my $parameters = [$genome_id];
	my $fields = 'HasResultsIn(to-link)';
	my $count = 0; #as per ERDB doc, setting to zero returns all results
	my @experiment_list = @{$erdb->GetAll($objectNames, $filterClause, $parameters, $fields, $count)};
	
	# check if we found anything for this genome
	my @expression_data_uuid_list = ();
	if(scalar @experiment_list >0) {
	    $status = $status."  -> found ".scalar(@experiment_list)." experiments for this genome.\n";
	    
	    # get the actual on/off calls (note, there is too much data to do this all at once)
	    $objectNames = 'IndicatesSignalFor';
	    $parameters = [];
	    
	    # go through each experiment that was found
	    my $exp_counter = 0;
	    foreach my $exp (@experiment_list) {
		$exp_counter ++; if ($exp_counter>5) { last; }
		print Dumper(${$exp}[0])."\n";
		$filterClause = "IndicatesSignalFor(from-link)=?";
		$fields = 'IndicatesSignalFor(from-link) IndicatesSignalFor(to-link) IndicatesSignalFor(level)';
		my @expression_data = @{$erdb->GetAll($objectNames, $filterClause, [${$exp}[0]], $fields, $count)};
		if(scalar @expression_data >0) {
		    $status = $status."  -> found experiment '${$exp}[0]' with ".scalar(@expression_data)." gene on/off calls.\n";
		    
		    # drop top level list and save as a data structure
		    my %on_off_calls;
		    foreach my $data (@expression_data) {
			$on_off_calls{${$data}[1]} = ${$data}[2]; 
		    }
		
		    # create a data structure to store the experimental data
		    my $data_uuid = $self->{'uuid_generator'}->create_str();
		    push @expression_data_uuid_list, $data_uuid;
		    print "uuid = ".$data_uuid."\n";
		    my $exp_data = {
			id => $data_uuid,
			on_off_call => \%on_off_calls,
			expression_data_source => 'KBase',
			expression_data_source_id => ${$exp}[0],
		    };
		    
		    # convert it to JSON
		    my $encoded_json_exp_data = encode_json $exp_data;
		    
		    # save this experiment to the workspace
		    my $workspace_save_obj_params = {
			id => $data_uuid,
			type => "Unspecified",
			data => $encoded_json_exp_data,
			workspace => $workspace_name,
			command => "Bio::KBase::PROM::retrieve_expression_data",
			auth => $token,
			json => 1,
			compressed => 0,
			retrieveFromURL => 0,
		    };
		    my $object_metadata = $ws->save_object($workspace_save_obj_params);
		    $status = $status."  -> saving data for experiment '${$exp}[0]' to your workspace with ID:$data_uuid\n";
		    print Dumper($object_metadata)."\n";
		    #print "DATA:\n".$encoded_json_data."\n";
		} else {
		    $status .= "  -> warning - no gene expression data found for experiment '${$exp}[0]'.\n";
		}
	    }
	    #print Dumper(@expression_data_uuid_list)."\n"; #print the list of expression data found
	    
	    # now we save the collection to the workspace
	    $expression_data_collection_id = $self->{'uuid_generator'}->create_str();
	    #print "collection uuid = ".$expression_data_collection_id."\n";
	    
	    # create the collection and encode it as JSON
	    my $exp_data_collection = {
		id => $expression_data_collection_id,
		expression_data => \@expression_data_uuid_list,
	    };
	    my $encoded_json_data_collection = encode_json $exp_data_collection;
	    
	    # save the collection to the workspace
	    my $workspace_save_obj_params = {
		id => $expression_data_collection_id,
		type => "Unspecified",
		data => $encoded_json_data_collection,
		workspace => $workspace_name,
		command => "Bio::KBase::PROM::retrieve_expression_data",
		auth => $token,
		json => 1,
		compressed => 0,
		retrieveFromURL => 0,
	    };
	    #print "DATA:\n".$encoded_json_data_collection."\n";
	    my $object_metadata = $ws->save_object($workspace_save_obj_params);
	    print Dumper($object_metadata)."\n";
	    
	    $status = $status."  -> saving data for the collection of experiments with ID:$expression_data_collection_id\n";
	    $status = "SUCCESS.\n".$status;
	    
	} else {
	    $status = "FAILURE - no gene expression experiments found for the specified genome.\n".$status;
	}
    
    #}
    #else {
    # 	$status = "failure - user and password combination could not be authenticated.\n".$status;
    #}
    
    #END get_expression_data_by_genome
    my @_bad_returns;
    (!ref($status)) or push(@_bad_returns, "Invalid type for return variable \"status\" (value was \"$status\")");
    (!ref($expression_data_collection_id)) or push(@_bad_returns, "Invalid type for return variable \"expression_data_collection_id\" (value was \"$expression_data_collection_id\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_expression_data_by_genome:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_expression_data_by_genome');
    }
    return($status, $expression_data_collection_id);
}




=head2 get_regulatory_network_by_genome

  $status, $regulatory_network_id = $obj->get_regulatory_network_by_genome($genome_id, $workspace_name, $token)

=over 4

=item Parameter and return types

=begin html

<pre>
$genome_id is a genome_id
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
$regulatory_network_id is a regulatory_network_id
genome_id is a kbase_id
kbase_id is a string
workspace_name is a string
auth_token is a string
status is a string
regulatory_network_id is a string

</pre>

=end html

=begin text

$genome_id is a genome_id
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
$regulatory_network_id is a regulatory_network_id
genome_id is a kbase_id
kbase_id is a string
workspace_name is a string
auth_token is a string
status is a string
regulatory_network_id is a string


=end text



=item Description

This method fetches a regulatory network from the regulation service that is associated with the given genome id.  If there
are multiple regulome models available for the given genome, then the model with the most regulons is selected.  The method
then constructs a regulatory network object in the specified workspace.  The method returns the ID of the regulatory network
in the workspace, along with a status message that provides details on what was retrieved and if anything failed.  If the
method does fail, or if there is no regulome for the given genome, then no regulatory network ID is returned.

Note 1: this method should be migrated to the regulation service
Note 2: this method should use the type compiler auth, but for simplicity  we now just pass an auth token directly.

=back

=cut

sub get_regulatory_network_by_genome
{
    my $self = shift;
    my($genome_id, $workspace_name, $token) = @_;

    my @_bad_arguments;
    (!ref($genome_id)) or push(@_bad_arguments, "Invalid type for argument \"genome_id\" (value was \"$genome_id\")");
    (!ref($workspace_name)) or push(@_bad_arguments, "Invalid type for argument \"workspace_name\" (value was \"$workspace_name\")");
    (!ref($token)) or push(@_bad_arguments, "Invalid type for argument \"token\" (value was \"$token\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_regulatory_network_by_genome:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_regulatory_network_by_genome');
    }

    my $ctx = $Bio::KBase::PROM::Service::CallContext;
    my($status, $regulatory_network_id);
    #BEGIN get_regulatory_network_by_genome
    
    # setup the return values and retrieve the client libs
    $status = '';
    $regulatory_network_id = '';
    my $reg = $self->{'regulation'};
    my $ws  = $self->{'workspace'};
    
    # get a regulomeModelId based on a kbase genome ID
    my $regulome_model_id = '';
    my $regulomes = $reg->getRegulomeModelsByGenomeId($genome_id);
    my $n_regulomes = scalar @{$regulomes};
    if ($n_regulomes == 0) {
	$status = "FAILURE - no regulome models exist for genome $genome_id\n".$status;
    } else {
	$status .= "  -> found $n_regulomes regulome model(s) for genome $genome_id\n";
	$status .= "  -> possible models are :\n";
	my $max_regulon_count = -1;
	foreach my $r (@$regulomes) {
	    $status .= "       -".$r->{regulomeModelId}." (regulomeSource:".$r->{regulomeSource}.", tfRegulonCount:".$r->{tfRegulonCount}.")\n";
	    if ($r->{tfRegulonCount} > $max_regulon_count) {
		$max_regulon_count = $r->{tfRegulonCount};
		$regulome_model_id = $r->{regulomeModelId};
	    }
	}
	$status .= "  -> selected regulome model with the most regulons ($regulome_model_id)\n"
    }
    
    # actually build the network if we found a regulome
    if($regulome_model_id ne '') {
	
	#as per PROM.spec, this object is an array of hashes, where each hash
	#is a regulatory interaction consisting of keys TF, target, probTTonGivenTFoff, and probTTonGivenTFon
	my $regulatory_network = [];
	# flat file version of the regulatory network, needed until workspace service handles lists...
	my $regulatory_network_flat = '';
	my $interactionCounter = 0;
	
	my $stats = $reg->getRegulonModelStats($regulome_model_id);
	
	foreach my $regulon_stat (@$stats) {
	    # fetch each regulon model, which is comprised of a set of regulators and a set of operons
	    my $regulonModel = $reg->getRegulonModel($regulon_stat->{regulonModelId});
    
	    # grab the kbase ids of each regulator for this regulon
	    my $regulators = $regulonModel->{regulators};
	    my @regulator_ids;
	    foreach my $r (@$regulators) { push @regulator_ids, $r->{regulatorId}; }
    
	    # loop through each gene of each operon regulated by the regulators, and build the network
	    # of pair-wise regulatory interactions
	    my $operons    = $regulonModel->{operons};
	    foreach my $opr (@$operons) {
	        foreach my $gene (@{$opr->{genes}}) {
	            foreach my $reg_id (@regulator_ids) {
	                my $regulatory_interaction = {
	                                TF => $reg_id,
	                                target => $gene->{geneId},
	                                probTTonGivenTFoff => '',
	                                probTTonGivenTFon => '',
	                                };
	                push @$regulatory_network, $regulatory_interaction;
			$regulatory_network_flat .= $reg_id."\t".$gene->{geneId}."\n";
			$interactionCounter++;
	            }
	        }
	    }
	}
	$status .= "  -> compiled regulatory network with $interactionCounter regulatory interactions\n";
	
	# if we were able to populate the network, then save it to workspace services 
	if($interactionCounter > 0) {
	    # create UUID for the workspace object
	    $regulatory_network_id = $self->{'uuid_generator'}->create_str();
	    
	    # encode the regulatory network as a JSON
	    my $encoded_json_reg_network = encode_json $regulatory_network;
	    #print "DATA:\n".$encoded_json_reg_network."\n";
	    #print "DATA(FLAT):\n".$regulatory_network_flat."\n";
	    
	    # save the collection to the workspace
	    my $workspace_save_obj_params = {
		id => $regulatory_network_id,
		type => "Unspecified",
		data => $regulatory_network_flat, #$encoded_json_reg_network,
		workspace => $workspace_name,
		command => "Bio::KBase::PROM::get_regulatory_network_by_genome",
		auth => $token,
		json => 0,
		compressed => 0,
		retrieveFromURL => 0,
	    };
	    
	    #print Dumper($workspace_save_obj_params)."\n";
	    my $object_metadata = $ws->save_object($workspace_save_obj_params);
	    #print Dumper($object_metadata)."\n";
	    $status = $status."  -> saving the regulatory network to your workspace with ID:$regulatory_network_id\n";
	    $status = "SUCCESS.\n".$status;

	} else {
	    $status = "FAILURE - no regulatory interactions found for \n".$status;
	}
    }
    
    #END get_regulatory_network_by_genome
    my @_bad_returns;
    (!ref($status)) or push(@_bad_returns, "Invalid type for return variable \"status\" (value was \"$status\")");
    (!ref($regulatory_network_id)) or push(@_bad_returns, "Invalid type for return variable \"regulatory_network_id\" (value was \"$regulatory_network_id\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_regulatory_network_by_genome:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_regulatory_network_by_genome');
    }
    return($status, $regulatory_network_id);
}




=head2 change_regulatory_network_namespace

  $status, $new_regulatory_network_id = $obj->change_regulatory_network_namespace($regulatory_network_id, $new_feature_names, $workspace_name, $token)

=over 4

=item Parameter and return types

=begin html

<pre>
$regulatory_network_id is a regulatory_network_id
$new_feature_names is a reference to a hash where the key is a string and the value is a string
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
$new_regulatory_network_id is a regulatory_network_id
regulatory_network_id is a string
workspace_name is a string
auth_token is a string
status is a string

</pre>

=end html

=begin text

$regulatory_network_id is a regulatory_network_id
$new_feature_names is a reference to a hash where the key is a string and the value is a string
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
$new_regulatory_network_id is a regulatory_network_id
regulatory_network_id is a string
workspace_name is a string
auth_token is a string
status is a string


=end text



=item Description

Maps the regulatory network stored in a workspace in one genome namespace to an alternate genome namespace.  This is useful,
for instance, if the regulatory network was built for

=back

=cut

sub change_regulatory_network_namespace
{
    my $self = shift;
    my($regulatory_network_id, $new_feature_names, $workspace_name, $token) = @_;

    my @_bad_arguments;
    (!ref($regulatory_network_id)) or push(@_bad_arguments, "Invalid type for argument \"regulatory_network_id\" (value was \"$regulatory_network_id\")");
    (ref($new_feature_names) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"new_feature_names\" (value was \"$new_feature_names\")");
    (!ref($workspace_name)) or push(@_bad_arguments, "Invalid type for argument \"workspace_name\" (value was \"$workspace_name\")");
    (!ref($token)) or push(@_bad_arguments, "Invalid type for argument \"token\" (value was \"$token\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to change_regulatory_network_namespace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'change_regulatory_network_namespace');
    }

    my $ctx = $Bio::KBase::PROM::Service::CallContext;
    my($status, $new_regulatory_network_id);
    #BEGIN change_regulatory_network_namespace
    
    $status = ''; $new_regulatory_network_id='';
    my $ws  = $self->{'workspace'};
    
     # check if the regulatory network data exists
    my $get_object_params = {
	id => $regulatory_network_id,
	type => "Unspecified",
	workspace => $workspace_name,
	auth => $token,
    };
    my $r_exists = $ws->has_object($get_object_params);
    if(!$r_exists) {
	$status = "FAILURE - no regulatory network data with ID $regulatory_network_id found!\n".$status;
    } else {
	# if it does exist grab the object
	my $interaction_counter = 0; my $converted_interaction_counter=0;
	$get_object_params->{id}=$regulatory_network_id;
	my $updated_version = "";
	my $object = $ws->get_object($get_object_params);
	my $regnet = $object->{data};
	my @lines = split /\n/, $regnet;
	foreach my $line (@lines) {
	    chomp $line;
	    my @ids = split /\t/, $line;
	    $interaction_counter++;
	    if( scalar(@ids) != 2 ) {
		$status = "ERROR - malformed line in regulatory network data: $line\n".$status;
		last;
	    }
	    if(exists $new_feature_names->{$ids[0]}) {
		if(exists $new_feature_names->{$ids[1]}) {
		    $updated_version .= $new_feature_names->{$ids[0]}."\t".$new_feature_names->{$ids[1]}."\n";
		    $converted_interaction_counter ++;
		} else {
		    $status .= "WARNING - cannot find match for target '".$ids[1]."', skipping this interaction\n";
		}
	    } else {
		$status .= "WARNING - cannot find match for TF '".$ids[0]."', skipping this interaction\n";
	    }
	}
	
	# save a new object in the workspace
	if($updated_version ne '') {
	    
	    $new_regulatory_network_id = $self->{'uuid_generator'}->create_str();
	    
	    # save the collection to the workspace
	    my $workspace_save_obj_params = {
		id => $new_regulatory_network_id,
		type => "Unspecified",
		data => $updated_version,
		workspace => $workspace_name,
		command => "Bio::KBase::PROM::get_regulatory_network_by_genome",
		auth => $token,
		json => 0,
		compressed => 0,
		retrieveFromURL => 0,
	    };
	    my $object_metadata = $ws->save_object($workspace_save_obj_params);
	    $status = $status."  -> saving the new regulatory network to your workspace with ID:$new_regulatory_network_id\n";
	    
	    $status = $status."  -> able to map $converted_interaction_counter of $interaction_counter original interactions\n";
	    $status = "SUCCESS.\n".$status;
	} else {
	    $status = "ERROR - not saving new version because no regulatory interactions in the new namespace exist!\n".$status;
	}
    }
    #END change_regulatory_network_namespace
    my @_bad_returns;
    (!ref($status)) or push(@_bad_returns, "Invalid type for return variable \"status\" (value was \"$status\")");
    (!ref($new_regulatory_network_id)) or push(@_bad_returns, "Invalid type for return variable \"new_regulatory_network_id\" (value was \"$new_regulatory_network_id\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to change_regulatory_network_namespace:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'change_regulatory_network_namespace');
    }
    return($status, $new_regulatory_network_id);
}




=head2 create_prom_constraints

  $status, $prom_constraint_id = $obj->create_prom_constraints($e_id, $r_id, $workspace_name, $token)

=over 4

=item Parameter and return types

=begin html

<pre>
$e_id is an expression_data_collection_id
$r_id is a regulatory_network_id
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
$prom_constraint_id is a prom_constraint_id
expression_data_collection_id is a string
regulatory_network_id is a string
workspace_name is a string
auth_token is a string
status is a string
prom_constraint_id is a string

</pre>

=end html

=begin text

$e_id is an expression_data_collection_id
$r_id is a regulatory_network_id
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
$prom_constraint_id is a prom_constraint_id
expression_data_collection_id is a string
regulatory_network_id is a string
workspace_name is a string
auth_token is a string
status is a string
prom_constraint_id is a string


=end text



=item Description

Once you have loaded gene expression data and a regulatory network for a specific genome, then
you can use this method to create add PROM contraints to the FBA model, thus creating a PROM model.  This method will then return
you the ID of the PROM model object created in your workspace.  The PROM Model object can then be simulated, visualized, edited, etc.
using methods from the FBAModeling Service.

=back

=cut

sub create_prom_constraints
{
    my $self = shift;
    my($e_id, $r_id, $workspace_name, $token) = @_;

    my @_bad_arguments;
    (!ref($e_id)) or push(@_bad_arguments, "Invalid type for argument \"e_id\" (value was \"$e_id\")");
    (!ref($r_id)) or push(@_bad_arguments, "Invalid type for argument \"r_id\" (value was \"$r_id\")");
    (!ref($workspace_name)) or push(@_bad_arguments, "Invalid type for argument \"workspace_name\" (value was \"$workspace_name\")");
    (!ref($token)) or push(@_bad_arguments, "Invalid type for argument \"token\" (value was \"$token\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to create_prom_constraints:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_prom_constraints');
    }

    my $ctx = $Bio::KBase::PROM::Service::CallContext;
    my($status, $prom_constraint_id);
    #BEGIN create_prom_constraints
    my $t_start = Benchmark->new;
    
    #set up return variables and fetch the workspace client handle
    $status = ""; $prom_constraint_id = "";
    my $ws  = $self->{'workspace'};
    
    # check if the gene expression data collection from a workspace exists
    my $get_object_params = {
	id => $e_id,
	type => "Unspecified",
	workspace => $workspace_name,
	auth => $token,
    };
    my $e_exists = $ws->has_object($get_object_params);
    if(!$e_exists) {
	$status = "FAILURE - no expression data collection with ID $e_id found!\n".$status;
    }
    # check if the regulatory network data from a workspace exists
    $get_object_params->{id}=$r_id;
    my $r_exists = $ws->has_object($get_object_params);
    if(!$r_exists) {
	$status = "FAILURE - no regulatory network data with ID $r_id found!\n".$status;
    }
    
    # if both data sets exist, then pull them down
    my $found_error;
    if($e_exists && $r_exists) {
	
	# a regulatory network is a list where each element is a list in the form [TF, target, p1, p2]
	# it is initially parsed in from the workspace object, at which point p1 and p2 are computed
	my $regulatory_network = [];
	
	$get_object_params->{id}=$r_id;
	my $regnet = $ws->get_object($get_object_params)->{data};
	my @lines = split /\n/, $regnet;
	my $reg_net_interaction_counter = 0;
	foreach my $line (@lines) {
	    chomp $line;
	    my @ids = split /\t/, $line;
	    $reg_net_interaction_counter++;
	    if( scalar(@ids) != 2 ) { $status = "ERROR - malformed line in regulatory network data: $line\n".$status; last; }
	    push @$regulatory_network, [$ids[0],$ids[1],-1,-1];
	}
	$status .= "  -> retrieved regulatory network with $reg_net_interaction_counter regulatory interactions.\n";
	$status .= "     ".timestr(timediff(Benchmark->new,$t_start))."\n";
	
	# now grab the expression data and store it in a parsed object
	# Note that this does not do any sort of error checking for IDs or anything else!!!
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
	my $expression_data_on_off_calls = [];
	$get_object_params->{id}=$e_id;
	my $exp_collection = $ws->get_object($get_object_params);
	my $expression_data_id_list = $exp_collection->{data}->{expression_data};
	$status .= "  -> retrieved expression data collection with ".scalar(@$expression_data_id_list)." experiments.\n";
	$status .= "     ".timestr(timediff(Benchmark->new,$t_start))."\n";
	#loop through each experiment
	my $n_features = -1; my $output_list = {};
	foreach my $expression_data_id (@$expression_data_id_list) {
	    
	    $get_object_params->{id}=$expression_data_id;
	    my $exp_data = $ws->get_object($get_object_params)->{data};
	    
	    push @$expression_data_on_off_calls, {geneCalls => $exp_data->{on_off_call},
						  media=> 'unknown',
						  description => $exp_data->{expression_data_source}."::".$exp_data->{expression_data_source_id},
						  label => $exp_data->{id}};
	    
	}
	$status .= "  -> retrieved all expression data for each experiment in the collection\n";
	$status .= "     ".timestr(timediff(Benchmark->new,$t_start))."\n";
	
	
	# still with us?  if so, then onwards and upwards.  Let's actually create the prom model now!
	if(!$found_error) {
	    
	    # compute the interaction probability map; this is the central component of a prom model
	    # Note that currently there is no annotation object used.  How do we get it?  I don't see why we even need it to be honest?? Shouldn't
	    # the Prom model be defined automatically in terms of feature ids, and then only later is that mapped to rxns or other model internals?
	    my ($computation_log, $tfMap) = computeInteractionProbabilities($regulatory_network, $expression_data_on_off_calls);
	    $status .= $computation_log;
	    $status .= "  -> computed regulation interaction probabilities\n";
	    $status .= "     ".timestr(timediff(Benchmark->new,$t_start))."\n";
	   # print Dumper($tfMap)."\n";
	    
	    # actually create the prom model object (note that it is misnamed in ModelSEED!!! should be a constraints object, not
	    # a model object)
	    #my $PromModelConstraints = ModelSEED::MS::PROMModel->new("annotation_uuid" => $annotation->uuid(), "transcriptionFactorMaps" => $tfMaps, "id" => "pm_$genomeid");
	    my $PromModelConstraints = ModelSEED::MS::PROMModel->new(
						    "annotation_uuid" => "some_annotation",
						    "transcriptionFactorMaps" => $tfMap,
						    "id" => "junior_prom");
	    print Dumper($PromModelConstraints)."\n";
	    
	    # save the prom constraints to the workspace
	    my $json_translator = new JSON;
	    $json_translator = $json_translator->allow_nonref(0);
	    $json_translator = $json_translator->allow_blessed;
	    $json_translator = $json_translator->convert_blessed;
	    
	    my $encoded_json_PromModelConstraints = $json_translator($PromModelConstraints);
	    print $encoded_json_PromModelConstraints."\n";
	    $prom_constraint_id = $self->{'uuid_generator'}->create_str();
	    my $workspace_save_obj_params = {
		id => $prom_constraint_id,
		type => "Unspecified",
		data => $encoded_json_PromModelConstraints,
		workspace => $workspace_name,
		command => "Bio::KBase::PROM::create_prom_constraints",
		auth => $token,
		json => 1,
		compressed => 0,
		retrieveFromURL => 0,
	    };
	    my $object_metadata = $ws->save_object($workspace_save_obj_params);
	    $status = $status."  -> saving the new PromModelConstraints object ID:$prom_constraint_id\n";
	    $status .= "     ".timestr(timediff(Benchmark->new,$t_start))."\n";
	    $status = "SUCCESS.\n".$status;
	    
	    print "Created Prom Model Constraints Object:\n";
	    print Dumper($object_metadata)."\n";
	    
	    
	}
    }
    
    
    
    
    #END create_prom_constraints
    my @_bad_returns;
    (!ref($status)) or push(@_bad_returns, "Invalid type for return variable \"status\" (value was \"$status\")");
    (!ref($prom_constraint_id)) or push(@_bad_returns, "Invalid type for return variable \"prom_constraint_id\" (value was \"$prom_constraint_id\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to create_prom_constraints:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_prom_constraints');
    }
    return($status, $prom_constraint_id);
}




=head2 load_expression_data

  $return_1, $return_2 = $obj->load_expression_data($data)

=over 4

=item Parameter and return types

=begin html

<pre>
$data is a boolean_gene_expression_data_collection
$return_1 is a status
$return_2 is an expression_data_collection_id
boolean_gene_expression_data_collection is a reference to a hash where the following keys are defined:
	id has a value which is an expression_data_collection_id
	expression_data_ids has a value which is a reference to a list where each element is a boolean_gene_expression_data_id
expression_data_collection_id is a string
boolean_gene_expression_data_id is a string
status is a string

</pre>

=end html

=begin text

$data is a boolean_gene_expression_data_collection
$return_1 is a status
$return_2 is an expression_data_collection_id
boolean_gene_expression_data_collection is a reference to a hash where the following keys are defined:
	id has a value which is an expression_data_collection_id
	expression_data_ids has a value which is a reference to a list where each element is a boolean_gene_expression_data_id
expression_data_collection_id is a string
boolean_gene_expression_data_id is a string
status is a string


=end text



=item Description

This method allows the end user to upload gene expression data directly to a workspace.  This is useful if, for
instance, the gene expression data needed is private or not yet uploaded to the CDM.  Note that it is critical that
the gene ids are the same as the ids used in the FBA model!

=back

=cut

sub load_expression_data
{
    my $self = shift;
    my($data) = @_;

    my @_bad_arguments;
    (ref($data) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"data\" (value was \"$data\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to load_expression_data:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'load_expression_data');
    }

    my $ctx = $Bio::KBase::PROM::Service::CallContext;
    my($return_1, $return_2);
    #BEGIN load_expression_data
    #END load_expression_data
    my @_bad_returns;
    (!ref($return_1)) or push(@_bad_returns, "Invalid type for return variable \"return_1\" (value was \"$return_1\")");
    (!ref($return_2)) or push(@_bad_returns, "Invalid type for return variable \"return_2\" (value was \"$return_2\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to load_expression_data:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'load_expression_data');
    }
    return($return_1, $return_2);
}




=head2 version 

  $return = $obj->version()

=over 4

=item Parameter and return types

=begin html

<pre>
$return is a string
</pre>

=end html

=begin text

$return is a string

=end text

=item Description

Return the module version. This is a Semantic Versioning number.

=back

=cut

sub version {
    return $VERSION;
}

=head1 TYPES



=head2 kbase_id

=over 4



=item Description

A KBase ID is a string starting with the characters "kb|".  KBase IDs are typed. The types are
designated using a short string.  KBase IDs may be hierarchical.  See the standard KBase documentation
for more information.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 feature_id

=over 4



=item Description

A KBase ID for a genome feature


=item Definition

=begin html

<pre>
a kbase_id
</pre>

=end html

=begin text

a kbase_id

=end text

=back



=head2 genome_id

=over 4



=item Description

A KBase ID for a genome


=item Definition

=begin html

<pre>
a kbase_id
</pre>

=end html

=begin text

a kbase_id

=end text

=back



=head2 workspace_name

=over 4



=item Description

The name of a workspace


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 boolean_gene_expression_data_id

=over 4



=item Description

A workspace ID for a gene expression data object.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 expression_data_collection_id

=over 4



=item Description

A workspace id for a set of expression data on/off calls


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 regulatory_network_id

=over 4



=item Description

A workspace ID for a regulatory network object


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 status

=over 4



=item Description

Status message used by this service to provide information on the final status of a step


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 prom_constraint_id

=over 4



=item Description

A workspace ID for the prom constraint object, used to access any models created by this service in
a user's workpace


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 source

=over 4



=item Description

Specifies the source of a data object, e.g. KBase or MicrobesOnline


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 source_id

=over 4



=item Description

Specifies the ID of the data object in the source


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 auth_token

=over 4



=item Description

The string representation of the bearer token needed to authenticate on the workspace service, this will eventually
be eliminated when this service is updated to use the auto type-compiler auth functionality


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 on_off_state

=over 4



=item Description

Indicates on/off state of a gene, 1=on, -1=off, 0=unknown


=item Definition

=begin html

<pre>
an int
</pre>

=end html

=begin text

an int

=end text

=back



=head2 boolean_gene_expression_data

=over 4



=item Description

A simplified representation of gene expression data under a SINGLE condition. Note that the condition
information is not explicitly tracked here. also NOTE: this data object should be migrated to the Expression
Data service, and simply imported here.

    mapping<feature_id,on_off_state> on_off_call - a mapping of genome features to on/off calls under the given
                                           condition (true=on, false=off).  It is therefore assumed that
                                           the features are protein coding genes.
    source expression_data_source        - the source of this collection of expression data
    source_id expression_data_source_id  - the id of this data object in the workspace


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is a boolean_gene_expression_data_id
on_off_call has a value which is a reference to a hash where the key is a feature_id and the value is an on_off_state
expression_data_source has a value which is a source
expression_data_source_id has a value which is a source

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is a boolean_gene_expression_data_id
on_off_call has a value which is a reference to a hash where the key is a feature_id and the value is an on_off_state
expression_data_source has a value which is a source
expression_data_source_id has a value which is a source


=end text

=back



=head2 boolean_gene_expression_data_collection

=over 4



=item Description

A collection of gene expression data for a single genome under a range of conditions.  This data is returned
as a list of IDs for boolean gene expression data objects in the workspace.  This is a simple object for creating
a PROM Model. NOTE: this data object should be migrated to the Expression Data service, and simply imported here.


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an expression_data_collection_id
expression_data_ids has a value which is a reference to a list where each element is a boolean_gene_expression_data_id

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an expression_data_collection_id
expression_data_ids has a value which is a reference to a list where each element is a boolean_gene_expression_data_id


=end text

=back



=head2 regulatory_interaction

=over 4



=item Description

A simplified representation of a regulatory interaction that also stores the probability of the interaction
(specificially, as the probability the target is on given that the regulator is off), which is necessary for PROM
to construct FBA constraints.  NOTE: this data object should be migrated to the Regulation service, and simply
imported here. NOTE 2: feature_id may actually be a more general ID, as models can potentially be loaded that
are not in the kbase namespace. In this case everything, including expression data and the fba model must be in
the same namespace.

    feature_id TF            - the genome feature that is the regulator
    feature_id target        - the genome feature that is the target of regulation
    float probTTonGivenTFoff - the probability that the transcriptional target is ON, given that the
                               transcription factor is not expressed, as defined in Candrasekarana &
                               Price, PNAS 2010 and used to predict cumulative effects of multiple
                               regulatory interactions with a single target.  Set to null or empty if
                               this probability has not been calculated yet.
    float probTTonGivenTFon  - the probability that the transcriptional target is ON, given that the
                               transcription factor is expressed.    Set to null or empty if
                               this probability has not been calculated yet.


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
TF has a value which is a feature_id
target has a value which is a feature_id
probabilityTTonGivenTFoff has a value which is a float
probabilityTTonGivenTFon has a value which is a float

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
TF has a value which is a feature_id
target has a value which is a feature_id
probabilityTTonGivenTFoff has a value which is a float
probabilityTTonGivenTFon has a value which is a float


=end text

=back



=head2 regulatory_network

=over 4



=item Description

A collection of regulatory interactions that together form a regulatory network. This is an extremely
simplified data object for use in constructing a PROM model.  NOTE: this data object should be migrated to
the Regulation service, and simply imported here.


=item Definition

=begin html

<pre>
a reference to a list where each element is a regulatory_interaction
</pre>

=end html

=begin text

a reference to a list where each element is a regulatory_interaction

=end text

=back



=head2 prom_constraint

=over 4



=item Description

An object that encapsulates the information necessary to apply PROM-based constraints to an FBA model. This
includes a regulatory network consisting of a set of regulatory interactions, and a copy of the expression data
that is required to compute the probability of regulatory interactions.  A prom constraint object can then be
associated with an FBA model to create a PROM model that can be simulated with tools from the FBAModelingService.

    list<regulatory_interaction> regulatory_network           - a collection of regulatory interactions that
                                                                compose a regulatory network.  Probabilty values
                                                                are initially set to nan until they are computed
                                                                from the set of expression experiments.
    list<boolean_gene_expression_data> expression_experiments - a collection of expression data experiments that
                                                                coorespond to this genome of interest.


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
regulatory_network has a value which is a regulatory_network
expression_data_collection_id has a value which is an expression_data_collection_id

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
regulatory_network has a value which is a regulatory_network
expression_data_collection_id has a value which is an expression_data_collection_id


=end text

=back



=cut

1;
