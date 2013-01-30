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

Note: for compatibility with the workspace service and legacy reasons, auth tokens are passed in as
parameters rather than handled automatically by the auto-generated client/server infrastructure.  This
will be fixed soon in one of the next builds.

[1] Chandrasekarana S. and Price ND. Probabilistic integrative modeling of genome-scale metabolic and
regulatory networks in Escherichia coli and Mycobacterium tuberculosis. PNAS (2010) 107:17845-50.

AUTHORS:
Michael Sneddon (mwsneddon@lbl.gov)
Matt DeJongh (dejongh@hope.edu)

created 11/27/2012 - msneddon

=cut

#BEGIN_HEADER

use Bio::KBase::ERDB_Service::Client;
use Bio::KBase::Regulation::Client;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::IDServer::Client;
use Bio::KBase::PROM::Util qw(computeInteractionProbabilities);
#use ModelSEED::MS::PROMModel;

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
    my %params;
    #if ((my $e = $ENV{KB_DEPLOYMENT_CONFIG}) && -e $ENV{KB_DEPLOYMENT_CONFIG})
    # I have to do this because the KBase deployment process is broken!!!
    if ((my $e = $ENV{PROM_DEPLOYMENT_CONFIG}) && -e $ENV{PROM_DEPLOYMENT_CONFIG})
    {
	my $service = $ENV{PROM_DEPLOYMENT_SERVICE_NAME};
	my $c = Config::Simple->new();
	print "looking at config file: ".$e."\n";
	print "service name: ".$service."\n";
	$c->read($e);
	my @params = qw(erdb regulation workspace idserver); # scratch-space);
	for my $p (@params)
	{
	    my $v = $c->param("$service.$p");
	    if ($v)
	    {
		$params{$p} = $v;
	    }
	}
    }

    if (defined $params{"erdb"}) {
	my $erdb_url = $params{"erdb"};
	$self->{'erdb'} = Bio::KBase::ERDB_Service::Client->new($erdb_url);
	print STDERR "Connecting ERDB Service client to server: $erdb_url\n";
    }
    else {
	print STDERR "ERDB Service configuration not found\n";
    }

    if (defined $params{"regulation"}) {
	my $reg_url = $params{"regulation"};
	$self->{'regulation'} = Bio::KBase::Regulation::Client->new($reg_url);
	print STDERR "Connecting Regulation Service client  to server: $reg_url\n";
    }
    else {
	print STDERR "Regulation Service configuration not found\n";
    }
	
    if (defined $params{"workspace"}) {
	my $workspace_url = $params{"workspace"};
	$self->{'workspace'} = Bio::KBase::workspaceService::Client->new($workspace_url);
	print STDERR "Connecting Workspace Service client to server : $workspace_url\n";
    }
    else {
	print STDERR "Workspace Service configuration not found\n";
    }
    
    if (defined $params{"idserver"}) {
	my $idserver_url = $params{"idserver"};
	$self->{'idserver'} = Bio::KBase::IDServer::Client->new($idserver_url);
	print STDERR "Connecting ID Server Service client to server : $idserver_url\n";
    }
    else {
	print STDERR "ID Server Service configuration not found\n";
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
		$exp_counter ++;
		#if ($exp_counter>2) { last; } #limit for debugging purposes...
		print "---Experiment $exp_counter:".${$exp}[0]."\n";
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
		    print "---ws_id = ".$data_uuid."\n";
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
		    #print Dumper($object_metadata)."\n";
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
	    print "---Expression Data Collection:\n".Dumper($object_metadata)."\n";
	    
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




=head2 create_expression_data_collection

  $status, $expression_data_collection_id = $obj->create_expression_data_collection($workspace_name, $token)

=over 4

=item Parameter and return types

=begin html

<pre>
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
$expression_data_collection_id is an expression_data_collection_id
workspace_name is a string
auth_token is a string
status is a string
expression_data_collection_id is a string

</pre>

=end html

=begin text

$workspace_name is a workspace_name
$token is an auth_token
$status is a status
$expression_data_collection_id is an expression_data_collection_id
workspace_name is a string
auth_token is a string
status is a string
expression_data_collection_id is a string


=end text



=item Description

This method creates a new, empty, expression data collection in the specified workspace. If the method was successful,
the ID of the expression data set will be returned.  The method also returns a status message providing additional
details of the steps that occured or a message that indicates what failed.  If the method fails, no expression
data ID is returned.

=back

=cut

sub create_expression_data_collection
{
    my $self = shift;
    my($workspace_name, $token) = @_;

    my @_bad_arguments;
    (!ref($workspace_name)) or push(@_bad_arguments, "Invalid type for argument \"workspace_name\" (value was \"$workspace_name\")");
    (!ref($token)) or push(@_bad_arguments, "Invalid type for argument \"token\" (value was \"$token\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to create_expression_data_collection:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_expression_data_collection');
    }

    my $ctx = $Bio::KBase::PROM::Service::CallContext;
    my($status, $expression_data_collection_id);
    #BEGIN create_expression_data_collection
	$status = ''; $expression_data_collection_id = '';
	my $ws = $self->{'workspace'};
	
	# generate a new collection id
	$expression_data_collection_id = $self->{'uuid_generator'}->create_str();
		
	# create the collection and encode it as JSON
	my $exp_data_collection = {
	    id => $expression_data_collection_id,
	    expression_data => [],
	};
	my $encoded_json_data_collection = encode_json $exp_data_collection;
		
	# save the collection to the workspace
	my $workspace_save_obj_params = {
	    id => $expression_data_collection_id,
	    type => "Unspecified",
	    data => $encoded_json_data_collection,
	    workspace => $workspace_name,
	    command => "Bio::KBase::PROM::create_expression_data_collection",
	    auth => $token,
	    json => 1,
	    compressed => 0,
	    retrieveFromURL => 0,
	};
	my $object_metadata = $ws->save_object($workspace_save_obj_params);
	print "---Expression Data Collection:\n".Dumper($object_metadata)."\n";
	    
	$status = $status."  -> created empty expression experiment collection with ID:$expression_data_collection_id\n";
	$status = "SUCCESS.\n".$status;
	    
    #END create_expression_data_collection
    my @_bad_returns;
    (!ref($status)) or push(@_bad_returns, "Invalid type for return variable \"status\" (value was \"$status\")");
    (!ref($expression_data_collection_id)) or push(@_bad_returns, "Invalid type for return variable \"expression_data_collection_id\" (value was \"$expression_data_collection_id\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to create_expression_data_collection:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_expression_data_collection');
    }
    return($status, $expression_data_collection_id);
}




=head2 add_expression_data_to_collection

  $status = $obj->add_expression_data_to_collection($expression_data, $expression_data_collecion_id, $workspace_name, $token)

=over 4

=item Parameter and return types

=begin html

<pre>
$expression_data is a reference to a list where each element is a boolean_gene_expression_data
$expression_data_collecion_id is an expression_data_collection_id
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
boolean_gene_expression_data is a reference to a hash where the following keys are defined:
	id has a value which is a boolean_gene_expression_data_id
	on_off_call has a value which is a reference to a hash where the key is a feature_id and the value is an on_off_state
	expression_data_source has a value which is a source
	expression_data_source_id has a value which is a source
boolean_gene_expression_data_id is a string
feature_id is a kbase_id
kbase_id is a string
on_off_state is an int
source is a string
expression_data_collection_id is a string
workspace_name is a string
auth_token is a string
status is a string

</pre>

=end html

=begin text

$expression_data is a reference to a list where each element is a boolean_gene_expression_data
$expression_data_collecion_id is an expression_data_collection_id
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
boolean_gene_expression_data is a reference to a hash where the following keys are defined:
	id has a value which is a boolean_gene_expression_data_id
	on_off_call has a value which is a reference to a hash where the key is a feature_id and the value is an on_off_state
	expression_data_source has a value which is a source
	expression_data_source_id has a value which is a source
boolean_gene_expression_data_id is a string
feature_id is a kbase_id
kbase_id is a string
on_off_state is an int
source is a string
expression_data_collection_id is a string
workspace_name is a string
auth_token is a string
status is a string


=end text



=item Description

This method provides a way to attach a set of boolean expression data to an expression data collection object created
in the current workspace.  Data collections can thus be composed of both CDS data and user data in this way.  The method
returns a status message providing additional details of the steps that occured or a message that indicates what failed.
If the method fails, then all updates to the expression_data_collection are not made, although some of the boolean gene
expression data may have been created in the workspace (see status message for IDs of the new expession data objects).

Note: when defining expression data, the id field must be explicitly defined.  This will be the ID used to save the expression
data in the workspace.  If expression data with that ID already exists, this method will overwrite that data and you will
have to use the workspace service revert method to undo the change.

=back

=cut

sub add_expression_data_to_collection
{
    my $self = shift;
    my($expression_data, $expression_data_collecion_id, $workspace_name, $token) = @_;

    my @_bad_arguments;
    (ref($expression_data) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument \"expression_data\" (value was \"$expression_data\")");
    (!ref($expression_data_collecion_id)) or push(@_bad_arguments, "Invalid type for argument \"expression_data_collecion_id\" (value was \"$expression_data_collecion_id\")");
    (!ref($workspace_name)) or push(@_bad_arguments, "Invalid type for argument \"workspace_name\" (value was \"$workspace_name\")");
    (!ref($token)) or push(@_bad_arguments, "Invalid type for argument \"token\" (value was \"$token\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to add_expression_data_to_collection:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'add_expression_data_to_collection');
    }

    my $ctx = $Bio::KBase::PROM::Service::CallContext;
    my($status);
    #BEGIN add_expression_data_to_collection
	$status = "";
	my $ws = $self->{'workspace'};
	my $fail = 0; #flag to indicate if we failed or not
	
	# first check if the expression data collection exists, and if so, fetch it.
	my $get_object_params = {
	    id=>$expression_data_collecion_id,type => "Unspecified",
	    workspace => $workspace_name, auth => $token
	};
	if($ws->has_object($get_object_params)) {
	    
	    my $collection = $ws->get_object($get_object_params);
	    $status.=" -> fetched expression data collection.\n";
	    
	    # now process and save all of the expression data sets, keeping track of all the IDs that we found
	    my $experiment_ids = [];
	    foreach my $exp(@$expression_data) {
		if(exists($exp->{id})) {
		    my $exp_id = $exp->{id};
		    if(exists($exp->{on_off_call})) {
			my $data_src = "loaded_from_outside_kbase"; my $data_src_id = "";
			if(exists($exp->{data_source})) { $data_src = $exp->{data_source}; }
			else { $status.=" -> warning: no data_source provided for experiment with id $exp_id";}
			if(exists($exp->{data_source_id})) { $data_src_id = $exp->{data_source_id}; }
			else { $status.=" -> warning: no data_source_id provided for experiment with id $exp_id";}
			$status.=" -> processing '$exp_id' (src:'$data_src',src_id:'$data_src_id')\n";
		    
			# save this expression data to the workspace
			my $encoded_json_data_collection = encode_json($exp);
			my $workspace_save_obj_params = {
			    id => $exp_id,
			    type => "Unspecified",
			    data => $encoded_json_data_collection,
			    workspace => $workspace_name,
			    command => "Bio::KBase::PROM::add_expression_data_to_collection",
			    auth => $token,
			    json => 1,
			    compressed => 0,
			    retrieveFromURL => 0,
			};
			my $object_metadata = $ws->save_object($workspace_save_obj_params);
			$status.=" -> saved '$exp_id' to workspace.\n";
			push @$experiment_ids,$exp_id;
		    
		    } else {
			$status.=" -> no data (on_off_call) provided for experimental data set with id $exp_id";
			$fail=1; last;
		    }
		} else {
		    $status.=' -> no ID provided for one of the experimental data sets.';
		    $fail=1; last;
		}
	    }
	    # make sure to save the original expression data sets
	    foreach my $original_member (@{$collection->{data}->{expression_data}}) {
		push @$experiment_ids, $original_member;
	    }
	    
	    #finally, we can add each of these data sets to the collection object and resave the collection
	    my $new_collection = {
		id=>$collection->{data}->{id},
		expression_data=>$experiment_ids
	    };
	    my $encoded_json_data_collection = encode_json($new_collection);
	    my $workspace_save_obj_params = {
		id => $collection->{data}->{id},
		type => "Unspecified",
		data => $encoded_json_data_collection,
		workspace => $workspace_name,
		command => "Bio::KBase::PROM::add_expression_data_to_collection",
		auth => $token,
		json => 1,
		compressed => 0,
		retrieveFromURL => 0,
		metadata=>$collection->{metadata}->[10],
	    };
	    my $collection_object_metadata = $ws->save_object($workspace_save_obj_params);
	    print "updated expression data collection:\n".Dumper($collection_object_metadata)."\n";
	    $status.=" -> updated the expression data collection to include the new data.\n";
	    
	    # for debugging to check if the object was created properly
	    #my $fresh_collection = $ws->get_object($get_object_params);
	    #print Dumper($fresh_collection)."\n";
	
	} else {
	    $status .= " -> no expression data collection with ID $expression_data_collecion_id found!\n";
	    $fail=1;
	}
	
	if($fail) { $status = "FAILURE.\n".$status;
	} else { $status = "SUCCESS.\n".$status; }
	
    #END add_expression_data_to_collection
    my @_bad_returns;
    (!ref($status)) or push(@_bad_returns, "Invalid type for return variable \"status\" (value was \"$status\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to add_expression_data_to_collection:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'add_expression_data_to_collection');
    }
    return($status);
}




=head2 change_expression_data_namespace

  $status = $obj->change_expression_data_namespace($expression_data_collection_id, $new_feature_names, $workspace_name, $token)

=over 4

=item Parameter and return types

=begin html

<pre>
$expression_data_collection_id is an expression_data_collection_id
$new_feature_names is a reference to a hash where the key is a string and the value is a string
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
expression_data_collection_id is a string
workspace_name is a string
auth_token is a string
status is a string

</pre>

=end html

=begin text

$expression_data_collection_id is an expression_data_collection_id
$new_feature_names is a reference to a hash where the key is a string and the value is a string
$workspace_name is a workspace_name
$token is an auth_token
$status is a status
expression_data_collection_id is a string
workspace_name is a string
auth_token is a string
status is a string


=end text



=item Description

Maps the expression data collection stored in a workspace in one genome namespace to an alternate genome namespace.  This is useful,
for instance, if expression data is available for one genome, but you intend to use it for a related genome or a genome with different
gene calls.  If a gene in the original expression data cannot be found in the translation mapping, then it is ignored and left as is
so that the number of features in the expression data set is not altered.  NOTE!: this is different from the default behavior of
change_regulatory_network_namespace, which will drop all genes that are not found in the mapping.  If successful, this method
returns the expression collection ID of the newly created expression data colleion.  This method also returns a status message indicating
what happened or what went wrong.

The mapping<string,string> new_features_names should be defined so that existing IDs are the key and the replacement IDs are the
values stored.

=back

=cut

sub change_expression_data_namespace
{
    my $self = shift;
    my($expression_data_collection_id, $new_feature_names, $workspace_name, $token) = @_;

    my @_bad_arguments;
    (!ref($expression_data_collection_id)) or push(@_bad_arguments, "Invalid type for argument \"expression_data_collection_id\" (value was \"$expression_data_collection_id\")");
    (ref($new_feature_names) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"new_feature_names\" (value was \"$new_feature_names\")");
    (!ref($workspace_name)) or push(@_bad_arguments, "Invalid type for argument \"workspace_name\" (value was \"$workspace_name\")");
    (!ref($token)) or push(@_bad_arguments, "Invalid type for argument \"token\" (value was \"$token\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to change_expression_data_namespace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'change_expression_data_namespace');
    }

    my $ctx = $Bio::KBase::PROM::Service::CallContext;
    my($status);
    #BEGIN change_expression_data_namespace
	
	$status="";
    
	my $ws = $self->{'workspace'};
	my $fail = 0; #flag to indicate if we failed or not
	
	# first check if the expression data collection exists, and if so, fetch it.
	my $get_object_params = {
	    id=>$expression_data_collection_id, type => "Unspecified",
	    workspace => $workspace_name, auth => $token
	};
	if($ws->has_object($get_object_params)) {
	    my $collection = $ws->get_object($get_object_params);
	    $status.=" -> fetched expression data collection.\n";
	    
	    #loop over each expression data set and update it.
	    my $experiment_ids = $collection->{data}->{expression_data};
	    foreach my $exp (@$experiment_ids) {
		$get_object_params->{id} = $exp;
		my $exp_obj = $ws->get_object($get_object_params);
		my $data_to_update = $exp_obj->{data}->{on_off_call};
		my $new_exp_data = {};
		
		#make the swap
		my $replacement_count= 0; my $total_count=0;
		foreach my $gene (keys %$data_to_update) {
		    $total_count++;
		    if(exists($new_feature_names->{$gene})) {
			$replacement_count++;
			$new_exp_data->{$new_feature_names->{$gene}} = $data_to_update->{$gene};
		    } else {
			$new_exp_data->{$gene} = $data_to_update->{$gene};
		    }
		}
		
		#push back the new object
		my $new_exp_object = {
		    id=>$exp_obj->{data}->{id},
		    on_off_call=>$new_exp_data,
		    expression_data_source => $exp_obj->{data}->{expression_data_source},
		    expression_data_source_id => $exp_obj->{data}->{expression_data_source_id}
		};
		my $encoded_json_data_exp = encode_json($new_exp_object);
		my $workspace_save_obj_params = {
		    id => $exp_obj->{data}->{id},
		    type => "Unspecified",
		     data => $encoded_json_data_exp,
		    workspace => $workspace_name,
		    command => "Bio::KBase::PROM::add_expression_data_to_collection",
		    auth => $token,
		    json => 1,
		    compressed => 0,
		    retrieveFromURL => 0,
		    metadata=>$exp_obj->{metadata}->[10],
		};
		my $object_metadata = $ws->save_object($workspace_save_obj_params);
		$status.=" -> updated '$exp_obj->{data}->{id}' in workspace (modified $replacement_count of $total_count gene names).\n";
		
	    }
	    
	} else {
	    $status .= " -> no expression data collection with ID $expression_data_collection_id found!\n";
	    $fail=1;
	}
	
	if($fail) { $status = "FAILURE.\n".$status;
	} else { $status = "SUCCESS.\n".$status; }
    
    
    #END change_expression_data_namespace
    my @_bad_returns;
    (!ref($status)) or push(@_bad_returns, "Invalid type for return variable \"status\" (value was \"$status\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to change_expression_data_namespace:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'change_expression_data_namespace');
    }
    return($status);
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
    
    if(defined $regulomes) {
	
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
		$status = "FAILURE - no regulatory interactions found for $genome_id\n".$status;
	    }
	}
    } else {
	$status = "FAILURE - no regulatory interactions found for $genome_id\n".$status;
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
for instance, if a regulatory network was built and is available for one genome, but you intend to use it for
a related genome or a genome with different gene calls.  If a gene in the original regulatory network cannot be found in
the translation mapping, then it is simply removed from the new regulatory network.  Thus, if you are only changing the names
of some genes, you still must provide an entry in the input mapping for the genes you wish to keep.  If successful, this method
returns the regulatory network ID of the newly created regulatory network.  This method also returns a status message indicating
what happened or what went wrong.

The mapping<string,string> new_features_names should be defined so that existing IDs are the key and the replacement IDs are the
values stored.

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

  $status, $prom_constraint_id = $obj->create_prom_constraints($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a create_prom_constraints_parameters
$status is a status
$prom_constraint_id is a prom_constraint_id
create_prom_constraints_parameters is a reference to a hash where the following keys are defined:
	genome_object_id has a value which is a genome_object_id
	expression_data_collection_id has a value which is an expression_data_collection_id
	regulatory_network_id has a value which is a regulatory_network_id
	workspace_name has a value which is a workspace_name
	token has a value which is an auth_token
genome_object_id is a string
expression_data_collection_id is a string
regulatory_network_id is a string
workspace_name is a string
auth_token is a string
status is a string
prom_constraint_id is a string

</pre>

=end html

=begin text

$params is a create_prom_constraints_parameters
$status is a status
$prom_constraint_id is a prom_constraint_id
create_prom_constraints_parameters is a reference to a hash where the following keys are defined:
	genome_object_id has a value which is a genome_object_id
	expression_data_collection_id has a value which is an expression_data_collection_id
	regulatory_network_id has a value which is a regulatory_network_id
	workspace_name has a value which is a workspace_name
	token has a value which is an auth_token
genome_object_id is a string
expression_data_collection_id is a string
regulatory_network_id is a string
workspace_name is a string
auth_token is a string
status is a string
prom_constraint_id is a string


=end text



=item Description

This method creates a set of Prom constraints for a given genome annotation based on a regulatory network
and a collection of gene expression data stored on a workspace.  Parameters are specified in the
create_prom_constraints_parameters object.  A status object is returned indicating success or failure along
with a message on what went wrong or statistics on the retrieved objects.  If the method was successful, the
ID of the new Prom constraints object is also returned. The Prom constraints can then be used in conjunction
with an FBA model using FBA Model Services.

=back

=cut

sub create_prom_constraints
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to create_prom_constraints:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_prom_constraints');
    }

    my $ctx = $Bio::KBase::PROM::Service::CallContext;
    my($status, $prom_constraint_id);
    #BEGIN create_prom_constraints
	
	# input description
	#typedef structure {
	#    genome_object_id genome_object_id;
	#    expression_data_collection_id expression_data_collection_id;
	#    regulatory_network_id regulatory_network_id;
	#    workspace_name workspace_name;
	#    auth_token token;
	#} create_prom_constraints_parameters;
	my $e_id = $params->{expression_data_collection_id};
	my $r_id = $params->{regulatory_network_id};
	my $genome_id = $params->{genome_object_id};
	my $workspace_name = $params->{workspace_name};
	my $token = $params->{token};
	$prom_constraint_id ="";
	
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
	$get_object_params->{type}="Unspecified";
	my $r_exists = $ws->has_object($get_object_params);
	if(!$r_exists) {
	    $status = "FAILURE - no regulatory network data with ID $r_id found!\n".$status;
	}
	# check if the annotation data from a workspace exists
	$get_object_params->{id}=$genome_id;
	$get_object_params->{type}="Genome";
	my $genome_exists = $ws->has_object($get_object_params);
	
	# get the genome so we can pull the annotation object
	my $annot;
	if(!$genome_exists) {
	    $status = "FAILURE - no genome object in workspace with ID $genome_id found!\n".$status;
	} else {
	    # if genome exists, then grab the cooresponding annotation object by reference
	    $get_object_params->{id}=$genome_id;
	    $get_object_params->{type}="Genome";
	    my $genome = $ws->get_object($get_object_params)->{data};
	    $status .= "  -> fetched genome object.\n";
	    $annot = $ws->get_object_by_ref( {reference => $genome->{annotation_uuid}, auth => $token} )->{data};
	    $status .= "  -> fetched hidden annotation object by reference with uuid: '$genome->{annotation_uuid}'.\n";
	}
	
	# if both data sets exist, thecdn pull them down
	my $found_error;
	if($e_exists && $r_exists && $genome_exists) {
	    
	    # an Annotation object will have a 'features' key that lists the feature IDs in kbase
	    # space, with a local UUID for internal mapping with the annotation object
	    # here, we create the ID to UUID mapping based on the genome annotation object    
	    
	    my $id_2_uuid = {};
	    my $feature_counter = 0;
	    my $annot_uuid = $annot->{_wsUUID};
	    my $features = $annot->{features};
	    foreach my $f (@$features) {
		$id_2_uuid->{$f->{id}} = $f->{uuid};
		$feature_counter++;
	    }
	    $status .= "  -> genome annotation has $feature_counter features.\n";
	    $status .= "     ".timestr(timediff(Benchmark->new,$t_start))."\n";
	    
	    # a regulatory network is a list where each element is a list in the form [TF, target, p1, p2]
	    # it is initially parsed in from the workspace object, at which point p1 and p2 are computed
	    my $regulatory_network = [];
	    
	    $get_object_params->{id}=$r_id;
	    $get_object_params->{type}="Unspecified";
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
	    
	    print "reg network found, $reg_net_interaction_counter interactions\n";
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
	    $get_object_params->{type}="Unspecified";
	    my $exp_collection = $ws->get_object($get_object_params);
	    my $expression_data_id_list = $exp_collection->{data}->{expression_data};
	    $status .= "  -> retrieved expression data collection with ".scalar(@$expression_data_id_list)." experiments.\n";
	    $status .= "     ".timestr(timediff(Benchmark->new,$t_start))."\n";
	    #loop through each experiment
	    my $n_features = -1; my $output_list = {}; my $exp_counter = 0;
	    foreach my $expression_data_id (@$expression_data_id_list) {
		$exp_counter++;
		print "exp data ( $exp_counter ) lookup: $expression_data_id \n";
		$get_object_params->{id}=$expression_data_id;
		my $exp_data = $ws->get_object($get_object_params)->{data};
		
		push @$expression_data_on_off_calls, {geneCalls => $exp_data->{on_off_call},
						      media=> 'unknown',
						      description => $exp_data->{expression_data_source}."::".$exp_data->{expression_data_source_id},
						      label => $exp_data->{id}};
		#if($exp_counter==4) { last; }; # for debugging purposes, kill after 4 experiments
	    }
	    $status .= "  -> retrieved all expression data for each experiment in the collection\n";
	    $status .= "     ".timestr(timediff(Benchmark->new,$t_start))."\n";
	    
	    
	    # still with us?  if so, then onwards and upwards.  Let's actually create the prom model now!
	    if(!$found_error) {
		
		# compute the interaction probability map; this is the central component of a prom model
		# Note that currently there is no annotation object used.  How do we get it?  I don't see why we even need it to be honest?? Shouldn't
		# the Prom model be defined automatically in terms of feature ids, and then only later is that mapped to rxns or other model internals?
		my ($computation_log, $tfMap) = computeInteractionProbabilities($regulatory_network, $expression_data_on_off_calls, $id_2_uuid);
		$status .= $computation_log;
		$status .= "  -> computed regulation interaction probabilities\n";
		$status .= "     ".timestr(timediff(Benchmark->new,$t_start))."\n";
		# print Dumper($tfMap)."\n";
		
		# use the ID server to generate a name for the prom constraints object
		my $idserver = $self->{idserver};
		my $prefix = $genome_id.".promconstraint.";
		my $id_number = $idserver->allocate_id_range($prefix,1);
		$prom_constraint_id = $prefix.$id_number;
		my $prom_constraints = {
			id => $prom_constraint_id,
			annotation_uuid => $annot_uuid,
			transcriptionFactorMaps => $tfMap,
			expression_data_collection_id => $e_id
		};
		#print Dumper($prom_constraints)."\n";
		
		# save the prom constraints to the workspace
		my $encoded_json_PromModelConstraints = encode_json($prom_constraints);
		print $encoded_json_PromModelConstraints."\n";
		my $workspace_save_obj_params = {
		    id => $prom_constraint_id,
		    type => "PromConstraints",
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



=head2 bool

=over 4



=item Description

indicates true or false values, false <= 0, true >=1


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

A workspace ID for the prom constraint object in a user's workpace


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



=head2 genome_object_id

=over 4



=item Description

A workspace ID for a genome object in a user's workspace, used to link a PromConstraintsObject to a genome


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


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
TF has a value which is a feature_id
target has a value which is a feature_id

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
TF has a value which is a feature_id
target has a value which is a feature_id


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



=head2 regulatory_target

=over 4



=item Description

Object required by the prom_constraint object which defines the computed probabilities for a target gene.  The
TF regulating this target can be deduced based on the tfMap object.

    string target_uuid        - id of the target gene in the annotation object namespace
    float tfOffProbability    - PROB(target=ON|TF=OFF)
                                the probability that the transcriptional target is ON, given that the
                                transcription factor is not expressed, as defined in Candrasekarana &
                                Price, PNAS 2010 and used to predict cumulative effects of multiple
                                regulatory interactions with a single target.  Set to null or empty if
                                this probability has not been calculated yet.
    float probTTonGivenTFon   - PROB(target=ON|TF=ON)
                                the probability that the transcriptional target is ON, given that the
                                transcription factor is expressed.    Set to null or empty if
                                this probability has not been calculated yet.


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
target_uuid has a value which is a string
tfOnProbability has a value which is a float
tfOffProbability has a value which is a float

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
target_uuid has a value which is a string
tfOnProbability has a value which is a float
tfOffProbability has a value which is a float


=end text

=back



=head2 tfMap

=over 4



=item Description

Object required by the prom_constraint object, this maps a transcription factor by its uuid (in some
annotation namespace) to a group of regulatory target genes.

    string transcriptionFactor_uuid                       - id of the TF in the annotation object namespace
    list <regulatory_target> transcriptionFactorMapTarget - collection of regulatory target genes for the TF
                                                            along with associated joint probabilities for each
                                                            target to be on given that the TF is on or off.


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
transcriptionFactor_uuid has a value which is a string
transcriptionFactorMapTarget has a value which is a reference to a list where each element is a regulatory_target

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
transcriptionFactor_uuid has a value which is a string
transcriptionFactorMapTarget has a value which is a reference to a list where each element is a regulatory_target


=end text

=back



=head2 annotation_uuid

=over 4



=item Description

the ID of the genome annotation object kept for reference in the prom_constraint object


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



=head2 prom_contstraint

=over 4



=item Description

An object that encapsulates the information necessary to apply PROM-based constraints to an FBA model. This
includes a regulatory network consisting of a set of regulatory interactions (implied by the set of tfMap
objects) and interaction probabilities as defined in each regulatory_target object.  A link the the annotation
object is required in order to properly link to an FBA model object.  A reference to the expression_data_collection
used to compute the interaction probabilities is provided for future reference.

    prom_constraint_id id                                         - the id of this prom_constraint object in a
                                                                    workspace
    annotation_uuid annotation_uuid                               - the id of the annotation object in the workspace
                                                                    which specfies how TFs and targets are named
    list <tfMap> transcriptionFactorMaps                          - the list of tfMaps which specifies both the
                                                                    regulatory network and interaction probabilities
                                                                    between TF and target genes
    expression_data_collection_id expression_data_collection_id   - the id of the expresion_data_collection object in
                                                                    the workspace which was used to compute the
                                                                    regulatory interaction probabilities


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is a prom_constraint_id
annotation_uuid has a value which is an annotation_uuid
transcriptionFactorMaps has a value which is a reference to a list where each element is a tfMap
expression_data_collection_id has a value which is an expression_data_collection_id

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is a prom_constraint_id
annotation_uuid has a value which is an annotation_uuid
transcriptionFactorMaps has a value which is a reference to a list where each element is a tfMap
expression_data_collection_id has a value which is an expression_data_collection_id


=end text

=back



=head2 create_prom_constraints_parameters

=over 4



=item Description

Named parameters for 'create_prom_constraints' method.  Currently all options are required.

    genome_object_id genome_object_id            - the workspace ID of the genome to link to the prom object
    expression_data_collection_id
               expression_data_collection_id     - the workspace ID of the expression data collection needed to
                                                   build the PROM constraints.
    regulatory_network_id regulatory_network_id  - the workspace ID of the regulatory network data to use
    workspace_name workspace_name                - the name of the workspace to use
    auth_token token                             - the auth token that has permission to write in the specified workspace


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
genome_object_id has a value which is a genome_object_id
expression_data_collection_id has a value which is an expression_data_collection_id
regulatory_network_id has a value which is a regulatory_network_id
workspace_name has a value which is a workspace_name
token has a value which is an auth_token

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
genome_object_id has a value which is a genome_object_id
expression_data_collection_id has a value which is an expression_data_collection_id
regulatory_network_id has a value which is a regulatory_network_id
workspace_name has a value which is a workspace_name
token has a value which is an auth_token


=end text

=back



=cut

1;
