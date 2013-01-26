#
# NOTE THAT THIS ASSUMES THAT YOU INVOKED THE CODE VIA MAKE TEST, OTHERWISE PATHS WILL BE WRONG.
#
# This test performs an end-to-end test of the PROM service, which means that by definition this
# code is an integration test that requires calls to workspaceService and fbaModelServices and
# indirectly requires the regulation service and expression service (once it is implemented).  Thus,
# this test also serves as a good example for getting started with using the PROM service in perl.
#

use strict;
use warnings;

use Test::More;
use Data::Dumper;

# MAKE SURE WE LOCALLY HAVE JSON RPC LIBS INSTALLED
use_ok("Bio::KBase::PROM::Client");
use_ok("Bio::KBase::workspaceService::Client");
use_ok("Bio::KBase::fbaModelServices::Client");
use_ok("Bio::KBase::AuthToken");

# AUTH INFORMATION FOR TESTING
my $user_id='kbasepromuser1';
my $password='open4me!';
my $workspace_name="active_prom_test_workspace";
my $token = Bio::KBase::AuthToken->new(user_id => $user_id, password => $password);
ok(defined $token,"auth could get token");

# READ THE LOCAL CONFIG FILE FOR URLS  (IS THERE A BETTER WAY TO FIND THE FILE THAN TO JUST GO THERE????)
my $c = Config::Simple->new();
$c->read("deploy.cfg");
ok(defined $c->param("prom_service.workspace"), "workspace url found");
my $workspace_url =$c->param("prom_service.workspace");
ok(defined $c->param("prom_service.fba"), "FBA url found");
my $fba_url =$c->param("prom_service.fba");

# 0) BOOTUP THE PROM CLIENT (HOW ELSE CAN I INJECT THE CONFIG LOCATION IN A TEST SCRIPT ?!?!?!?)
use Server;
$ENV{PROM_DEPLOYMENT_CONFIG}='deploy.cfg';
$ENV{PROM_DEPLOYMENT_SERVICE_NAME}='prom_service';
my ($pid, $url) = Server::start('PROM');
print "-> attempting to connect to:'".$url."' with PID=$pid\n";
my $prom = Bio::KBase::PROM::Client->new($url, user_id=>$user_id, password=>$password);
ok(defined($prom),"instantiating PROM client");

# 1) CREATE A WORKSPACE IF IT DOES NOT EXIST
my $ws = Bio::KBase::workspaceService::Client->new($workspace_url);
my $ws_list = $ws->list_workspaces( { auth=>$token->token() } );
my $found = 0;
foreach my $ws_name (@$ws_list) {
    if($ws_name->[0] eq $workspace_name) { $found=1; }
}
if( $found != 1 ) {
    my $create_workspace_params = {
        workspace => $workspace_name,
        default_permission => 'w',
        auth => $token->token()
    };
    my $workspace_meta = $ws->create_workspace($create_workspace_params);
    ok(defined $workspace_meta, "workspace creation");
    print "Created new workspace: \n".Dumper($workspace_meta)."\n";
} else {
    ok(1, "workspace already exists");
}

# 2) LOAD A GENOME AND CREATE AN FBAMODEL
my $fba = Bio::KBase::fbaModelServices::Client->new($fba_url);
my $genome_to_workspace_params = {
    genome => "kb|g.372",
    workspace => $workspace_name,
    auth => $token->token(),
};
my $genome_meta = $fba->genome_to_workspace($genome_to_workspace_params);
ok(defined $genome_meta, "genome import seemed to work");
print "Imported genome to workspace: \n".Dumper($genome_meta)."\n";

my $get_object_params = {
    id => "kb|g.372",
    type => "Genome",
    workspace => $workspace_name,
    auth => $token->token()
};
my $obj_returned = $ws->get_object($get_object_params);
my $annotation_uuid = $obj_returned->{data}->{annotation_uuid};
ok(defined $annotation_uuid, "yes, genome successfully imported because i have an annotation object");

# could create an fba model to get the genome annotation object here too!



# 3) USE THE PROM SERVICE TO LOAD SOME REGULATORY NETWORK DATA
# note that for now we only have a model for kb|g.20848, not kb|g.372!!!
my $regulatory_network_id; my $status;
($status, $regulatory_network_id) = $prom->get_regulatory_network_by_genome("kb|g.20848",$workspace_name, $token->token());
ok($status,"creating the regulatory network returned some status flag");
ok($regulatory_network_id,"regulatory network  defined");
ok($regulatory_network_id ne "","regulatory network id not empty");
print "STATUS: \n$status\n";
print "RETURNED ID: $regulatory_network_id\n";

# 4) USE THE PROM SERVICE TO CONVERT THE NAMESPACE OF THE REGULTORY NETWORK
# first get the mappings from a file.

# 5) CREATE AN EXPRESSION DATA SET
my $expression_data_collection_id;
($status, $expression_data_collection_id) = $prom->get_expression_data_by_genome("kb|g.372",$workspace_name, $token->token());
ok($expression_data_collection_id,"expression collection id defined");
ok($expression_data_collection_id ne "","expression collection id not empty");
print "STATUS: \n$status\n";
print "RETURNED ID: $expression_data_collection_id\n";

# 6) CONVERT THE NAMESPACE OF THE EXPRESSION DATA SET
# not yet functional or necessary for now....

# 7) CREATE THE PROM CONSTRAINTS
my $create_prom_constraints_parameters = {
    new_prom_constraint_id => "myFirstProm",
    overwrite => 1,
    e_id => $expression_data_collection_id,
    r_id => $regulatory_network_id,
    a_id => $annotation_uuid,
    workspace_name => $workspace_name,
    token =>  $token->token()
};
$status = $prom->create_prom_constraints($create_prom_constraints_parameters);
ok($status,"prom creation status defined");
ok($status ne "","prom creation status not empty");
print "STATUS: \n$status\n";


# 8) RUN AN FBA MODEL WITH THE PROM CONSTRAINTS
# not necessary here - where can we do integration testing ?!?!?


# 9) DELETE THE WORKSPACE
my $delete_workspace_params = {
    workspace => $workspace_name,
    auth => $token->token()
};
my $workspace_meta=$ws->delete_workspace($delete_workspace_params);
ok(defined $workspace_meta, "workspace deletion");
print "Deleted workspace: \n".Dumper($workspace_meta)."\n";

done_testing();
